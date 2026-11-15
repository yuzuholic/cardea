#!/bin/sh
# the yuzuholic/cardea launcher builds, the stack it carries renders with the right paths
# and required values, and the launcher really starts and stops a stack. needs docker.
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $*" >&2; exit 1; }

IMAGE=cardea-launcher:test
PROJECT=cardeatest
work=$(mktemp -d)
cleanup() {
  (cd "$work" && docker compose down >/dev/null 2>&1) || true
  docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker network rm "${PROJECT}_default" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

docker build -q -t "$IMAGE" nas >/dev/null || fail "launcher image does not build"

# every value nas/.env.example leaves empty gets a dummy; the optional token stays empty.
sed -E 's/^([A-Z_]+)=$/\1=dummy-\1/; s/^CLOUDFLARE_TUNNEL_TOKEN=.*/CLOUDFLARE_TUNNEL_TOKEN=/' nas/.env.example > "$work/filled.env"

# --- the outer compose names a missing value ---------------------------------
out=$(docker compose -f nas/compose.yml --env-file /dev/null config 2>&1) && fail "outer compose accepted no settings"
echo "$out" | grep -q 'set [A-Z_]* in .env' || fail "outer compose error doesn't name the missing value: $out"
docker compose -f nas/compose.yml --env-file "$work/filled.env" config >/dev/null || fail "outer compose rejects a filled .env"

# --- the stack renders inside the launcher ------------------------------------
render() { docker run --rm --env-file "$1" --entrypoint docker "$IMAGE" compose -p lab -f /cardea/compose.yml config 2>&1; }
config=$(render "$work/filled.env") || fail "stack does not render: $config"
echo "$config" | grep -q 'DATABASE_URL: postgresql://postgres:dummy-POSTGRES_PASSWORD@postgres' || fail "DATABASE_URL isn't built from POSTGRES_PASSWORD"
echo "$config" | grep -q 'HINDSIGHT_API_DATABASE_URL: postgresql://hindsight:dummy-HINDSIGHT_DB_PASSWORD@hindsight-db' || fail "hindsight's database URL isn't built from HINDSIGHT_DB_PASSWORD"
echo "$config" | grep -q 'HINDSIGHT_API_MCP_AUTH_TOKEN: dummy-HINDSIGHT_MCP_TOKEN' || fail "hindsight's MCP token isn't passed through"
echo "$config" | grep -q 'HINDSIGHT_API_LLM_MODEL: claude-haiku-4-5' || fail "hindsight's model has no default"
echo "$config" | grep -q 'HINDSIGHT_API_LLM_PROVIDER: claude-code' || fail "hindsight isn't on the claude-code provider"
echo "$config" | grep -q 'HINDSIGHT_API_LLM_API_KEY: dummy-CLAUDE_CODE_OAUTH_TOKEN' || fail "hindsight's claude token isn't passed through"
echo "$config" | grep -q 'HINDSIGHT_API_OTEL_TRACES_ENABLED: "true"' && fail "hindsight traces are on without HINDSIGHT_LANGFUSE_AUTH"
{ cat "$work/filled.env"; echo HINDSIGHT_LANGFUSE_AUTH=dGVzdA==; } > "$work/traces.env"
traces=$(render "$work/traces.env") || fail "stack does not render with HINDSIGHT_LANGFUSE_AUTH: $traces"
echo "$traces" | grep -q 'HINDSIGHT_API_OTEL_TRACES_ENABLED: "true"' || fail "hindsight traces don't turn on with HINDSIGHT_LANGFUSE_AUTH"
echo "$traces" | grep -q 'Authorization=Basic dGVzdA==' || fail "hindsight's langfuse auth isn't passed through"
echo "$config" | grep -q 'HINDSIGHT_API_AUDIT_LOG_ENABLED: "true"' || fail "hindsight's audit log isn't on"
echo "$config" | grep -q 'host_ip: 127.0.0.1' || fail "a control port isn't bound to loopback"
echo "$config" | grep -qi 'aletheia' && fail "a personal project name is baked into the stack"
echo "$config" | grep -q 'TELEMETRY_ENABLED: "false"' || fail "langfuse telemetry isn't off by default"
echo "$config" | grep -q '^  cloudflared:' && fail "cloudflared renders without the tunnel profile"
grep -v '^SALT=' "$work/filled.env" > "$work/nosalt.env"
render "$work/nosalt.env" | grep -q 'set SALT in .env' || fail "stack starts without SALT"
grep -v '^HINDSIGHT_MCP_TOKEN=' "$work/filled.env" > "$work/notoken.env"
render "$work/notoken.env" | grep -q 'set HINDSIGHT_MCP_TOKEN in .env' || fail "stack starts without HINDSIGHT_MCP_TOKEN"
grep -v '^CLAUDE_CODE_OAUTH_TOKEN=' "$work/filled.env" > "$work/noclaude.env"
render "$work/noclaude.env" | grep -q 'set CLAUDE_CODE_OAUTH_TOKEN in .env' || fail "stack starts without CLAUDE_CODE_OAUTH_TOKEN"

# --- the launcher starts and stops a real (tiny) stack -------------------------
cp "$work/filled.env" "$work/.env"
cat > "$work/inner.yml" <<'EOF'
services:
  probe:
    image: docker:29.9.0-cli
    entrypoint: ["sh", "-c", "echo pg=$$PG; exec sleep 3600"]
    environment:
      PG: ${POSTGRES_PASSWORD:?missing}
  tunnel:
    image: docker:29.9.0-cli
    profiles: [tunnel]
    entrypoint: ["sh", "-c", "exec sleep 3600"]
EOF
sed -e "s|yuzuholic/cardea:latest|$IMAGE|" -e "s|^name: cardea|name: $PROJECT-outer|" \
    -e "s|      - /var/run/docker.sock:/var/run/docker.sock|&\n      - ./inner.yml:/cardea/compose.yml:ro|" \
    -e "s|    environment:|    environment:\n      CARDEA_PROJECT: $PROJECT|" nas/compose.yml > "$work/compose.yml"

wait_for() { i=0; until docker ps --format '{{.Names}}' | grep -q "$1"; do i=$((i+1)); [ $i -lt 60 ] || return 1; sleep 1; done; }

(cd "$work" && docker compose up -d >/dev/null 2>&1) || fail "launcher did not start"
wait_for "$PROJECT-probe" || fail "launcher never started the stack"
docker logs "$PROJECT-probe-1" 2>&1 | grep -q 'pg=dummy-POSTGRES_PASSWORD' || fail "settings don't reach the stack"
docker ps --format '{{.Names}}' | grep -q "$PROJECT-tunnel" && fail "tunnel started without a token"

sed -i.bak 's/^CLOUDFLARE_TUNNEL_TOKEN=.*/CLOUDFLARE_TUNNEL_TOKEN=tok/' "$work/.env"
(cd "$work" && docker compose up -d >/dev/null 2>&1) || fail "launcher did not restart after a .env change"
wait_for "$PROJECT-tunnel" || fail "tunnel didn't start once a token was set"

(cd "$work" && docker compose stop >/dev/null 2>&1)
docker ps --format '{{.Names}}' | grep -q "$PROJECT-probe" && fail "stopping the launcher left the stack running"

echo "ok: launcher builds, renders, starts, applies .env changes and stops"

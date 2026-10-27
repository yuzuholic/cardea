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
render() { docker run --rm --env-file "$1" -e CARDEA_KB=/srv/kb --entrypoint docker "$IMAGE" compose -p lab -f /cardea/compose.yml config 2>&1; }
config=$(render "$work/filled.env") || fail "stack does not render: $config"
[ "$(echo "$config" | grep -c 'source: /srv/kb$')" -eq 2 ] || fail "basic memory and obsidian aren't both mounted from CARDEA_KB"
echo "$config" | grep -q 'BASIC_MEMORY_PROJECT_ROOT: /app/kb' || fail "basic memory can create projects outside kb/"
echo "$config" | grep -q 'DATABASE_URL: postgresql://postgres:dummy-POSTGRES_PASSWORD@postgres' || fail "DATABASE_URL isn't built from POSTGRES_PASSWORD"
echo "$config" | grep -q '^  cloudflared:' && fail "cloudflared renders without the tunnel profile"
grep -v '^SALT=' "$work/filled.env" > "$work/nosalt.env"
render "$work/nosalt.env" | grep -q 'set SALT in .env' || fail "stack starts without SALT"

# --- the launcher starts and stops a real (tiny) stack -------------------------
mkdir -p "$work/kb" && echo note > "$work/kb/n.md"
cp "$work/filled.env" "$work/.env"
cat > "$work/inner.yml" <<'EOF'
services:
  probe:
    image: docker:29.9.0-cli
    entrypoint: ["sh", "-c", "ls /data; echo pg=$$PG; exec sleep 3600"]
    environment:
      PG: ${POSTGRES_PASSWORD:?missing}
    volumes:
      - ${CARDEA_KB:-./kb}:/data
  tunnel:
    image: docker:29.9.0-cli
    profiles: [tunnel]
    entrypoint: ["sh", "-c", "exec sleep 3600"]
EOF
sed -e "s|yuzuholic/cardea:latest|$IMAGE|" -e "s|^name: cardea|name: $PROJECT-outer|" \
    -e "s|      - ./kb:/kb:ro|      - ./kb:/kb:ro\n      - ./inner.yml:/cardea/compose.yml:ro|" \
    -e "s|    environment:|    environment:\n      CARDEA_PROJECT: $PROJECT|" nas/compose.yml > "$work/compose.yml"

wait_for() { i=0; until docker ps --format '{{.Names}}' | grep -q "$1"; do i=$((i+1)); [ $i -lt 60 ] || return 1; sleep 1; done; }

(cd "$work" && docker compose up -d >/dev/null 2>&1) || fail "launcher did not start"
wait_for "$PROJECT-probe" || fail "launcher never started the stack"
docker logs "$PROJECT-probe-1" 2>&1 | grep -q 'n.md' || fail "notes folder isn't mounted"
docker logs "$PROJECT-probe-1" 2>&1 | grep -q 'pg=dummy-POSTGRES_PASSWORD' || fail "settings don't reach the stack"
[ "$(docker inspect -f '{{range .Mounts}}{{.Source}}{{end}}' "$PROJECT-probe-1")" = "$work/kb" ] || fail "notes mount isn't the host path"
docker ps --format '{{.Names}}' | grep -q "$PROJECT-tunnel" && fail "tunnel started without a token"

sed -i.bak 's/^CLOUDFLARE_TUNNEL_TOKEN=.*/CLOUDFLARE_TUNNEL_TOKEN=tok/' "$work/.env"
(cd "$work" && docker compose up -d >/dev/null 2>&1) || fail "launcher did not restart after a .env change"
wait_for "$PROJECT-tunnel" || fail "tunnel didn't start once a token was set"

(cd "$work" && docker compose stop >/dev/null 2>&1)
docker ps --format '{{.Names}}' | grep -q "$PROJECT-probe" && fail "stopping the launcher left the stack running"

echo "ok: launcher builds, renders, starts, applies .env changes and stops"

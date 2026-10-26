#!/bin/sh
# cardea launcher — runs the lab stack (lab/docker-compose.yml, baked in at /cardea) on the
# docker engine whose socket is mounted here. the services run as normal sibling
# containers on the host; this container only starts them, and stops them when it stops.
# settings arrive as this container's environment (see ../compose.yml).
set -eu

PROJECT="${CARDEA_PROJECT:-lab}"

# the engine runs on the host, so the stack's notes mount needs the host path of kb/, not
# a path in here. read it off our own /kb mount.
if [ -z "${CARDEA_KB:-}" ]; then
  CARDEA_KB=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/kb"}}{{.Source}}{{end}}{{end}}' "$(hostname)" 2>/dev/null || true)
fi
[ -n "$CARDEA_KB" ] || { echo "cardea: mount your notes folder at /kb" >&2; exit 1; }
export CARDEA_KB

# the tunnel is optional; without a token, cloudflared is left out entirely.
PROFILES=""
[ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] && PROFILES="--profile tunnel"

compose() {
  # shellcheck disable=SC2086
  docker compose -p "$PROJECT" -f /cardea/compose.yml $PROFILES "$@"
}

stop() {
  echo "cardea: stopping $PROJECT"
  compose stop
  exit 0
}
trap stop TERM INT

echo "cardea: starting $PROJECT (notes at $CARDEA_KB${PROFILES:+, tunnel on})"
compose up -d --remove-orphans
# idle until docker stops us; the trap above takes the stack down with it.
tail -f /dev/null &
wait $!

#!/bin/sh
# cardea launcher — runs the lab stack (lab/docker-compose.yml, baked in at /cardea) on the
# docker engine whose socket is mounted here. the services run as normal sibling
# containers on the host; this container only starts them, and stops them when it stops.
# settings arrive as this container's environment (see ../compose.yml).
set -eu

PROJECT="${CARDEA_PROJECT:-lab}"

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

echo "cardea: starting $PROJECT${PROFILES:+ (tunnel on)}"
compose up -d --remove-orphans
# idle until docker stops us; the trap above takes the stack down with it.
tail -f /dev/null &
wait $!

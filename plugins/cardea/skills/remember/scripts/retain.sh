#!/bin/sh
# retain.sh [--bank <bank>] [--tag <tag>]... <text>
# saves one memory to Hindsight over REST, no model involved, and prints the operation id.
# the server is HINDSIGHT_URL, else NAS_URL on port 8888. the REST API takes no token.
set -eu

bank=cardea
tags='[]'

while [ $# -gt 0 ]; do
  case $1 in
    --bank) bank=${2:?--bank needs a value}; shift 2 ;;
    --tag) tags=$(printf '%s' "$tags" | jq -c --arg t "${2:?--tag needs a value}" '. + [$t]'); shift 2 ;;
    *) break ;;
  esac
done

[ $# -ge 1 ] || { echo "usage: retain.sh [--bank <bank>] [--tag <tag>]... <text>" >&2; exit 2; }
text=$*

url=${HINDSIGHT_URL:-}
[ -n "$url" ] || url=$(printf '%s' "${NAS_URL:-}" | sed -n 's|^\([a-z]*://[^/:]*\).*|\1:8888|p')
[ -n "$url" ] || { echo "set HINDSIGHT_URL (for example http://truenas.local:8888)" >&2; exit 2; }

body=$(jq -nc --arg c "$text" --argjson t "$tags" '{async: true, items: [{content: $c, tags: $t}]}')
resp=$(curl -fsS -X POST "$url/v1/default/banks/$bank/memories" -H 'Content-Type: application/json' -d "$body")

printf '%s' "$resp" | jq -r '.operation_id // empty' | grep . || { echo "no operation id: $resp" >&2; exit 1; }

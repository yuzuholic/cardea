#!/bin/sh
# usage: start.sh <summary-file> <title> [claude args...]
# opens a tab in the caller's workspace and folder, starts claude there with the given args,
# names the session <title>, sends the summary and prints the new session's reply. the caller
# closes its own pane only after reading that reply.
set -eu
summary=$1
title=$2
shift 2
name="handoff-$(date +%H%M%S)"
field() { python3 -c 'import json, sys; print(json.load(sys.stdin)["result"][sys.argv[1]][sys.argv[2]])' "$1" "$2"; }

cwd=$(herdr pane get "$HERDR_PANE_ID" | field pane cwd)
pane=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$cwd" --label "$title" --no-focus | field root_pane pane_id)

if ! herdr agent start "$name" --kind claude --pane "$pane" --timeout 60000 -- "$@" >/dev/null 2>&1; then
  screen=$(herdr pane read "$pane" --source visible)

  # the old session already works in this folder, so trusting it grants nothing new.
  case $screen in
    *"Yes, I trust this folder"*)
      herdr agent send-keys "$name" down enter >/dev/null
      herdr agent wait "$name" --until idle --timeout 60000 >/dev/null ;;
    *)
      printf '%s\n' "$screen"
      echo "handoff stopped: the new session in pane $pane is blocked at startup; nothing was sent" >&2
      exit 1 ;;
  esac
fi

herdr agent prompt "$name" "/rename $title" >/dev/null
herdr agent prompt "$name" "$(cat "$summary")" --wait --timeout 600000 >/dev/null

herdr agent read "$name" --source recent-unwrapped --lines 120
echo "new session: $name in pane $pane"

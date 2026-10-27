#!/bin/sh
# the plugin's hooks, fed sample hook input: secrets and bad commit messages are denied, the
# rest pass silently, the web nudge shows once per session, and the session note survives an
# unreachable basic memory. tests/fakes/nas.py stands in for basic memory. needs python3, git.
set -eu
cd "$(dirname "$0")/.."
HOOK=plugins/cardea/hooks/hook.py
PORT=8767

fail() { echo "FAIL: $*" >&2; [ -z "${out:-}" ] || echo "--- output: $out" >&2; exit 1; }
for t in python3 git curl; do command -v "$t" >/dev/null || fail "$t is not installed"; done

work=$(mktemp -d)
python3 tests/fakes/nas.py "$PORT" & nas=$!
trap 'kill "$nas" 2>/dev/null || true; wait "$nas" 2>/dev/null || true; rm -rf "$work"' EXIT
tries=0
until curl -s -o /dev/null "http://127.0.0.1:$PORT/api/public/health"; do
  tries=$((tries + 1)); [ "$tries" -lt 50 ] || fail "the fake NAS did not start"; sleep 0.1
done

# run <hook> <stdin json>: the hook's stdout lands in $out; a non-zero exit fails the test.
run() { out=$(printf '%s' "$2" | env HOME="$work/home" CLAUDE_PLUGIN_DATA="$work/data" python3 -I "$HOOK" "$1") || fail "$1 exited non-zero"; }
tool() { python3 -c 'import json,sys; print(json.dumps({"session_id": sys.argv[1], "tool_name": sys.argv[2], "tool_input": {sys.argv[3]: sys.argv[4]}}))' "$@"; }
denied()  { run "$1" "$2"; case $out in *'"permissionDecision": "deny"'*) ;; *) fail "$1 should deny: $2" ;; esac; }
allowed() { run "$1" "$2"; [ -z "$out" ] || fail "$1 should stay silent: $2"; }
says()    { case $out in *"$1"*) ;; *) fail "output should mention: $1" ;; esac; }

# secrets: files by tool, then the obvious bash readers.
for f in .env .env.local .env.production id_rsa id_ed25519 server.pem cert.p12 tls.key AuthKey_ABC.p8; do
  denied secrets "$(tool s Read file_path "/repo/$f")"
done
says 'environment variables only'
for f in .env.example .env.sample .env.template id_rsa.pub README.md; do
  allowed secrets "$(tool s Read file_path "/repo/$f")"
done
denied secrets "$(tool s Grep path /repo/.env)"
denied secrets "$(tool s Edit file_path /repo/.env.local)"
for c in 'cat .env' 'less .env.local' 'head -5 .env.production' 'tail -f .env' 'grep KEY .env' \
         "sed -n 1p .env" "awk '{print}' .env" 'bat .env' 'source .env' '. ./.env' 'cp .env /dev/stdout' \
         'cat < .env' 'echo "$(cat .env)"' 'cd app && cat ~/.ssh/id_ed25519' 'cat .env*' 'sudo cat /etc/ssl/server.key' \
         'FOO=1 head "config/.env"'; do
  denied secrets "$(tool s Bash command "$c")"
done
for c in 'cat .env.example' 'ls -la' 'cat ~/.ssh/id_rsa.pub' 'cp .env.example .env' 'source .venv/bin/activate' \
         'git status' 'echo .env' 'grep -r TODO src'; do
  allowed secrets "$(tool s Bash command "$c")"
done

# commit: the user's one-line format, inline messages only.
for c in 'git commit -m "feat: add session hooks"' "git commit -m 'fix: handle a missing project'" \
         'git add -A && git commit -m "chore: bump version to 0.3.0" && git log -1' 'git commit -am "docs: fix typo"' \
         "git commit -m \"\$(cat <<'EOF'
test: cover the hooks
EOF
)\"" "git commit -F - <<'EOF'
ci: run the hook tests
EOF" 'git commit' 'git commit --amend --no-edit' 'git commit -m "$MSG"' 'git status' 'git -C repo commit -m "perf: skip a query"' \
         "git commit -m \"feat: $(printf 'x%.0s' $(seq 65))\""; do
  allowed commit "$(tool s Bash command "$c")"
done
# denied <expected phrase> <command>
deny_commit() { denied commit "$(tool s Bash command "$2")"; says "$1"; }
deny_commit '\"Feat\" is not a type' 'git commit -m "Feat: add hooks"'
deny_commit '\"feature\" is not a type' 'git commit -m "feature: add hooks"'
deny_commit 'is not \"<type>: <subject>\"' 'git commit -m "add hooks"'
deny_commit 'drop the scope' 'git commit -m "feat(ui): add hooks"'
deny_commit 'drop the scope or \"!\"' 'git commit -m "feat!: add hooks"'
deny_commit 'lowercase letter' 'git commit -m "feat: Add hooks"'
deny_commit 'trailing period' "git commit -m 'feat: add hooks.'"
deny_commit 'is 73 characters' "git commit -m \"feat: $(printf 'x%.0s' $(seq 67))\""
deny_commit 'remove the body' 'git commit -m "feat: add hooks" -m "they help"'
deny_commit 'remove the trailers' "git commit -m \"\$(cat <<'EOF'
feat: add hooks

Co-Authored-By: Someone <a@b.c>
EOF
)\""
deny_commit 'remove the body' "git commit -F - <<'EOF'
fix: stop the loop

it spun forever
EOF"
deny_commit 'trailing period' 'git add . && git commit -m "fix: x."'
python3 -c 'import json,sys; json.loads(sys.argv[1])' "$out" || fail "the deny output is not JSON"

# web: once per session, and stale state is pruned.
mkdir -p "$work/data/web-nudged"; touch -t 202001010000 "$work/data/web-nudged/old-session"
run web "$(tool one WebSearch query 'grdb observation')"; says 'retrieval-order'
[ ! -e "$work/data/web-nudged/old-session" ] || fail "stale web state was not pruned"
allowed web "$(tool one WebFetch url https://example.com)"
run web "$(tool two WebFetch url https://example.com)"; says 'once per session'

# session: a repo with a project and graphify-out, a worktree of it, one without a project,
# then basic memory unreachable and not configured.
mkdir -p "$work/home" "$work/Demo/graphify-out" "$work/Other"
for r in Demo Other; do git -C "$work/$r" init -q; done
git -C "$work/Demo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m 'chore: init'
git -C "$work/Demo" worktree add -q "$work/demo-wt" 2>/dev/null
cfg() { printf '{"mcpServers": {"basic-memory": {"type": "http", "url": "%s"}}}' "$1" > "$work/home/.claude.json"; }
session() { out=$(printf '{"source": "startup"}' | env HOME="$work/home" CLAUDE_PROJECT_DIR="$1" python3 -I "$HOOK" session) || fail "session exited non-zero"; }
cfg "http://127.0.0.1:$PORT/mcp"
session "$work/Demo"
says 'project for this repo: \"demo\"'; says 'graphify-out/ exists'; says 'Use CRDTs for sync'; says 'retrieval-order skill'
[ "$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])["hookSpecificOutput"]["additionalContext"].splitlines()))' "$out")" -le 15 ] || fail "the session note is over 15 lines"
session "$work/demo-wt"; says 'project for this repo: \"demo\"'
session "$work/Other"; says 'no project \"other\"'; says 'No graphify-out/'
cfg http://127.0.0.1:1/mcp
session "$work/Demo"; says 'unreachable'; says 'project for this repo: \"demo\"'
rm "$work/home/.claude.json"
session "$work/Demo"; says "isn't configured"

# every hook fails open on input it can't read.
for h in session secrets commit web; do allowed "$h" 'not json'; done

echo "ok: hooks pass"

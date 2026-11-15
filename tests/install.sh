#!/bin/sh
# install.sh end to end, against stand-ins: brew, claude and herdr in
# tests/fakes log their arguments instead of installing anything, and tests/fakes/nas.py
# answers for basic memory and langfuse on 127.0.0.1:8766. every case runs with the plain
# prompts, then again with gum when gum is installed. needs expect, python3, curl, git.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
NAS=http://127.0.0.1:8766

out=''
fail() {
  echo "FAIL: $*" >&2
  if [ -n "$out" ] && [ -f "$out" ]; then echo "--- last output:" >&2; tail -40 "$out" >&2; fi
  exit 1
}
for t in expect python3 curl git; do command -v "$t" >/dev/null || fail "$t is not installed"; done

work=$(mktemp -d)
python3 tests/fakes/nas.py 8766 & nas=$!
trap 'kill "$nas" 2>/dev/null || true; wait "$nas" 2>/dev/null || true; rm -rf "$work"' EXIT
tries=0
until curl -s -o /dev/null "$NAS/api/public/health"; do
  tries=$((tries + 1)); [ "$tries" -lt 50 ] || fail "the fake NAS did not start"; sleep 0.1
done
kill -0 "$nas" 2>/dev/null || fail "127.0.0.1:8766 is taken by something else"

MODES=plain
GUM=$(command -v gum || true)
if [ -n "$GUM" ]; then
  MODES='plain gum'; mkdir "$work/gumbin"; ln -s "$GUM" "$work/gumbin/gum"
else
  echo "note: gum is not installed, so only the plain prompts are tested"
fi
SYS=/usr/bin:/bin:/usr/sbin:/sbin
# plain mode means "gum isn't installed yet", which a system-wide gum makes untestable.
! PATH=$SYS command -v gum >/dev/null || fail "gum is in a system directory; install it elsewhere so plain mode can run without it"
ESC=$(printf '\033')

# setup <case> <mode>: a minimal copy of the repo, a scratch HOME, and this mode's PATH.
setup() {
  name="$1/$2"; mode=$2
  dir="$work/$1-$2"; mkdir -p "$dir/repo" "$dir/home"
  cp install.sh Brewfile .env.example "$dir/repo/"; cp -R claude scripts "$dir/repo/"
  log="$dir/fake.log"; out="$dir/out"; : > "$log"
  P="$ROOT/tests/fakes:$SYS"
  [ "$mode" = plain ] || P="$ROOT/tests/fakes:$work/gumbin:$SYS"
}
# run <command...>: in the copy, with the fakes and the scratch HOME. output goes to $out.
run() {
  (cd "$dir/repo" && unset NO_COLOR BASIC_MEMORY_URL LANGFUSE_HOST LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY &&
    exec env FAKE_LOG="$log" HOME="$dir/home" PATH="$P" SHELL=/bin/zsh \
    TERM=xterm-256color "$@") > "$out" 2>&1
}
# drive <answer>...: install.sh on a terminal, answering its prompts in order.
drive() {
  if [ "$mode" = gum ]; then run env GUM=1 expect "$ROOT/tests/install.exp" "$@"
  else run expect "$ROOT/tests/install.exp" "$@"; fi
}
# term <command> [VAR=value...]: any shell command on a terminal, no prompts expected.
term() { t_cmd=$1; shift; run env CMD="$t_cmd" "$@" expect "$ROOT/tests/install.exp"; }

has_env() { grep -qx "$1=$2" "$dir/repo/.env" || fail "$name: .env should hold $1=$2, has '$(grep "^$1=" "$dir/repo/.env" || true)'"; }
said()    { grep -aqF -- "$1" "$out" || fail "$name: output should mention: $1"; }
unsaid()  { ! grep -aqF -- "$1" "$out" || fail "$name: output should not contain: $1"; }
called()  { grep -qF -- "$1" "$log" || fail "$name: expected a call: $1"; }
uncalled() { ! grep -qF -- "$1" "$log" || fail "$name: unexpected call: $1"; }
calls()   { [ "$(grep -cF -- "$1" "$log")" -eq "$2" ] || fail "$name: expected $2 calls of '$1', got $(grep -cF -- "$1" "$log")"; }
# the work a full run does: four mcp servers, the plugins, the vendored skills, the rules link.
installed() {
  calls 'mcp add-json -s user' 4
  called "claude plugin install langfuse-observability --marketplace langfuse/Claude-Observability-Plugin -y"
  called "claude plugin install cardea --marketplace $dir/repo -y"
  for m in superpowers:obra/superpowers-marketplace ponytail:DietrichGebert/ponytail \
           apple-skills:Prisma-Labs-Dev/apple-skills cloudflare:cloudflare/skills humanizer:blader/humanizer axe:cameroncooke/AXe; do
    called "claude plugin install ${m%%:*} --marketplace ${m#*:} -y"
  done
  called 'uv tool install graphifyy==0.9.88'
  called 'npm install -g @playwright/cli@0.1.24'
  called 'playwright-cli install-browser chromium'
  for s in herdr graphify playwright-cli; do
    grep -qx "name: $s" "$dir/home/.claude/skills/$s/SKILL.md" 2>/dev/null || fail "$name: the $s skill wasn't installed"
  done
  called "plugin configure langfuse-observability@langfuse-observability --values-stdin <<< {\"LANGFUSE_BASE_URL\":\"$1\""
  [ "$(readlink "$dir/home/.claude/CLAUDE.md")" = "$dir/repo/claude/CLAUDE.md" ] || fail "$name: ~/.claude/CLAUDE.md is not linked to the repo"
  [ "$(readlink "$dir/home/.claude/skills/tldr")" = "$dir/repo/claude/skills/tldr" ] || fail "$name: ~/.claude/skills/tldr is not linked to the repo"
  [ "$(readlink "$dir/home/.claude/skills/baby")" = "$dir/repo/claude/skills/baby" ] || fail "$name: ~/.claude/skills/baby is not linked to the repo"
  grep -q '"CLAUDE_CODE_ENABLE_TODO_TOOLS": "1"' "$dir/home/.claude/settings.json" 2>/dev/null || fail "$name: the task list was not turned on in ~/.claude/settings.json"
  settings_has "$dir/home/.claude/settings.json"
  said 'claude auth login'
}
# the read-only basic memory tools are allowed once each, and the write tools are not.
settings_has() {
  for t in search_notes read_note build_context recent_activity list_directory list_memory_projects; do
    [ "$(grep -c "\"mcp__basic-memory__$t\"" "$1")" -eq 1 ] || fail "$name: $t should be allowed exactly once in $1"
  done
  ! grep -q 'mcp__basic-memory__\(write\|edit\|move\|delete\)_note' "$1" || fail "$name: a basic memory write tool is allowed"
}
# gum drew the prompts in gum mode, and never in plain mode.
prompted_by() {
  if [ "$mode" = gum ]; then said '›'; else unsaid '›'; fi
}

sh -n install.sh || fail "install.sh has a syntax error"

for mode in $MODES; do
  # a bare ip gets the default's port and path; langfuse defaults to the same host.
  # nothing serves langfuse on :3000 here, so its retry is ended and kept untested.
  setup bare-ip "$mode"
  drive 127.0.0.1 "" || fail "$name: exited non-zero"
  has_env BASIC_MEMORY_URL "$NAS/mcp"
  has_env LANGFUSE_HOST http://127.0.0.1:3000
  said "speaks MCP: fake-nas 1"
  prompted_by
  installed http://127.0.0.1:3000
  called "basic-memory {\"type\":\"http\",\"url\":\"$NAS/mcp\"}"

  # a bad port, enter twice (each retries), then the bare ip recovers. keys are hidden.
  setup retry "$mode"
  drive 127.0.0.1:1 "" "" 127.0.0.1 "$NAS" pk-visible-test sk-hidden-test || fail "$name: exited non-zero"
  [ "$(grep -c 'testing http://127.0.0.1:1/mcp' "$out")" -eq 3 ] || fail "$name: expected the bad url to be tested 3 times"
  has_env BASIC_MEMORY_URL "$NAS/mcp"
  has_env LANGFUSE_HOST "$NAS"
  said "langfuse url — healthy"
  has_env LANGFUSE_PUBLIC_KEY pk-visible-test
  has_env LANGFUSE_SECRET_KEY sk-hidden-test
  unsaid pk-visible-test
  unsaid sk-hidden-test
  [ "$(ls -l "$dir/repo/.env" | cut -c1-10)" = '-rw-------' ] || fail "$name: .env is not mode 600"

  # a rerun where enter keeps every existing value, keys included.
  drive "" "" "" "" || fail "$name (rerun): exited non-zero"
  has_env BASIC_MEMORY_URL "$NAS/mcp"
  has_env LANGFUSE_SECRET_KEY sk-hidden-test
  # gum splits its placeholder around the cursor, so check its summary line instead.
  if [ "$mode" = gum ]; then said 'kept'; else said '[keep existing]'; fi

  # a stray paste saved in .env neither runs as a command nor is offered back, and a
  # pasted value with spaces is asked again.
  setup stray "$mode"
  printf 'BASIC_MEMORY_URL=%s/mcp\nLANGFUSE_HOST=%s\nLANGFUSE_PUBLIC_KEY=# Persona: x\nnot a setting\n' "$NAS" "$NAS" > "$dir/repo/.env"
  drive "" "" "pk with spaces" pk-ok sk-ok || fail "$name: exited non-zero"
  unsaid 'command not found'
  said "the saved langfuse public key isn't a key"
  said 'that has spaces'
  has_env LANGFUSE_PUBLIC_KEY pk-ok
  has_env LANGFUSE_SECRET_KEY sk-ok

  # a bad langfuse address, then skip keeps it untested.
  setup skip "$mode"
  drive 127.0.0.1 127.0.0.1:1 skip || fail "$name: exited non-zero"
  has_env LANGFUSE_HOST http://127.0.0.1:1
  said "keeping http://127.0.0.1:1 untested"

  # the end key (ctrl-d, or esc in gum) stops the retry loop instead of spinning.
  setup end-key "$mode"
  drive 127.0.0.1:1 || fail "$name: exited non-zero"
  has_env BASIC_MEMORY_URL http://127.0.0.1:1/mcp
  said "keeping http://127.0.0.1:1/mcp untested"

  # --no-prompt on a terminal asks nothing and finishes.
  setup no-prompt "$mode"
  term 'sh install.sh --no-prompt' || fail "$name: exited non-zero"
  said '.env created with placeholder values (mode 600)'
  has_env BASIC_MEMORY_URL http://truenas.local:8766/mcp
  installed http://truenas.local:3000
  said 'running 12 jobs in parallel'
  said '~/.local/bin is not on PATH'
  grep -ao '[0-9]* ok ' "$out" | head -1 > "$work/ok-$mode"
  # without gum the jobs print one line each, and nothing moves the cursor or hides it.
  if [ "$mode" = plain ]; then unsaid "$ESC[?25"; unsaid "${ESC}[2K"; fi

  # an existing settings.json keeps its other keys and env entries.
  setup settings "$mode"
  mkdir -p "$dir/home/.claude"
  printf '{"model":"x","env":{"A":"1"}}' > "$dir/home/.claude/settings.json"
  term 'sh install.sh --no-prompt' || fail "$name: exited non-zero"
  installed http://truenas.local:3000
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(not (d["model"]=="x" and d["env"]["A"]=="1"))' "$dir/home/.claude/settings.json" || fail "$name: settings.json lost its other keys"

  # a second run keeps the allow list free of duplicates (installed counts each rule once).
  term 'sh install.sh --no-prompt' || fail "$name: second run exited non-zero"
  settings_has "$dir/home/.claude/settings.json"
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("agent",""))' "$dir/home/.claude/settings.json")" = "" ] || fail "$name: --no-prompt set the agent"

  # the default agent: yes sets it, no removes the cardea value and keeps a foreign one.
  agent() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("agent",""))' "$dir/home/.claude/settings.json"; }
  setup agent-yes "$mode"
  drive "" "" "" "" n y || fail "$name: exited non-zero"
  [ "$(agent)" = cardea:orchestrator ] || fail "$name: yes should set the agent, has '$(agent)'"
  TAGLINE='export CC_LANGFUSE_TRACE_TAGS="${CC_LANGFUSE_TRACE_TAGS:-agent:cardea:orchestrator}"'
  ENVLINE='export LANGFUSE_TRACING_ENVIRONMENT="${LANGFUSE_TRACING_ENVIRONMENT:-agent-orchestrator}"'
  [ "$(grep -cxF "$TAGLINE" "$dir/home/.zshrc")" -eq 1 ] && [ "$(grep -cxF "$ENVLINE" "$dir/home/.zshrc")" -eq 1 ] || fail "$name: yes should add the Langfuse label lines to ~/.zshrc once"
  [ "$(grep -c '^# label hand-started' "$dir/home/.zshrc")" -eq 1 ] || fail "$name: yes should add the comment once"
  said 'Langfuse agent label set in ~/.zshrc'
  drive "" "" "" "" n y || fail "$name (rerun): exited non-zero"
  [ "$(grep -cxF "$TAGLINE" "$dir/home/.zshrc")" -eq 1 ] && [ "$(grep -cxF "$ENVLINE" "$dir/home/.zshrc")" -eq 1 ] && [ "$(grep -c '^# label hand-started' "$dir/home/.zshrc")" -eq 1 ] || fail "$name (rerun): the Langfuse label lines were added again"
  setup agent-no "$mode"
  mkdir -p "$dir/home/.claude"; printf '{"agent":"cardea:orchestrator"}' > "$dir/home/.claude/settings.json"
  printf 'alias keep=true\n# label hand-started claude sessions in Langfuse\n%s\n%s\n' "$TAGLINE" "$ENVLINE" > "$dir/home/.zshrc"
  drive "" "" "" "" n n || fail "$name: exited non-zero"
  [ -z "$(agent)" ] || fail "$name: no should remove the cardea agent, has '$(agent)'"
  [ "$(cat "$dir/home/.zshrc")" = 'alias keep=true' ] || fail "$name: no should remove only the Langfuse label lines, has '$(cat "$dir/home/.zshrc")'"
  setup agent-noprompt "$mode"
  printf 'alias keep=true\n%s\n' "$TAGLINE" > "$dir/home/.zshrc"
  term 'sh install.sh --no-prompt' || fail "$name: exited non-zero"
  [ "$(cat "$dir/home/.zshrc")" = "alias keep=true
$TAGLINE" ] || fail "$name: --no-prompt changed the profile"
  setup agent-foreign "$mode"
  mkdir -p "$dir/home/.claude"; printf '{"agent":"other:agent"}' > "$dir/home/.claude/settings.json"
  drive "" "" "" "" n n || fail "$name: exited non-zero"
  [ "$(agent)" = other:agent ] || fail "$name: no should keep a foreign agent, has '$(agent)'"

  # curl | sh: the script arrives on stdin and brew reads stdin.
  setup pipe "$mode"
  term 'cat install.sh | sh -s -- --no-prompt' EAT_STDIN=1 || fail "$name: exited non-zero"
  called 'brew bundle'
  installed http://truenas.local:3000

  # one failing job is reported with its log, the others still finish, and the run exits non-zero.
  setup job-fail "$mode"
  if term 'sh install.sh --no-prompt' FAKE_FAIL='plugin install ponytail'; then fail "$name: a failed job should fail the run"; fi
  said 'plugin ponytail'
  said 'simulated failure for: plugin install ponytail'
  called 'plugin install humanizer'
  called 'plugin install cloudflare'
  calls 'mcp add-json -s user' 4
  said 'failed'

  # a plugin install that "succeeds" without being recorded is found and redone, and says so.
  setup lost-plugin "$mode"
  term 'sh install.sh --no-prompt' FAKE_LOST='plugin install ponytail' || fail "$name: exited non-zero"
  calls 'plugin install ponytail' 2
  said 'plugin ponytail: a concurrent write was lost and repaired'
  installed http://truenas.local:3000

  # the same for an MCP server, and a server that fails its health check is named.
  setup lost-mcp "$mode"
  term 'sh install.sh --no-prompt' FAKE_LOST='mcp add-json -s user swiftlens' FAKE_MCP_DOWN=xcode || fail "$name: exited non-zero"
  calls 'mcp add-json -s user swiftlens' 2
  said 'mcp swiftlens: a concurrent write was lost and repaired'
  said 'xcodebuild — connected'
  said 'xcode — failed to connect'

  # still missing after the retry is a failure.
  setup lost-always "$mode"
  if term 'sh install.sh --no-prompt' FAKE_LOST='plugin install ponytail' FAKE_LOST_ALWAYS=1; then fail "$name: an unrecorded plugin should fail the run"; fi
  said 'plugin ponytail: not recorded, even after a retry'

  # a missing required tool fails --check and is named in the summary; optional ones only note it.
  setup no-pnpm "$mode"
  mkdir "$dir/bin"
  for f in "$ROOT"/tests/fakes/*; do [ "${f##*/}" = pnpm ] || ln -s "$f" "$dir/bin/${f##*/}"; done
  P="$dir/bin:$SYS"; [ "$mode" = plain ] || P="$dir/bin:$work/gumbin:$SYS"
  if term 'sh install.sh --check'; then fail "$name: --check should fail without pnpm"; fi
  said 'not installed: pnpm'
  said 'docker — optional, not installed'

  # --check probes and changes nothing.
  setup check "$mode"
  term 'sh install.sh --check' || fail "$name: exited non-zero"
  [ ! -e "$dir/repo/.env" ] || fail "$name: --check wrote .env"
  [ ! -e "$dir/home/.claude" ] || fail "$name: --check touched ~/.claude"
  uncalled 'brew bundle'; uncalled 'add-json'; uncalled 'mcp remove'; uncalled 'plugin install'; uncalled 'herdr integration'
  said 'basic memory — not configured'
  unsaid 'add ~/.local/bin to PATH'
  [ ! -e "$dir/home/.zshrc" ] || fail "$name: --check wrote a shell profile"

  # a .local address draws the mDNS warning in --check; an ip address does not.
  setup mdns-local "$mode"
  printf 'BASIC_MEMORY_URL=http://truenas.local:8766/mcp\nLANGFUSE_HOST=http://truenas.local:3000\n' > "$dir/repo/.env"
  term 'sh install.sh --check' || true
  said 'can stall for seconds'

  setup mdns-ip "$mode"
  printf 'BASIC_MEMORY_URL=http://192.0.2.10:8766/mcp\nLANGFUSE_HOST=http://192.0.2.10:3000\n' > "$dir/repo/.env"
  term 'sh install.sh --check' || true
  unsaid 'can stall for seconds'

  # a fixable warning is offered at the end: yes appends the profile line once, a rerun keeps it
  # at one, no leaves the profile alone, and runs that cannot ask change nothing.
  setup fix-yes "$mode"
  printf 'BASIC_MEMORY_URL=%s/mcp\nLANGFUSE_HOST=%s\nLANGFUSE_PUBLIC_KEY=pk\nLANGFUSE_SECRET_KEY=sk\n' "$NAS" "$NAS" > "$dir/repo/.env"
  PATHLINE='export PATH="$HOME/.local/bin:$PATH"'
  drive "" "" "" "" y || fail "$name: exited non-zero"
  said 'add ~/.local/bin to PATH in ~/.zshrc?'
  said '~/.local/bin on PATH, set in ~/.zshrc'
  [ "$(grep -cxF "$PATHLINE" "$dir/home/.zshrc")" -eq 1 ] || fail "$name: ~/.zshrc should hold the PATH line once"
  drive "" "" "" "" y || fail "$name (rerun): exited non-zero"
  [ "$(grep -cxF "$PATHLINE" "$dir/home/.zshrc")" -eq 1 ] || fail "$name (rerun): the PATH line was appended again"

  setup fix-no "$mode"
  printf 'BASIC_MEMORY_URL=%s/mcp\nLANGFUSE_HOST=%s\nLANGFUSE_PUBLIC_KEY=pk\nLANGFUSE_SECRET_KEY=sk\n' "$NAS" "$NAS" > "$dir/repo/.env"
  drive "" "" "" "" n || fail "$name: exited non-zero"
  said 'add ~/.local/bin to PATH in ~/.zshrc?'
  said '~/.local/bin is not on PATH'
  [ ! -e "$dir/home/.zshrc" ] || fail "$name: answering no still wrote ~/.zshrc"

  setup fix-no-prompt "$mode"
  term 'sh install.sh --no-prompt' || fail "$name: exited non-zero"
  unsaid 'add ~/.local/bin to PATH'
  [ ! -e "$dir/home/.zshrc" ] || fail "$name: --no-prompt wrote ~/.zshrc"
done

# the same run counts the same number of ok lines with and without gum.
[ -z "$GUM" ] || [ "$(cat "$work/ok-plain")" = "$(cat "$work/ok-gum")" ] || fail "ok counts differ: plain $(cat "$work/ok-plain"), gum $(cat "$work/ok-gum")"

# no terminal at all (curl | sh from a script): plain output, no colour, still completes.
setup no-tty plain
P="$ROOT/tests/fakes:$work/gumbin:$SYS"
run env EAT_STDIN=1 sh -c 'cat install.sh | sh -s -- --no-prompt' < /dev/null || fail "$name: exited non-zero"
installed http://truenas.local:3000
unsaid "$ESC"
said '✓ plugin ponytail'
said ' ok '

if [ -n "$GUM" ]; then
  # NO_COLOR turns gum off too.
  setup no-color gum
  term 'NO_COLOR=1 sh install.sh --no-prompt' || fail "$name: exited non-zero"
  installed http://truenas.local:3000
  unsaid "$ESC"

  # a fresh mac: no gum until the Brewfile runs, then gum for the rest of the run.
  setup bootstrap plain
  mkdir "$dir/late"; P="$ROOT/tests/fakes:$dir/late:$SYS"
  mode=gum; FAKE_GUM=$GUM; FAKE_GUM_DIR="$dir/late"; export FAKE_GUM FAKE_GUM_DIR
  drive 127.0.0.1 "" || fail "$name: exited non-zero"
  unset FAKE_GUM FAKE_GUM_DIR
  [ -x "$dir/late/gum" ] || fail "$name: the fake bundle did not provide gum"
  said '›'
  has_env BASIC_MEMORY_URL "$NAS/mcp"
fi

echo "ok: install.sh cases pass (${MODES})"

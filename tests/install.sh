#!/bin/sh
# install.sh end to end, against stand-ins: brew, claude, herdr and plannotator in
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
    exec env FAKE_LOG="$log" HOME="$dir/home" PATH="$P" \
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
# the work a full run does: five mcp servers, the plugins, the vendored skills, the rules link.
installed() {
  calls 'mcp add-json -s user' 5
  called "claude plugin install langfuse-observability --marketplace langfuse/Claude-Observability-Plugin -y"
  called "claude plugin install cardea --marketplace $dir/repo -y"
  # plannotator is already installed in the fake, so a run refreshes it instead.
  called "claude plugin update plannotator@plannotator"
  for m in superpowers:obra/superpowers-marketplace ponytail:DietrichGebert/ponytail \
           apple-skills:Prisma-Labs-Dev/apple-skills cloudflare:cloudflare/skills humanizer:blader/humanizer; do
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
  said 'claude auth login'
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
  said '.env created from the example'
  has_env BASIC_MEMORY_URL http://truenas.local:8766/mcp
  installed http://truenas.local:3000

  # an existing settings.json keeps its other keys and env entries.
  setup settings "$mode"
  mkdir -p "$dir/home/.claude"
  printf '{"model":"x","env":{"A":"1"}}' > "$dir/home/.claude/settings.json"
  term 'sh install.sh --no-prompt' || fail "$name: exited non-zero"
  installed http://truenas.local:3000
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(not (d["model"]=="x" and d["env"]["A"]=="1"))' "$dir/home/.claude/settings.json" || fail "$name: settings.json lost its other keys"

  # curl | sh: the script arrives on stdin and brew reads stdin.
  setup pipe "$mode"
  term 'cat install.sh | sh -s -- --no-prompt' EAT_STDIN=1 || fail "$name: exited non-zero"
  called 'brew bundle'
  installed http://truenas.local:3000

  # --check probes and changes nothing.
  setup check "$mode"
  term 'sh install.sh --check' || fail "$name: exited non-zero"
  [ ! -e "$dir/repo/.env" ] || fail "$name: --check wrote .env"
  [ ! -e "$dir/home/.claude" ] || fail "$name: --check touched ~/.claude"
  uncalled 'brew bundle'; uncalled 'add-json'; uncalled 'mcp remove'; uncalled 'plugin install'; uncalled 'herdr integration'
  said 'basic memory — not configured'
done

# no terminal at all (curl | sh from a script): plain output, no colour, still completes.
setup no-tty plain
P="$ROOT/tests/fakes:$work/gumbin:$SYS"
run env EAT_STDIN=1 sh -c 'cat install.sh | sh -s -- --no-prompt' < /dev/null || fail "$name: exited non-zero"
installed http://truenas.local:3000
unsaid "$ESC"

if [ -n "$GUM" ]; then
  # NO_COLOR turns gum off too.
  setup no-color gum
  term 'NO_COLOR=1 sh install.sh --no-prompt' || fail "$name: exited non-zero"
  installed http://truenas.local:3000
  unsaid "$ESC[38;"

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

#!/bin/sh
# cardea — install the agent stack.
#
#   ./install.sh                 interactive: prompts for urls and keys, then probes them
#   ./install.sh --no-prompt     keep whatever .env already holds, prompt for nothing
#   ./install.sh --check         probe the stack and exit, change nothing
#
# safe to run repeatedly. existing config is backed up, not overwritten.
set -eu

# under curl | sh the script arrives on stdin, and anything that reads stdin (brew)
# would eat the rest of it. a brace group is parsed whole before any of it runs.
{
REPO_URL="https://github.com/yuzuholic/cardea.git"
REPO_DIR="${CARDEA_HOME:-$HOME/Repositories/cardea}"
STAMP="$(date +%Y%m%d-%H%M%S)"

# --- ui --------------------------------------------------------------------
# colour only on a real terminal, and never when NO_COLOR is set.
FANCY=
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  FANCY=1
  B=$(printf '\033[1m');  D=$(printf '\033[2m');  R=$(printf '\033[0m')
  GRN=$(printf '\033[32m'); YEL=$(printf '\033[33m')
  RED=$(printf '\033[31m'); CYN=$(printf '\033[36m')
else
  B=''; D=''; R=''; GRN=''; YEL=''; RED=''; CYN=''
fi

# gum draws the ui when it is installed and there is a terminal to draw on. the printf
# lines are the fallback, and the only ui on a fresh mac until the Brewfile installs gum.
# checked on every call, so the run switches over as soon as gum appears.
has_gum() {
  [ -n "$FANCY" ] && [ "${TERM:-dumb}" != dumb ] && command -v gum >/dev/null 2>&1
}
# cardea's palette (eva unit-01). gum drops to 256 colours where truecolor is missing.
AMETHYST='#995CD0'; PLUMP='#5549B7'; INCHWORM='#8EDF5F'; MANDARIN='#EC7744'
# for $(...): gum leaves colour out when its output is not a terminal. callers put -- before
# the text (it may start with a dash), and stdin is closed because gum style reads it when
# the text is empty, and under curl | sh stdin is the rest of this script.
paint() { CLICOLOR_FORCE=1 gum style "$@" < /dev/null; }

banner() {
  if has_gum; then
    gum style --border rounded --border-foreground "$PLUMP" --padding '0 2' --margin '1 2' -- \
      "$(paint --bold --foreground "$INCHWORM" -- Cardea)  $(paint --faint -- '·  the hinge the gate swings on')"
    return 0
  fi
  printf '\n%s  ╭────────────────────────────────────────────╮%s\n' "$CYN" "$R"
  printf '%s  │%s  %sCardea%s  %s·  the hinge the gate swings on%s   %s│%s\n' \
    "$CYN" "$R" "$B" "$R" "$D" "$R" "$CYN" "$R"
  printf '%s  ╰────────────────────────────────────────────╯%s\n\n' "$CYN" "$R"
}
step() {
  if has_gum; then printf '\n%s %s\n' "$(paint --foreground "$AMETHYST" -- ▸)" "$(paint --bold -- "$1")"; return 0; fi
  printf '\n%s▸ %s%s\n' "$B" "$1" "$R"
}
# mark <gum colour> <glyph> <plain colour> <text>
mark() {
  if has_gum; then printf '  %s %s\n' "$(paint --foreground "$1" -- "$2")" "$4"; return 0; fi
  printf '  %s%s%s %s\n' "$3" "$2" "$R" "$4"
}
ok()   { mark "$INCHWORM" '✓' "$GRN" "$1"; }
info() {
  if has_gum; then printf '  %s\n' "$(paint --faint -- "· $1")"; return 0; fi
  printf '  %s·%s %s\n' "$D" "$R" "$1"
}
warn() { mark "$MANDARIN" '!' "$YEL" "$1"; }
bad()  { mark 1 '✗' "$RED" "$1"; }
die()  { printf '\n%scardea:%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }

# spin <title> <command...>: a spinner while it runs, its output shown only if it fails.
# returns the command's own exit status either way. gum hands its stdin to the command,
# so it gets none: under curl | sh stdin is the script, and the terminal would leave
# anything that reads it waiting on the keyboard behind the spinner.
spin() {
  s_title="$1"; shift
  if has_gum; then
    gum spin --spinner dot --spinner.foreground "$INCHWORM" --title " $s_title" --show-error -- "$@" < /dev/null
  else
    info "$s_title"; "$@"
  fi
}

# --- args ------------------------------------------------------------------
PROMPT=1; CHECK_ONLY=
while [ $# -gt 0 ]; do
  case "$1" in
    --no-prompt) PROMPT= ;;
    --check)     CHECK_ONLY=1; PROMPT= ;;
    -h|--help)   sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           die "unknown option '$1' (try --help)" ;;
  esac
  shift
done

# prompting needs a terminal of its own: stdin is the script when piped from curl.
if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
  [ -n "$PROMPT" ] && { PROMPT=; NOTTY=1; }
fi

banner

# --- locate the repo -------------------------------------------------------
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)"
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/claude/CLAUDE.md" ]; then
  REPO_DIR="$SELF_DIR"
elif [ -d "$REPO_DIR/.git" ]; then
  step "repo"; info "updating $REPO_DIR"
  # local edits make the pull refuse; install from what is on disk rather than stop.
  git -C "$REPO_DIR" pull --ff-only || warn "could not update — using the local copy as it is"
else
  step "repo"; info "cloning into $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --depth 1 "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR"
ENV_FILE="$REPO_DIR/.env"
# the user-scope MCP servers cardea owns; anything else in claude code is left alone.
MCP_NAMES='container-use|xcodebuild|swiftlens|xcode|basic-memory'

# --- probes ----------------------------------------------------------------
# any http status at all means something answered. an MCP endpoint may well reply
# 404/405/406 to a bare GET — that still proves the host and port are live.
# a reachable port proves very little, so each service is asked something it has to
# understand. these set REACHED=1 on success so the prompts can offer a retry.
REACHED=

# speaks MCP? a streamable-http endpoint must answer initialize with a serverInfo.
probe_mcp() {
  url="$1"; label="$2"; REACHED=
  [ -n "$url" ] || { info "$label — not configured"; return; }
  body=$(curl -s --max-time 8 -X POST "$url" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"cardea","version":"1"}}}' \
    2>/dev/null) || body=''
  if [ -z "$body" ]; then
    bad "$label — nothing answered at $url"
    return
  fi
  # the reply is json, or SSE framing with a data: line wrapping the same json
  name=$(printf '%s' "$body" | sed -n 's/.*"serverInfo"[^}]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  vers=$(printf '%s' "$body" | sed -n 's/.*"serverInfo"[^}]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  if [ -n "$name" ]; then
    ok "$label — speaks MCP: $name${vers:+ $vers}"; REACHED=1
  elif printf '%s' "$body" | grep -q '"error"'; then
    msg=$(printf '%s' "$body" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    bad "$label — answered, but not with MCP: ${msg:-unexpected reply}"
  else
    bad "$label — answered, but not with MCP (is the transport streamable-http?)"
  fi
}

# .env is data, not a script: read KEY=value lines, so a stray paste in it can't run as a command.
load_env() {
  [ -f "$ENV_FILE" ] || return 0
  while IFS= read -r l_line || [ -n "$l_line" ]; do
    l_key=${l_line%%=*}
    case "$l_line" in [A-Z_]*=*) ;; *) continue ;; esac
    case "$l_key" in *[!A-Z0-9_]*) continue ;; esac
    export "$l_key=${l_line#*=}"
  done < "$ENV_FILE"
}

# langfuse publishes a health endpoint; use it rather than guessing from the homepage.
probe_langfuse() {
  host="$1"; label="$2"; REACHED=
  [ -n "$host" ] || { info "$label — not configured"; return; }
  url="${host%/}/api/public/health"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$url" 2>/dev/null) || code=000
  [ -n "$code" ] || code=000
  case "$code" in
    000) bad "$label — nothing answered at $host" ;;
    200) ok  "$label — healthy"; REACHED=1 ;;
    503) bad "$label — up but unhealthy (http 503; check its own logs)" ;;
    *)   bad "$label — answered http $code at $url, expected 200" ;;
  esac
}

probe_http() {
  url="$1"; label="$2"; REACHED=
  [ -n "$url" ] || { info "$label — not configured"; return; }
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null) || code=000
  [ -n "$code" ] || code=000
  case "$code" in
    000) bad  "$label — no answer from $url" ;;
    2*)  ok   "$label — $url ($code)"; REACHED=1 ;;
    *)   ok   "$label — $url reachable (http $code)"; REACHED=1 ;;
  esac
}

probe_tool() {
  name="$1"; label="${2:-$1}"
  if command -v "$name" >/dev/null 2>&1; then ok "$label"; else bad "$label — not installed"; fi
}

run_checks() {
  step "tools"
  for t in brew git docker claude herdr uv uvx playwright-cli container-use xcode-build-server plannotator; do
    probe_tool "$t"
  done
  # an exported key makes claude code bill the api instead of using the subscription login.
  [ -n "${ANTHROPIC_API_KEY:-}" ] && warn "ANTHROPIC_API_KEY is set — claude code will use it instead of your subscription"
  if [ -d /Applications/Xcode.app ]; then
    ok "Xcode — $(/usr/bin/defaults read /Applications/Xcode.app/Contents/Info CFBundleShortVersionString 2>/dev/null || echo 'version unknown')"
  else
    bad "Xcode — not found (xcrun mcpbridge needs 26.3+, running)"
  fi
  if command -v docker >/dev/null 2>&1; then
    docker info >/dev/null 2>&1 && ok "docker daemon running" || bad "docker installed but daemon not running (container-use needs it)"
  fi

  step "services"
  load_env
  probe_mcp      "${BASIC_MEMORY_URL:-}" "basic memory"
  probe_langfuse "${LANGFUSE_HOST:-}"    "langfuse"

  if command -v claude >/dev/null 2>&1; then
    step "claude code mcp servers"
    # claude mcp list health-checks every server; show only the ones cardea registers.
    claude mcp list 2>/dev/null | grep -E "^($MCP_NAMES):" | sed 's/^/  /' || warn "none registered yet"
  fi
}

if [ -n "$CHECK_ONLY" ]; then
  run_checks
  printf '\n'
  exit 0
fi

# --- brew ------------------------------------------------------------------
step "packages"
if command -v brew >/dev/null 2>&1; then
  # homebrew 7 refuses third-party taps until they are trusted.
  if brew trust --help >/dev/null 2>&1; then
    sed -n 's/^tap "\(.*\)"/\1/p' "$REPO_DIR/Brewfile" | xargs brew trust --tap
  fi
  # not piped: a pipe would report sed's exit status, not brew's.
  if spin "applying the Brewfile (can take a few minutes)" brew bundle --file="$REPO_DIR/Brewfile"; then
    ok "Brewfile applied"
  else
    bad "brew bundle failed — see above; the checks at the end show what is missing"
  fi
else
  warn "homebrew not found — skipping Brewfile, then rerun this script"
fi

# --- env -------------------------------------------------------------------
# load whatever is already there so re-runs offer the current value as the default.
step "configuration"
if [ -f "$ENV_FILE" ]; then
  load_env
  info "editing existing .env — press enter to keep a value"
elif [ -z "$PROMPT" ]; then
  cp "$REPO_DIR/.env.example" "$ENV_FILE"
  warn ".env created from the example with placeholder values"
  [ -n "${NOTTY:-}" ] && info "no terminal available, so nothing was asked"
fi

# gum input reads keys from stdin, which is the script itself under curl | sh, so it is
# pointed at the terminal. it ignores ctrl-d, so esc stands in for it there.
# gum_read <placeholder> <label> [flags]: sets reply, and g_rc to 0 (enter), 1 (esc), or
# anything else when gum could not draw and the caller should fall back to a plain read.
gum_read() {
  g_ph="$1"; g_label="$2"; shift 2
  g_rc=0
  reply=$(gum input "$@" --prompt "  ${g_label}› " --prompt.foreground "$AMETHYST" \
    --cursor.foreground "$INCHWORM" --placeholder "$g_ph" --no-show-help < /dev/tty 2>/dev/tty) || g_rc=$?
  # ctrl-c in gum is a keypress, not a signal; stop the run as a plain read would.
  [ "$g_rc" -ne 130 ] || { printf '\n' > /dev/tty; exit 130; }
  return 0
}

# gum clears its prompt on enter, so leave a line saying what was chosen.
chosen() { printf '  %s %s\n' "$(paint --bold -- "$1")" "$(paint --faint -- "$2")" > /dev/tty; }

ask() {
  var="$1"; label="$2"; default="$3"
  eval "current=\${$var:-}"
  [ -n "$current" ] && default="$current"
  if [ -z "$PROMPT" ]; then eval "$var=\"\$default\""; return; fi
  reply=''; ASK_EOF=; g_rc=2
  if has_gum; then
    gum_read "${default:-optional}" "$label"
    [ "$g_rc" -ne 1 ] || ASK_EOF=1
  fi
  if [ "$g_rc" -gt 1 ]; then
    if [ -n "$default" ]; then
      printf '  %s%s%s %s[%s]%s ' "$B" "$label" "$R" "$D" "$default" "$R" > /dev/tty
    else
      printf '  %s%s%s %s(optional)%s ' "$B" "$label" "$R" "$D" "$R" > /dev/tty
    fi
    # eof (ctrl-d, or a closed tty) is noted so retry loops can stop instead of spinning.
    read -r reply < /dev/tty || ASK_EOF=1
  fi
  [ -n "$reply" ] || reply="$default"
  [ "$g_rc" -gt 1 ] || chosen "$label" "${reply:-not set}"
  eval "$var=\"\$reply\""
}

ask_secret() {
  var="$1"; label="$2"; s_name=$(printf '%s' "$2" | sed 's/ *$//')
  eval "current=\${$var:-}"
  # keys never contain spaces; one that does is a stray paste, so don't offer to keep it.
  case "$current" in *[[:space:]]*) warn "the saved $s_name isn't a key; paste it again"; current='' ;; esac
  if [ -z "$PROMPT" ]; then eval "$var=\"\$current\""; return; fi
  while :; do
    reply=''; g_rc=2
    if has_gum; then
      if [ -n "$current" ]; then s_ph='keep existing'; else s_ph='hidden, optional'; fi
      gum_read "$s_ph" "$label" --password
      # esc keeps what was there, like enter on an empty field
      [ "$g_rc" -ne 1 ] || reply=''
    fi
    if [ "$g_rc" -gt 1 ]; then
      stty -echo < /dev/tty 2>/dev/null || true
      if [ -n "$current" ]; then
        printf '  %s%s%s %s[keep existing]%s ' "$B" "$label" "$R" "$D" "$R" > /dev/tty
      else
        printf '  %s%s%s %s(hidden, optional)%s ' "$B" "$label" "$R" "$D" "$R" > /dev/tty
      fi
      read -r reply < /dev/tty || true
      stty echo < /dev/tty 2>/dev/null || true
      printf '\n' > /dev/tty
    else
      if [ -n "$reply" ]; then s_note='set'; elif [ -n "$current" ]; then s_note='kept'; else s_note='not set'; fi
      chosen "$label" "$s_note"
    fi
    case "$reply" in *[[:space:]]*) bad "$s_name — that has spaces, so it isn't a key; paste just the key" ;; *) break ;; esac
  done
  [ -n "$reply" ] || reply="$current"
  eval "$var=\"\$reply\""
}

# ask, then actually talk to the thing. a wrong url is cheapest to fix right now,
# while you are still looking at it — not at the end of the run.
ask_url() {
  u_var="$1"; u_label="$2"; u_default="$3"; u_prober="$4"; u_shown="$2"; u_fill="$3"
  u_prev=''
  while :; do
    ask "$u_var" "$u_label" "$u_default"
    eval "u_value=\${$u_var:-}"
    # skip only means something after a failed test: keep the last url, untested.
    if { [ "$u_value" = skip ] || [ -n "${ASK_EOF:-}" ]; } && [ -n "$u_prev" ]; then
      eval "$u_var=\$u_prev"
      warn "keeping $u_prev untested — ./install.sh --check once it is up"
      return 0
    fi
    [ -n "$u_value" ] || return 0
    # a bare host or host:port gets the original default's scheme, port and path filled in.
    # a full url with a scheme is taken exactly as typed.
    case "$u_value" in
      *://*) ;;
      *)
        u_value="${u_value%/}"; u_host="${u_value%%/*}"
        case "$u_host" in
          *:*) ;;
          *) u_host="$u_host$(printf '%s' "$u_fill" | sed -n 's|^[a-z]*://[^/:]*\(:[0-9]*\).*|\1|p')" ;;
        esac
        case "$u_value" in
          */*) u_path="/${u_value#*/}" ;;
          *)   u_path=$(printf '%s' "$u_fill" | sed -n 's|^[a-z]*://[^/]*||p') ;;
        esac
        u_value="${u_fill%%://*}://$u_host$u_path" ;;
    esac
    eval "$u_var=\$u_value"
    [ -n "$PROMPT" ] || return 0
    info "testing $u_value"
    "$u_prober" "$u_value" "$(printf '%s' "$u_shown" | sed 's/ *$//')"
    [ -n "$REACHED" ] && return 0
    u_prev="$u_value"; u_default="$u_value"; u_label="$u_shown"
    if has_gum; then u_skip='skip (or esc)'; else u_skip='skip'; fi
    info "enter retries, type a different url, or $u_skip to keep it untested"
  done
}

if [ -n "$PROMPT" ]; then printf '\n'; fi
ask_url BASIC_MEMORY_URL "basic memory MCP url " "http://truenas.local:8766/mcp" probe_mcp
# everything runs on the one NAS, so offer whatever host basic memory was given.
NAS_BASE=$(printf '%s' "$BASIC_MEMORY_URL" | sed -n 's|^\([a-z]*://[^/:]*\).*|\1|p')
ask_url LANGFUSE_HOST    "langfuse url         " "${NAS_BASE:-http://truenas.local}:3000" probe_langfuse
ask_secret LANGFUSE_PUBLIC_KEY "langfuse public key  "
ask_secret LANGFUSE_SECRET_KEY "langfuse secret key  "

# write atomically, then lock it down — this file holds keys.
TMP_ENV="$ENV_FILE.$$"
{
  printf '# cardea — written by install.sh on %s. not committed.\n\n' "$STAMP"
  printf '# --- basic memory (NAS) ---\n'
  printf 'BASIC_MEMORY_URL=%s\n\n' "$BASIC_MEMORY_URL"
  printf '# --- langfuse (NAS) ---\n'
  printf 'LANGFUSE_HOST=%s\n'          "$LANGFUSE_HOST"
  printf 'LANGFUSE_PUBLIC_KEY=%s\n'    "$LANGFUSE_PUBLIC_KEY"
  printf 'LANGFUSE_SECRET_KEY=%s\n'    "$LANGFUSE_SECRET_KEY"
} > "$TMP_ENV"
mv "$TMP_ENV" "$ENV_FILE"
chmod 600 "$ENV_FILE"
ok "wrote .env (mode 600)"

# --- linking ---------------------------------------------------------------
step "links"
link() {
  src="$1"; dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    [ "$(readlink "$dest")" = "$src" ] && { ok "${dest#"$HOME"/}"; return; }
    rm "$dest"
  elif [ -e "$dest" ]; then
    backup="$REPO_DIR/backup/$STAMP"
    mkdir -p "$backup"
    mv "$dest" "$backup/$(basename "$dest")"
    warn "existing $(basename "$dest") moved to backup/$STAMP/"
  fi
  ln -s "$src" "$dest"
  ok "${dest#"$HOME"/}"
}

# per-file, not whole-directory: claude code keeps sessions, plugins and settings in ~/.claude
link "$REPO_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
link "$REPO_DIR/claude/skills/tldr" "$HOME/.claude/skills/tldr"
link "$REPO_DIR/claude/skills/baby" "$HOME/.claude/skills/baby"

# --- claude code -----------------------------------------------------------
step "claude code"
# installed by the Brewfile (claude-code@latest). a native install in ~/.local/bin would
# shadow it on PATH and update itself out of step, so flag one if it is there.
[ -x "$HOME/.local/bin/claude" ] && warn "a native claude install in ~/.local/bin shadows homebrew's — remove it"
command -v claude >/dev/null 2>&1 || die "claude code is not installed — the Brewfile step should have done it"
ok "claude $(claude --version 2>/dev/null | cut -d' ' -f1)"

# the task tools (TaskCreate, TaskList, TaskUpdate) are off by default on newer models. claude
# has no command to set a settings env entry, so merge it in; an unreadable file is left alone.
if python3 -c '
import json, os, sys
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) else {}
env = d.setdefault("env", {})
if env.get("CLAUDE_CODE_ENABLE_TODO_TOOLS") != "1":
    env["CLAUDE_CODE_ENABLE_TODO_TOOLS"] = "1"
    os.makedirs(os.path.dirname(p), exist_ok=True)
    json.dump(d, open(p, "w"), indent=2)
' "$HOME/.claude/settings.json" 2>/dev/null; then
  ok "task list on (CLAUDE_CODE_ENABLE_TODO_TOOLS)"
else
  warn "could not set CLAUDE_CODE_ENABLE_TODO_TOOLS in ~/.claude/settings.json — add it to \"env\" by hand"
fi

# user scope, so every project gets them. values are baked in from .env at install time;
# rerun this script after changing .env. remove-then-add keeps it idempotent.
mcp() {
  claude mcp remove -s user "$1" >/dev/null 2>&1 || true
  if claude mcp add-json -s user "$1" "$2" >/dev/null; then ok "mcp: $1"; else bad "mcp: $1 — could not register"; fi
}
mcp container-use '{"type":"stdio","command":"container-use","args":["stdio"]}'
mcp xcodebuild    '{"type":"stdio","command":"npx","args":["-y","xcodebuildmcp@2.7.0","mcp"],"env":{"XCODEBUILDMCP_SENTRY_DISABLED":"true"}}'
mcp swiftlens     '{"type":"stdio","command":"uvx","args":["swiftlens@0.2.14"]}'
# a bare `xcrun mcpbridge` is the bridge; it only connects while xcode is running.
mcp xcode         '{"type":"stdio","command":"xcrun","args":["mcpbridge"]}'
if [ -n "$BASIC_MEMORY_URL" ]; then
  mcp basic-memory "{\"type\":\"http\",\"url\":\"$BASIC_MEMORY_URL\"}"
else
  claude mcp remove -s user basic-memory >/dev/null 2>&1 || true
  info "mcp: basic-memory — no url in .env, skipped"
fi

plugin() {
  id="$1"; p_src="$2"
  if claude plugin list --json 2>/dev/null | grep -q "\"id\": \"$id\""; then
    # installed but switched off still counts as missing from the setup.
    claude plugin enable "$id" >/dev/null 2>&1 || true
    # the install is a cached copy, so a rerun refreshes it.
    if spin "updating plugin $id" claude plugin update "$id" >/dev/null; then ok "plugin: $id"; else bad "plugin: $id — update failed"; fi
    return 0
  fi
  if spin "installing plugin $id" claude plugin install "${id%@*}" --marketplace "$p_src" -y >/dev/null; then ok "plugin: $id"; else bad "plugin: $id — install failed"; fi
}

# plannotator's plugin only wires hooks; they call the plannotator binary, installed bare.
if ! command -v plannotator >/dev/null 2>&1; then
  spin "installing plannotator v0.28.31 (binary only)" sh -c \
    'curl -fsSL https://plannotator.ai/install.sh | bash -s -- --version v0.28.31 --minimal --non-interactive' \
    || warn "plannotator binary failed to install"
fi
plugin plannotator@plannotator backnotprop/plannotator

plugin langfuse-observability@langfuse-observability langfuse/Claude-Observability-Plugin
# point it at the NAS even without keys, so it never falls back to langfuse's own cloud.
# stdin keeps the secret out of the process list.
if [ -n "$LANGFUSE_HOST" ]; then
  {
    printf '{"LANGFUSE_BASE_URL":"%s"' "$LANGFUSE_HOST"
    [ -n "$LANGFUSE_PUBLIC_KEY" ] && printf ',"LANGFUSE_PUBLIC_KEY":"%s"' "$LANGFUSE_PUBLIC_KEY"
    [ -n "$LANGFUSE_SECRET_KEY" ] && printf ',"LANGFUSE_SECRET_KEY":"%s"' "$LANGFUSE_SECRET_KEY"
    printf '}'
  } | claude plugin configure langfuse-observability@langfuse-observability --values-stdin >/dev/null \
    && ok "langfuse plugin → $LANGFUSE_HOST" || warn "langfuse plugin configure failed — run /plugin configure in claude"
  [ -n "$LANGFUSE_PUBLIC_KEY" ] || info "no langfuse keys yet — tracing stays off until you add them and rerun"
fi

# cardea's own skills and agents. installed from this checkout, which claude code reads in
# place, so edits here show up at the next session without reinstalling.
plugin cardea@cardea "$REPO_DIR"

plugin superpowers@superpowers-marketplace obra/superpowers-marketplace
plugin ponytail@ponytail DietrichGebert/ponytail
plugin apple-skills@apple-skills Prisma-Labs-Dev/apple-skills
plugin cloudflare@cloudflare cloudflare/skills
plugin humanizer@humanizer blader/humanizer

# --- herdr -----------------------------------------------------------------
if command -v herdr >/dev/null 2>&1; then
  step "herdr"
  herdr integration install claude || warn "herdr integration failed — run it by hand"
fi

# --- vendored skills -------------------------------------------------------
# herdr, graphify and playwright-cli ship their own skills, generated from the installed versions;
# marimo and langfuse publish theirs in git repos.
step "skills"
if command -v uv >/dev/null 2>&1; then
  spin "installing graphify 0.9.88" uv tool install graphifyy==0.9.88 >/dev/null \
    || warn "graphify failed to install"
fi
if command -v npm >/dev/null 2>&1; then
  spin "installing playwright-cli 0.1.24" npm install -g @playwright/cli@0.1.24 >/dev/null \
    || warn "playwright-cli failed to install"
  command -v playwright-cli >/dev/null 2>&1 \
    && { spin "installing chromium for playwright-cli" playwright-cli install-browser chromium >/dev/null \
         || warn "chromium failed to install"; }
else
  warn "npm not found, skipping playwright-cli"
fi
if sh "$REPO_DIR/scripts/vendor-skills.sh" "$HOME/.claude/skills" >/dev/null; then
  ok "herdr, graphify, playwright-cli, marimo-notebook and langfuse skills"
else
  warn "a vendored skill could not be generated — run scripts/vendor-skills.sh to see why"
fi

run_checks

# --- next steps ------------------------------------------------------------
if has_gum; then
  gum style --border rounded --border-foreground "$AMETHYST" --padding '1 2' --margin '1 2' -- \
    "$(paint --bold --foreground "$INCHWORM" -- 'Next')

1. $(paint --bold -- 'claude auth login')
   sign in with your claude subscription (interactive)
2. per iOS project
   $(paint --bold -- 'xcode-build-server config -project X.xcodeproj -scheme X')
3. on the NAS, in /mnt/main/Docker/lab
   $(paint --bold -- 'sudo docker compose up -d')
   $(paint --faint -- 'https://yuzuholic.github.io/cardea/docs/nas')

$(paint --faint -- 're-run anytime. ./install.sh --check probes without changing anything.')"
else
  printf '\n%s▸ next%s\n' "$B" "$R"
  cat <<EOF
  1. claude auth login                   sign in with your claude subscription (interactive)
  2. per iOS project:                    xcode-build-server config -project X.xcodeproj -scheme X
  3. on the NAS:                         sudo docker compose up -d in /mnt/main/Docker/lab
                                         (see https://yuzuholic.github.io/cardea/docs/nas)

  re-run anytime. ${D}./install.sh --check${R} probes without changing anything.

EOF
fi
}

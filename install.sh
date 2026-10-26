#!/bin/sh
# cardea — install the agent stack.
#
#   ./install.sh                 interactive: prompts for urls and keys, then probes them
#   ./install.sh --no-prompt     keep whatever .env already holds, prompt for nothing
#   ./install.sh --check         probe the stack and exit, change nothing
#
# safe to run repeatedly. existing config is backed up, not overwritten.
set -eu

REPO_URL="https://github.com/angelocarasig/cardea.git"
REPO_DIR="${CARDEA_HOME:-$HOME/Repositories/cardea}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"

# --- ui --------------------------------------------------------------------
# colour only on a real terminal, and never when NO_COLOR is set.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$(printf '\033[1m');  D=$(printf '\033[2m');  R=$(printf '\033[0m')
  GRN=$(printf '\033[32m'); YEL=$(printf '\033[33m')
  RED=$(printf '\033[31m'); CYN=$(printf '\033[36m')
else
  B=''; D=''; R=''; GRN=''; YEL=''; RED=''; CYN=''
fi

banner() {
  printf '\n%s  ╭────────────────────────────────────────────╮%s\n' "$CYN" "$R"
  printf '%s  │%s  %scardea%s  %s·  the hinge the gate swings on%s   %s│%s\n' \
    "$CYN" "$R" "$B" "$R" "$D" "$R" "$CYN" "$R"
  printf '%s  ╰────────────────────────────────────────────╯%s\n\n' "$CYN" "$R"
}
step() { printf '\n%s▸ %s%s\n' "$B" "$1" "$R"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$R" "$1"; }
info() { printf '  %s·%s %s\n' "$D" "$R" "$1"; }
warn() { printf '  %s!%s %s\n' "$YEL" "$R" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$R" "$1"; }
die()  { printf '\n%scardea:%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }

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
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/opencode/opencode.json" ]; then
  REPO_DIR="$SELF_DIR"
elif [ -d "$REPO_DIR/.git" ]; then
  step "repo"; info "updating $REPO_DIR"
  git -C "$REPO_DIR" pull --ff-only
else
  step "repo"; info "cloning into $REPO_DIR"
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --depth 1 "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR"
ENV_FILE="$REPO_DIR/.env"

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
  for t in brew git docker opencode herdr ruler uv uvx container-use xcode-build-server; do
    probe_tool "$t"
  done
  if [ -d /Applications/Xcode.app ]; then
    ok "Xcode — $(/usr/bin/defaults read /Applications/Xcode.app/Contents/Info CFBundleShortVersionString 2>/dev/null || echo 'version unknown')"
  else
    bad "Xcode — not found (xcrun mcpbridge needs 26.3+, running)"
  fi
  if command -v docker >/dev/null 2>&1; then
    docker info >/dev/null 2>&1 && ok "docker daemon running" || bad "docker installed but daemon not running (container-use needs it)"
  fi

  step "services"
  # shellcheck disable=SC1090
  [ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
  probe_mcp      "${BASIC_MEMORY_URL:-}" "basic memory"
  probe_langfuse "${LANGFUSE_HOST:-}"    "langfuse"
}

if [ -n "$CHECK_ONLY" ]; then
  run_checks
  printf '\n'
  exit 0
fi

# --- brew ------------------------------------------------------------------
step "packages"
if command -v brew >/dev/null 2>&1; then
  brew bundle --file="$REPO_DIR/Brewfile" 2>&1 | sed 's/^/  /'
  ok "Brewfile applied"
else
  warn "homebrew not found — skipping Brewfile, then rerun this script"
fi

# --- env -------------------------------------------------------------------
# load whatever is already there so re-runs offer the current value as the default.
step "configuration"
if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
  info "editing existing .env — press enter to keep a value"
elif [ -z "$PROMPT" ]; then
  cp "$REPO_DIR/.env.example" "$ENV_FILE"
  warn ".env created from the example with placeholder values"
  [ -n "${NOTTY:-}" ] && info "no terminal available, so nothing was asked"
fi

ask() {
  var="$1"; label="$2"; default="$3"
  eval "current=\${$var:-}"
  [ -n "$current" ] && default="$current"
  if [ -z "$PROMPT" ]; then eval "$var=\"\$default\""; return; fi
  if [ -n "$default" ]; then
    printf '  %s%s%s %s[%s]%s ' "$B" "$label" "$R" "$D" "$default" "$R" > /dev/tty
  else
    printf '  %s%s%s %s(optional)%s ' "$B" "$label" "$R" "$D" "$R" > /dev/tty
  fi
  reply=''; read -r reply < /dev/tty || true
  [ -n "$reply" ] || reply="$default"
  eval "$var=\"\$reply\""
}

ask_secret() {
  var="$1"; label="$2"
  eval "current=\${$var:-}"
  if [ -z "$PROMPT" ]; then eval "$var=\"\$current\""; return; fi
  stty -echo < /dev/tty 2>/dev/null || true
  if [ -n "$current" ]; then
    printf '  %s%s%s %s[keep existing]%s ' "$B" "$label" "$R" "$D" "$R" > /dev/tty
  else
    printf '  %s%s%s %s(hidden, optional)%s ' "$B" "$label" "$R" "$D" "$R" > /dev/tty
  fi
  reply=''; read -r reply < /dev/tty || true
  stty echo < /dev/tty 2>/dev/null || true
  printf '\n' > /dev/tty
  [ -n "$reply" ] || reply="$current"
  eval "$var=\"\$reply\""
}

# ask, then actually talk to the thing. a wrong url is cheapest to fix right now,
# while you are still looking at it — not at the end of the run.
ask_url() {
  u_var="$1"; u_label="$2"; u_default="$3"; u_prober="$4"; u_shown="$2"
  u_prev=''
  while :; do
    ask "$u_var" "$u_label" "$u_default"
    eval "u_value=\${$u_var:-}"
    [ -n "$u_value" ] || return
    [ -n "$PROMPT" ] || return
    info "testing $u_value"
    "$u_prober" "$u_value" "$(printf '%s' "$u_shown" | sed 's/ *$//')"
    [ -n "$REACHED" ] && return
    if [ "$u_value" = "$u_prev" ]; then
      warn "keeping it anyway — you can fix it in .env later"
      return
    fi
    u_prev="$u_value"; u_default="$u_value"; u_label="$u_shown"
    info "enter keeps it, or type a different url"
  done
}

if [ -n "$PROMPT" ]; then printf '\n'; fi
ask_url BASIC_MEMORY_URL "basic memory MCP url " "http://nas.local:8766/mcp" probe_mcp
ask_url LANGFUSE_HOST    "langfuse url         " "http://nas.local:3000"     probe_langfuse
ask GRAPHIFY_ROOT    "graphify root        " "/mnt/main/docker/lab/kb"
ask_secret LANGFUSE_PUBLIC_KEY "langfuse public key  "
ask_secret LANGFUSE_SECRET_KEY "langfuse secret key  "
ask_secret ANTHROPIC_API_KEY   "anthropic api key    "
ask_secret OPENAI_API_KEY      "openai api key       "

# write atomically, then lock it down — this file holds keys.
TMP_ENV="$ENV_FILE.$$"
{
  printf '# cardea — written by install.sh on %s. not committed.\n\n' "$STAMP"
  printf '# --- basic memory (NAS) ---\n'
  printf 'BASIC_MEMORY_URL=%s\n\n' "$BASIC_MEMORY_URL"
  printf '# --- langfuse (NAS) ---\n'
  printf 'LANGFUSE_HOST=%s\n'          "$LANGFUSE_HOST"
  printf 'LANGFUSE_PUBLIC_KEY=%s\n'    "$LANGFUSE_PUBLIC_KEY"
  printf 'LANGFUSE_SECRET_KEY=%s\n\n'  "$LANGFUSE_SECRET_KEY"
  printf '# --- graphify ---\n'
  printf 'GRAPHIFY_ROOT=%s\n\n' "$GRAPHIFY_ROOT"
  printf '# --- models ---\n'
  printf 'ANTHROPIC_API_KEY=%s\n' "$ANTHROPIC_API_KEY"
  printf 'OPENAI_API_KEY=%s\n'    "$OPENAI_API_KEY"
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

# per-file, not whole-directory: opencode keeps its own state in ~/.config/opencode
link "$REPO_DIR/opencode/opencode.json" "$CONFIG_HOME/opencode/opencode.json"
link "$REPO_DIR/opencode/AGENTS.md"     "$CONFIG_HOME/opencode/AGENTS.md"
# ruler distributes rules only; AGENTS.md has one source of truth
link "$REPO_DIR/ruler/ruler.toml"       "$CONFIG_HOME/ruler/ruler.toml"
link "$REPO_DIR/opencode/AGENTS.md"     "$CONFIG_HOME/ruler/AGENTS.md"
link "$ENV_FILE"                        "$CONFIG_HOME/cardea/env"

# --- shell wiring ----------------------------------------------------------
# opencode resolves {env:VAR} from the shell, so the env file must be exported.
SHELL_LINE='[ -f "$HOME/.config/cardea/env" ] && set -a && . "$HOME/.config/cardea/env" && set +a'
RC="$HOME/.zshrc"
if [ -f "$RC" ] && grep -qF 'cardea/env' "$RC"; then
  ok "~/.zshrc already sources the env"
else
  printf '\n# cardea\n%s\n' "$SHELL_LINE" >> "$RC"
  ok "added env sourcing to ~/.zshrc"
fi

# --- herdr -----------------------------------------------------------------
if command -v herdr >/dev/null 2>&1; then
  step "herdr"
  herdr integration install opencode 2>&1 | sed 's/^/  /' || warn "herdr integration failed — run it by hand"
fi

run_checks

# --- next steps ------------------------------------------------------------
printf '\n%s▸ next%s\n' "$B" "$R"
cat <<EOF
  1. exec \$SHELL -l                      load the env into this shell
  2. opencode auth login                 pick a model provider (interactive, can't be scripted)
  3. per iOS project:                    xcode-build-server config -project X.xcodeproj -scheme X
  4. on the NAS:                         docker compose up -d in nas/lab
                                         (see nas/README.md)

  re-run anytime. ${D}./install.sh --check${R} probes without changing anything.

EOF

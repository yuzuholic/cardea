#!/bin/sh
# cardea: install the agent stack.
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
  RED=$(printf '\033[31m'); BLU=$(printf '\033[34m')
else
  B=''; D=''; R=''; GRN=''; YEL=''; RED=''; BLU=''
fi

# gum draws the ui when it is installed and there is a terminal to draw on. the printf
# lines are the fallback, and the only ui on a fresh mac until the Brewfile installs gum.
# checked on every call, so the run switches over as soon as gum appears.
has_gum() {
  [ -n "$FANCY" ] && [ "${TERM:-dumb}" != dumb ] && command -v gum >/dev/null 2>&1
}
# cardea's palette (apple system colours). gum drops to 256 colours where truecolor is missing.
ACCENT='#2997ff'; SUCCESS='#30d158'; WARNING='#ff9f0a'; FAILURE='#ff453a'
# for $(...): gum leaves colour out when its output is not a terminal. callers put -- before
# the text (it may start with a dash), and stdin is closed because gum style reads it when
# the text is empty, and under curl | sh stdin is the rest of this script.
paint() { CLICOLOR_FORCE=1 gum style "$@" < /dev/null; }

banner() {
  b_text='Installs Claude Code, its MCP servers and plugins, and their NAS services.'
  if has_gum; then
    printf '\n  %s\n  %s\n' "$(paint --bold -- Cardea)" "$(paint --faint -- "$b_text")"
    return 0
  fi
  printf '\n  %sCardea%s\n  %s%s%s\n' "$B" "$R" "$D" "$b_text" "$R"
}
step() {
  if has_gum; then printf '\n%s %s\n' "$(paint --foreground "$ACCENT" -- ▸)" "$(paint --bold -- "$1")"; return 0; fi
  printf '\n%s%s▸%s %s%s%s\n' "$BLU" "$B" "$R" "$B" "$1" "$R"
}
# mark <gum colour> <glyph> <plain colour> <text>
mark() {
  if has_gum; then printf '  %s %s\n' "$(paint --foreground "$1" -- "$2")" "$4"; return 0; fi
  printf '  %s%s%s %s\n' "$3" "$2" "$R" "$4"
}
N_OK=0; N_WARN=0; N_BAD=0; T0=$(date +%s)
# what the summary lists at the end: one tab-separated "glyph, text, hint" record per line.
TAB=$(printf '\t'); ITEMS=; MISSING=
track() { ITEMS="$ITEMS$1$TAB$2$TAB${3:-}
"; }
# warnings the script can fix; offer_fixes asks about each one after the summary.
FIXES=
fixable() { FIXES="$FIXES $1"; }
ok()   { N_OK=$((N_OK + 1)); mark "$SUCCESS" '✓' "$GRN" "$1"; }
info() {
  if has_gum; then printf '  %s\n' "$(paint --faint -- "· $1")"; return 0; fi
  printf '  %s·%s %s\n' "$D" "$R" "$1"
}
# hint: a second line, faint and indented, for what to type.
hint() {
  if has_gum; then printf '      %s\n' "$(paint --faint -- "$1")"; return 0; fi
  printf '      %s%s%s\n' "$D" "$1" "$R"
}
warn() { N_WARN=$((N_WARN + 1)); track '!' "$1" "${2:-}"; mark "$WARNING" '!' "$YEL" "$1"; [ -z "${2:-}" ] || hint "$2"; }
bad()  { N_BAD=$((N_BAD + 1)); track '✗' "$1"; mark "$FAILURE" '✗' "$RED" "$1"; }
die()  { printf '\n%scardea:%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }

# spin <title> <command...>: a spinner while it runs, its output shown only if it fails.
# returns the command's own exit status either way. gum hands its stdin to the command,
# so it gets none: under curl | sh stdin is the script, and the terminal would leave
# anything that reads it waiting on the keyboard behind the spinner.
spin() {
  s_title="$1"; shift
  if has_gum; then
    gum spin --spinner dot --spinner.foreground "$ACCENT" --title " $s_title" --show-error -- "$@" < /dev/null
  else
    info "$s_title"; "$@"
  fi
}

# --- jobs ------------------------------------------------------------------
# independent installs run side by side. job <label> <function> starts the function in its own
# process group with its output in a log and stdin closed; await_jobs shows them, one line each:
# a board redrawn in place under gum, one line per finished job otherwise.
JOBDIR=; JOBS=; NJOB=0; JOB_FAILS=0; FAILED_LABELS=; HIDDEN=

job() {
  j_label="$1"; shift
  [ -n "$JOBDIR" ] || JOBDIR=$(mktemp -d)
  NJOB=$((NJOB + 1)); j_id=j$NJOB
  set -m
  (
    j_start=$(date +%s)
    "$@" > "$JOBDIR/$j_id.log" 2>&1 < /dev/null && j_rc=0 || j_rc=$?
    echo "$j_rc $(( $(date +%s) - j_start ))" > "$JOBDIR/$j_id.tmp" && mv "$JOBDIR/$j_id.tmp" "$JOBDIR/$j_id.done"
  ) &
  j_pid=$!
  set +m
  eval "J_PID_$j_id=$j_pid; J_LABEL_$j_id=\$j_label; J_AT_$j_id=$(date +%s)"
  JOBS="$JOBS $j_id"
}

# the escape gum puts before styled text, so the board colours a line without calling gum.
tint() { t_s=$(paint "$@" -- X); printf '%s' "${t_s%%X*}"; }

# a job whose function fails stops there, so jobs chain with || and return a status of their own.
await_jobs() {
  [ -n "$JOBS" ] || return 0
  a_board=; has_gum && a_board=1
  a_frame=0; a_seen=' '; a_drawn=
  info "running $NJOB jobs in parallel"
  if [ -n "$a_board" ]; then
    a_ok=$(tint --foreground "$SUCCESS"); a_bad=$(tint --foreground "$FAILURE")
    a_run=$(tint --foreground "$ACCENT"); a_dim=$(tint --faint)
    printf '\033[?25l'; HIDDEN=1
  fi
  while :; do
    a_left=0; a_now=$(date +%s)
    [ -z "$a_drawn" ] || [ -z "$a_board" ] || printf '\033[%dA' "$NJOB"
    for a_id in $JOBS; do
      eval "a_label=\$J_LABEL_$a_id; a_at=\$J_AT_$a_id"
      a_secs=$((a_now - a_at)); a_g=
      if [ -f "$JOBDIR/$a_id.done" ]; then
        read -r a_rc a_secs < "$JOBDIR/$a_id.done"
        # a time only means something once it is long enough to notice.
        case "$a_seen" in
          *" $a_id "*) ;;
          *)
            a_seen="$a_seen$a_id "
            if [ "$a_rc" -eq 0 ]; then
              if [ -n "$a_board" ]; then N_OK=$((N_OK + 1)); elif [ "$a_secs" -ge 3 ]; then ok "$a_label (${a_secs}s)"; else ok "$a_label"; fi
            else
              JOB_FAILS=$((JOB_FAILS + 1)); FAILED_LABELS="$FAILED_LABELS|$a_label|"
              if [ -n "$a_board" ]; then N_BAD=$((N_BAD + 1)); track '✗' "$a_label failed"; else bad "$a_label failed"; fi
            fi ;;
        esac
      else
        a_left=$((a_left + 1))
      fi
      [ -n "$a_board" ] || continue
      if [ ! -f "$JOBDIR/$a_id.done" ]; then
        case $((a_frame % 10)) in
          0) a_g='⠋' ;; 1) a_g='⠙' ;; 2) a_g='⠹' ;; 3) a_g='⠸' ;; 4) a_g='⠼' ;;
          5) a_g='⠴' ;; 6) a_g='⠦' ;; 7) a_g='⠧' ;; 8) a_g='⠇' ;; *) a_g='⠏' ;;
        esac
        a_c=$a_run
      elif [ "$a_rc" -eq 0 ]; then a_g='✓'; a_c=$a_ok
      else a_g='✗'; a_c=$a_bad; fi
      if [ "$a_secs" -ge 3 ]; then a_t="${a_secs}s"; else a_t=; fi
      printf '\033[2K  %s%s%s %-34s %s%5s%s\n' "$a_c" "$a_g" "$R" "$a_label" "$a_dim" "$a_t" "$R"
    done
    a_drawn=1; a_frame=$((a_frame + 1))
    [ "$a_left" -gt 0 ] || break
    sleep 0.1
  done
  [ -z "$a_board" ] || { printf '\033[?25h'; HIDDEN=; }
  for a_id in $JOBS; do
    eval "a_pid=\$J_PID_$a_id"
    wait "$a_pid" 2>/dev/null || true
    read -r a_rc a_secs < "$JOBDIR/$a_id.done"
    [ "$a_rc" -ne 0 ] || continue
    eval "a_label=\$J_LABEL_$a_id"
    info "$a_label: last lines of $JOBDIR/$a_id.log"
    tail -n 12 "$JOBDIR/$a_id.log" | sed 's/^/      /'
  done
  JOBS=
}

stop_jobs() {
  for x_id in $JOBS; do
    [ ! -f "$JOBDIR/$x_id.done" ] || continue
    eval "x_pid=\$J_PID_$x_id"
    kill -TERM -- "-$x_pid" 2>/dev/null || kill -TERM "$x_pid" 2>/dev/null || true
  done
}
# ctrl-c ends the run, which stops what is still running; logs are kept only after a failure.
leave() {
  stop_jobs
  [ -z "$HIDDEN" ] || printf '\033[?25h'
  [ -z "$JOBDIR" ] || [ "$JOB_FAILS" -gt 0 ] || rm -rf "$JOBDIR"
}
trap leave EXIT
trap 'exit 130' INT TERM HUP

# how the run went, then what needs doing: every failure and every warning, one line each.
summary() {
  s_secs=$(( $(date +%s) - T0 ))
  s_w=warnings; [ "$N_WARN" -ne 1 ] || s_w=warning
  if has_gum; then
    printf '\n  %s  %s  %s  %s\n' "$(paint --foreground "$SUCCESS" -- "✓ $N_OK ok")" \
      "$(paint --foreground "$WARNING" -- "! $N_WARN $s_w")" "$(paint --foreground "$FAILURE" -- "✗ $N_BAD failed")" \
      "$(paint --faint -- "· ${s_secs}s")"
  else
    printf '\n  %s✓ %s ok%s  %s! %s %s%s  %s✗ %s failed%s  %s· %ss%s\n' "$GRN" "$N_OK" "$R" "$YEL" "$N_WARN" "$s_w" "$R" \
      "$RED" "$N_BAD" "$R" "$D" "$s_secs" "$R"
  fi
  [ -z "$MISSING" ] || mark "$FAILURE" '✗' "$RED" "not installed: $MISSING"
  while IFS="$TAB" read -r s_glyph s_text s_hint; do
    [ -n "$s_glyph" ] || continue
    if [ "$s_glyph" = '!' ]; then mark "$WARNING" '!' "$YEL" "$s_text"; else mark "$FAILURE" '✗' "$RED" "$s_text"; fi
    [ -z "$s_hint" ] || hint "$s_hint"
  done <<SUMMARY
$ITEMS
SUMMARY
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
MCP_NAMES='xcodebuild|swiftlens|xcode|hindsight'; MCP_LIST=

# --- probes ----------------------------------------------------------------
# any http status at all means something answered. an MCP endpoint may well reply
# 404/405/406 to a bare GET, which still proves the host and port are live.
# a reachable port proves very little, so each service is asked something it has to
# understand. these set REACHED=1 on success so the prompts can offer a retry.
REACHED=

# .local names go through mDNS, which stalls for seconds now and then. a warning only.
warn_mdns() {
  case "$(printf '%s' "$1" | sed -n 's|^[a-z]*://\([^/:]*\).*|\1|p')" in
    *.local) warn "$2 uses a .local name" ".local names resolve over mDNS and can stall for seconds; use the NAS's fixed IP or a router DNS name" ;;
  esac
}

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

# NAS_BASE is NAS_URL without any port or path. shortcut: a .env that still has only
# BASIC_MEMORY_URL gets its NAS_URL from it; drop this fallback one release after it ships.
derive_nas() {
  [ -n "${NAS_URL:-}" ] || NAS_URL=$(printf '%s' "${BASIC_MEMORY_URL:-}" | sed -n 's|^\([a-z]*://[^/:]*\).*|\1|p')
  NAS_BASE=$(printf '%s' "${NAS_URL:-}" | sed -n 's|^\([a-z]*://[^/:]*\).*|\1|p')
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

# a missing required tool fails the run; the summary names them together. an optional one is
# only noted.
probe_tool() {
  name="$1"; label="${2:-$1}"
  if command -v "$name" >/dev/null 2>&1; then ok "$label"; return 0; fi
  if [ "${3:-}" = optional ]; then
    info "$label — optional, not installed"
    return 0
  fi
  N_BAD=$((N_BAD + 1)); MISSING="${MISSING:+$MISSING, }$name"
  mark "$FAILURE" '✗' "$RED" "$label — not installed"
}

run_checks() {
  step "tools"
  for t in brew git claude herdr uv uvx pnpm gh jq playwright-cli; do
    probe_tool "$t"
  done
  # the isolation and iOS extras.
  for t in docker xcode-build-server; do
    probe_tool "$t" "$t" optional
  done
  # graphify installs into ~/.local/bin, which a stock shell profile leaves off PATH.
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "~/.local/bin is not on PATH" 'export PATH="$HOME/.local/bin:$PATH"'; fixable path ;;
  esac
  info "default agent — $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("agent", "none"))' "$HOME/.claude/settings.json" 2>/dev/null || echo none)"
  # an exported key makes claude code bill the api instead of using the subscription login.
  [ -n "${ANTHROPIC_API_KEY:-}" ] && warn "ANTHROPIC_API_KEY is set — claude code will use it instead of your subscription"
  if [ -d /Applications/Xcode.app ]; then
    ok "Xcode — $(/usr/bin/defaults read /Applications/Xcode.app/Contents/Info CFBundleShortVersionString 2>/dev/null || echo 'version unknown')"
  else
    bad "Xcode — not found (xcrun mcpbridge needs 26.3+, running)"
  fi
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      ok "docker daemon running"
    else
      warn "docker is installed but its daemon is not running" "open OrbStack"
      [ ! -d /Applications/OrbStack.app ] || fixable docker
    fi
  fi

  step "services"
  load_env
  derive_nas
  probe_http     "${NAS_URL:-}"       "nas"
  probe_langfuse "${LANGFUSE_HOST:-}" "langfuse"
  warn_mdns "${NAS_URL:-}"       "nas"
  warn_mdns "${LANGFUSE_HOST:-}" "langfuse"

  if command -v claude >/dev/null 2>&1; then
    step "claude code mcp servers"
    # claude mcp list health-checks every server; show only the ones cardea registers. the install
    # run has already asked once, and keeps the answer.
    [ -n "$MCP_LIST" ] || MCP_LIST=$(claude mcp list 2>/dev/null || true)
    c_found=
    while IFS= read -r c_line; do
      c_name=${c_line%%:*}
      case "|$MCP_NAMES|" in *"|$c_name|"*) ;; *) continue ;; esac
      c_found=1
      case "$c_line" in
        *Connected*) ok "$c_name — connected" ;;
        *Failed*|*✗*) bad "$c_name — failed to connect" ;;
        *) warn "$c_name — ${c_line##* - }" ;;
      esac
    done <<MCPLIST
$MCP_LIST
MCPLIST
    [ -n "$c_found" ] || warn "no MCP servers registered yet"
  fi
}

if [ -n "$CHECK_ONLY" ]; then
  run_checks
  summary
  printf '\n'
  [ -z "$MISSING" ] || exit 1
  exit 0
fi

# --- brew ------------------------------------------------------------------
step "packages"
if command -v brew >/dev/null 2>&1; then
  # homebrew 7 refuses third-party taps until they are trusted.
  if brew trust --help >/dev/null 2>&1; then
    sed -n 's/^tap "\(.*\)"/\1/p' "$REPO_DIR/Brewfile" | xargs brew trust --tap
  fi
  # brew's full output goes to a log; a failure shows only its error lines.
  BREW_LOG=$(mktemp -t cardea-brew)
  if spin "applying the Brewfile (can take a few minutes)" sh -c 'brew bundle --file="$1" > "$2" 2>&1' sh "$REPO_DIR/Brewfile" "$BREW_LOG"; then
    ok "Brewfile applied"
    rm -f "$BREW_LOG"
  else
    bad "brew bundle failed — the checks at the end show what is missing"
    grep -E '^Error:|failed!?$' "$BREW_LOG" | sed 's/^/      /'
    info "full log: $BREW_LOG"
  fi
else
  warn "homebrew not found — skipping Brewfile, then rerun this script"
fi

# --- claude code -----------------------------------------------------------
step "claude code"
# installed by the Brewfile (claude-code, the stable channel). a native install in ~/.local/bin would
# shadow it on PATH and update itself out of step, so flag one if it is there.
if [ -x "$HOME/.local/bin/claude" ]; then
  warn "a native claude install in ~/.local/bin shadows homebrew's — remove it"
  fixable shadow
fi
command -v claude >/dev/null 2>&1 || die "claude code is not installed — the Brewfile step should have done it"
ok "claude $(claude --version 2>/dev/null | cut -d' ' -f1)"

# the task tools (TaskCreate, TaskList, TaskUpdate) are off by default on newer models, and the
# Hindsight's delete_document should not wait on a permission prompt. claude has no command to set
# either, so merge them in; an unreadable file is left alone.
if python3 -c '
import json, os, sys
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) else {}
env = d.setdefault("env", {})
env["CLAUDE_CODE_ENABLE_TODO_TOOLS"] = "1"
allow = d.setdefault("permissions", {}).setdefault("allow", [])
if "mcp__hindsight__delete_document" not in allow:
    allow.append("mcp__hindsight__delete_document")
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
' "$HOME/.claude/settings.json" 2>/dev/null; then
  ok "task list on (CLAUDE_CODE_ENABLE_TODO_TOOLS), hindsight delete_document allowed"
else
  warn "could not edit ~/.claude/settings.json — add CLAUDE_CODE_ENABLE_TODO_TOOLS to \"env\" and mcp__hindsight__delete_document to \"permissions.allow\" by hand"
fi

# herdr writes its hook into the same settings.json the plugin installs write to, so it goes
# first and alone.
if command -v herdr >/dev/null 2>&1; then
  spin "installing herdr's claude integration" herdr integration install claude >/dev/null \
    && ok "herdr integration" || { warn "herdr integration failed — run it by hand"; fixable herdr; }
fi

# --- parallel installs -----------------------------------------------------
# what follows needs no answers, so it starts now and runs while the prompts are on screen. the
# claude jobs write ~/.claude.json, settings.json and the plugin caches at the same time; nine
# concurrent installs and registrations against the real claude lost no write, so they run
# side by side too.
plugin() {
  p_id="$1"; p_src="$2"
  if claude plugin list --json 2>/dev/null | grep -q "\"id\": \"$p_id\""; then
    # installed but switched off still counts as missing from the setup.
    claude plugin enable "$p_id" >/dev/null 2>&1 || true
    # the install is a cached copy, so a rerun refreshes it.
    claude plugin update "$p_id"
  else
    claude plugin install "${p_id%@*}" --marketplace "$p_src" -y
  fi
}

# herdr, graphify and playwright-cli ship their own skills, generated from the installed
# versions; marimo and langfuse publish theirs in git repos.
vendor() { sh "$REPO_DIR/scripts/vendor-skills.sh" "$HOME/.claude/skills" "$@"; }
job_graphify() {
  command -v uv >/dev/null 2>&1 || { echo "uv not found"; return 1; }
  uv tool install graphifyy==0.9.88 || return 1
  # uv puts the binary in ~/.local/bin, which the skill step needs on PATH.
  PATH="$PATH:$HOME/.local/bin" vendor graphify
}
job_playwright() {
  command -v npm >/dev/null 2>&1 || { echo "npm not found"; return 1; }
  npm install -g @playwright/cli@0.1.24 || return 1
  j_ok=0
  vendor playwright-cli || j_ok=1
  playwright-cli install-browser chromium || j_ok=1
  return "$j_ok"
}
job_skills() { vendor herdr marimo-notebook langfuse; }
job_plugin() { plugin "$@"; }

job "graphify" job_graphify
job "playwright-cli + chromium" job_playwright
job "herdr, marimo, langfuse skills" job_skills
# every plugin the run installs, "id source" per line. langfuse has a job of its own.
PLUGIN_SPECS="langfuse-observability@langfuse-observability langfuse/Claude-Observability-Plugin
cardea@cardea $REPO_DIR
superpowers@superpowers-marketplace obra/superpowers-marketplace
ponytail@ponytail DietrichGebert/ponytail
apple-skills@apple-skills Prisma-Labs-Dev/apple-skills
cloudflare@cloudflare cloudflare/skills
humanizer@humanizer blader/humanizer
axe@axe cameroncooke/AXe"
while read -r s_id s_src; do
  case "$s_id" in langfuse-observability@*) continue ;; esac
  job "plugin ${s_id%@*}" job_plugin "$s_id" "$s_src"
done <<PLUGINS
$PLUGIN_SPECS
PLUGINS

# --- env -------------------------------------------------------------------
# load whatever is already there so re-runs offer the current value as the default.
step "configuration"
if [ -f "$ENV_FILE" ]; then
  load_env
  derive_nas
  info "editing existing .env — press enter to keep a value"
elif [ -z "$PROMPT" ]; then
  cp "$REPO_DIR/.env.example" "$ENV_FILE"
  FROM_EXAMPLE=1
  [ -n "${NOTTY:-}" ] && info "no terminal available, so nothing was asked"
fi

# gum input reads keys from stdin, which is the script itself under curl | sh, so it is
# pointed at the terminal. it ignores ctrl-d, so esc stands in for it there.
# gum_read <placeholder> <label> [flags]: sets reply, and g_rc to 0 (enter), 1 (esc), or
# anything else when gum could not draw and the caller should fall back to a plain read.
gum_read() {
  g_ph="$1"; g_label="$2"; shift 2
  g_rc=0
  reply=$(gum input "$@" --prompt "  ${g_label}› " --prompt.foreground "$ACCENT" \
    --cursor.foreground "$ACCENT" --placeholder "$g_ph" --no-show-help < /dev/tty 2>/dev/tty) || g_rc=$?
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
# while you are still looking at it, not at the end of the run.
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
    warn_mdns "$u_value" "$(printf '%s' "$u_shown" | sed 's/ *$//')"
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
ask_url NAS_URL "nas url              " "http://truenas.local" probe_http
# everything runs on the one NAS, so offer its host to the other services.
derive_nas
ask_url LANGFUSE_HOST    "langfuse url         " "${NAS_BASE:-http://truenas.local}:3000" probe_langfuse
ask_secret LANGFUSE_PUBLIC_KEY "langfuse public key  "
ask_secret LANGFUSE_SECRET_KEY "langfuse secret key  "

# write atomically, then lock it down: this file holds keys.
TMP_ENV="$ENV_FILE.$$"
{
  printf '# cardea — written by install.sh on %s. not committed.\n\n' "$STAMP"
  printf '# --- nas ---\n'
  printf 'NAS_URL=%s\n\n' "$NAS_URL"
  printf '# --- hindsight (NAS) ---\n'
  printf 'HINDSIGHT_MCP_TOKEN=%s\n\n' "${HINDSIGHT_MCP_TOKEN:-}"
  printf '# --- langfuse (NAS) ---\n'
  printf 'LANGFUSE_HOST=%s\n'          "$LANGFUSE_HOST"
  printf 'LANGFUSE_PUBLIC_KEY=%s\n'    "$LANGFUSE_PUBLIC_KEY"
  printf 'LANGFUSE_SECRET_KEY=%s\n'    "$LANGFUSE_SECRET_KEY"
} > "$TMP_ENV"
mv "$TMP_ENV" "$ENV_FILE"
chmod 600 "$ENV_FILE"
if [ -n "${FROM_EXAMPLE:-}" ]; then warn ".env created with placeholder values (mode 600)"; else ok "wrote .env (mode 600)"; fi

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

# --- late jobs -------------------------------------------------------------
# these bake in what the prompts just collected. cardea's own plugin is installed from this
# checkout, which claude code reads in place, so edits here show up at the next session.
# user scope, so every project gets the servers. rerun this script after changing .env;
# remove-then-add keeps it idempotent.
mcp_json() {
  case "$1" in
    xcodebuild)    echo '{"type":"stdio","command":"npx","args":["-y","xcodebuildmcp@2.7.0","mcp"],"env":{"XCODEBUILDMCP_SENTRY_DISABLED":"true"}}' ;;
    swiftlens)     echo '{"type":"stdio","command":"uvx","args":["swiftlens@0.2.14"]}' ;;
    # a bare `xcrun mcpbridge` is the bridge; it only connects while xcode is running.
    xcode)         echo '{"type":"stdio","command":"xcrun","args":["mcpbridge"]}' ;;
    # one bank for every project; the bearer token sits in the registered command, as keys do elsewhere.
    hindsight)     printf '{"type":"http","url":"%s:8888/mcp/cardea/","headers":{"Authorization":"Bearer %s"}}\n' "$NAS_BASE" "$HINDSIGHT_MCP_TOKEN" ;;
  esac
}
mcp() {
  claude mcp remove -s user "$1" >/dev/null 2>&1 || true
  claude mcp add-json -s user "$1" "$(mcp_json "$1")" >/dev/null && echo "mcp: $1" || { echo "mcp: $1 — could not register"; return 1; }
}
# the servers this run registers; hindsight only with a token and a NAS host.
mcp_wanted() { echo "xcodebuild swiftlens xcode${HINDSIGHT_MCP_TOKEN:+${NAS_BASE:+ hindsight}}"; }
job_mcp() {
  j_ok=0
  for j_name in xcodebuild swiftlens xcode; do
    mcp "$j_name" || j_ok=1
  done
  if [ -n "${HINDSIGHT_MCP_TOKEN:-}" ] && [ -n "$NAS_BASE" ]; then
    mcp hindsight || j_ok=1
  else
    claude mcp remove -s user hindsight >/dev/null 2>&1 || true
    echo "mcp: hindsight — no token in .env, skipped"
  fi
  return "$j_ok"
}
job_langfuse() {
  plugin langfuse-observability@langfuse-observability langfuse/Claude-Observability-Plugin || return 1
  # point it at the NAS even without keys, so it never falls back to langfuse's own cloud.
  # stdin keeps the secret out of the process list.
  [ -n "$LANGFUSE_HOST" ] || return 0
  {
    printf '{"LANGFUSE_BASE_URL":"%s"' "$LANGFUSE_HOST"
    [ -n "$LANGFUSE_PUBLIC_KEY" ] && printf ',"LANGFUSE_PUBLIC_KEY":"%s"' "$LANGFUSE_PUBLIC_KEY"
    [ -n "$LANGFUSE_SECRET_KEY" ] && printf ',"LANGFUSE_SECRET_KEY":"%s"' "$LANGFUSE_SECRET_KEY"
    printf '}'
  } | claude plugin configure langfuse-observability@langfuse-observability --values-stdin \
    && echo "langfuse plugin → $LANGFUSE_HOST" || { echo "langfuse plugin configure failed — run /plugin configure in claude"; return 1; }
  [ -n "$LANGFUSE_PUBLIC_KEY" ] || echo "no langfuse keys yet — tracing stays off until you add them and rerun"
}
job "mcp servers" job_mcp
job "plugin langfuse-observability" job_langfuse

# claude's own files are written by several jobs at once; read them back, and redo serially
# whatever a concurrent write lost. a job that failed already said so, so it is not retried.
verify_claude() {
  v_list=$(claude plugin list --json 2>/dev/null || true)
  while read -r v_id v_src; do
    v_label="plugin ${v_id%@*}"
    case "$FAILED_LABELS" in *"|$v_label|"*) continue ;; esac
    case "$v_list" in *"\"id\": \"$v_id\""*) continue ;; esac
    plugin "$v_id" "$v_src" >/dev/null 2>&1 || true
    if claude plugin list --json 2>/dev/null | grep -q "\"id\": \"$v_id\""; then
      warn "plugin ${v_id%@*}: a concurrent write was lost and repaired"
    else
      JOB_FAILS=$((JOB_FAILS + 1)); bad "plugin ${v_id%@*}: not recorded, even after a retry"
    fi
  done <<VERIFY
$PLUGIN_SPECS
VERIFY
  case "$FAILED_LABELS" in *"|mcp servers|"*) return 0 ;; esac
  MCP_LIST=$(claude mcp list 2>/dev/null || true)
  v_redo=
  for v_name in $(mcp_wanted); do
    printf '%s\n' "$MCP_LIST" | grep -q "^$v_name:" && continue
    mcp "$v_name" >/dev/null 2>&1 || true
    v_redo=1
    if claude mcp list 2>/dev/null | grep -q "^$v_name:"; then
      warn "mcp $v_name: a concurrent write was lost and repaired"
    else
      JOB_FAILS=$((JOB_FAILS + 1)); bad "mcp $v_name: not recorded, even after a retry"
    fi
  done
  [ -z "$v_redo" ] || MCP_LIST=$(claude mcp list 2>/dev/null || true)
}

# confirm <question> <y|n>: the answer is the exit status, and the second argument is what enter
# picks. eof (ctrl-d, or a closed tty) answers no.
confirm() {
  q_def=$2
  if has_gum; then
    q_flag=--default=true; [ "$q_def" = y ] || q_flag=--default=false
    q_rc=0
    gum confirm "$1" "$q_flag" --prompt.foreground "$ACCENT" --selected.background "$ACCENT" \
      --no-show-help < /dev/tty > /dev/tty 2>&1 || q_rc=$?
    [ "$q_rc" -ne 130 ] || { printf '\n' > /dev/tty; exit 130; }
    if [ "$q_rc" -le 1 ]; then
      if [ "$q_rc" -eq 0 ]; then chosen "$1" yes; else chosen "$1" no; fi
      return "$q_rc"
    fi
  fi
  if [ "$q_def" = y ]; then q_hint='[Y/n]'; else q_hint='[y/N]'; fi
  printf '  %s%s%s %s%s%s ' "$B" "$1" "$R" "$D" "$q_hint" "$R" > /dev/tty
  read -r q_reply < /dev/tty || q_reply=n
  case "$q_reply" in
    '') [ "$q_def" = y ] ;;
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

# the profile that a new shell reads for its PATH.
profile_file() {
  case "${SHELL:-}" in
    */zsh) echo "$HOME/.zshrc" ;;
    */bash) echo "$HOME/.bashrc" ;;
    *) echo "$HOME/.profile" ;;
  esac
}

# offer each fixable warning once, after the summary. nothing is asked or changed without a prompt.
offer_fixes() {
  [ -n "$PROMPT" ] && [ -n "$FIXES" ] || return 0
  printf '\n'
  for f_id in $FIXES; do
    case "$f_id" in
      path)
        f_file=$(profile_file); f_line='export PATH="$HOME/.local/bin:$PATH"'
        confirm "add ~/.local/bin to PATH in ~${f_file#"$HOME"}?" y || continue
        if { [ -f "$f_file" ] && grep -qxF "$f_line" "$f_file"; } || printf '%s\n' "$f_line" >> "$f_file"; then
          PATH="$HOME/.local/bin:$PATH"; ok "~/.local/bin on PATH, set in ~${f_file#"$HOME"}"
        else
          bad "could not write to $f_file"
        fi ;;
      docker)
        confirm "open OrbStack to start docker?" y || continue
        if open -a OrbStack; then ok "OrbStack opened"; else bad "could not open OrbStack"; fi ;;
      herdr)
        confirm "retry herdr's claude integration?" y || continue
        if spin "installing herdr's claude integration" herdr integration install claude >/dev/null; then
          ok "herdr integration"
        else
          bad "herdr integration failed again — run it by hand"
        fi ;;
      shadow)
        confirm "delete the native claude in ~/.local/bin?" n || continue
        if rm "$HOME/.local/bin/claude"; then ok "removed the native claude in ~/.local/bin"; else bad "could not delete ~/.local/bin/claude"; fi ;;
    esac
  done
}

# the agent setting makes a plain `claude` start as the orchestrator; an explicit --agent still wins.
# no answer (--no-prompt, no terminal) leaves the key alone, and a foreign value is never removed.
offer_default_agent() {
  [ -n "$PROMPT" ] || return 0
  printf '\n'
  if confirm "start every claude session as cardea:orchestrator?" y; then a_want=1; else a_want=; fi
  if a_now=$(WANT="$a_want" python3 -c '
import json, os, sys
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) else {}
if os.environ["WANT"]:
    d["agent"] = "cardea:orchestrator"
elif d.get("agent") == "cardea:orchestrator":
    del d["agent"]
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
print(d.get("agent", "none"))
' "$HOME/.claude/settings.json" 2>/dev/null); then
    ok "default agent: $a_now"
  else
    warn "could not edit ~/.claude/settings.json — set \"agent\" by hand"
  fi

  a_file=$(profile_file)
  a_lines='# label hand-started claude sessions in Langfuse
export CC_LANGFUSE_TRACE_TAGS="${CC_LANGFUSE_TRACE_TAGS:-agent:cardea:orchestrator}"
export LANGFUSE_TRACING_ENVIRONMENT="${LANGFUSE_TRACING_ENVIRONMENT:-agent-orchestrator}"'
  if [ -n "$a_want" ]; then
    printf '%s\n' "$a_lines" | while IFS= read -r a_line; do
      { [ -f "$a_file" ] && grep -qxF "$a_line" "$a_file"; } || printf '%s\n' "$a_line" >> "$a_file" || exit 1
    done && ok "Langfuse agent label set in ~${a_file#"$HOME"}" || bad "could not write to $a_file"
  elif [ -f "$a_file" ] && printf '%s\n' "$a_lines" | grep -qxFf - "$a_file"; then
    a_tmp="$a_file.cardea.$$"
    { printf '%s\n' "$a_lines" | grep -vxFf - "$a_file" > "$a_tmp" || [ $? -eq 1 ]; } &&
      cat "$a_tmp" > "$a_file" && rm -f "$a_tmp" && ok "Langfuse agent label removed from ~${a_file#"$HOME"}" || bad "could not edit $a_file"
  fi
}

step "installing"
await_jobs
verify_claude
run_checks
summary
offer_fixes
offer_default_agent

# --- next steps ------------------------------------------------------------
if has_gum; then
  printf '\n  %s\n\n' "$(paint --bold --foreground "$ACCENT" -- 'Next')"
  printf '  1. %s\n     sign in with your claude subscription (interactive)\n' "$(paint --bold -- 'claude auth login')"
  printf '  2. per iOS project\n     %s\n' "$(paint --bold -- 'xcode-build-server config -project X.xcodeproj -scheme X')"
  printf '  3. on the NAS, in /mnt/main/Docker/lab\n     %s\n     %s\n' "$(paint --bold -- 'sudo docker compose up -d')" \
    "$(paint --faint -- 'https://yuzuholic.github.io/cardea/docs/nas')"
  printf '\n  %s\n\n' "$(paint --faint -- 're-run anytime. ./install.sh --check probes without changing anything.')"
else
  printf '\n  %s%sNext%s\n' "$BLU" "$B" "$R"
  cat <<EOF
  1. claude auth login                   sign in with your claude subscription (interactive)
  2. per iOS project                     xcode-build-server config -project X.xcodeproj -scheme X
  3. on the NAS                          sudo docker compose up -d in /mnt/main/Docker/lab
                                         (see https://yuzuholic.github.io/cardea/docs/nas)

  re-run anytime. ${D}./install.sh --check${R} probes without changing anything.

EOF
fi

# a failed job already showed its log, and a missing tool the summary; the exit status says so too.
[ "$JOB_FAILS" -eq 0 ] && [ -z "$MISSING" ] || exit 1
}

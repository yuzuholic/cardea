"""cardea's claude code hooks: python3 hook.py session|secrets|commit|web, hook json on stdin.
every hook fails open: any error exits 0 with no output, so a broken hook never blocks."""
import json
import os
import re
import shlex
import subprocess
import sys
import time
import urllib.request

ALLOWED_ENV = {".env.example", ".env.sample", ".env.template"}
READERS = {"cat", "less", "more", "head", "tail", "grep", "egrep", "fgrep", "rg", "sed", "awk",
           "gawk", "bat", "source", ".", "nl", "tac", "strings", "xxd", "od", "hexdump", "base64"}
STDOUT = {"/dev/stdout", "/dev/fd/1", "/dev/tty", "-"}
TYPES = ("feat", "fix", "docs", "style", "refactor", "test", "chore", "perf", "ci", "build")
BM_TIMEOUT = 1.5
NOTES = 5
STATE_DAYS = 7


def emit(event, **fields):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": event, **fields}}))


def deny(reason):
    emit("PreToolUse", permissionDecision="deny", permissionDecisionReason=reason)


# session start

def git_project(path):
    # the common dir, so a worktree still maps to its repo's project.
    out = subprocess.run(["git", "-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                         capture_output=True, text=True, timeout=2).stdout.strip()
    if not out:
        return os.path.basename(os.path.abspath(path)).lower()
    root = os.path.dirname(out) if os.path.basename(out) == ".git" else out.removesuffix(".git")
    return os.path.basename(root).lower()


def mcp_call(url, tool, arguments):
    headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}

    def post(body):
        req = urllib.request.Request(url, json.dumps(body).encode(), headers)
        with urllib.request.urlopen(req, timeout=BM_TIMEOUT) as r:
            if r.headers.get("mcp-session-id"):
                headers["mcp-session-id"] = r.headers["mcp-session-id"]
            text = r.read().decode()
        for line in text.splitlines():
            if line.startswith("data:"):
                msg = json.loads(line[5:])
                if msg.get("id") == body.get("id"):
                    return msg
        return json.loads(text) if text.strip() else {}

    post({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "cardea-hook", "version": "1"}}})
    headers["MCP-Protocol-Version"] = "2025-06-18"
    post({"jsonrpc": "2.0", "method": "notifications/initialized"})
    return post({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                 "params": {"name": tool, "arguments": arguments}})["result"]


def recent_notes(project):
    try:
        with open(os.path.expanduser("~/.claude.json")) as f:
            url = json.load(f)["mcpServers"]["basic-memory"]["url"]
    except Exception:
        return ["- Basic Memory isn't configured for Claude Code; skip it."]
    try:
        result = mcp_call(url, "recent_activity", {"project": project, "timeframe": "7d",
                                                    "page_size": NOTES, "output_format": "json"})
    except Exception:
        return ["- Basic Memory is unreachable (it answers on the LAN only); carry on without it."]
    text = "".join(c.get("text", "") for c in result.get("content", []))
    if result.get("isError"):
        if "not found" in text.lower():
            return [f'- Basic Memory has no project "{project}" yet; ask the user before creating one.']
        return ["- Basic Memory returned an error for recent_activity; skip it this session."]
    rows = (result.get("structuredContent") or {}).get("result")
    if not isinstance(rows, list):
        rows = json.loads(text)
    titles = [r["title"] for r in rows if isinstance(r, dict) and r.get("title")][:NOTES]
    if not titles:
        return [f"- No notes changed in {project} in the last 7 days."]
    return [f"- Notes changed in {project} in the last 7 days:"] + [f"  - {t}" for t in titles]


def session(data):
    path = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
    project = git_project(path)
    graph = os.path.isdir(os.path.join(path, "graphify-out"))
    lines = [
        "cardea session note:",
        "- Look things up in the order the retrieval-order skill sets: this session, rules and memory, "
        "Basic Memory, the active plan, graphify, Serena and the code, git history, live evidence, "
        "skills and docs, then the web, and the user last. Stop at the first source that answers.",
        f'- Basic Memory project for this repo: "{project}" (pass it as project).',
        "- graphify-out/ exists here: start codebase questions with the graphify skill." if graph
        else "- No graphify-out/ in this project.",
    ]
    try:
        lines += recent_notes(project)
    except Exception:
        lines.append("- Couldn't read recent Basic Memory notes; skip them.")
    emit("SessionStart", additionalContext="\n".join(lines))


# secrets

def secret(word):
    name = os.path.basename(word.rstrip("/").split("=")[-1].strip("'\""))
    if name in ALLOWED_ENV:
        return False
    return bool(re.fullmatch(r"\.env([.*?\[].*)?", name)
                or re.fullmatch(r"id_(rsa|ed25519|ecdsa|dsa)", name)
                or re.search(r"\.(pem|key|p12|p8)$", name))


def bash_secret(command):
    # ponytail: word-level scan of each simple command, not a shell parser. it catches the
    # obvious readers; indirection (a variable, a script, grep -r over a folder) gets through.
    for segment in re.split(r"[;&|\n`()]|\$\(", command):
        for target in re.findall(r"(?<![<\d])<(?!<)\s*(\S+)", segment):
            if secret(target):
                return target
        words = [w.strip("'\"") for w in segment.split()]
        while words and (re.fullmatch(r"\w+=.*", words[0]) or words[0] in {"sudo", "command", "env", "nohup", "time", "exec"}):
            words.pop(0)
        if not words:
            continue
        cmd = os.path.basename(words[0])
        hits = [w for w in words[1:] if secret(w)]
        if hits and (cmd in READERS or (cmd == "cp" and STDOUT & set(words[1:]))):
            return hits[0]
    return None


def secrets(data):
    tool, args = data.get("tool_name"), data.get("tool_input") or {}
    if tool == "Bash":
        hit = bash_secret(args.get("command", ""))
    else:
        hit = next((p for p in (args.get("file_path"), args.get("path"), args.get("glob")) if p and secret(p)), None)
    if hit:
        deny(f"cardea: {hit} holds secrets (a .env file or a private key), so no tool may read or print it. "
             "Secrets are referenced through environment variables only: use the variable name, and read "
             ".env.example for the names. Don't try another tool or command to get at it.")


# commit message

def heredoc(text):
    m = re.search(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n(.*?)\n[ \t]*\2[ \t]*(\n|$)", text, re.S)
    return m.group(3) if m else None


def commit_message(command):
    """the inline message of a git commit in command, or None when there isn't one to check."""
    m = re.search(r"\bgit\s+(?:-[Cc]\s+\S+\s+)*commit\b(.*)", command, re.S)
    if not m:
        return None
    rest = m.group(1)
    if re.match(r"[^\n]*?(-m\s*|--message[=\s]\s*)\"\$\(cat\s*<<", rest):
        return heredoc(rest)
    if re.match(r"[^\n]*?(\s-F\s*-|\s--file[=\s]-)(\s|$)", rest):
        return heredoc(rest)
    try:
        lex = shlex.shlex(rest.split("\n")[0] if "<<" in rest else rest, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        words = list(lex)
    except ValueError:
        return None
    parts, i = [], 0
    while i < len(words):
        w = words[i]
        if w in {"&&", "||", ";", "|", "&"}:
            break
        flag = re.fullmatch(r"-[a-ln-zA-Z]*m(.*)|--message(?:=(.*))?", w)
        if flag:
            if flag.group(1) or flag.group(2):
                parts.append(flag.group(1) or flag.group(2))
            elif i + 1 < len(words):
                i += 1
                parts.append(words[i])
        i += 1
    if not parts or any("$" in p or "`" in p for p in parts):
        return None
    return "\n\n".join(parts)


def commit_problems(message):
    lines = message.strip().split("\n")
    subject, problems = lines[0], []
    m = re.fullmatch(r"(\w+)(\([^)]*\))?(!)?: (.+)", subject)
    if not m:
        problems.append(f'"{subject}" is not "<type>: <subject>"')
    else:
        kind, scope, bang, text = m.groups()
        if kind not in TYPES:
            problems.append(f'"{kind}" is not a type; use one of {", ".join(TYPES)}')
        if scope or bang:
            problems.append(f'drop the scope or "!": write "{kind}: {text}"')
        if text[0].isupper():
            problems.append("start the subject with a lowercase letter")
        if text.endswith("."):
            problems.append("drop the trailing period")
    if len(subject) >= 72:
        problems.append(f"the line is {len(subject)} characters; keep it under 72")
    rest = [line for line in lines[1:] if line.strip()]
    if any(re.match(r"[\w-]+:\s", line) for line in rest):
        problems.append("remove the trailers (Co-Authored-By and the like)")
    elif rest:
        problems.append("remove the body; the message is the subject line only")
    return problems


def commit(data):
    message = commit_message((data.get("tool_input") or {}).get("command", ""))
    problems = commit_problems(message) if message else []
    if problems:
        deny("cardea: commit message rejected: " + "; ".join(problems) + ". The format is one line, "
             '"<type>: <subject>", no scope, lowercase start, no trailing period, under 72 characters, '
             "no body and no Co-Authored-By or other trailers.")


# web nudge

def web(data):
    sid = re.sub(r"[^\w-]", "", data.get("session_id") or "")
    if not sid:
        return
    state = os.path.join(os.environ.get("CLAUDE_PLUGIN_DATA") or "/tmp/cardea", "web-nudged")
    os.makedirs(state, exist_ok=True)
    try:
        os.close(os.open(os.path.join(state, sid), os.O_CREAT | os.O_EXCL | os.O_WRONLY))
    except FileExistsError:
        return
    cutoff = time.time() - STATE_DAYS * 86400
    for name in os.listdir(state):
        p = os.path.join(state, name)
        if os.path.getmtime(p) < cutoff:
            os.remove(p)
    emit("PreToolUse", additionalContext=(
        "cardea: before relying on the web, check Basic Memory, the code and the git history first, "
        "as the retrieval-order skill sets out. The web is for current versions, external APIs and "
        "anything new. This reminder shows once per session."))


if __name__ == "__main__":
    try:
        {"session": session, "secrets": secrets, "commit": commit, "web": web}[sys.argv[1]](json.load(sys.stdin))
    except Exception:
        pass

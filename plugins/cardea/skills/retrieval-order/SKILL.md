---
name: retrieval-order
description: "The order to look things up in: session, rules, Hindsight, the active plan, the vault, graphify, the code, git history, live evidence, docs, the web, then the user. Use before any search or lookup: finding code, answering how or why something works, checking a past decision, looking up an API or a fact, or before asking the user a question."
---

# Retrieval order

Look things up cheapest and most authoritative first, and stop at the first source that answers.
Asking the user is last.

## The order

| # | Source | Answers | How |
|---|---|---|---|
| 1 | **This session** | What was said, read or decided already | Scroll back before you search again. |
| 2 | **Rules and auto-memory** | Standing instructions and facts about the user | Global and project `CLAUDE.md`, and the auto-memory `MEMORY.md`. Already loaded; reread them, don't rediscover them. |
| 3 | **Hindsight** | Past decisions, constraints, preferences, gotchas: the *why* | `recall` with `include_chunks: true`, filtered by `project:<app>` (see `hindsight`). |
| 4 | **The active plan** | What we agreed to do right now | The plan file under `/tmp` named in this session, read by path. |
| 5 | **The vault** | Settled, authored knowledge about a project | The page in `/Volumes/NAS/Vault/<Project>/`: start at its home page or `Index` (see `obsidian`). |
| 6 | **graphify** | Where to look in a codebase you don't know yet | `graphify-out/` if it exists (see `graphify`). |
| 7 | **The code** | What actually exists: the *what* | Grep, Glob and Read. |
| 8 | **Git history and GitHub** | Why the code is this way, and when it changed | `git log -S`, `git log -p <file>`, `git blame`; `gh pr` and `gh issue` for the discussion. |
| 9 | **Live evidence** | What really happens when it runs | Run the test, build or app: XcodeBuildMCP, the simulator, `gh run view --log-failed` for CI. |
| 10 | **Skills and offline docs** | How to do a kind of task; Apple APIs | The skill that matches the task; the apple-skills references before the web. |
| 11 | **The web** | Current versions, external APIs, anything new | Official docs and changelogs first. Say "unverified" when sources disagree. |
| 12 | **The user** | Intent, preferences, decisions only they can make | Only after the above. Say what you checked. |

## Which source wins

- **Why something is the way it is:** Hindsight and git history, over your reading of the code.
- **What the code does now:** the code and live evidence, over notes, comments and docs, which go
  stale. If a note contradicts the code, trust the code and update the note.
- **What to do next:** the user's latest message, then the active plan.
- **Versions and external APIs:** the web, checked against what's installed (`--version`, lock
  files).

## Rules

- **Don't skip ahead.** Never search the web or ask the user for something a note, the code or
  the history already holds.
- **Go deeper only on a miss.** Move down the order only when the current source has nothing,
  or when what it says needs checking against something more authoritative.
- **Name the source.** Say where an answer came from, especially when it isn't the code.
- **Write back.** When an answer cost real digging and will matter again, retain it in Hindsight
  so the next lookup stops at step 3.
- **Past sessions.** Earlier conversations are in Langfuse on the NAS (see `langfuse`), which
  only the user can open. Point them to it rather than guessing what was said.

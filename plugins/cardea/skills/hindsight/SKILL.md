---
name: hindsight
description: "Recall and retain durable memory in Hindsight, the self-hosted memory server. Use before asking the user something they may have answered, before a design choice a past decision may cover, after a lasting decision, constraint or preference, or when the user says 'remember', 'what did we decide', 'hindsight' or 'memory'."
---

# Hindsight

Hindsight is the long-term memory shared by every session and project: decisions, constraints,
preferences, gotchas and the reason behind them. It is the MCP server `hindsight`, bank `cardea`
(one bank for all projects). It extracts facts from what is retained, so retain short,
self-contained statements with the reason, never transcripts. Settled, authored knowledge lives in
the vault instead (see `obsidian`).

## Recall

- Before asking the user a question about past decisions or preferences. Ask only if nothing
  answers it.
- Before a design choice, or a change a past decision may cover (schema, dependency,
  architecture).
- At the start of non-trivial work, once, scoped by the project tag. Do not dump the bank.
- When the user says "what did we decide", "did we ever", "last time", "why did we", "remind me",
  or names a project or component not yet seen this session.

Call `recall` with `query` and `include_chunks: true`: extracted facts drop detail, and the chunk
holds the original wording. Filter with `tags` on `project:<app>`. Cap chunk size with
`max_chunk_tokens`.

Make at most two `recall` calls per lookup, stop at the first answer and do not recall again for
something already recalled this session. Code and live evidence beat a recalled fact when they
disagree: correct the memory rather than trusting it.

## Retain

Whether to save is one judgment on a spectrum. At one end is a real design choice, constraint or
preference meant to outlast this session. At the other is something mentioned for the work at
hand, which stays in the conversation. Save only what sits clearly at the lasting end; a trigger
phrase is evidence, never the decision. When a case sits near the middle, do not save; ask once if
the value is high.

| Said | Placement |
|---|---|
| "we use pnpm for all web projects" | Save: a standing rule |
| "use pnpm here" (mid-task) | Session only |
| "remember: releases are cut from main only" | Save: a constraint |
| "remember to bump the version before merging" | Session only: a task reminder |
| "always give me the short version" | Save: a global preference |
| "keep it short, I'm on my phone" | Session only: tied to the moment |

Implicit candidates: a confirmed decision, a constraint not visible in the code, a correction that
will recur, a preference beyond this task, the root cause of a non-obvious fixed bug, and a
finished task's outcome. Save once it is settled (decision confirmed, fix verified, task done),
not the moment it appears.

An explicit "remember this" always saves, through `/cardea:remember <text>`.

### Never save

- Secrets: keys, tokens, passwords, `.env` values, connection strings with credentials, private
  keys. Refuse even when asked, and say why.
- Transient state: the current branch, running processes, a failing test mid-debug, scratchpad
  contents.
- What the repo records: code structure, git history, CLAUDE.md content, file lists.
- Chit-chat, mood, persona flourish, session logs and turn-by-turn narration.
- Unverified guesses, unless labelled `unverified`.
- Personal data about third parties.

### Shape

- `content`: one to three plain sentences, present tense, self-contained: what, and why. No persona.
- `tags`: a preference is global by default and carries no project tag; add `project:<app>` only
  when it is tied to how one app works. Other memories carry `project:<app>`. Add one kind tag
  (`decision`, `constraint`, `preference`, `gotcha`, `outcome`).
- `document_id`: `<project>/<kind>/<slug>`, or `user/preference/<slug>` for a global preference.
  The slug is lowercase and hyphenated, from the subject. Reuse an id only to refine the same fact
  in place.
- `context`: one line on where it came from, such as `user instruction`.

### Superseding

Never overwrite a decision or a wrong fact. Retain the new memory under a new `document_id`, with
text that names what it replaces and why, then call `invalidate_memory` on the old memory with the
reason. The old one stays as history.

## If it is unreachable

The server answers on the LAN only. If calls fail, say so and carry on; do not retry in a loop.
`./install.sh --check` in the cardea repo tests it.

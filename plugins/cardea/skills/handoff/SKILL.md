---
name: handoff
description: Hand the session over to a fresh one before autocompact - write a complete summary of the work, start a new Claude session in a new herdr tab with it, and close the old pane once the new one confirms. Use when cardea's hook says the context is near autocompact, or when the user says "handoff", "/handoff", "hand off" or "fresh session".
---

# Handoff

Autocompact summarises in a hurry at the limit and drops details. A handoff is a deliberate
summary written while there is still room, read by a fresh session with a clean context.

## When

- cardea's `UserPromptSubmit` hook adds a note once a session passes about 195k tokens (65% of
  the 300k window, ten points before autocompact). Answer the user's message first, then propose
  the handoff in one line.
- Or the user asks for one.

Always propose and wait for a yes; never hand off on your own. Outside herdr
(`HERDR_ENV` is not `1`), write the summary in chat instead and tell the user to start a new
session with it.

Before handing off, file anything durable as usual: decisions in Basic Memory or the project's
decisions page. The summary carries the session, not the long-term record.

## 1. Write the summary

Leave nothing out: the new session knows only what this says. Formal and plain, no persona.
Write it to a file in the scratchpad (or `/tmp`), in this order:

1. **Opening line, verbatim:** `You are taking over from a previous session that is closing.
   Read everything below, then reply with RECEIVED followed by the to-do list, one line per
   item, and wait for the user's next message.`
2. **Session:** its name, the repo, the branch, the agent type and effort, and the old
   transcript path (`~/.claude/projects/<project>/<session id>.jsonl`) for looking up details.
3. **The user's instructions this session:** every standing instruction, preference and
   correction, quoted where the wording matters.
4. **Done:** each piece of work, with how it was checked and whether it is committed or pushed.
5. **In progress:** the exact state, including commands mid-run and background jobs.
6. **To do:** everything outstanding, including what waits for the user's word. Mark what must
   not start without approval.
7. **Decisions:** what was decided, and where each is recorded.
8. **Files:** every file changed, created or left uncommitted, and scratch files still needed.
9. **Problems:** errors hit, how each was fixed, and anything unresolved.
10. **Other agents:** herdr agents and implementers in flight, by name and pane, and any
    requests from peers still open.

## 2. Start the new session

Read the current flags: `herdr pane process-info --current`, then take the `claude` entry's
argv without `claude` itself and without `--resume`, `-r`, `--continue` or `-c` and their
values. The title is this session's name (the pane's terminal title, such as
`Cardea - Orchestrator`).

```sh
sh "${CLAUDE_PLUGIN_ROOT}/skills/handoff/scripts/start.sh" <summary-file> "<title>" [flags...]
```

The script opens a tab in this workspace and this session's folder, starts Claude with the same
flags, renames the session to the title, sends the summary, waits for the reply and prints it
with the new agent's name and pane. If Claude stops at the folder-trust prompt, the script
accepts it, because the old session already works in that folder. Any other startup block stops
the script with nothing sent; tell the user and leave both sessions open.

## 3. Close the old session

Check the printed reply: `RECEIVED` and a to-do list that matches the summary. If either is
missing or wrong, stop, leave both sessions open and tell the user.

When it matches, tell the user in one line which tab took over, then close this pane as the
last action: `herdr pane close "$HERDR_PANE_ID"`. A tab whose last pane closes closes with it.

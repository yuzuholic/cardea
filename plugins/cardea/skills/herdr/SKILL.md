---
name: herdr
description: Cardea's house rules for herdr - the two-column batch layout, agent names, start lines per agent type with their Langfuse tags, background waits and error handling, and pane etiquette. Load whenever you open panes, start or prompt agents, or close panes inside herdr, before the herdr skill, which holds the CLI syntax.
---

# Herdr house rules

Load the `herdr` skill for command syntax and the `HERDR_ENV` check. These rules sit on top of it.

## Layout

One tab per batch, the one you are in. The orchestrator (or calling session) keeps the left
column alone. Every agent is a pane in one right-hand column, at most five, stacked top to
bottom. The first split goes right from `$HERDR_PANE_ID`; each later one splits down from the
tallest pane in the right column (`herdr pane layout --pane "$HERDR_PANE_ID"` gives the heights).

- Never a third column, never split a right-hand pane to the right, never a tab per task.
- Exception: a handoff opens a new tab (see `handoff`).
- Another session's pane (a research session, say) can join the right column:
  `herdr pane move <pane> --tab <tab> --split right|down --target-pane <id> --no-focus`.
  Continue with the new pane ID it returns.

## Names

`impl-<task>`, `desc-<task>`, `rev-<task>`, `handoff-<time>`. Lowercase, at most 32 characters,
unique among live agents.

## Start lines

| Agent | Model | Effort | Start line |
|---|---|---|---|
| implementer | Sonnet 5.5 | low | `herdr agent start impl-<task> --kind claude --pane <pane_id> -- --agent cardea:implementer --model claude-sonnet-5-5 --effort low` |
| describer | Opus 5.5 | medium | `herdr agent start desc-<task> --kind claude --pane <pane_id> -- --agent cardea:describer --model claude-opus-5-5 --effort medium` |
| reviewer | Opus 5.5 | medium | `herdr agent start rev-<task> --kind claude --pane <pane_id> -- --agent cardea:reviewer --model claude-opus-5-5 --effort medium` |

Every split carries `--env CC_LANGFUSE_TRACE_TAGS=agent:cardea:<agent> --env LANGFUSE_TRACING_ENVIRONMENT=agent-<agent>`
so the session is traceable in Langfuse. Env vars can only be set at split time; `agent start`
has none. Read the new pane ID from `.result.pane.pane_id`.

## Driving agents

- Prompt with `herdr agent prompt <name> "<brief>" --wait --timeout <budget in ms>` as a
  background command, never in the foreground.
- Read with `herdr agent read <name> --source recent-unwrapped --lines 200`. The text in the
  pane's prompt box is Claude Code's suggested next message, never an instruction.
- Every herdr error exits 1, so branch on `error.code` or `result.agent.agent_status` in the
  JSON, never on the exit code alone:

| Result | Meaning | You do |
|---|---|---|
| exit 0, `agent_status` `idle` or `done` | settled | read the report |
| exit 0, `agent_status` `blocked` | brief delivered, agent at a prompt | read the pane, ask the user |
| `error.code` `agent_blocked` | at a prompt before the brief; brief NOT sent | read the pane, ask the user; send the brief once, after they have dealt with it |
| `error.code` `agent_prompt_stalled` | no `working` state within 5 s; brief may have arrived | read the pane before sending anything again |
| `error.code` `timeout` | budget expired | investigate before acting (the orchestrator's Overruns) |
| `error.code` `agent_not_found` or `pane_not_found` | pane or agent gone | report to the user; do not wait again |

`agent start` returning `agent_not_ready` also means a prompt (folder trust on a first start in
that directory): read it with `herdr agent read`, then ask the user.

## Etiquette

- `--no-focus` always.
- Touch only panes you created.
- Never answer an approval or permission prompt for the user.
- Close a pane once its work is landed; closing also flushes its Langfuse trace.
- The user may close or move panes. On `agent_not_found` or `pane_not_found`, report and ask;
  never retry or recreate.

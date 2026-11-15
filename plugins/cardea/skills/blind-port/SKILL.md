---
name: blind-port
description: Port an existing UI to another framework or codebase without the implementer ever seeing the original - a describer sees it and briefs in words, a blind implementer builds, a reviewer audits the code. Use inside cardea:orchestrator when a UI must be rebuilt to match an existing web or Swift UI, given as a running app, its code or only screenshots, or when the user says "blind port".
---

# Blind port

A blind port moves an existing UI from one framework or codebase to another, for example from
React to SwiftUI. A describer sees the reference UI. A blind implementer builds from the describer's words alone, so
it cannot copy what it cannot see, and the result is judged on how it looks and behaves. Once the
UI passes, a reviewer audits the code.

## 1. Gate

This skill is for orchestrators only. If this session is not running as `cardea:orchestrator`
(a subagent, or a session started without `--agent cardea:orchestrator`), stop and say so: only
the orchestrator opens herdr panes, starts the agents and lands the work. Do not continue.

Blind-port needs herdr (`test "${HERDR_ENV:-}" = 1`), because the blind implementer must be
started with environment variables and only herdr can set them (see step 3). Outside herdr, stop
and tell the user.

For a web reference, check `command -v playwright-cli`. If it is missing, stop and give the user
the install command, `npm install -g @playwright/cli@0.1.24 && playwright-cli install-browser chromium`,
or tell them to rerun `install.sh`.

## Roles

| Role | Agent | Model | Does |
|---|---|---|---|
| Describer | `cardea:describer` | Opus 5.5, medium | Views the reference (`playwright-cli` for web; the official AXe plugin for Swift; the Read tool for screenshots) and may read its code. Writes the rubric, briefs the implementer, grades the rendered UI, never the code. Writes no product code. |
| Blind implementer | `cardea:implementer` | Sonnet 5.5, low | Builds only from the describer's briefs. Never sees the reference. |
| Reviewer | `cardea:reviewer` | Opus 5.5, medium | After building passes: the `comment-audit` skill plus a logic rubric on the code, and applies the fixes. |

## 2. Plan

1. Per feature, collect: the reference, the feature's target directory in the worktree, and the
   check that builds or runs it. The reference is at least one of a running UI (a URL, or an app
   and screen), the absolute paths to its code, or a folder of screenshots.
2. Create one worktree per feature, as the orchestrator's Worktrees section sets out. The blind
   implementer works there; the reference stays in the user's checkout. Exclude `.blind/` so
   `git add -A` cannot stage the rubric and briefs:
   `echo .blind/ >> "$(git -C "$W" rev-parse --git-path info/exclude)"`.
   Pick a reference whose look is its own, not inherited from a shared layout, and block the
   sibling pages or components the look could be copied from as well.
3. Set time budgets for the building and the review phases per the orchestrator's Plan section.
   They still apply, and so do its overrun rules.
4. Work out the blocked set for the implementer:
   - `CARDEA_BLIND_PATHS`: absolute paths to the reference frontend, its build output and any
     screenshots folder, separated by the OS path separator (`:` on macOS and Linux, `;` on Windows). When the
     reference frontend lives in the same repo as the feature, the worktree holds its own copy of
     it: list the reference paths in the user's checkout and their copies inside the worktree.
   - `CARDEA_BLIND_URLS`: comma-separated URL prefixes of the reference dev server and Storybook,
     for example `http://localhost:5173,http://localhost:6006`.

## 3. Enforce blindness

The implementer is started with these variables in its environment:

| Variable | Value |
|---|---|
| `CARDEA_BLIND` | `1` |
| `CARDEA_BLIND_PATHS` | the paths from step 2 |
| `CARDEA_BLIND_URLS` | the URL prefixes from step 2 |

While `CARDEA_BLIND` is set, cardea's hook denies the implementer's reads of the listed paths and
URLs, of `dist/`, `build/`, `.next/` and `storybook-static/`, any `playwright-cli`, AXe or
`simctl` screenshot command, and browser or screenshot MCP tools. A deny never prompts the user.
The describer and reviewer run without the variables.

`herdr agent start` has no environment option, but `herdr pane split` and `herdr tab create` have
`--env <KEY=VALUE>`. A pane created with it passes the variables to commands run at its shell
prompt, and `herdr agent start` runs claude at that prompt, so the implementer inherits them.
Create the implementer's pane with the variables, then start the agent in it as usual (the layout
commands below do this).

Agent-tool fallback: the Agent tool cannot set environment variables on a subagent, so the hook
would not block it and the build would not be blind. Blind-port therefore needs herdr. Outside
herdr, stop and tell the user; never run a blind port through the fallback.

## 4. Layout in herdr

Follow `cardea:herdr` for the layout, names, Langfuse env and etiquette. A feature's describer and
implementer sit in adjacent rows, the implementer directly below its describer. At review, both
close and the reviewer takes one row. Commands (read the pane IDs from the JSON each command
returns):

```sh
# the first describer: split the orchestrator's pane to the right; later ones split the tallest
# right-hand pane down
herdr pane split --pane <orchestrator_pane> --direction right --cwd "<worktree>" --no-focus \
  --env CC_LANGFUSE_TRACE_TAGS=agent:cardea:describer --env LANGFUSE_TRACING_ENVIRONMENT=agent-describer
herdr pane split --pane <tallest_right_pane> --direction down --cwd "<worktree>" --no-focus \
  --env CC_LANGFUSE_TRACE_TAGS=agent:cardea:describer --env LANGFUSE_TRACING_ENVIRONMENT=agent-describer
# the implementer: split its describer's pane down, with the blind variables
herdr pane split --pane <describer_pane> --direction down --cwd "<worktree>" --no-focus \
  --env CC_LANGFUSE_TRACE_TAGS=agent:cardea:implementer --env LANGFUSE_TRACING_ENVIRONMENT=agent-implementer --env CARDEA_BLIND=1 --env "CARDEA_BLIND_PATHS=<paths>" --env "CARDEA_BLIND_URLS=<urls>"
# start the agents in their panes
herdr agent start desc-<feature> --kind claude --pane <describer_pane> -- --agent cardea:describer --model claude-opus-5-5 --effort medium
herdr agent start impl-<feature> --kind claude --pane <implementer_pane> -- --agent cardea:implementer --model claude-sonnet-5-5 --effort low
# at review: split the reviewer pane down from the implementer's, then close the implementer and
# describer panes so the reviewer holds the feature's one row
herdr pane split --pane <implementer_pane> --direction down --cwd "<worktree>" --no-focus \
  --env CC_LANGFUSE_TRACE_TAGS=agent:cardea:reviewer --env LANGFUSE_TRACING_ENVIRONMENT=agent-reviewer
herdr pane close <implementer_pane>
herdr pane close <describer_pane>
herdr agent start rev-<feature> --kind claude --pane <reviewer_pane> -- --agent cardea:reviewer --model claude-opus-5-5 --effort medium
```

Send briefs, read reports and branch on the results as `cardea:herdr` sets out.

## 5. Concurrency

The orchestrator's cap of five agents holds, counting sessions and right-hand rows alike: a
building feature (describer plus implementer) takes two rows, a reviewing feature (the reviewer
alone, describer and implementer both closed) one. Two features can build at once with room for
one in review. A feature that would exceed the cap
waits in the queue and starts when a slot frees.

## 6. Flow

1. Start the describer with its brief (template below). It writes the rubric to
   `<worktree>/.blind/rubric.md`, then the first implementer brief to `.blind/brief-1.md`.
2. Read the rubric for sanity (every item observable, none naming code). Read the brief and
   check it contains no reference code or reference paths.
3. Start the blind implementer and send it the describer's brief.
4. Build loop. After each build, the describer runs the UI and grades it against the rubric. The
   score is the percentage of rubric items that pass. Stop at 95 percent or after 6 rounds. If
   below, the describer writes the next brief from the failing items only and you send it to the
   same implementer.
5. When building passes, close the implementer and describer panes and start the reviewer
   (template below) alone in the row, as step 4 shows. The reviewer scores the code: the `comment-audit` skill plus the logic rubric. Stop
   at 95 percent or after 3 rounds.
6. At either cap, do not continue: bring the user the failing items and let them extend, rescope
   or accept.
7. Land the reviewer's staged diff, tear down and report, as the orchestrator's Review and land
   section sets out. Remove `.blind/` from the staged change before landing: the rubric and briefs
   are not product code.

## Templates

### Describer brief

```
Goal: describe the reference UI for <feature> so a blind implementer can rebuild it, then grade
what it builds.
Reference: <URL | app, scheme and screen | screenshots folder>. Reference code, which you may
read, if any: <paths>.
View it with: <playwright-cli, opened with --browser=chromium | the official AXe plugin
| the Read tool>.
With screenshots only, list the states they do not show before round one.
Worktree to run and grade the implementer's UI in: <worktree path>. How to run it: <command>.
Write the rubric to <worktree>/.blind/rubric.md, in the rubric format below, before anything else.
Write the implementer's briefs to <worktree>/.blind/brief-<round>.md. Words and numbers only: no
reference code, file paths or screenshots.
Each round I tell you the build is ready. Run the UI and grade every rubric item pass or fail.
Never grade or edit the code. Never edit product code.
Budget: <minutes>, due <clock time>.
Report: the rubric path and item count, the score and each failing item, the next brief path.
```

### Rubric format

```
# Rubric: <feature>

| # | Item | How to observe | Pass when |
|---|---|---|---|
| 1 | <one visual or behavioural fact> | <screen, state, action> | <exact value or outcome> |
```

One fact per item, observable in the rendered UI, no reference to code. Cover layout, spacing,
colour, type, states (empty, loading, error, hover, disabled), interactions, responsiveness and
copy. Fixed before round one; never edited between rounds.

With a screenshots-only reference, items cover only what the screenshots show. Before round one
the describer lists the states it cannot see (hover, error, loading and the like), and the
orchestrator brings the list to the user to add screenshots or accept the gap.

### Implementer brief (written by the describer)

```
Goal: build <feature> as described below.
Where: <worktree path>, in <target directory>.
Description: <layout, spacing, colours, type, states, interactions, copy; in words and numbers>.
Constraints: you must not read, open or screenshot the reference UI or its code in any form.
Conventions to match: <from the target project>.
Check: <command that builds or runs it>.
Report: files changed, the check's output, anything left undone, any denied command.
```

On later rounds the brief lists only the failing items, each with what was seen and what is
expected.

### Reviewer brief (written by the orchestrator)

```
Goal: audit and fix the code of <feature>, whose UI already passes its rubric.
Where: <worktree path>. Changed files: <list from git diff --cached --name-only>.
Run the comment-audit skill on every changed file, then check the logic rubric:
<logic items for this feature: correctness, edge cases, error handling, state, naming and
structure matching the surrounding code>.
Score = percentage of items passing. Fix every failing item; do not change looks or behaviour.
Check: <command>. Stage the result with git add -A; never commit.
Budget: <minutes>, due <clock time>.
Report: score before and after, files changed, the check's output, anything left, any denied
command.
```

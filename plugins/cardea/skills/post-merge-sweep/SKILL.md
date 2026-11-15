---
name: post-merge-sweep
description: "Sweep the leftovers of finished tasks after work merges to main - herdr tabs, git worktrees and branches, simulator clones and orphaned build data - including those left by crashed or restarted sessions, and report the space freed. Use after a pull request or local merge lands on main, when an orchestrator's batch is done, or when the user asks to sweep or clean up after tasks."
---

# Post-merge sweep

Each session cleans up what it remembers making. Sessions that crashed or restarted remember
nothing, so their tabs, worktrees, branches and simulators stay behind. This sweep looks at what
actually exists, ties each item to a task, and removes only what belongs to a finished task.

Run it from the repo's main checkout after any merge to `main`.

## Rules

- **Live means a running Claude session uses it.** An item (worktree, branch, simulator clone,
  tab, build folder) is live if any running session uses it. Never touch a live item. Find the
  sessions as in "Liveness" below.
- **Remove only what no session uses and you can tie to a finished task.** A task is finished
  when its worktree has no uncommitted changes and its branch's work is in `main`: the branch is
  an ancestor of `main` (`git merge-base --is-ancestor <branch> main`) **with at least one commit
  of its own** (`git reflog show <branch> | grep -q commit`; ancestry alone cannot tell, because
  an empty branch is trivially an ancestor), or its pull request is `MERGED`. A branch with no
  commits of its own is a brand-new task, not a finished one: if no session uses it, put it on
  the ask list.
- **Anything you can't attribute, list it and ask.** Never delete it silently.
- **Never touch** the golden simulator, stock simulators, simulator runtimes, `main`, or the tab
  you are running in (`$HERDR_TAB_ID`).
- **Never delete a remote branch without asking.** List merged ones and offer.

Task names come from the cardea conventions: tabs and branches named `impl-<task>`, worktrees in
`~/Repositories/.worktrees/<repo>/impl-<task>`, and simulator clones named `<app>-<task>`.
Worktrees can also live in `~/.herdr/worktrees/<repo>/<name>` (herdr's own worktree feature), and
branches may lack the `impl-` prefix. Take the task name from the worktree's branch. Anything
outside these patterns goes on the ask list.

## Liveness

List the running sessions. `herdr agent list` covers every workspace; each agent has
`agent_session.value` (the session ID), `cwd`, `agent_status`, `tab_id` and `pane_id`. Exclude
the sweep's own session, the one whose pane is `$HERDR_PANE_ID`: it mentions items while sweeping.

```sh
herdr agent list
```

A session uses an item if its `cwd` is inside the item, or if its transcript or any of its
subagents' transcripts mentions the item's path, branch name or simulator UDID:

```sh
grep -lF "<path, branch or udid>" ~/.claude/projects/*/<session id>.jsonl \
  ~/.claude/projects/*/<session id>/subagents/*.jsonl 2>/dev/null
```

Backstop for processes outside any session (an `xcodebuild`, a booted simulator): a process whose
working directory is inside the item or whose command line names it, and any simulator that is
`Booted`.

```sh
lsof -d cwd -Fn | grep -F "<item path>"
ps -axo args | grep -F "<item path, branch or udid>" | grep -v grep
```

Transcripts of sessions that are no longer running are ignored, so an ended session never blocks
cleanup.

## 1. Measure

```sh
df -h /System/Volumes/Data
```

## 2. herdr

Skip outside herdr (`test "${HERDR_ENV:-}" = 1`).

```sh
herdr tab list
```

List tabs in every workspace and keep those whose agent `cwd` is inside this repo or its
worktrees. Close each such tab that no running session uses and whose task is finished. Never
close the tab in `$HERDR_TAB_ID`. Take each tab ID from the `tab_id` field of a fresh
`herdr tab list`, never from a remembered value: `herdr tab close <tab_id>`. List the tabs again
afterwards and report a tab that is still there rather than retrying in a loop.

Implementers run as panes in the orchestrator's right-hand column (see `cardea:herdr`), so also check
`herdr pane list --workspace "$HERDR_WORKSPACE_ID"`. Close an `impl-<task>` pane whose agent is
`idle` or `done`, whose task is finished and that no running session uses, with
`herdr pane close <pane_id>`. Never close `$HERDR_PANE_ID` or a pane you can't tie to a finished
task.

## 3. git

```sh
git worktree prune
git worktree list
git branch --merged main
git ls-remote --heads origin
```

- Remove the worktree of each finished, unused task with `git worktree remove <path>`. Without
  `--force` it refuses a worktree with changes; that means the task is not finished, so ask.
- Delete local branches of finished, unused tasks with `git branch -d`, or `git branch -D` for a
  branch whose pull request was squash-merged.
- `gh pr view <branch> --json state` exits non-zero with "no pull requests found" when the branch
  has no pull request. Then it counts as merged only by the git rule above.
- List remote branches with `git ls-remote --heads origin` (`git branch -r` can be stale), mark
  the merged ones and ask before `git push origin --delete <branch>`.

## 4. Simulators

```sh
xcrun simctl list devices
for d in ~/Library/Developer/CoreSimulator/Devices/*/; do
  u=$(basename "$d")
  xcrun simctl list devices | grep -qF "$u" || echo "orphan: $d"
done
```

- Delete each `<app>-<task>` clone whose task is finished, that no session uses and that is
  `Shutdown`, then check its folder is gone: `ls ~/Library/Developer/CoreSimulator/Devices/<udid>`
  must fail. A `Booted` clone is in use; ask.
- Folders in `Devices` whose UUID is not in `simctl list devices` go on the ask list.
- `xcrun simctl delete unavailable`.
- Deletion finishes in the background through `$TMPDIR/Deleting-*`; wait for it before measuring
  (see `sim-clone-restore`).

## 5. Build data

A task's `.context/dd` goes with its worktree. Xcode's own DerivedData folders record the project
they belong to, so list the ones whose project no longer exists, and the ones that record none:

```sh
for d in ~/Library/Developer/Xcode/DerivedData/*/; do
  p=$(plutil -extract WorkspacePath raw "${d}info.plist" 2>/dev/null) || { echo "unattributed: $d"; continue; }
  [ -e "$p" ] || echo "orphan: $d"
done
```

Delete the orphans with `rm -rf` if no session uses them. They belong to removed worktrees or
deleted projects, and Xcode rebuilds any it needs. Unattributed folders go on the ask list.

## 6. Report

Measure again with `df -h /System/Volumes/Data` and report:

- what was removed, by kind
- the space freed, from `df`, not `du`
- anything left because it is live, plus anything you couldn't attribute, with the question
  for the user

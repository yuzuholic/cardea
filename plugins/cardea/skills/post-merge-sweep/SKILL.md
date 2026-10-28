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

- **Remove only what you can tie to a finished task.** A task is finished when its worktree has
  no uncommitted changes and its branch is merged: `git merge-base --is-ancestor <branch> main`,
  or for a squash-merged pull request, `gh pr view <branch> --json state` says `MERGED`.
- **A task is live** while a herdr agent for it is `working` or `blocked`, or its worktree has
  uncommitted changes. Never touch anything of a live task.
- **Anything you can't attribute, list it and ask.** Never delete it silently.
- **Never touch** the golden simulator, stock simulators, simulator runtimes, `main`, or the tab
  you are running in.
- **Never delete a remote branch without asking.** List merged ones and offer.

Task names come from the cardea conventions: tabs and branches named `impl-<task>`, worktrees in
`~/Repositories/.worktrees/<repo>/impl-<task>`, and simulator clones named `<app>-<task>`.

## 1. Measure

```sh
df -h /System/Volumes/Data
```

## 2. herdr

Skip outside herdr (`test "${HERDR_ENV:-}" = 1`).

```sh
herdr agent list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
```

Close each `impl-<task>` tab whose agent is `idle`, `done` or gone and whose task is finished:
`herdr tab close <tab_id>`. List the tabs again afterwards; a close can fail without an error, and
a tab that is still there gets reported, not retried in a loop.

## 3. git

```sh
git worktree prune
git worktree list
git branch --merged main
```

- Remove the worktree of each finished task with `git worktree remove <path>`. Without `--force`
  it refuses a worktree with changes; that means the task is not finished, so ask.
- Delete local branches of finished tasks with `git branch -d`, or `git branch -D` for a branch
  whose pull request was squash-merged.
- List remote branches that are merged and ask before `git push origin --delete <branch>`.

## 4. Simulators

```sh
xcrun simctl list devices
```

- Delete each `<app>-<task>` clone whose task is finished and that is `Shutdown`, then check its
  folder is gone: `ls ~/Library/Developer/CoreSimulator/Devices/<udid>` must fail. A `Booted`
  clone is in use; ask.
- `xcrun simctl delete unavailable`.
- Deletion finishes in the background through `$TMPDIR/Deleting-*`; wait for it before measuring
  (see `sim-clone-restore`).

## 5. Build data

A task's `.context/dd` goes with its worktree. Xcode's own DerivedData folders record the project
they belong to, so list the ones whose project no longer exists:

```sh
for d in ~/Library/Developer/Xcode/DerivedData/*/; do
  p=$(plutil -extract WorkspacePath raw "$d/info.plist" 2>/dev/null) || continue
  [ -e "$p" ] || echo "$d"
done
```

Delete those with `rm -rf`. They belong to removed worktrees or deleted projects, and Xcode
rebuilds any it needs.

## 6. Report

Measure again with `df -h /System/Volumes/Data` and report:

- what was removed, by kind
- the space freed, from `df`, not `du`
- anything left because it is live, plus anything you couldn't attribute, with the question
  for the user

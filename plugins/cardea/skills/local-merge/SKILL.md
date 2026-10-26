---
name: local-merge
description: Merge a branch into main locally when CI is unavailable - run the CI test command on this machine, and only when it passes squash merge, push main and delete the branch. Use when the user says to merge a branch and the project has no working CI or pull request flow, or names a merge-local script.
---

# Local merge

For when pull requests can't gate merges (CI out of credit, offline, a solo repo). The branch still
gets tested exactly as CI would test it, and `main` still gets one squash commit per branch.

Merge only when the user says to. Never bypass a protect-main hook with `--no-verify`.

## If the project has a script

Use it: `scripts/merge-local.sh <branch> "<type>: <subject>"` or whatever the project names. Run it
from the main checkout. A branch checked out in a worktree can't be switched to, so detach the
worktree first (`git -C <worktree> switch --detach`) and delete the worktree after the merge.

## If it doesn't

Offer to add one. A minimal version:

```sh
#!/bin/sh
# usage: scripts/merge-local.sh <branch> "<type>: <subject>"
set -eu
branch=$1
subject=$2
root=$(git rev-parse --show-toplevel)
log=$root/.context/merge-local.log

cd "$root"
mkdir -p .context
git switch "$branch"

if ! <the exact test command ci runs> >"$log" 2>&1; then
    grep -E "error:|failed|FAIL" "$log" | head -20
    echo "tests failed - $branch was not merged"
    exit 1
fi

git switch main
git pull --ff-only origin main
# one subject on main, every branch commit listed in the body so "(closes #n)" still closes issues
body=$(git log --reverse --format='- %s' "main..$branch")
git merge --squash "$branch"
ALLOW_MAIN_COMMIT=1 git commit -m "$subject" -m "$body"
ALLOW_MAIN_COMMIT=1 git push origin main
git branch -D "$branch"
git push origin --delete "$branch" 2>/dev/null || true
git log --oneline -1
```

Pair it with a pre-commit / pre-push hook that refuses commits and pushes to `main` unless
`ALLOW_MAIN_COMMIT` is set. Only the script sets it; never set it by hand.

For an Xcode project the test command is `xcodebuild test` with `-parallel-testing-enabled NO`, a
derived data path of its own, and ad-hoc signing (`CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual
DEVELOPMENT_TEAM=`) so it runs without a provisioning profile. Pick a stock simulator, never one
holding real data.

## Steps

1. The branch is committed and the pre-commit audit passed.
2. Run the script. It takes the full test run's time; run it in the foreground with a long timeout
   or in the background and wait for it.
3. On failure: show the failing lines from the log verbatim; nothing was merged.
4. On success: report the new `main` commit, the test count, and clean up the worktree and any
   simulator made for the task.

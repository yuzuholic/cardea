---
name: pre-commit-audit
description: The pre-commit audit - comment audit, docs, affected tests, a clean zero-warning build and hygiene checks, in that order, ending in a fixed report. Use when asked for a "pre commit audit", "audit check", "pre-commit checks" or "finishing checks", or before any commit or pull request.
---

# Pre-commit audit

Run every step in order on the change as it stands, fix what each step finds, and loop back when a
fix touches app code. The audit is not a commit: stop after the report unless the user also asked
to commit or merge.

If the project has its own pre-commit skill or checklist, it wins; use this for the parts it does
not cover.

## 0. Scope

```sh
git status -s
git diff --name-only HEAD       # plus untracked files from status
```

The changed files are the scope. Files the user left uncommitted on purpose (their own config,
scratch notes) are never part of it: don't audit, stage or revert them. Ask if unsure.

## 1. Comments

Run the `comment-audit` skill on every changed file - all five steps.

## 2. Docs

Update anything in the project's docs that the change makes wrong or incomplete. Grep the docs for
the types, screens and behaviours touched. If the change alters a documented convention, confirm
with the user before rewriting the doc. Don't run slow doc builds unless the project says to.

## 3. Tests

Add or update tests for what changed, following the project's layout (tests usually mirror the
source path; stubs and fixtures in a support folder). Then run only the affected suites: the mirror
of each changed file, plus suites for callers whose behaviour can change (grep the changed type in
the test folder). A view-only change may have none - say so. Never the full suite unless the user
asks.

For Xcode projects:

```sh
xcodebuild test -project <App>.xcodeproj -scheme <Scheme> \
  -destination id=<sim> -derivedDataPath .context/dd-warn \
  -parallel-testing-enabled NO \
  -only-testing:<TestTarget>/<Suite> [-only-testing:<TestTarget>/<Suite> ...]
```

`-parallel-testing-enabled NO` stops xcodebuild cloning the simulator into
`~/Library/Developer/XCTestDevices`. If clones appear anyway, delete them
(`xcrun simctl --set testing delete <udid>`). Use a simulator made for this task, never a shared one.

If a test fix changes app code, go back to step 1 for that file.

## 4. Clean build, zero warnings

Clean, not incremental - an incremental build only re-emits warnings for files it recompiles.

```sh
xcodebuild -project <App>.xcodeproj -scheme <Scheme> -destination id=<sim> \
  -derivedDataPath .context/dd-warn clean build 2>&1 | grep -E 'warning:|error:|BUILD' | sort -u
```

Zero compiler warnings; fix any before going on. Other stacks: the project's lint plus type check
(`tsc --noEmit`, `go vet`, and so on). Tool noise that is not a compiler warning (for example
`appintentsmetadataprocessor` "Metadata extraction skipped") is not a warning to fix.

## 5. Hygiene

- No temporary code: demo slowdowns, debug overrides, `print(` / `console.log`, draft preview files,
  anything marked `TEMP` (`git diff | grep -n 'TEMP\|print('`).
- No magic numbers where the project keeps constants or design tokens.
- The project's copy and terminology rules hold for user-facing text.
- Flag, do not ship silently: any database schema change, new dependency or destructive removal.

## 6. Report

One message, plain language first:

- **Comments:** what was deleted and why; what survived and under which kind.
- **Docs:** which files changed, or "none needed" and why.
- **Tests:** suites run, pass/fail counts, new tests. Paste failures verbatim.
- **Build:** warning count from the clean build.
- **Skipped:** anything skipped, and why.

## If asked to commit

- On the change's own branch, never the default branch.
- Stage by path, never `git add -A`.
- Message via `semantic-commit`: `<type>: <subject>`, no body.
- Respect the project's trailer rules (some forbid `Co-Authored-By`).
- Merge only when the user says - see `local-merge` if the project merges locally.

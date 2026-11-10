---
name: release-changelog
description: Cut a release - bump the app version, write the user-facing changelog entry in the house voice, run the checks, merge the release commit and push an annotated tag. Use when asked to bump the version, cut or tag a release, or write, review or reconstruct release notes.
---

# Release and changelog

A version bump is a release: a new app version, its changelog entry and, once tagged, whatever
build the tag starts (Xcode Cloud, a GitHub release workflow). If the project has its own release
skill or versioning doc, read it first; it wins.

## Rules

- **The user picks the number.** If they name none, propose the next patch and confirm.
- **A version has shipped once its tag is on the remote** (`git ls-remote --tags origin`). Fixing a
  shipped release is always the next patch. A pushed tag is never moved or deleted.
- **Tag only when the user asks**, and only after the release commit is on `main`. A tag push
  usually starts a build and cannot be taken back.
- **Release commit holds only the bump and the changelog**, staged by path, message
  `chore: release x.y.z`.

## Steps

1. **Range.** `git describe --tags --abbrev=0` is the last release; `git log <tag>..HEAD` is what this
   one carries. Uncommitted work outside the release stays out.
2. **Bump.** Change the version where the project keeps it. Xcode: `MARKETING_VERSION` in the
   project-level build configurations of `project.pbxproj`; targets that inherit it follow, and test
   or demo targets that carry their own `1.0` stay untouched. `CURRENT_PROJECT_VERSION` stays as is
   when the CI supplies build numbers. Check with `grep -n MARKETING_VERSION`. Node: `package.json`.
3. **Changelog.** Write the entry (see below) where the project keeps it: an in-app data file, a
   `CHANGELOG.md`, or both.
4. **Checks.** Run the `pre-commit-audit` on the files the release touched, a clean zero-warning
   build, and any changelog test the project has. Say if a check was skipped.
5. **Merge.** On a `release-x.y.z` branch from an up-to-date `main`, commit, then merge it the
   project's way (pull request or `local-merge`). Squash merges create a new commit on `main`; that
   new one is what gets tagged.
6. **Tag** (only when asked). `git switch main && git pull`, check `git log -1` carries the bump,
   then `git tag -a vx.y.z -m "x.y.z"` and `git push origin vx.y.z`. Never `--no-verify` past a hook
   that refuses the push; a refusal means the release commit is wrong.
7. **Forward.** If another surface mirrors the changelog (a website, a store listing), send it the
   notes verbatim.

## Writing the changelog

The changelog is product copy, not a commit ledger, migration history or engineering report.

Choosing what goes in:

1. List the commits in the range.
2. Drop docs, formatting, dependency plumbing, warning cleanup, probes and refactors with no visible
   outcome.
3. Read the diff when a subject does not establish the behaviour. Code decides whether something
   shipped; commit subjects are leads.
4. Combine commits that delivered one user-facing capability.
5. Keep a fix only when a user could recognise the symptom.

Aim for three to six additions or changes and two to four meaningful fixes, under `Added`, `Changed`
and `Fixed`.

Voice: the `app-copy` rules - state the condition, action or result outright.

- Lead with the ability or visible outcome: `Filter chapters by source, scanlator or language.`
- Present tense for capabilities, symptom language for fixes:
  `The chapter you had just finished was not marked as read after leaving the reader.`
- One idea per note. A second sentence only to answer the immediate practical question.
- Concrete screens and actions over implementation names.
- Avoid `implemented`, `refactored`, `migrated`, `various improvements`, `bug fixes`, `seamless`,
  `powerful`, repeated `now`, and `finally` unless the delay itself matters.
- Describe privacy precisely: hiding something behind Face ID is not encryption.

Bad: `Fixed a persistence race in ReaderViewModel.` Good: the symptom a user saw.

Reconstructing history: treat each version bump as the release cut. Changes after the newest bump
are unreleased unless the user confirms otherwise. Prefer tags or store records for dates, and flag
when a date is only a commit date.

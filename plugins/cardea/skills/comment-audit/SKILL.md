---
name: comment-audit
description: The comment rules (default to none, five allowed kinds, lowercase, ASCII only, no new MARK) and the five-step audit that enforces them on every changed file. Use when writing or reviewing code comments, when asked for a "comment audit", or as step one of a pre-commit audit.
---

# Comment audit

## The rules

Default to no comments. A file header block (if the project uses one) and almost nothing else.

A comment survives only if it is context the code cannot say about itself, and it falls under one of
these five kinds:

1. **Incident** - this shape looks wrong but is intentional because of something that happened.
2. **Platform or library quirk** - the framework behaves surprisingly here.
3. **Damaging invariant** - breaking it causes real harm, and it is not derivable from the
   surrounding code. If the thing it explains is visible a few lines away, it is narration.
4. **Deliberate tradeoff** - performance or security chosen over the obvious alternative.
5. **Actionable TODO / FIXME / HACK.**

Design rationale does not qualify. "recedes rather than vanishing, so the reader knows where it went"
can be accurate and well written and still wrong to write. The test: if it reads as obviously correct
once you see the code, delete it. Being true is not the bar.

Style:

- lowercase, terse, no trailing period
- why, never what
- ASCII punctuation only: no em dash, en dash, ellipsis character or curly quotes
- never add `// MARK:` (or the language's equivalent section marker) to new code, even when
  rewriting a file wholesale
- legacy doc comments and MARK blocks stay as they are unless you are already editing that comment

Three good comments in a 400-line file is normal; twenty is a smell.

If the project has its own comment rules (a `Comments.md`, a CONTRIBUTING section, a CLAUDE.md
block), read them first. They win where they differ from this.

## The audit

"Comment audit" means all five steps, in order. Not a skim of what you just wrote.

1. **Re-read the rules** - the project's own doc if it has one, else the section above. Do not audit
   from memory.
2. **Scope is every comment in every changed file**, not only the diff hunks:

   ```sh
   git diff --name-only HEAD      # plus untracked files from git status
   ```

3. **New comments: justify or delete.** Name which of the five kinds each one falls under. No kind,
   no comment.
4. **Existing comments: check they are still true.** A change that makes a nearby comment wrong or
   misleading is the most likely thing this audit catches. Fix or delete it.
5. **Mechanical pass** - grep, don't eyeball:

   ```sh
   git diff -U0 | grep '^+' | grep -nP '[\x{2013}\x{2014}\x{2026}\x{2018}\x{2019}\x{201C}\x{201D}]'
   git diff -U0 | grep -c '^+.*// MARK'      # must be 0
   ```

   New files get the same grep over the whole file.

## Report

What was deleted and why, and what survived under which kind. Not just the survivors.

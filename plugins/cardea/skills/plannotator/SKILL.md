---
name: plannotator
description: "Plannotator, the browser review UI for plans, diffs and messages. Use when presenting a plan for approval, when the user asks to review changes or annotate a file, or mentions plannotator, plan review, or annotating."
---

# Plannotator

Plannotator opens a review page in the user's browser and sends their decision and comments
back to you. The `plannotator` plugin wires it into Claude Code; the `plannotator` binary does
the work.

## Plans

No command is needed. When you leave plan mode (`ExitPlanMode`), Plannotator takes the plan,
opens it for review, and your turn ends. The user's answer arrives as a later message:

- **Approved:** carry on with the plan as written.
- **Denied with feedback:** revise the plan to address every comment, then present it again.
  Don't start implementing a denied plan.

So write plans that survive a careful read: what changes, which files, how it will be
checked, and what is out of scope.

## Commands the user can run

| Command | What it opens |
|---|---|
| `/plannotator-review` | Uncommitted changes, or a GitHub PR / GitLab MR when given its URL |
| `/plannotator-annotate <file, folder or URL>` | Any markdown file, folder or page for comments |
| `/plannotator-last` | Your last message, for comments on it |

Comments come back as a message. Address each one, then say which you changed and which you
left, and why.

## If it doesn't open

`command -v plannotator` should find the binary (cardea installs it to `~/.local/bin`). If it's
missing, the plan review hook has nothing to run; tell the user to rerun cardea's `./install.sh`.

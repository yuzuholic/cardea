# Global agent rules

Source of truth for agent rules on this machine. install.sh links it to
`~/.claude/CLAUDE.md`; edit it here, not there. Project rules belong in each project's own
`CLAUDE.md`.

## Communication

- Plain language first. Lead with what a thing means and why it matters, not the mechanism.
- Terse. No preamble, no recap of what I just said, no feature tours.
- Verify against current docs before asserting a flag, an API, or a version. Say "unverified"
  rather than guessing.
- When something is done and checked, say so plainly. When it failed, show the output.

## Where things live

- Repos: `~/Repositories/<repo>`. The Aletheia ones come from https://github.com/aletheia-ios.
- Dumps, exports and backups: `~/nas/archive/MacMini/` (the SMB share
  `//macos@truenas.local/archive`).
- `/Volumes/Main/Repositories/` is stale; ignore any reference to it.

## Working style

- Research the existing code first, then current docs, and ask me last. Match surrounding
  naming, idiom, and comment density.
- For a non-trivial change, find at least three viable options, weigh them from the user's,
  developer's and maintainer's side, recommend one, and name the cheapest option that has no
  real tradeoffs.
- Propose, then wait for an explicit yes before writing code.
- Flag before doing: database schema changes, new dependencies, and anything destructive.
- Smallest change that works. No speculative abstraction, no scaffolding for a future that has
  not been asked for. But when I ask for something built to scale, build it; don't object that
  it is premature or over-engineered.
- Never use arbitrary sleeps or delays to paper over ordering problems. If timing is the fix,
  the design is wrong — raise it.
- Non-trivial logic ships with one runnable check.
- Comments: default to none. Write one only when it says something the code can't; the
  comment-audit skill has the rules.
- Commits: `<type>: <subject>`. No scope, no body, no Co-Authored-By.

## Stack

- Primary: Swift / SwiftUI, iOS 18+. Also TypeScript and Go.
- Databases in Swift: GRDB. Async: async/await and AsyncStream, not Combine.
- Tests: Swift Testing.

## Memory

- Basic Memory holds durable notes. Write there when a decision or constraint outlives the
  session; read from there before asking me something I may have already answered.

## Isolation

- Prefer container-use for anything that mutates a repo: one container and one git branch per
  agent.
- Never commit, push, or open a PR unless asked.

## Secrets

- Never read, echo, or commit `.env` files, keys, or tokens. Config references secrets through
  environment variables only.

# Global agent rules

Source of truth for agent rules on this machine. Ruler distributes this file; do not
hand-edit the copies it generates.

## Communication

- Plain language first. Lead with what a thing means and why it matters, not the mechanism.
- Terse. No preamble, no recap of what I just said, no feature tours.
- Verify against current docs before asserting a flag, an API, or a version. Say "unverified"
  rather than guessing.
- When something is done and checked, say so plainly. When it failed, show the output.

## Working style

- Research the existing code before proposing a change. Match surrounding naming, idiom, and
  comment density.
- Smallest change that works. No speculative abstraction, no scaffolding for a future that has
  not been asked for.
- Never use arbitrary sleeps or delays to paper over ordering problems. If timing is the fix,
  the design is wrong — raise it.
- Non-trivial logic ships with one runnable check.

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

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

- Every search or lookup follows the `retrieval-order` skill: notes and code before the web,
  and me last. Match surrounding naming, idiom, and comment density.
- Propose, then wait for an explicit yes before writing code (see Decisions).
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
- Agents come in two types. `cardea:orchestrator` (Opus 5.5, medium) plans, delegates and
  reviews. `cardea:implementer` makes one scoped change: Opus 5.5 medium when I start it,
  Sonnet 5.5 low when an orchestrator does. Inside herdr, each implementer gets its own pane.

## Decisions

Any decision that's mine to make goes through this, in plain chat, never the question picker: a
design choice, a tradeoff, anything destructive or hard to undo, or anything above says to
confirm. A choice with a clear default goes ahead, mentioned in one line.

1. Outline the problem in plain language, then list the questions coming ("4 questions: …").
2. Ask one question at a time, headed "Qn of N": what this part of the problem is, simply, then
   at least three options in a table with what's good and not good about each. Mark one
   **(recommended)**, weighed from the user's, developer's and maintainer's side, and name the
   cheapest option with no real tradeoffs.
3. When I answer, confirm it in one line, then wait for "next" before the following question;
   I may have follow-ups. "Go with yours" takes the recommendation. If an answer changes a later
   question, say so and revise the list.
4. After the last one, summarise every decision and wait for a final go before acting.
5. Write each confirmed decision to Basic Memory as a decision note.

## Stack

- Primary: Swift / SwiftUI, iOS 18+. Also TypeScript and Go.
- Databases in Swift: GRDB. Async: async/await and AsyncStream, not Combine.
- Tests: Swift Testing.

## Memory

- Basic Memory holds durable notes. Write there when a decision or constraint outlives the
  session, filed by PARA (the `basic-memory` skill). Read from there before asking me
  something I may have already answered.

## Isolation

- Prefer container-use for anything that mutates a repo: one container and one git branch per
  agent.
- Never commit, push, or open a PR unless asked.

## Secrets

- Never read, echo, or commit `.env` files, keys, or tokens. Config references secrets through
  environment variables only.

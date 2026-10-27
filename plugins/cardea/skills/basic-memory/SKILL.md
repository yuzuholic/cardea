---
name: basic-memory
description: "Read and write durable notes in Basic Memory, the self-hosted knowledge base on the NAS. Use before asking the user something they may have answered already, after a decision or constraint that outlives the session, or when the user says 'remember', 'note this', 'what did we decide', or mentions basic memory, kb, or the vault."
---

# Basic Memory

Basic Memory is the long-term memory shared by every session and project. It runs on the
NAS (`basic-memory` MCP server, `http://truenas.local:8766/mcp`) and stores plain markdown in
the NAS's `kb/` folder, the same files the user reads in Obsidian (see the `obsidian` skill).

## Projects

Every top-level folder in `kb/` is a project, and the server registers it on start.

| Project | For |
|---|---|
| `aletheia` | The Aletheia app. The default. |
| `homelab` | The NAS, the network, the Mac setup, cardea itself. |

Pass `project` explicitly. A project's notes can't link to another project's, so keep a note
in the project it is about. For a new project, ask the user: it is a new folder in `kb/` and a
restart of the stack.

## Layout: PARA

Every project has the same four folders. One question picks the folder:

| Folder | Holds | Ask |
|---|---|---|
| `1-plans/<plan>/` | Work with an end: a feature, a migration. Spec, plan, open questions. | Does it finish? |
| `2-areas/<area>/` | Lasting parts of the project, such as `sync/` or `nas/`. Decisions, constraints, gotchas, how it works. | Is it part of the project for good? |
| `3-resources/` | Outside material: a library, an API, research, a vendor's quirks. | Did someone else make it? |
| `4-archive/` | Finished plans and superseded notes, kept for their history. | Is it done or replaced? |

- Areas are lowercase folder names, one per part of the project. Reuse an existing area
  before adding one; `list_directory` shows them.
- When a plan finishes, move anything lasting it produced (a decision, a gotcha) into its area,
  then move the plan's folder to `4-archive/` with `move_note`.
- When a decision is replaced, set the old note's `status: superseded`, move it to
  `4-archive/`, and link the new one to it with `supersedes`.

## Notes

One topic per note. The title is what someone would search for, in sentence case:
`Use CRDTs for sync`, `iCloud renames files during conflicts`. The note's kind goes in
frontmatter, not in the folder:

```markdown
---
type: decision        # decision, constraint, gotcha, reference or plan
status: accepted      # decisions only: proposed, accepted or superseded
date: 2026-10-27
---
# Use CRDTs for sync

Why, in a few sentences: the problem, what was chosen, what it costs.

## Observations
- [decision] Automerge for note bodies, last-write-wins for metadata #sync
- [rejected] Operational transform: needs a central server

## Relations
- supersedes [[Last-write-wins sync]]
- constrained_by [[Notes must open offline in under 200ms]]
```

`## Observations` (`- [category] fact #tag`) and `## Relations` (`- relation [[Note title]]`)
are what Basic Memory indexes; the links also draw the Obsidian graph. Dates are
`YYYY-MM-DD`. Basic Memory adds its own `title` and `permalink`; leave them.

## When to read

- At the start of non-trivial work in a project: `recent_activity`, then `search_notes` for the
  topic. Read the hits with `read_note` or `build_context` (`memory://...` URIs).
- Before asking the user a question about past decisions. Ask only if nothing answers it.

## When to write

- A decision and why it was made, a constraint that is not visible in the code, a gotcha that
  cost time, the state of a plan in flight.
- Not: things the repo already records (code structure, git history, CLAUDE.md), session logs,
  or anything only this session needs.
- Never secrets, keys, tokens or `.env` contents.

`write_note` refuses to overwrite an existing note unless asked; prefer `edit_note` to append
to or update a note that exists. Search first so you don't create a near-duplicate.

## If it is unreachable

The server only answers on the LAN. If calls fail, say so and carry on; don't retry in a
loop. `./install.sh --check` in the cardea repo tests it.

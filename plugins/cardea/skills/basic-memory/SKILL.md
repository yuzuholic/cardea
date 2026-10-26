---
name: basic-memory
description: "Read and write durable notes in Basic Memory, the self-hosted knowledge base on the NAS. Use before asking the user something they may have answered already, after a decision or constraint that outlives the session, or when the user says 'remember', 'note this', 'what did we decide', or mentions basic memory, kb, or the vault."
---

# Basic Memory

Basic Memory is the long-term memory shared by every session and project. It runs on the
NAS (`basic-memory` MCP server, `http://truenas.local:8766/mcp`) and stores plain markdown in
the NAS's `kb/` folder, the same files the user reads in Obsidian (see the `obsidian` skill).

## Projects

| Project | For |
|---|---|
| `alethia` | The Aletheia app: design notes, decisions, constraints. The default. |
| `homelab` | The NAS, the Mac setup, cardea itself. |

Pass `project` explicitly. If a call fails because a project is missing, `list_memory_projects`
shows what exists; registering a new one is the user's job on the NAS.

## When to read

- At the start of non-trivial work in a project: `recent_activity`, then `search_notes` for the
  topic. Read the hits with `read_note` or `build_context` (`memory://...` URIs).
- Before asking the user a question about past decisions. Ask only if nothing answers it.

## When to write

- A decision and why it was made, a constraint that is not visible in the code, a gotcha that
  cost time. One topic per note.
- Not: things the repo already records (code structure, git history, CLAUDE.md), progress
  logs, or anything only this session needs.
- Never secrets, keys, tokens or `.env` contents.

`write_note` refuses to overwrite an existing note unless asked; prefer `edit_note` to append
to or update a note that exists. Search first so you don't create a near-duplicate.

## Format

Write for a person reading in Obsidian: a clear title, a short body, and `[[Wikilinks]]` to
related notes so the graph connects. Keep frontmatter minimal; Basic Memory adds its own.

## If it is unreachable

The server only answers on the LAN. If calls fail, say so and carry on; don't retry in a
loop. `./install.sh --check` in the cardea repo tests it.

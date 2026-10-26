---
name: obsidian
description: "How the user reads and edits notes in Obsidian, self-hosted on the NAS. Use when the user mentions Obsidian, the vault, or wants to see or edit notes by hand, or when writing notes that should read well there."
---

# Obsidian

Obsidian runs on the NAS and streams to the browser at `https://truenas.local:3001` (the
`obsidian` container in cardea's NAS stack). Its vault is the NAS `kb/` folder, the same
markdown Basic Memory reads and writes. Edits on either side are the same files; nothing syncs.

## What this means for you

- You do not drive Obsidian. To change notes, use the Basic Memory tools (see the
  `basic-memory` skill); the user sees the result in Obsidian straight away.
- Write so the note reads well there: a title the user would search for, short sections,
  `[[Wikilinks]]` to related notes, and plain markdown. No HTML, no tool-specific syntax.
- `kb/.obsidian/` holds Obsidian's own settings. Never write to it.
- To point the user at a note, give its title or path inside the vault, for example
  `alethia/decisions/offline-first.md`.

## Access

LAN only, behind a login (`OBSIDIAN_USER` / `OBSIDIAN_PASSWORD` in the NAS `.env`). The
certificate is self-signed, so the browser warns once. Anyone past the login is root inside
that container, so never suggest exposing it through the tunnel.

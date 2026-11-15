---
name: obsidian
description: "How the user reads and edits notes in Obsidian on the Mac. Use when the user mentions Obsidian, the vault, or wants to see or edit notes by hand, or when writing notes that should read well there."
---

# Obsidian

The user opens the vault in Obsidian on the Mac. The vault is the NAS `kb/` folder, the same
markdown Basic Memory reads and writes. Edits on either side are the same files; nothing syncs.

## What this means for you

- You do not drive Obsidian. To change notes, use the Basic Memory tools (see the
  `basic-memory` skill); the user sees the result in Obsidian straight away. Never edit or
  rename `kb/` files directly over SMB: with the server watching, that has blanked notes.
- Write every note to the templates in the `basic-memory` skill, so it reads as a wiki page
  there. No HTML.
- The vault is set up for that shape. A CSS snippet (`kb/.obsidian/snippets/hide-bm-properties.css`)
  hides the `title` and `permalink` properties, and the inline title is off, so the `# H1` is
  the only title shown. The Automatic Table of Contents plugin renders `toc` code blocks
  (from level 2, leaving out Key facts and Relations); without it they show as empty code.
  Mermaid diagrams and `> [!warning]` / `> [!note]` callouts render natively.
- `kb/.obsidian/` holds Obsidian's own settings. Never write to it.
- The core Templates plugin points at `system/templates/` (a user setting). Those templates are
  excluded from Basic Memory with an ignore file (`.bmignore` or `.gitignore`; unverified until
  checked after the server restart), so that it does not stamp `title` and `permalink` into
  them. If it does anyway, move them to a dot-folder such as `kb/.templates/` and repoint the
  plugin. Links from project pages into `system/` resolve in Obsidian only, not in Basic
  Memory.
- To point the user at a note, give its title or path inside the vault, for example
  `<project>/apps/<app>/<area>/<Title>.md`.

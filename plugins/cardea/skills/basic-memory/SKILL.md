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
| `homelab` | The NAS, the network, the Mac setup (`apps/nas/`, `apps/network/`, `apps/mac/`). Cardea's own decisions live in its repo, on `docs/content/docs/decisions.mdx`. |
| `system` | The rules every project shares and the six templates. |

Pass `project` explicitly. Basic Memory cannot link across projects, so keep a note in the
project it is about; a link from a project page to a `system` page resolves in Obsidian only.
For a new project, ask the user: it is a new folder in `kb/` and a restart of the stack.

## Layout

Each project files its pages under four folders, replacing PARA's `areas/` and `resources/`.
One question picks the folder:

| Folder | Holds | Ask |
|---|---|---|
| `apps/<app>/<area>/` | Lasting knowledge about each thing the project builds or runs: decisions, constraints, gotchas, how it works. | Is it about something the project builds or runs? |
| `research/<topic>/` | What was learnt from outside: other apps, source sites, platforms, design frameworks. | Did someone else make it? |
| `plans/<plan>/` | Work in flight: a feature, a migration. Spec, plan, open questions. | Is it work in flight? |
| `archive/<topic>/` | Finished plans and superseded pages, kept for their reasoning. | Is it done or replaced? |

- `apps/` means each thing the project builds or runs, so a project without software uses it
  too (homelab: `apps/nas/`). A project can leave `apps/` out until it needs it.
- Folder names are lowercase. Reuse an existing app, area or topic before adding one;
  `list_directory` shows them.
- Every folder has a portal page (`type: area`) that links every page in it and names its
  parent on its breadcrumb. The project front page, named after the project, links every
  top-level portal.
- Portal titles are unique across the whole vault, because Obsidian resolves links by file
  name (`Sources Repo` for a source packages app, not `Sources`, which is an iOS area).
- When a plan finishes, move anything lasting it produced (a decision, a gotcha) into its app
  area, then move the plan's folder to `archive/` with `move_note`.
- When a decision is replaced, set the old note's `status: superseded`, move it to
  `archive/`, and link the new one to it with `supersedes`.

### The system project

The `system/` folder at the vault root holds the project-agnostic rules (`How Notes Are
Written`), vault-wide decisions and the templates (`system/templates/<Kind> Template.md`). It
is a Basic Memory project once the server has restarted. `[[System]]` is its front page for
the vault-wide rules.

`system/templates/` is excluded from Basic Memory with an ignore file (`.bmignore` or
`.gitignore`; which one, and where it must sit, is unverified until checked after the
restart), so that Basic Memory does not stamp `title` and `permalink` into the templates. If
they get stamped anyway, move the templates to a dot-folder such as `kb/.templates/` and
repoint Obsidian's Templates plugin.

This skill and [templates.md](templates.md) mirror those rules and templates in full, because
other setups may not have a `system/` folder. Where the vault has a `system` project, its
`How Notes Are Written` and templates win; otherwise use this skill and `templates.md`.
Whoever changes one updates the other.

## Notes

Every note is a wiki page that the user reads in Obsidian and agents read through Basic
Memory. One topic per note, and one template per kind of note: `decision`, `reference`,
`gotcha`, `constraint`, `plan` or `area`. Copy the template from
[templates.md](templates.md), which also has the diagram rules.

### Page anatomy

1. **Properties:** `type`, `status` (decisions only: `proposed`, `accepted` or
   `superseded`), `tags: [<area>]` once, `aliases` (other names people search for) and
   `updated: YYYY-MM-DD`, bumped on every meaningful edit. Basic Memory adds `title` and
   `permalink`; leave them.
2. **Title and breadcrumb:** one `# H1` matching the title, then `Part of [[<Area>]]`.
3. **Lead:** one to three sentences. A reader who stops there still knows the answer.
4. **Body:** `##` sections from the template. Add a `toc` block under the lead when there are
   three or more.
5. **Basic Memory section:** a `---` rule, then `# Basic Memory` with `## Key facts` (three to
   eight `- [category] fact` lines, no tags) and `## Relations`.

```markdown
---
type: decision
status: accepted
tags: [sync]
aliases: [CRDT sync]
updated: 2026-10-28
---
# Use CRDTs for Sync

Part of [[Sync]]

Note bodies merge with Automerge, so edits made offline on two devices never overwrite
each other.

## Context
...

---
# Basic Memory

## Key facts
- [decision] Automerge for note bodies, last-write-wins for metadata
- [rejected] Operational transform: needs a central server

## Relations
- part_of [[Sync]]
- supersedes [[Last-Write-Wins Sync]]
```

### Rules

- **Titles** are what someone would search for, in title case, and the file name always equals
  the title. A decision states the choice (`Use GRDB for Offline Storage`), a gotcha states the
  symptom (`iCloud Renames Files During Conflicts`), and an area page is just the area's name
  (`Sync`).
- **Title case:** capitalise every word except these: the articles a, an, the; the
  coordinating conjunctions and, but, or, nor, for, so, yet; and the short prepositions as, at,
  by, from, in, into, of, on, onto, per, to, via, vs, with, than. Any of them is capitalised
  when it is the first or last word or follows an opening parenthesis. Capitalise each part of a
  hyphenated word (`Last-Write-Wins Sync`). Code names, acronyms and version tags keep their
  own casing (`iCloud`, `GRDB`, `v2.1.0`).
- **Key facts** use the categories `decision`, `rejected`, `constraint`, `gotcha`, `rule`,
  `fact` and `todo`. They summarise the body, so rewrite them whenever the body changes.
- **Relations** are typed and only these: `part_of` (required: the parent portal or plan page),
  `supersedes` and `depends_on`. Links in the prose become `links_to` on their own.
- **Links** go in the prose at the first mention of a concept, once per page, never in a
  heading. Every area page links each of its pages with one line on what it covers, and each
  project has a front page named after the project that links every top-level portal.
- **Qualifiers:** no colons, slashes or other characters a filename cannot hold; use
  parentheses for a qualifier (`MangaBall Source (JSON API Rebuild)`).
- **Style:** plain English, Australian spelling, present tense, active voice. No filler, no
  persona, no first person. Dates `YYYY-MM-DD`, numbers with units (`44pt`, `200ms`).
- **Prose and lists:** paragraphs of two to four sentences. Prose for reasoning, lists for
  parallel items, tables for comparisons. One fact per bullet; a bullet that needs a semicolon
  is two bullets.
- **Code:** fenced blocks with a language, code names in backticks. Give each rule its reason,
  and a short example when the rule touches code.
- **Callouts:** `> [!warning]` for a trap, `> [!note]` for context.

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

> [!warning]
> Change notes through `write_note`, `edit_note` and `move_note`, not by editing `kb/` files
> directly. The server watches those files, and a direct rename plus link rewrites in one pass
> has left notes as 80-170 byte stubs holding only default frontmatter, with the body gone. If
> a bulk direct edit is unavoidable, snapshot the files locally, rewrite content in place, let
> Basic Memory sync, then do pure renames in a separate pass, and diff every file against the
> snapshot.

## If it is unreachable

The server only answers on the LAN. If calls fail, say so and carry on; don't retry in a
loop. `./install.sh --check` in the cardea repo tests it.

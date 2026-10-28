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
| `homelab` | The NAS, the network, the Mac setup. Cardea's own decisions live in its repo, on `docs/content/docs/decisions.mdx`. |

Pass `project` explicitly. A project's notes can't link to another project's, so keep a note
in the project it is about. For a new project, ask the user: it is a new folder in `kb/` and a
restart of the stack.

## Layout: PARA

Every project has the same four folders. One question picks the folder:

| Folder | Holds | Ask |
|---|---|---|
| `plans/<plan>/` | Work with an end: a feature, a migration. Spec, plan, open questions. | Does it finish? |
| `areas/<area>/` | Lasting parts of the project, such as `sync/` or `nas/`. Decisions, constraints, gotchas, how it works. | Is it part of the project for good? |
| `resources/` | Outside material: a library, an API, research, a vendor's quirks. | Did someone else make it? |
| `archive/` | Finished plans and superseded notes, kept for their history. | Is it done or replaced? |

- Areas are lowercase folder names, one per part of the project. Reuse an existing area
  before adding one; `list_directory` shows them.
- When a plan finishes, move anything lasting it produced (a decision, a gotcha) into its area,
  then move the plan's folder to `archive/` with `move_note`.
- When a decision is replaced, set the old note's `status: superseded`, move it to
  `archive/`, and link the new one to it with `supersedes`.

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
- **Title case:** capitalise every word except articles, coordinating conjunctions and these
  short prepositions: as, at, by, from, in, into, of, on, onto, per, to, via, vs, with, than.
  Those are capitalised too when first, last or right after "(". Capitalise each part of a
  hyphenated word (`Last-Write-Wins Sync`). Code names, acronyms and version tags keep their
  own casing (`iCloud`, `GRDB`, `v2.1.0`).
- **Key facts** use the categories `decision`, `rejected`, `constraint`, `gotcha`, `rule`,
  `fact` and `todo`. They summarise the body, so rewrite them whenever the body changes.
- **Relations** are typed and only these: `part_of` (required: the area or plan page),
  `supersedes` and `depends_on`. Links in the prose become `links_to` on their own.
- **Links** go in the prose at the first mention of a concept, once per page, never in a
  heading. Every area page links each of its pages with one line on what it covers, and each
  project has a front page named after the project that links every area, plan and resource
  hub.
- **Style:** plain English, British spelling, present tense. Short paragraphs, one fact per
  bullet, tables for comparisons, `> [!warning]` and `> [!note]` callouts for what a reader
  must not miss. Dates `YYYY-MM-DD`, numbers with units (`44pt`, `200ms`). No persona and no
  first person.

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

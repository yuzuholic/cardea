---
name: obsidian
description: "How the vault is laid out and written: the folder tree, page anatomy, the nine page kinds, interlinking, diagrams, infoboxes, captioned media and the lint pass. Use when the user mentions Obsidian or the vault, when writing, editing, moving or reviewing a note, or when asked for a lint pass."
---

# Obsidian

The vault is plain Obsidian markdown on the NAS, at `/Volumes/NAS/Vault` on the Mac. The user reads
it in Obsidian; agents read and write the same files directly, and nothing syncs. Page templates
are in [templates.md](templates.md). Durable decisions and preferences go to Hindsight (see
`hindsight`); the vault holds settled, authored knowledge, compiled into pages.

## What this means for you

- You do not drive Obsidian. Edit notes directly as files; the user sees the result at once.
- Never write to `.obsidian/`: it holds Obsidian's own settings.
- No HTML in notes. Mermaid diagrams, tables and `> [!warning]` / `> [!note]` callouts render
  natively; the Automatic Table of Contents plugin renders `toc` code blocks.
- Never write secrets, keys, tokens or `.env` contents.
- To point the user at a note, give its title or its path inside the vault.

## Tree

One title-cased folder per project at the vault root (`Aletheia/`, `Homelab/`, `System/`). One
project is one product and one memory boundary. Each project follows the same shape:

```
<Project>/
├─ <Project>.md          home page
├─ Index.md              every page by type, with counts
├─ <Subsystem>/          one folder per component of the product
│  ├─ <Subsystem>.md     subsystem portal
│  └─ <Area>/
│     ├─ <Area>.md       area portal
│     └─ <Page>.md
├─ Concepts/             cross-cutting concept pages
├─ Research/             what was learnt from outside
├─ Plans/                work in flight
└─ Archive/              finished plans and superseded pages
```

- Subsystems are first-class folders whose portal is `Part of [[<Project>]]`. There is no `apps/`
  wrapper. A project without separate components files its areas directly under the project.
- Folders and files are title-cased, and the file name always equals the page title.
- A folder gives a page one home and one `Part of` parent. Meaning travels through links, which
  may point anywhere.
- Reuse an existing subsystem, area or topic before adding one. A new project is a new folder:
  ask the user first.
- When a plan finishes, move what it produced that lasts (a decision, a gotcha) into its area,
  then move the plan to `Archive/`. When a decision is replaced, set the old page's
  `status: superseded`, move it to `Archive/`, and link the new page to it in `## See also`.

## Page anatomy

One self-contained concept per page; a title that needs "and" is two pages. Length follows
atomicity and is not a target.

1. **Frontmatter:** `type`; `status` (decisions only: `proposed`, `accepted` or `superseded`);
   `tags: [<kind>, <area>]`, the page kind first, then its one area; `aliases` (other search
   phrasings, the highest-leverage field); `updated: YYYY-MM-DD`, bumped on every meaningful
   edit; `reviewed: YYYY-MM-DD`, set when the page is re-verified without change.
2. **Title and breadcrumb:** one `# H1` equal to the file name, then `Part of [[<Parent>]]`.
3. **Lead:** one to three sentences that answer the page. A reader who stops here still has the
   answer.
4. **Body:** `##` sections, with a `toc` block under the lead when there are three or more.
5. **See also:** a `## See also` list of wikilinks, each with a one-line reason.

There is no trailing key-facts or relations block. Where an at-a-glance summary helps, use an
infobox.

## Page kinds

| Kind | Title states | Example |
|---|---|---|
| `home` | the project name | Aletheia |
| `index` | "Index" | Index |
| `area` | the area or subsystem name | Reader, iOS App |
| `concept` | the term of art, as searched | Best Chapter Resolution |
| `decision` | the choice made | Use GRDB for Offline Storage |
| `gotcha` | the symptom | iCloud Renames Files During Conflicts |
| `constraint` | the limit | Reader Must Work Fully Offline |
| `reference` | the subject | Source Comment Support Survey |
| `plan` | the work in flight | Chapter Comments |

The kind goes in `type` and as the first `tags` entry.

## Titles and style

- Titles are what someone would search for, in title case. A decision states the choice, a gotcha
  the symptom, an area page just its name.
- Title case: capitalise every word except the articles a, an, the; the conjunctions and, but, or,
  nor, for, so, yet; and the short prepositions as, at, by, from, in, into, of, on, onto, per, to,
  via, vs, with, than. Any of them is capitalised as the first or last word or after an opening
  parenthesis. Capitalise each part of a hyphenated word. Code names, acronyms and version tags
  keep their own casing (`iCloud`, `GRDB`, `v2.1.0`).
- No colons, slashes or other characters a file name cannot hold; use parentheses for a qualifier
  (`Payments Service (Retry Rewrite)`).
- Plain English, Australian spelling, present tense, active voice. No filler, no persona, no first
  person. Dates `YYYY-MM-DD`, numbers with units (`44pt`, `200ms`).
- Lead first: the answer in the first sentence. State the reason, including rejected
  alternatives.
- Paragraphs of two to four sentences. Prose for reasoning, lists for parallel items, tables for
  comparisons. One fact per bullet.
- Code goes in fenced blocks with a language, code names in backticks. Give each rule its reason.
- Tags stay minimal: the kind plus one area. Links do the structural work.

## Interlinking

The link graph is the knowledge structure: dense, traversable, no dead ends.

- Link in prose at the first mention of a concept, once per page, never in a heading.
- `Part of [[<Parent>]]` is required on every page. `supersedes`, `depends_on`, `relates_to` and
  `contradicts` become `## See also` entries, each with a one-line reason.
- Every area and subsystem portal lists its pages with one line each and names its parent. Each
  project's home page links every subsystem and top-level portal.
- `Index` lists every page grouped by type with counts, and is where orphans show up. Regenerate
  it after a batch and update the portals that gained members.
- Portal titles are unique across the vault, because Obsidian resolves links by file name. Prefer
  `[[<Page>|Human Title]]` when the text should differ.
- A link to a page that does not exist yet is a gap while writing and a lint finding afterwards.
- A diagram's links are not part of the graph: every page a diagram names is also linked in the
  surrounding prose.

## Visual vocabulary

Text-encoded visuals are first-class because agents read raw markdown; prefer them. A binary
image is a human-only supplement and must be captioned so that a text agent is not blind to it.

### Diagrams

Follow the `mermaid` skill: at most about 12 nodes, no styling, a verb on every non-obvious edge.

| Case | Diagram | The reader gets |
|---|---|---|
| How parts fit together; data down a pipeline | `flowchart LR` | the overall shape and what rides each edge |
| Subsystems with boundaries | `flowchart LR` with `subgraph`s | where one ends and the next begins |
| A process with branches or a decision | `flowchart TD`, `{ }` decisions | every decision point and its branches |
| Who calls whom, in order | `sequenceDiagram` | the ordering and round-trips |
| The legal states of a thing | `stateDiagram-v2` | the states and the event for each transition |
| A data model | `erDiagram` | entities, fields and cardinality |

Diagrams belong mostly in reference, plan and area pages, and rarely in decisions, gotchas or
constraints.

### Beyond diagrams

| Visual | Use for | Agent reads it |
|---|---|---|
| Infobox (`> [!info]`, floated right by the Wikidian theme) | portal, concept and decision pages with identifying facts | yes |
| Table | options, coverage matrices, parallel items | yes |
| Callout (`[!warning]`, `[!note]`) | a trap or an aside beside the prose | yes |
| Screenshot or annotated screenshot | a UI where the pixels are the point | no, caption it |
| Demo video | a flow or animation prose cannot convey | no, caption it |
| Data chart | real numbers worth seeing as a shape | partly, ship the table too |

### Media

- Embed with `![[<name>.png]]`; Obsidian resolves attachments vault-wide. Place the image inside
  the section it illustrates, directly after the sentence it supports, with a caption line
  immediately below.
- The caption states what the image shows and, when known, the app version it depicts, for example
  *Library filter, v1.8.0*. If the version is unknown, say so rather than guess. A screenshot
  without a caption is incomplete.

## Lint pass

Run per project on request or on a schedule, not per write. It reports and never silently
overwrites.

| Check | Finds | Action |
|---|---|---|
| Contradictions | two pages asserting incompatible facts | link both under `## See also` as contradicting; a decision resolves it |
| Stale claims | `reviewed` is old, or a newer source superseded the claim | re-verify, or set `status: superseded` and archive |
| Orphans | no backlinks and not in `Index` | link in, or archive |
| Missing pages | a concept on many pages with no page of its own | promote to a `concept` page |
| Dangling links | wikilinks to files that do not exist | create the page or remove the link |
| Near-duplicates | two pages on the same concept | merge, and link the survivor to the other |
| Uncaptioned media | an image or video with no caption or version | add both |

## Ruleset

1. One concept per page; the file name equals the title.
2. Nine page kinds, in `type` and as the first tag.
3. Every page has one `Part of` parent, is listed on a portal and appears in `Index`.
4. Lead first; `aliases` capture other phrasings.
5. Text-encoded visuals before images; every image captioned and version-referenced.
6. Compile, do not retrieve: read a source once and write it into the pages it touches.
7. Stamp `updated` and `reviewed` so the lint pass is repeatable.
8. Edit files directly, never `.obsidian/`, never HTML, never secrets.

---
name: panel
description: Put a design question to the panel - a UX designer, the average chud and a power user review it in parallel, then their verdicts are merged into one table and a recommendation. Use when the user says "ask the panel", "/panel", "what would the panel think", or wants a design choice judged from several user perspectives.
---

# The panel

Three reviewers, each a subagent from this plugin:

| Agent | Lens |
|---|---|
| `panel-ux-designer` | hierarchy, semantic colour, redundancy, affordance, information architecture |
| `panel-average-chud` | an ordinary non-technical user: clarity, confusion, anxiety, "does it just work" |
| `panel-power-user` | efficiency, density, bulk actions, predictability, edge cases |

Plugin agents may be listed with the plugin prefix (`cardea:panel-ux-designer`); use whichever
name the agent list shows.

## 1. Frame the question

Write one brief all three get, word for word:

- **Context:** the screen or feature, and what the user is trying to do there. One short paragraph.
- **The question:** what is being decided.
- **Options:** each labelled (A, B, C...) with a plain description of what the user would see, or the
  single design under review.
- **Material:** absolute paths to screenshots, mockups or the relevant source files. Reviewers read
  them; don't paste file contents into the brief.
- **Constraints:** anything already decided that is not up for review.

Keep your own preference out of the brief. A leading brief makes three copies of your opinion.

## 2. Run them in parallel

Dispatch all three in one message so they run concurrently and independently. Tell each to read the
material and answer in its own format. Don't share one reviewer's answer with another.

## 3. Merge

When all three are back, give the user:

| Reviewer | Pick | Why | Tweak |
|---|---|---|---|
| UX designer | ... | ... | ... |
| Average chud | ... | ... | ... |
| Power user | ... | ... | ... |

Then:

- **Verdict:** where they agree, and where they split (and why, in a line).
- **Combined proposal:** the pick plus the tweaks that don't conflict, as concrete behaviour the user
  can approve.
- **Open question:** only if the reviewers genuinely conflict and the user has to choose.

Don't build anything off the verdict until the user approves it.

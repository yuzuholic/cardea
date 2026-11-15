# Page templates

Copy the block for the page's `type`, then replace every `<placeholder>`. The anatomy and writing
rules are in [SKILL.md](SKILL.md). Every page carries the kind as `type` and as the first `tags`
entry, one `Part of` parent, and a `## See also` list when it has related pages.

## Decision

Modelled on MADR.

````markdown
---
type: decision
status: accepted
tags: [decision, <area>]
aliases: []
updated: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
# <Use X for Y>

Part of [[<Area>]]

<One to three sentences: what was decided and why it matters.>

## Context

<The problem and the forces that shaped the choice.>

## Decision

<What was chosen, stated plainly, with how it works where that is not obvious.>

## Options considered

| Option | Good | Not good |
|---|---|---|
| <Chosen option> | <...> | <...> |
| <Rejected option> | <...> | <...> |

## Consequences

- <What this makes easier.>
- <What it costs or rules out.>

## See also

- [[<Page>]]: <why it relates>
````

## Reference

````markdown
---
type: reference
tags: [reference, <area>]
aliases: []
updated: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
# <Subject>

Part of [[<Area>]]

<One to three sentences: what this covers and when you need it.>

```toc
```

## <First group>

<Short description, then bullets or a table. One fact per bullet, each with its reason.>

## <Second group>

<...>

## Example

```swift
<a short, real example>
```

<Optional: a mermaid diagram inside the section it explains.>

## See also

- [[<Page>]]: <why it relates>
````

## Gotcha

````markdown
---
type: gotcha
tags: [gotcha, <area>]
aliases: []
updated: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
# <What goes wrong, as the symptom>

Part of [[<Area>]]

<One to two sentences: the symptom and where it bites.>

## Symptom

<What you see.>

## Cause

<Why it happens.>

## Fix

<What to do instead, with a short code example where it helps.>

> [!warning]
> <The one line a reader must remember.>

## See also

- [[<Page>]]: <why it relates>
````

## Constraint

````markdown
---
type: constraint
tags: [constraint, <area>]
aliases: []
updated: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
# <The rule, stated as a rule>

Part of [[<Area>]]

<One sentence: the rule.>

## Why

<What breaks, or what it protects, if the rule is ignored.>

## Applies to

<The code, screens or data it covers, and any exceptions.>

## See also

- [[<Page>]]: <why it relates>
````

## Plan

````markdown
---
type: plan
tags: [plan, <area>]
aliases: []
updated: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
# <What the work delivers>

Part of [[<Plans portal>]]

<One to three sentences: the goal and its current state.>

```toc
```

## Goal

<What done looks like.>

## Approach

<How it will be built, in stages if it has them. Optional: a mermaid diagram of the stages.>

## Status

| Stage | State | Notes |
|---|---|---|
| <Stage> | done, in progress or not started | <...> |

## Open questions

- <Question, and who answers it.>

## See also

- [[<Page>]]: <why it relates>
````

## Concept

````markdown
---
type: concept
tags: [concept, <area>]
aliases: []
updated: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
# <Term of Art>

Part of [[Concepts]]

> [!info]
> **Used in:** [[<Area>]]
> **Related to:** [[<Concept>]]

<One to three sentences: what the term means and why it matters.>

## <How it works>

<The explanation, with a table or a diagram where it helps.>

## See also

- [[<Page>]]: <why it relates>
````

## Area

A portal page named after its folder, linking every page in it. A subsystem portal has the same
shape and is `Part of [[<Project>]]`.

````markdown
---
type: area
tags: [area, <area>]
aliases: [<Area> overview]
updated: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
# <Area name>

Part of [[<Parent portal>]]

<Two to four sentences: what this part does and how its pages are grouped.>

<Optional: a mermaid architecture diagram of the area's main parts.>

```toc
```

## <Group of pages>

- [[<Page title>]]: <one line on what it covers>
- [[<Page title>]]: <...>

## <Another group>

- [[<Page title>]]: <...>

## See also

- [[<Area>]]: <how it connects>
````

## Home

````markdown
---
type: home
tags: [home, <project>]
aliases: [Home, Front Page]
updated: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
# <Project>

<One to three sentences: what the project is and what it contains. Every subsystem, research
topic, plan and concept is reachable from here.>

```toc
```

## Subsystems

- **[[<Subsystem>]]**: <one line>

## Concepts

- **[[<Concept>]]**: <one line>

## Research

- [[<Page>]]: <one line>

## Plans

- [[<Page>]]: <one line>

## Archive

- [[<Page>]]: <one line>

## See also

- [[Index]]: every page, by type.
- [[System]]: vault-wide conventions.
````

## Index

Regenerated after each batch of changes: every page grouped by type, with counts.

````markdown
---
type: index
tags: [index, <project>]
aliases: []
updated: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
# Index

Part of [[<Project>]]

Every page in <Project>, grouped by type.

## Decisions (<count>)

- [[<Page>]]

## Gotchas (<count>)

- [[<Page>]]
````

## Diagrams

Mermaid diagrams render natively in Obsidian. Add one when a page describes a flow, a sequence of
calls, a state machine, a schema or an architecture, and follow the `mermaid` skill's rules. Links
inside a diagram are not part of the graph, so every page a diagram names is also linked in the
surrounding prose.

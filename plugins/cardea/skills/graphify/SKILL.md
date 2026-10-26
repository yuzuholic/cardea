---
name: graphify
description: "When and how to use graphify, the local code knowledge graph, in this setup. Use when starting on an unfamiliar or large codebase, answering architecture or 'how does X connect to Y' questions across many files, or when a graphify-out/ folder exists in the project."
---

# graphify

graphify turns a folder into a knowledge graph: code is parsed locally, and its structure
(files, symbols, calls, clusters) becomes something you can query instead of grepping. Its
own skill, `/graphify`, is installed by cardea straight from the graphify package and has the
full command reference. This note covers how it fits here.

## When it's worth it

- A codebase you don't know yet, or a question that spans many files ("what touches sync?",
  "how does a chapter get from a source into the library?").
- Not for a single file or a symbol you can name; Serena (`find_symbol`,
  `find_referencing_symbols`) answers those faster.

## Building and updating

- Build once per project with `/graphify .`; it writes `graphify-out/` in the project.
- After a batch of changes, `/graphify . --update` re-reads only what changed.
- `graphify-out/` is generated. Add it to the project's `.gitignore` rather than committing
  it, unless the user says otherwise.

## Keep it local

graphify sends documents, papers and images to a model for concept extraction; code is parsed
locally. In a project with private documents, build with code only, or ask first.

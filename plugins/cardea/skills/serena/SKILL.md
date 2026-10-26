---
name: serena
description: "Serena, the MCP server that reads and edits code by symbol through a language server. Use for navigating or changing code by type, function or method (find a definition, its references, its implementations, rename across the project), especially in Swift projects, and when the user mentions serena."
---

# Serena

Serena (`serena` MCP server, `--context claude-code`) works on symbols instead of text: it
asks the project's language server where things are defined and used. It starts in whatever
directory Claude Code was launched from (`--project-from-cwd`).

## Reach for it when

| Task | Tool |
|---|---|
| What's in a file, without reading all of it | `get_symbols_overview` |
| Find a type, function or method by name | `find_symbol` |
| Where is this defined / implemented | `find_declaration`, `find_implementations` |
| Who uses this | `find_referencing_symbols` |
| Rename everywhere, safely | `rename_symbol` |
| Replace or add a whole function or type | `replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol` |
| Remove something only if nothing uses it | `safe_delete_symbol` |
| Compiler errors for a file | `get_diagnostics_for_file` |

For plain text searches, config files and non-code files, the built-in tools are simpler.

## Swift needs a build server

Serena's Swift support reads `buildServer.json`. Without it, symbol lookups in an Xcode
project come back empty or wrong. Once per project, from its root:

```sh
xcode-build-server config -project MyApp.xcodeproj -scheme MyApp
```

(`-workspace MyApp.xcworkspace` for a workspace.) If lookups look stale after big changes,
build the scheme once in Xcode or XcodeBuildMCP so the index catches up.

## Memory

Serena has its own memory tools. Don't use them: durable notes go in Basic Memory (see the
`basic-memory` skill), so there is one place to look.

# cardea

Cardea was the Roman goddess of the door hinge — Forculus had the door, Limentinus the
threshold, Cardea the thing that lets it swing. This repo is the hinge: one command installs
my agentic coding setup.

    git clone https://github.com/angelocarasig/cardea.git ~/Repositories/cardea
    cd ~/Repositories/cardea
    ./install.sh

Or, on a fresh machine:

    curl -fsSL https://raw.githubusercontent.com/angelocarasig/cardea/main/install.sh | sh

Install Xcode 26.3+ first and keep it running — `xcrun mcpbridge` needs it and cannot be
scripted in.

## What it does

`install.sh` is idempotent and safe to re-run. It applies the `Brewfile`, asks for the NAS
addresses and API keys, writes them to `.env` (mode 600), symlinks config into place, adds one
line to `~/.zshrc` so the variables are exported — OpenCode resolves `{env:VAR}` from the
shell — and finishes by probing every tool and service so you can see what actually works.

Anything that varies per project belongs in that project, not here.

| Flag | Effect |
|---|---|
| *(none)* | Prompt for each value, showing the current one as the default. Enter keeps it. |
| `--no-prompt` | Ask nothing; keep whatever `.env` already holds. For unattended runs. |
| `--check` | Probe tools and services, then exit. Changes nothing. |

Prompts read from `/dev/tty` rather than stdin, so piping the script from `curl` still works.
Keys are typed hidden and never echoed. Anything real already sitting at a link target is
moved into `backup/<timestamp>/` rather than clobbered.

Each URL is tested the moment you type it, not at the end of the run, so a typo costs one
line instead of a whole install. A failed test re-asks with what you typed as the default:
type a correction, or press Enter twice to keep it anyway and fix it in `.env` later.

The tests ask each service something it has to understand rather than just knocking on the
port. Basic Memory gets an MCP `initialize` and has to answer with its own name and version —
which also proves the transport is right, since an SSE-only endpoint fails it. Langfuse gets
`/api/public/health` and has to answer 200.

| Link | Target |
|---|---|
| `~/.config/opencode/opencode.json` | `opencode/opencode.json` |
| `~/.config/opencode/AGENTS.md` | `opencode/AGENTS.md` |
| `~/.config/ruler/ruler.toml` | `ruler/ruler.toml` |
| `~/.config/ruler/AGENTS.md` | `opencode/AGENTS.md` |
| `~/.config/cardea/env` | `.env` |

Per-file, not whole-directory — OpenCode keeps its own state in `~/.config/opencode`.

After installing, `opencode auth login` picks a model provider. It is interactive and cannot
be scripted.

## Ownership split

Ruler distributes **rules only** (`ruler/ruler.toml` sets `mcp.enabled = false`).
`opencode.json` owns **MCP servers and plugins**. Nothing writes to both, so `ruler apply`
cannot clobber the MCP block. `AGENTS.md` has exactly one source of truth, linked twice.

## Stack

| Area | Tool | Pin |
|---|---|---|
| Agent runtime | OpenCode | brew |
| Multiplexer | herdr | brew |
| Rules sync | Ruler | `0.3.46` (npm, global) |
| Plan review | Plannotator | `@plannotator/opencode@0.28.31` |
| Code understanding | Serena | `v2.1.0` (uvx, git tag) |
| iOS build/test | XcodeBuildMCP | `xcodebuildmcp@2.7.0` |
| iOS symbols | SwiftLens | `swiftlens@0.2.14` |
| iOS bridge | `xcrun mcpbridge` | Xcode 26.3+ |
| iOS LSP feed | xcode-build-server | brew |
| Isolation | container-use | `v0.4.2` (brew) |
| Observability | Langfuse | `4.70.0` (NAS) |
| Memory | Basic Memory | `0.24.1` (NAS) |
| Code graph | graphify | `graphifyy` 0.9.95 |
| Notes UI | Obsidian | cask |

Every version is pinned. `@latest` makes reinstalls unreproducible.

Dropped: Beads (too early), rulesync (unstable releases), other agents (staying on OpenCode).

## Per-project setup

Serena reads `buildServer.json`, which xcode-build-server generates:

    xcode-build-server config -project MyApp.xcodeproj -scheme MyApp

## NAS

    cd nas/lab && docker compose up -d

Basic Memory's SQLite index must sit on a local dataset — never run it on the Mac pointed at
an SMB share. It also has **no auth** on its HTTP endpoints: keep it on LAN or VPN, or front
it with an authenticating reverse proxy. Langfuse's compose has no HA and no backups.

Obsidian opens the NAS `kb/` folder over SMB. Register each Basic Memory project after first
boot:

    docker compose exec basic-memory basic-memory project create homelab /app/kb/homelab

## Secrets

Only `.env.example` is committed. `.env*` is gitignored. Nothing in this repo reads a secret
from a file in version control.

## Unverified — check before trusting

`./install.sh --check` covers whether tools are installed and whether the NAS answers. It
does not cover the items below, which are best-guesses from the docs, marked in-file. Each is
a single command away from being confirmed.

1. **Basic Memory streamable HTTP flag.** `compose.yml` uses
   `--transport streamable-http --host 0.0.0.0 --port 8000`. The image defaults to SSE.
   Confirm with `docker run --rm ghcr.io/basicmachines-co/basic-memory:v0.24.1 basic-memory mcp --help`.
2. **Config volume path.** Mounted at `/home/appuser/.basic-memory` per current docs. Verify
   the running image actually writes there. (The image tag is confirmed: `0.24.1`, with no
   `v` prefix — the GitHub release tag has one, the container tag does not.)
3. **OpenCode `type: remote` against that endpoint.** Untested end to end.
4. **`xcrun mcpbridge` subcommand.** Guessed as `serve`; the entry is `enabled: false` until
   confirmed with `xcrun mcpbridge --help`.
5. **graphify MCP entry.** Docs show `graphify claude install`; no OpenCode target found.
   Entry is `enabled: false` with a guessed `graphify mcp` command.
6. **OpenCode → Langfuse traces.** Not wired. Candidate is `opencode-plugin-otel` pointed at
   Langfuse's OpenTelemetry endpoint.
7. **Serena picking up `buildServer.json`.** Expected, not confirmed on a real Swift project.

Undecided: LiteLLM as a single model endpoint once local LLMs come in.

## Licences

herdr and Basic Memory are AGPL-3.0. Personal use, no redistribution — fine.

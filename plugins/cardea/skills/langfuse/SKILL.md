---
name: langfuse
description: "Langfuse, the self-hosted tracing for every Claude Code session. Use when the user asks what happened in an earlier session, wants to look up a trace, asks why tracing is missing, or mentions langfuse, traces, or observability."
---

# Langfuse

Every Claude Code turn is sent to Langfuse on the NAS (`http://truenas.local:3000`) by the
`langfuse-observability` plugin: the prompt, the reply, each tool call with its input and
output, and timing, grouped by session and tagged with the skills used.

## Finding something from an earlier session

Point the user at the UI: **Tracing → Sessions**, newest first. Each Claude Code session is
one Langfuse session, so searching by a phrase from the conversation or by date finds it. You
cannot read Langfuse yourself; the keys live in the macOS keychain and are not yours to fetch.

## When tracing seems to be off

Check in this order, and stop at the first failure:

1. Langfuse is up: `curl -s -o /dev/null -w '%{http_code}' http://truenas.local:3000/api/public/health`
   should print `200`. The first request after a restart can take about 30 seconds.
2. The plugin is installed and enabled: `claude plugin list`.
3. It has keys: `claude plugin configure langfuse-observability@langfuse-observability` lists
   which options are unset. The user creates keys in the Langfuse UI under **Settings → API
   Keys**, puts them in cardea's `.env`, and reruns `./install.sh`.

## Privacy

Traces include everything in the session, including file contents you read. They stay on the
NAS. Don't paste secrets into a session in the first place; Langfuse would keep them.

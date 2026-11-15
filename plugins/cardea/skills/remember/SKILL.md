---
name: remember
description: "Save a memory to Hindsight on purpose. Use when the user runs /cardea:remember <text> or says 'remember this' and wants it stored without a judgment call."
---

# Remember

`/cardea:remember <text>` is an explicit save. It always saves: the spectrum test in the memory
notes is for implicit saves only. Do not summarise, skip or ask first.

1. Call `mcp__hindsight__retain` at once with `content` set to the text as given. Set `tags`,
   `document_id` and `context` only when they apply:
   - `tags`: a preference is global by default and takes no project tag. Add `project:<app>` only
     when the user ties it to how one app works.
   - `document_id`: a short slug of the subject, such as `user/preference/<slug>` or
     `<project>/decision/<slug>`.
   - `context`: `user instruction`.
2. If the new memory replaces an old decision, retain it under a new `document_id`, then call
   `mcp__hindsight__invalidate_memory` on the old one (`memory_id`, `reason`). Never overwrite.
3. Reply with the operation id and nothing else.

Never save a secret, even when asked: say so instead.

Fallback with no model: `!sh ${CLAUDE_PLUGIN_ROOT}/skills/remember/scripts/retain.sh [--bank <bank>] [--tag <tag>]... <text>`.

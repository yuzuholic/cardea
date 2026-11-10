---
name: app-copy
description: The house rules for user-facing app copy - state the condition, action or result outright, with a substitution test for loose verbs and the patterns that make strings read as machine-written. Use when writing, changing or reviewing UI strings, alerts, empty states, settings labels, onboarding or release notes.
---

# App copy

User-facing copy states the condition, action or result outright. The aim is exactness, not
avoiding text that "sounds like AI": judging by feel is barely better than chance, and an exact
string reads as written by a person anyway. If the project has its own copy or terminology
rules, they win; use this for the parts they do not cover.

## The substitution test

For each new or changed string, replace any loose verb with "is", "is not" or the actual
operation. If the result is more exact, use it. If it is equal or loses meaning, keep the
original.

`stays`, `goes`, `lives`, `brings` and `holds` are prompts to check, not bans. A verb used
literally passes:

| String | Verdict |
|---|---|
| `Similar Titles stays empty until you choose a model.` | Rewrite: `Similar titles are unavailable until a recommendation model is selected.` |
| `%@ downloads once and stays on this device.` | Rewrite: `%@ is stored on this device once downloaded.` |
| `\(name) goes for good.` | Rewrite: `\(name) is permanently deleted.` |
| `It stays in your library.` | Keep: literal |
| `It stays unlocked until you quit the app.` | Keep: literal |

## Patterns to rewrite

| Pattern | Before | After |
|---|---|---|
| Loose verb for a state or capability | `Google and DeepL bring their own languages.` | `Google and DeepL each support different languages.` |
| Breezy reassurance | `Change the capitalisation here and it stays yours.` | `Capitalisation set here is not overwritten.` |
| Quippy fragments | `One tap. Done.` | `Tap Import to add the file.` |
| Clipped negative | `Works offline, no account needed.` | `Does not require an account.` |
| Slogan triad | `Fast, private, yours.` | The one specific claim. |
| Avoiding "is", or "quietly" | `Quietly serves as your reading history.` | `Lists the chapters you have read.` |
| Staged opener | `Good news: your backup is ready.` | `Backup complete.` |
| Feature with a personality | `The reader learns what you like.` | `Recommendations use your reading history.` |

Keep a negative when it corrects a belief the reader holds, such as `not uploaded` in privacy
copy.

## Voice

- Warmth lives in what is said and in addressing the reader as "you", not in figurative verbs or
  reassurance.
- Passive voice is fine for states (`is not counted in your stats`). Buttons and links start
  with a verb (`Send`, `Delete Backup`).
- Errors and destructive actions get plain, neutral wording with no warmth: what happened and
  what to do next.
- Empty states give a clear next step and do not hold information the user needs elsewhere.
- Use possessives sparingly and avoid "we".

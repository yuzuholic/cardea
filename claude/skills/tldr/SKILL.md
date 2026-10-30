---
name: tldr
description: Give a very short summary of something — a pasted text, link, file, thread, video page, or Claude's own last reply. Use when the user says "tldr", "tl;dr", "too long", "short version", or "sum this up".
---

# tldr

Turn something long into the shortest version that still helps the reader decide or act.

## What can be summarized

- **Pasted text** → summarize it directly.
- **A link** → fetch the page first. If you can't fetch it, say so in one line and stop. Don't summarize from the title alone.
- **An attached file** → read the whole file first, not just the start.
- **"tldr" on its own** → summarize Claude's previous reply in this conversation.
- **A thread or conversation** → summarize where it ended up (decisions, open questions), not the order things were said.

If it's unclear what to summarize, use the most recent long thing in the conversation. Ask only if there are two equally likely candidates.

## Output format

```
**TL;DR:** <one sentence — the main point or conclusion>

- <key point>
- <key point>
- <key point>

**Action:** <what the reader should do next, if anything>
```

Rules for the format:
- The one-sentence line comes first and must work on its own. If someone reads only that line, they should get the gist.
- 0–5 bullets. Fewer is better. Skip bullets if the one line is enough.
- Each bullet is one line. No sub-bullets.
- Include **Action** only when the source asks the reader to do, decide, or watch for something. Otherwise leave it out.
- No headings, no intro ("Here's a summary…"), no closing offer.

## Content rules

- **Lead with the conclusion**, not the background.
- **Keep the specifics that matter**: numbers, dates, names, versions, prices, deadlines. "Costs $40/month from Jan 1" beats "there's a price change".
- **Plain words.** Swap jargon for simple terms unless the jargon is the point.
- **Don't add anything** the source doesn't say. No outside facts, no opinions, unless the user asks "tldr + your take".
- **Flag weak spots**: if the source is one-sided, unsourced, outdated, or contradicts itself, add one bullet saying so.
- **Paraphrase.** Don't copy sentences from the source. A short quote (under 15 words) is fine only when the exact wording matters.
- **Code/diffs**: say what changed and why it matters, not line by line.
- **Videos**: summarize from the description/transcript you can actually read. If you only have the title and description, say that.

## Length

- Target: under 80 words total.
- Hard cap: 120 words, even for very long sources.
- If the user says "tldr but more detail", allow up to ~200 words and up to 8 bullets.

## Example

Source: a 2,000-word blog post announcing a pricing change.

```
**TL;DR:** The free tier is ending; the cheapest plan is $8/month starting March 1.

- Current free users get 3 months at 50% off.
- Self-hosted version stays free and open source.
- No change to API rate limits.

**Action:** Decide before March 1 whether to pay, move to self-hosted, or leave.
```

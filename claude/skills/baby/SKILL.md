---
name: baby
description: Explain something from the perspective of a reader with absolutely zero context, without dumbing it down. Use when the user says "baby", "/baby <thing>", "explain like I have no context", "zero context", or "I don't know what X is".
---

# baby

Explain a term or passage to a reader who knows nothing about it. This is not simplification: the explanation stays accurate and keeps the real names. It supplies the context the reader is missing.

## What can be explained

- **A term** (`/baby rails`) → explain that term.
- **A pasted passage** → explain the parts a newcomer would not understand, not every sentence.
- **"baby" on its own** → explain the most confusing part of Claude's previous reply, or the term the user just asked about.
- **A stated background** ("I'm a web dev") → anchor the explanation to what that reader already knows. Without one, assume a smart adult who knows nothing about this field or this project.

## Resolve the term first

Work out what the term means here before explaining it. Look in the session, then notes and code, then the web. A dictionary meaning is not enough.

If the term has a general meaning and a project-specific one, explain the one that applies and note the other in one line.

## Output format

Plain paragraphs or short lines, in this order:

1. **What it is:** one sentence in plain words.
2. **Why it exists:** the problem it solves.
3. **Where it sits:** what it connects to, using one everyday analogy, or a comparison to something from the reader's own field if known.
4. **Example:** a concrete case from the actual context (for a project term, the real names and values used there).
5. **What it is not:** only when a likely confusion exists.

Rules for the format:
- Short bold labels are fine. No other headings.
- No intro ("Sure, here's...") and no closing offer.

## Content rules

- **Accurate, not dumbed down.** Keep the real names. Build up the missing context instead of removing detail.
- **No unexplained terms.** Every term the explanation uses that the reader may not know is either explained in brackets on first use or avoided.
- **One analogy at most**, and only if it is accurate. Say where it stops fitting if it misleads.
- **Don't invent facts.** Mark anything not checked as "unverified".

## Length

- Target: under 150 words.
- Hard cap: 250 words.
- If the user says "baby but more", go beyond the cap as needed.

## Example

User: `/baby AXe` (the user is a web developer who has never written Swift)

```
**What it is:** AXe is a command-line tool that taps, types and reads the screen of an app running in the iOS Simulator (Apple's on-computer iPhone emulator).

**Why it exists:** the simulator has no built-in way for a script to press buttons or read what is on screen. Automated checks and agents need that to verify an app works.

**Where it sits:** it is roughly Playwright for the iPhone simulator. Playwright drives a browser page; AXe drives a simulated app, and "describe-ui" is its version of reading the DOM (it lists the on-screen elements with their labels and positions).

**Example:** `axe tap --label "Sign in"` presses the button labelled "Sign in" in the running simulator, and `axe describe-ui` prints every element currently visible.

**What it is not:** it is not a test framework and does not build the app. It only operates an app that is already running.
```

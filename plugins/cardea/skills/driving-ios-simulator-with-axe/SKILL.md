---
name: driving-ios-simulator-with-axe
description: Use when an iOS Simulator app must be tapped, navigated, typed into, or screenshotted to verify a change - especially when there is no Simulator.app window (Xcode 27), when axe taps report success but nothing happens, or when describe-ui is missing elements shown on screen in sheets or popovers.
---

# Driving the iOS Simulator with AXe

## Overview

`axe` (brew `cameroncooke/axe/axe`, docs at axe-cli.com/docs) drives a booted simulator through
HID events and reads its accessibility tree. It needs no Simulator.app window, which Xcode 27
does not ship. **Every HID command is fire-and-forget: "completed successfully" means the event
was sent, not that the app reacted.** Confirm each step with a screenshot or `describe-ui`.

For the full vendor reference: `axe init --print`, or `axe help <command>`.

## Quick reference

| Goal | Command |
|---|---|
| Find UDID | `axe list-simulators` |
| Reliable tap | `axe touch -x X -y Y --down --up --delay 0.12 --udid U` |
| Read screen tree | `axe describe-ui --udid U` |
| Read element at point | `axe describe-ui --point X,Y --udid U` |
| Type | `axe type 'text' --udid U` (`--stdin` for tricky quoting) |
| Scroll | `axe swipe --start-x .. --start-y .. --end-x .. --end-y .. --udid U` |
| Screenshot | `axe screenshot --udid U --output shot.png` |
| Many steps, one process | `axe batch --udid U --step "touch -x 1 -y 2 --down --up --delay 0.12" --step "sleep 1.5"` |

Coordinates are logical points (e.g. 440x956 on iPhone 17 Pro Max), not screenshot pixels.
Screenshot pixels / 3 = points on 3x devices.

## Gotchas observed on Xcode 27 + iOS 26 SwiftUI apps

1. **`axe tap` drops taps on SwiftUI buttons.** Tab bar items, toolbar buttons, glass buttons
   and `Button`-backed custom controls ignored `tap` in both `--tap-style simulator` and
   `physical`, while printing success. A held `touch --down --up --delay 0.12` activated every
   one. Default to `touch` for taps; use `tap --label` only after confirming it works on that
   screen.
2. **`describe-ui` (full tree) omits presented sheets.** With a sheet up, the full dump still
   lists the screen underneath, so `tap --label` resolves to the element *behind* the sheet.
   `describe-ui --point X,Y` does see sheet content - use it to probe, and take coordinates from
   the screenshot.
3. **Wait for transitions.** Sleep ~1.5s after a tap that navigates or presents before the next
   tap or screenshot, or the tap lands mid-animation and is lost.

## Verify loop

```bash
U=<udid>
t() { axe touch -x "$1" -y "$2" --down --up --delay 0.12 --udid "$U" >/dev/null; sleep 1.5; }
shot() { axe screenshot --udid "$U" --output "$1" >/dev/null && sips -Z 900 "$1" >/dev/null; }

t 143 905          # e.g. a tab
t 399 832          # e.g. a button that presents a sheet
shot /tmp/after.png  # then view the image; never assume the tap landed
```

`sips -Z 900` keeps the image small enough to read without wasting context.

## Common mistakes

| Mistake | Fix |
|---|---|
| Trusting "Tap ... completed successfully" | Screenshot after every step that matters |
| Using screenshot pixel coordinates | Divide by device scale, or read `frame` from `describe-ui` |
| `tap --label` inside a sheet | Probe with `describe-ui --point`, tap by coordinate with `touch` |
| Chained taps with no sleep | Sleep after navigation/presentation |
| `open -a Simulator` to see the screen | Not needed; screenshot with `axe` or `xcrun simctl io U screenshot` |

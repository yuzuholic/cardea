---
name: aletheia-conventions
description: "Day-to-day coding conventions for the Aletheia iOS app: files and headers, constants, modern APIs, taps, GRDB, design personas, visual rules and haptics. Use whenever writing or reviewing Swift or SwiftUI in the aletheia repo (~/Repositories/aletheia or its worktrees)."
---

# Aletheia conventions

Carried over from the old global agent rules and trimmed to what the code still does. The
repo's own `CLAUDE.md` and the Basic Memory project `aletheia` win where they say more; code
wins over both.

- **Files:** PascalCase, named for the primary type. New Swift files start with the same header
  block as their neighbours (copy it from a file in the same folder and set today's date as
  `D/M/YY`); keep existing headers.
- **Constants:** no magic numbers. A private `Layout` enum per view, the dimension and palette
  tokens, `UserDefaults` for anything the reader controls (ask when unsure which), xcconfig for
  per-environment values.
- **Modern APIs:** Observation over `ObservableObject`, async/await and `AsyncStream` over Combine,
  Swift Testing over XCTest. SwiftUI shorthand (`.rect`, `.capsule`). UIKit only where SwiftUI
  can't.
- **Taps:** `.tappable` over `Button` for plain taps; `NavigationLink` and other semantic controls
  where they fit.
- **GRDB:** no N+1 queries (batch fetch and group in memory), query interface over raw SQL, raw SQL
  names tables and columns through `databaseTableName` and column enums, `fetchCount` not
  `fetchAll().count`, batch writes, and pass `db` into anything called inside a transaction or it
  throws "database methods are not reentrant". Observations cancel in `onTermination` and finish on
  error. The `grdb` skill has the details.
- **Design personas:** judge UI as a UX designer, an average chud and a power user; the `panel`
  skill runs all three. The Basic Memory area `apps/ios/design-system` holds the visual rules in
  full (start at "Design system overview").
- **Visual rules:** positive framing; semantic colour (green success, blue interactive or in
  progress, yellow/orange attention, red error or destructive, grey neutral); one hero per section;
  no redundant encodings; progressive disclosure; clear next steps; empty states guide with an
  action. Avoid badge soup, orphaned numbers, alarm colours for non-errors, negative framing,
  unexplained jargon, buried primary actions, meaningless decoration and redundant success badges.
- **Haptics:** `.sensoryFeedback(trigger:)` in step with the animation, one per user action, never
  while reading or scrolling; background work gets one at start and one at completion at most.

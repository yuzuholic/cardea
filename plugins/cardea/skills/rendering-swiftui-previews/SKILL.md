---
name: rendering-swiftui-previews
description: Use when a SwiftUI view or #Preview needs to be seen as an image without opening Xcode's canvas - iterating on UI design drafts, comparing layout options, or screenshotting a view in isolation from app data. Xcode 26.3+ / 27.
---

# Rendering SwiftUI Previews

## Overview

Xcode ships an MCP server (`xcrun mcpbridge`) whose `RenderPreview` tool builds a `#Preview` and
returns a PNG. It runs through the user's open Xcode: no simulator driving, no canvas clicking.
`render_preview.py` in this folder wraps the JSON-RPC handshake.

## When to Use

- Design iteration: several hardcoded drafts as `#Preview`s, rendered and compared
- Checking a component's look in isolation

**Not for:** verifying real data flows or navigation. Run the app on a simulator for that.

## Quick Reference

```bash
pgrep -x Xcode   # must be running
python3 -I ~/.claude/skills/rendering-swiftui-previews/render_preview.py \
    MyApp/Screens/Feature/FeatureDrafts.swift /abs/out/dir/out.png 0 \
    --project /abs/path/MyApp.xcodeproj
sips -Z 900 /abs/out/dir/out.png --out /abs/out/dir/out-small.png   # then Read the small one
```

- The source path is **project-relative** (as in Xcode's navigator), not absolute.
- Always pass `--project` with an absolute path. Agent shells reset their working directory, and the fallback search starts from it.
- The output folder is created if missing. Put renders in the session scratchpad.

## Quirks

| Symptom | Cause / fix |
|---|---|
| `NEEDS APPROVAL` / "waiting for the user to approve" | First use per agent. Ask the user to approve it from Xcode's **MCP menu bar icon**, then rerun |
| Index 2+ renders preview 0 or 1 | Only the first two `#Preview`s in a file render. Move the wanted one to the top |
| "Waiting for packages to load" / "File not found in project structure" | Xcode is still resolving SPM, or hasn't synced a just-written file yet. The script retries for 5 min |
| `ThunkBuildTimeoutError` / "type checker appears to have timed out" | The drafts file is too heavy. Split shared mock data and each pair of drafts into their own files, and pull ternaries and long string concatenations out of view bodies into helpers |
| Light mode when the app is dark | Add `.preferredColorScheme(.dark)` in the preview |
| Grey placeholders instead of art | `UIImage(contentsOfFile: "/abs/host/path.jpg")` works in previews. Copy real images (e.g. from a simulator's Kingfisher cache) to a scratch folder and load by path. Never commit them as assets |

## Draft Workflow

1. Write throwaway `FeatureDrafts.swift` in the app target, wrapped in `#if DEBUG`. Use one named `#Preview` per direction, built from the real components, theme tokens and a mock data struct.
2. Render each preview (two per file at most, see Quirks) and show the PNGs to the user.
3. Iterate on feedback, then build the chosen direction into the real screen.
4. Delete the drafts file.

## Common Mistakes

- Passing an absolute path as `sourceFilePath`. It must be project-relative
- Trusting the index. Check that the printed `[displayName]` matches the preview you asked for
- Mock data with fake grey boxes. Real art changes the verdict

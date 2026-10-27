---
name: sim-clone-restore
description: Give a task its own iOS simulator holding real app data - clone a shut-down "golden" simulator, or seed one by restoring a backup through the app - check disk space first, and delete what you made afterwards. Use when asked to verify a change on a simulator with real data, make or rebuild a golden simulator, restore a backup into a simulator, or when simulators fail with "no space left on device".
---

# Simulator clones and restores

Real data on a simulator comes from one shut-down **golden** simulator that holds it. Each task
works on its own clone, so concurrent sessions never share a device and the golden copy is never
touched. If the project names its golden simulator or seed folder (in its CLAUDE.md or a skill),
use those names.

## Rules

- **Never use the golden simulator directly.** Only `simctl clone` it, and only while it is shut
  down. Never touch another task's clone or a stock simulator someone else is using.
- **One clone per task**, named `<app>-<task>`. Delete it when the work lands; under an
  orchestrator, its teardown does this from the UDID the implementer reports.
- **Tests run with `-parallel-testing-enabled NO`** while other tasks may be running, so no task
  makes shared test clones that another task's cleanup could delete mid-run.
- **Restoring is destructive** - it replaces the app's data. Only into a simulator made for this task,
  or the golden one when rebuilding it was asked for. Never a physical device.
- Golden missing: stop and tell the user. Rebuild it only when asked.
- Builds for a clone use their own derived data (`-derivedDataPath .context/dd`) so concurrent
  sessions don't lock a shared one.
- Drive the app with the `driving-ios-simulator-with-axe` skill.

## 1. Check disk space first

A clone of a simulator holding a real library can be several GB, and a full disk fails mid-clone or
mid-build in confusing ways.

```sh
df -h /System/Volumes/Data                       # the truth; du overcounts APFS clones
xcrun simctl --set testing list devices          # parallel-test clones left by xcodebuild
xcrun simctl list devices | grep -i unavailable  # sims whose runtime is gone
xcrun simctl list devices | grep -E '<app>-'     # leftover task clones
```

Under about 20 GB free, offer to clear these before cloning (list them with sizes, let the user pick):

| What | Safe? | Delete with |
|---|---|---|
| Parallel-test clones (`~/Library/Developer/XCTestDevices`) | yes if none are Booted; xcodebuild recreates them | `xcrun simctl --set testing delete all` |
| Unavailable simulators | yes | `xcrun simctl delete unavailable` |
| SwiftUI preview simulators | yes; Xcode recreates them | `xcrun simctl --set previews delete all` |
| This project's stale task clones | only ones whose task is finished; ask about any you didn't make | `xcrun simctl delete <udid>` |
| Simulator runtimes | the user's working set | only on explicit request: `xcrun simctl runtime delete <id>` |

Gotchas:

- `simctl delete` finishes in the background via `$TMPDIR/Deleting-*`, so `$TMPDIR` briefly grows.
  Wait before measuring:
  `while find "$TMPDIR" -maxdepth 1 -name 'Deleting-*' | grep -q .; do sleep 5; done; df -h /System/Volumes/Data`
- Report the space `df` shows freed, not what `du` claimed.
- Always `du -x`: home folders can hold network mounts, and `du` without it crawls them.
- zsh aborts a command line on a glob with no matches, so an `rm` with a glob can silently do
  nothing. Use `find ... -exec` or check the glob matched.
- Test clones come back after every parallel test run; `-parallel-testing-enabled NO` prevents them.

## 2. Clone

```sh
xcrun simctl list devices | grep "<Golden name>"     # must say (Shutdown)
xcrun simctl clone "<Golden name>" <app>-<task>
U=$(xcrun simctl list devices | grep "<app>-<task>" | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot $U
xcrun simctl install $U <DerivedData>/Build/Products/Debug-iphonesimulator/<App>.app
xcrun simctl launch $U <bundle id>
```

## 3. Seeding with a backup (fresh sim, rebuilding golden, or a specific backup)

An app-group container usually cannot be copied off a phone, so real data reaches a simulator by
restoring the app's own backup file inside the app.

1. **Pick the backup.** The project's seed folder if it has one, newest first; otherwise ask the user
   to export one from the phone and save it to the Mac, then copy it into the seed folder so the
   next rebuild finds it.
2. **Make Files' local storage exist.** On a fresh simulator it doesn't until a document picker runs,
   and launching the Files app directly fails. Open the app's own import or restore picker once.
3. **Drop the file into On My iPhone.** The container metadata plists are binary, so match the
   identifier with `plutil`, not `grep`:

   ```sh
   G=~/Library/Developer/CoreSimulator/Devices/$U/data/Containers/Shared/AppGroup
   D=
   for f in $G/*/.com.apple.mobile_container_manager.metadata.plist; do
     [[ "$(plutil -extract MCMMetadataIdentifier raw "$f" 2>/dev/null)" == "group.com.apple.FileProvider.LocalStorage" ]] \
       && D="${f:h}/File Provider Storage"
   done
   [[ -n "$D" ]] && mkdir -p "$D" && cp "$BACKUP" "$D/"
   ```

   Guard on `$D`: an empty one turns `${f:h}` into the working directory and the copy lands in the
   repo. The file shows up in the picker within seconds, no reboot.
4. **Restore** through the app's own flow (Browse > On My iPhone > the file), confirm, and wait for
   its success screen with `describe-ui`, not a fixed sleep.
5. **Check** the data arrived: a count on screen, or copy the simulator's database and open the copy
   read-only. Never query a live database file.

### Rebuilding golden

Only when asked. Delete the old one, `xcrun simctl create "<Golden name>" "<device type>"`, run
step 3 on it with the newest simulator build, then shut it down and leave it alone.

## 4. Clean up

When the work lands (or the task is abandoned):

```sh
xcrun simctl shutdown $U; xcrun simctl delete $U
ls ~/Library/Developer/CoreSimulator/Devices/ | grep -c $U    # 0
xcrun simctl --set testing list devices                        # delete any test clones this task left
```

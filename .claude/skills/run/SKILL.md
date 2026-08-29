---
name: run
description: Build and launch the Miya SwiftUI app in the iOS Simulator, and tail its logs. Use when asked to run, build, launch, or screenshot the Miya app, or to verify a change works in the Simulator.
---

# Run Miya in the iOS Simulator

Miya is a single-target SwiftUI iOS app with a shared Xcode scheme (`Miya`) and no dependency manager. There's no `xcworkspace` from CocoaPods/SPM to worry about — build straight from `Miya.xcodeproj`.

## 1. Pick a simulator

List available devices and pick a booted or bootable iPhone simulator:
```
xcrun simctl list devices available
```
Prefer a device that's already `(Booted)`. Otherwise pick any available iPhone (e.g. "iPhone 16 Pro") — the exact model doesn't matter unless the task specifically calls for a certain screen size.

## 2. Build

```
xcodebuild -project Miya.xcodeproj -scheme Miya -destination 'platform=iOS Simulator,name=<device name>' build
```

Watch for `** BUILD SUCCEEDED **` at the end of output. On failure, the errors are usually near the end of the log — grep for `error:` if the output is long.

## 3. Boot the simulator and install/launch the app

```
xcrun simctl boot "<device name>" 2>/dev/null   # no-op if already booted
open -a Simulator
xcrun simctl install booted "$(xcodebuild -project Miya.xcodeproj -scheme Miya -destination 'platform=iOS Simulator,name=<device name>' -showBuildSettings 2>/dev/null | awk -F'= ' '/ CODESIGNING_FOLDER_PATH/{print $2}')"
xcrun simctl launch booted com.hurtado.Miya
```

## 4. Verify

- Take a screenshot to confirm the UI rendered as expected:
  ```
  xcrun simctl io booted screenshot /tmp/miya-screenshot.png
  ```
- Tail logs to check for runtime issues while the app is running:
  ```
  xcrun simctl spawn booted log stream --predicate 'process == "Miya"'
  ```

## Notes

- The bundle identifier is `com.hurtado.Miya` — needed for `simctl launch`/`simctl uninstall`.
- There are no test targets in this project, so there is no `xcodebuild test` step.
- Re-run the build step after every source change before relaunching; `simctl launch` does not rebuild.

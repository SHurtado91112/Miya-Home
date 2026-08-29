# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Build for the iOS Simulator:
```
xcodebuild -project Miya.xcodeproj -scheme Miya -destination 'platform=iOS Simulator,name=<simulator name>' build
```
List available simulator destinations with `xcrun simctl list devices available`.

There are no test targets in this project yet, so there is no `xcodebuild test` invocation to run.

The `Miya` scheme is shared (`Miya.xcodeproj/xcshareddata/xcschemes/Miya.xcscheme`), so `xcodebuild -list -project Miya.xcodeproj` and CLI builds resolve it without opening Xcode first.

## Architecture

- Single-target SwiftUI iOS app (bundle id `com.hurtado.Miya`, iOS 18.2 deployment target, Swift 5), using the SwiftUI App lifecycle (`Miya/MiyaApp.swift`, no AppDelegate/SceneDelegate).
- No external dependencies (no SPM packages, no CocoaPods).
- Code is organized by role under `Miya/`:
  - `Models/` — view models, built with the `@Observable` macro (not `ObservableObject`/`@Published`). See `Models/HomeModel.swift`.
  - `Views/` — SwiftUI views, one struct per file (`Views/HomeView.swift`, `Views/PreviewCard.swift`).
  - `Extensions/` — cross-cutting extensions. `Extensions/Font.swift` centralizes typography by overriding the standard SwiftUI font roles (`.largeTitle`, `.title`, `.headline`, `.body`, `.caption`) with custom font names — use these environment-based font overrides rather than hardcoding `Font.custom(...)` in views.
- Views are constructed with an injected model (e.g. `ContentView` builds a `HomeModel` and passes it into `HomeView`) rather than views owning their own state.

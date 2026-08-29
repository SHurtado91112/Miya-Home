# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Build for the iOS Simulator:
```
xcodebuild -project Miya.xcodeproj -scheme Miya -destination 'platform=iOS Simulator,name=<simulator name>' -skipMacroValidation build
```
`-skipMacroValidation` is required on the command line — TCA and its dependencies ship Swift macros whose fingerprints Xcode otherwise refuses to run outside the GUI ("Target 'ComposableArchitectureMacros' must be enabled before it can be used"). In Xcode.app, trust the macros once when prompted instead.

List available simulator destinations with `xcrun simctl list devices available`.

There are no test targets in this project yet, so there is no `xcodebuild test` invocation to run. When a test target is added, use Swift Testing (`@Test`/`#expect`) with TCA's `TestStore` — not XCTest. Apply the `swift-engineering:swift-testing` and `swift-engineering:composable-architecture` skills.

The `Miya` scheme is shared (`Miya.xcodeproj/xcshareddata/xcschemes/Miya.xcscheme`), so `xcodebuild -list -project Miya.xcodeproj` and CLI builds resolve it without opening Xcode first.

## Architecture

Single-target SwiftUI iOS app (bundle id `com.hurtado.Miya`, iOS 18.2 deployment target, Swift 5), using the SwiftUI App lifecycle (`Miya/MiyaApp.swift`, no AppDelegate/SceneDelegate).

**This project is committed to The Composable Architecture (TCA).** All feature logic lives in reducers, not in view models. Apply the `swift-engineering:composable-architecture` skill for any feature work.

- **Dependency** — `swift-composable-architecture` (Point-Free) via SPM, pinned to **exact version `1.17.1`** in `project.pbxproj`, with the full transitive graph frozen in `Miya.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (commit that file). The pin is deliberate: this machine runs **Xcode 16.2 / Swift 6.0.3**, and TCA ≥ 1.24 needs Swift tools 6.4 while `swift-navigation` ≥ 2.8 uses Swift 6.1 trailing-comma syntax. Do not bump TCA or run "Update to Latest Package Versions" until Xcode is upgraded (target Xcode 26 for the current 1.26.x line, then move the pin to `upToNextMajor` from that version). TCA is the only third-party dependency the project should carry directly.
- **Features** — each screen or reusable unit of behavior is a `@Reducer` struct with an `@ObservableState struct State`, an `enum Action`, and a `body` returning the reducer. Compose parent/child features with `Scope`, `ifLet`, and `forEach`. Model navigation with state (`@Presents`, `StackState`), never with raw SwiftUI navigation bindings.
- **Collections of child state** use `IdentifiedArrayOf<Child.State>` and are rendered with `ForEach(store.scope(state:action:))`. Element ids must be unique within their collection.
- **Side effects** run in `Effect` values returned from the reducer. External systems (clocks, network, persistence, seed data) are reached through `@Dependency` and are overridden in previews and tests with `withDependencies` / `TestStore.dependencies`.
- **Stores** — the root `StoreOf<AppFeature>` is created once in the composition root (`MiyaApp` or a dedicated root view) with `Store(initialState:reducer:)`. Child views receive scoped stores; views never construct their own stores or models.

Code is organized by role under `Miya/`. The target uses a `PBXFileSystemSynchronizedRootGroup`, so new files under `Miya/` are picked up automatically — no `project.pbxproj` edits needed to add sources.
- `Features/` — one `@Reducer` per file (`Features/HomeFeature.swift`), paired with its SwiftUI view (`Features/HomeView.swift`) in the same file or alongside it. This replaces the old `Models/` + `Views/` split.
- `Views/` — only truly presentational, store-free components (`Views/PreviewCard.swift`).
- `Extensions/` — cross-cutting extensions. `Extensions/Font.swift` centralizes typography by overriding the standard SwiftUI font roles (`.largeTitle`, `.title`, `.headline`, `.body`, `.caption`) with custom font names — use these environment-based font overrides rather than hardcoding `Font.custom(...)` in views.

`HomeFeature` is the reference example: `@Reducer` with `@ObservableState` `State` (`title`, `sections: IdentifiedArrayOf<HomeSection>`), a nested `View` action enum consumed via `@ViewAction`, and placeholder `sections` seeded in `State.init` (to be replaced by an `@Dependency`-loaded client when real data exists). `ContentView` owns the root `Store` in `@State` and passes it to `HomeView`.

## Development principles

Use the most modern Swift, SwiftUI, and architecture practices for all new code:

- **The Composable Architecture** — the non-negotiable app architecture, as described above. Reducers hold all state and logic; views are thin projections of a `Store`.
- **Modern SwiftUI** — current iOS 17+ idioms only: `NavigationStack` over `NavigationView`, `.task`/`.refreshable` for async work, structured concurrency (`async`/`await`, actors, `Sendable`) over completion handlers, and the environment-based font/style overrides in `Extensions/`. Do not introduce `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject` — TCA's `@ObservableState` and `@Bindable var store` cover view state. Apply the `swift-engineering:modern-swift` and `swift-engineering:swiftui-patterns` skills.
- **HIG & accessibility** — honour the Apple Human Interface Guidelines, Dynamic Type, VoiceOver, and dark mode. Apply the `swift-engineering:ios-hig` skill.
- **Testing** — write tests with Swift Testing and TCA's `TestStore`, asserting every state mutation. Apply the `swift-engineering:swift-testing` skill.

## Migration status

The `HomeModel` → `HomeFeature` migration is **complete**. `Miya/Models/` and the old `Views/HomeView.swift` are gone; `MiyaApp` no longer prints font families on appear; `protocol Preview` was deleted.

Remaining follow-ups when the Home screen gains real behavior:
- Replace the placeholder `sections` seeded in `HomeFeature.State.init` with an `@Dependency` client (e.g. `HomeClient.load`) invoked from `.view(.onAppear)`; override it in the `#Preview` and in tests.
- If `HomeSection` / `HomeSectionItem` gain their own behavior, promote them to child `@Reducer`s composed with `forEach`, iterated in the view via `store.scope`. Their `Int` ids are unique within each `IdentifiedArrayOf` today; switch to a stable domain id (or `UUID`) once the data is real.
- No test target exists yet. When one is added, cover `HomeFeature` with a `TestStore` (Swift Testing).

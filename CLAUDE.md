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

- **Info.plist** — `GENERATE_INFOPLIST_FILE = YES`, so most keys come from `INFOPLIST_KEY_*` build settings. `Info.plist` at the **repo root** (not under `Miya/`) holds the handful of keys Xcode's generator has no `INFOPLIST_KEY_` equivalent for — today just `UIBackgroundModes = [audio]` — and the generated keys are merged into it via `INFOPLIST_FILE`. Setting `INFOPLIST_KEY_UIBackgroundModes` does nothing; it's silently dropped. It lives outside `Miya/` because that folder is a synchronized root group, which would also copy the plist as a bundle resource and fail the build with "Multiple commands produce .../Info.plist".
- **Dependency** — `swift-composable-architecture` (Point-Free) via SPM, pinned to **exact version `1.17.1`** in `project.pbxproj`, with the full transitive graph frozen in `Miya.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (commit that file). The pin is deliberate: this machine runs **Xcode 16.2 / Swift 6.0.3**, and TCA ≥ 1.24 needs Swift tools 6.4 while `swift-navigation` ≥ 2.8 uses Swift 6.1 trailing-comma syntax. Do not bump TCA or run "Update to Latest Package Versions" until Xcode is upgraded (target Xcode 26 for the current 1.26.x line, then move the pin to `upToNextMajor` from that version). TCA is the only third-party dependency the project should carry directly.
- **Features** — each screen or reusable unit of behavior is a `@Reducer` struct with an `@ObservableState struct State`, an `enum Action`, and a `body` returning the reducer. Compose parent/child features with `Scope`, `ifLet`, and `forEach`. Model navigation with state (`@Presents`, `StackState`), never with raw SwiftUI navigation bindings.
- **Collections of child state** use `IdentifiedArrayOf<Child.State>` and are rendered with `ForEach(store.scope(state:action:))`. Element ids must be unique within their collection.
- **Side effects** run in `Effect` values returned from the reducer. External systems (clocks, network, persistence, seed data) are reached through `@Dependency` and are overridden in previews and tests with `withDependencies` / `TestStore.dependencies`.
- **Stores** — the root `StoreOf<AppFeature>` is created once in the composition root (`MiyaApp` or a dedicated root view) with `Store(initialState:reducer:)`. Child views receive scoped stores; views never construct their own stores or models.

Code is organized by role under `Miya/`. The target uses a `PBXFileSystemSynchronizedRootGroup`, so new files under `Miya/` are picked up automatically — no `project.pbxproj` edits needed to add sources.
- `Features/` — one `@Reducer` per file (`Features/HomeFeature.swift`), paired with its SwiftUI view (`Features/HomeView.swift`) in the same file or alongside it. This replaces the old `Models/` + `Views/` split.
- `Views/` — only truly presentational, store-free components (`Views/PreviewCard.swift`).
- `Services/` — `@DependencyClient` clients and their backing implementations (`HomeClient`, `MiyaGraphQLClient`, `AudioPlayerClient` + `AudioPlayerEngine`).
- `Extensions/` — cross-cutting extensions. `Extensions/Font.swift` centralizes typography by overriding the standard SwiftUI font roles (`.largeTitle`, `.title`, `.headline`, `.body`, `.caption`) with custom font names — use these environment-based font overrides rather than hardcoding `Font.custom(...)` in views.

**Audio playback** lives in `SongPreviewFeature`, which owns the queue, transport state, and the long-lived player effect. Two rules keep it working:
- The player effect is started by a reducer action (`HomeFeature.openItem` sends `.preview(.presented(.song(.start)))`), never by a view's `.task`/`.onAppear`. `HomeView` swaps `SongPreviewView` (sheet) for `SongMiniBar` (overlay) when the sheet collapses, so a view-scoped task would stop the music on every minimize.
- `AudioPlayerEngine`'s methods are `async` even where nothing suspends. Swift 5 language mode doesn't diagnose a synchronous call to a `@MainActor` member from a nonisolated async context, so without the suspension point `AVPlayer` / `MPNowPlayingInfoCenter` work would run off the main thread.

Songs get their stream URL from the server's `Song.audioUrl`; `AudioTrack.init(item:…)` falls back to a bundled generated track (`Miya/Resources/test-track-{0,1,2}.m4a`, picked by a stable hash of the item id) for the JSON fixtures and for songs with no ingested audio file.

`HomeFeature` is the reference example: `@Reducer` with `@ObservableState` `State` (`title`, `sections: IdentifiedArrayOf<HomeSection>`), a nested `View` action enum consumed via `@ViewAction`, and placeholder `sections` seeded in `State.init` (to be replaced by an `@Dependency`-loaded client when real data exists). `ContentView` owns the root `Store` in `@State` and passes it to `HomeView`.

## Authentication

Google SSO, with **no third-party SDK** — `ASWebAuthenticationSession` + OAuth 2.0 PKCE (RFC 8252), Keychain via the Security framework. An iOS OAuth client is a *public client*: Google issues no client secret for it, and PKCE is what authenticates the exchange, so the SDK buys nothing that isn't in `Services/GoogleOAuth.swift` + `Services/PKCE.swift`.

The authorization code is redeemed **server-side**. The device sends `code` + `code_verifier` + `nonce` to MiyaServer, which calls Google, verifies the `id_token` (signature, `iss`, `aud`, `exp`, `nonce`, `email_verified`), and returns Miya's own credentials. Google's tokens never touch the phone; the only credentials on device are ones the server can revoke.

Three rules keep this correct:

- **No secrets in TCA `State` or `Action`.** TCA prints actions through CustomDump (`_printChanges`, `TestStore` diffs, `reportIssue`), so a `Session` in an action is both tokens in the Xcode console and in CI logs. Reducers deal only in `UserProfile`; `Session` lives in the Keychain and inside the `SessionStore` actor. `Session` also has a redacting `CustomDumpStringConvertible`.
- **The fixture-mode bypass is `#if DEBUG` only** (`Services/RunMode.swift`). `MIYA_SERVER_URL` is set solely in the Debug scheme's `LaunchAction`, so it is absent from Release, TestFlight, and the App Store — a runtime-only "no server ⇒ no wall" check would ship an app with no authentication at all.
- **Refresh is single-flight.** `HomeFeature.view(.onAppear)` fires `loadSections` and `loadAlbums` concurrently, so two callers routinely hit the same expired token. Refresh tokens are single-use and rotated, so a double redemption reads as a replay and revokes every session for that user. `SessionStore.refresh(presenting:)` makes concurrent callers join one task.

`AuthClient` is the only seam reducers and `HomeClient` touch. `AppFeature` is the root: an `@ObservableState` **enum** (`@CasePathable` must be written explicitly — `@ObservableState` does not add it, and `ifCaseLet` requires it) so signing out *destroys* `HomeFeature.State` rather than leaving the previous user's library in memory. Sign-out also has to stop audio explicitly — `ifCaseLet` cancels the child's effects, but `AudioPlayerEngine` is a separate `@MainActor` singleton and would keep playing over the sign-in screen.

`MiyaGraphQLClient.execute` attaches `Authorization: Bearer` and retries **once** on a 401 (`allowRetry`, not recursion). The server returns a genuine HTTP 401 rather than Strawberry's default 200-with-`errors[]`, because the client cannot tell an auth failure from an ordinary query error otherwise, and would never refresh.

`/media` bytes are protected by **signed URLs**, not the bearer token: `AVPlayer` and `AsyncImage` fetch those URLs directly and attach no headers of ours. The server HMACs each `/media` path with an expiry (bucketed to the hour so the URL stays stable and the `immutable` cache header still works). No iOS code is involved — the signed URL simply arrives inside an already-authenticated GraphQL response.

**Setup.** Create an *iOS* OAuth client for `com.hurtado.Miya` in the Google Cloud Console, then put the client id in `MiyaGoogleClientID` and its reversed form in `CFBundleURLSchemes` — both in the **root** `Info.plist`, for the same reason `UIBackgroundModes` lives there (no `INFOPLIST_KEY_` equivalent, and a plist inside the synchronized group double-copies). Set `GOOGLE_IOS_CLIENT_ID`, `JWT_SECRET`, and `MEDIA_URL_SECRET` in MiyaServer's `.env`.

**Testing against a real server:** `xcrun simctl launch` does **not** inherit the scheme's environment, so pass `SIMCTL_CHILD_MIYA_SERVER_URL=…`. On the Simulator, mkcert's root CA is not trusted (it was trusted on the *device*), so either `xcrun simctl keychain booted add-root-cert "$(mkcert -CAROOT)/rootCA.pem"` or test sign-in on device. Unlike Sign in with Apple, this flow does work on the Simulator.

**Guideline 4.8:** shipping Google as the only login is an App Store rejection risk — an app offering third-party SSO must also offer a login limiting data to name and email. `SignInFeature.Provider` is an enum over a list of buttons precisely so Sign in with Apple is one more case, not a rewrite. It needs the `com.apple.developer.applesignin` entitlement and a paid Developer Program membership.


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

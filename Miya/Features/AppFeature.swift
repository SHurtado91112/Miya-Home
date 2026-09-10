//
//  AppFeature.swift
//  Miya
//

import ComposableArchitecture
import SwiftUI

/// The root feature: shows the sign-in wall until there is a session, then Home.
@Reducer
struct AppFeature {
    /// An enum rather than two always-present children, so signing out
    /// *destroys* `HomeFeature.State` -- the previous user's library must not
    /// linger in memory behind the wall.
    ///
    /// `@CasePathable` is written explicitly: `@ObservableState` does not add
    /// it, and `ifCaseLet` requires `State: CasePathable`.
    @ObservableState
    @CasePathable
    enum State: Equatable {
        case signIn(SignInFeature.State)
        case home(HomeFeature.State)

        /// Starts on the wall in its restoring state rather than a separate
        /// `.launching` case: `@ObservableState`'s enum expansion hands a
        /// payload-less case a fresh identity on every read, which churns
        /// observation, and this avoids a flash of the sign-in button before
        /// the Keychain read finishes.
        init() { self = .signIn(SignInFeature.State(isRestoring: true)) }
    }

    enum Action {
        case onAppear
        case restored(UserProfile?)
        case sessionInvalidated
        case signOutRequested
        case signIn(SignInFeature.Action)
        case home(HomeFeature.Action)
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.audioPlayer) var audioPlayer

    private enum CancelID { case invalidation }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
                    .run { send in
                        await send(.restored(await authClient.restore()))
                    },
                    .run { send in
                        for await _ in authClient.sessionInvalidated() {
                            await send(.sessionInvalidated)
                        }
                    }
                    .cancellable(id: CancelID.invalidation, cancelInFlight: true)
                )

            case let .restored(profile):
                state = profile == nil
                    ? .signIn(SignInFeature.State())
                    : .home(HomeFeature.State(title: "Miya"))
                return .none

            case .signIn(.delegate(.signedIn)):
                state = .home(HomeFeature.State(title: "Miya"))
                return .none

            case .sessionInvalidated:
                guard case .home = state else { return .none }
                state = .signIn(SignInFeature.State())
                return stopAudio()

            case .signOutRequested:
                state = .signIn(SignInFeature.State())
                return .merge(
                    stopAudio(),
                    .run { _ in await authClient.signOut() }
                )

            case .home(.delegate(.signOutRequested)):
                return .send(.signOutRequested)

            case .signIn, .home:
                return .none
            }
        }
        .ifCaseLet(\.signIn, action: \.signIn) { SignInFeature() }
        .ifCaseLet(\.home, action: \.home) { HomeFeature() }
    }

    /// `ifCaseLet` cancels the departing child's effects, but the audio engine
    /// is a separate `@MainActor` singleton -- cancelling `SongPreviewFeature`'s
    /// subscription does not stop playback. Without this, music keeps playing
    /// over the sign-in screen, complete with a live lock-screen entry.
    private func stopAudio() -> Effect<Action> {
        .run { _ in await audioPlayer.stop() }
    }
}

struct AppView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Group {
            if let signIn = store.scope(state: \.signIn, action: \.signIn) {
                SignInView(store: signIn)
            } else if let home = store.scope(state: \.home, action: \.home) {
                HomeView(store: home)
            }
        }
        // On the outer Group so it doesn't re-fire when the case flips.
        .task { store.send(.onAppear) }
    }
}

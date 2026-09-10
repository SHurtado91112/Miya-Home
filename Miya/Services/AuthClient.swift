//
//  AuthClient.swift
//  Miya
//

import ComposableArchitecture
import Foundation

/// The only auth seam reducers and `HomeClient` touch.
///
/// Note every method deals in `UserProfile`, never `Session`: tokens must not
/// cross into reducer state or actions, where TCA's logging would print them.
@DependencyClient
struct AuthClient: Sendable {
    /// Runs the Google consent flow and establishes a session.
    var signInWithGoogle: @Sendable () async throws -> UserProfile
    /// The persisted session at launch, revalidated against the server.
    /// `nil` when signed out.
    var restore: @Sendable () async -> UserProfile?
    /// Bearer token for the next request, refreshed if needed. `nil` in
    /// fixture mode, where there is no server to authenticate to.
    var accessToken: @Sendable () async throws -> String?
    /// Called after a 401 so the next request refreshes rather than resending
    /// a token the server just rejected.
    var invalidateAccessToken: @Sendable () async -> Void
    /// Revokes server-side where possible, then clears local state.
    var signOut: @Sendable () async -> Void
    /// Fires when the session dies outside a user action, so the root feature
    /// can drop back to the sign-in wall.
    var sessionInvalidated: @Sendable () -> AsyncStream<Void> = { .never }
}

extension AuthClient: DependencyKey {
    static let liveValue: AuthClient = {
        // In fixture mode there is no server; every method degrades to a no-op
        // so the rest of the app can run against bundled JSON.
        guard let serverURL = RunMode.serverURL else {
            return .fixture
        }

        let store = SessionStore(
            keychain: .liveValue,
            api: MiyaAuthAPI(baseURL: serverURL),
            oauth: GoogleOAuthPresenter()
        )

        return AuthClient(
            signInWithGoogle: {
                guard let clientID = RunMode.googleClientID,
                      let redirectURI = RunMode.googleRedirectURI
                else { throw AuthError.notConfigured }
                return try await store.signIn(clientID: clientID, redirectURI: redirectURI)
            },
            restore: { await store.restore() },
            accessToken: { try await store.validAccessToken() },
            invalidateAccessToken: { await store.invalidateAccessToken() },
            signOut: { await store.signOut() },
            sessionInvalidated: {
                AsyncStream { continuation in
                    let task = Task {
                        for await _ in await store.invalidationEvents() {
                            continuation.yield(())
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )
    }()

    /// Always signed in as a stand-in user, with no tokens. Used by previews
    /// and by `RunMode.isFixtureMode` launches.
    static let fixture = AuthClient(
        signInWithGoogle: { .fixture },
        restore: { .fixture },
        accessToken: { nil },
        invalidateAccessToken: {},
        signOut: {},
        sessionInvalidated: { .never }
    )

    static var previewValue: AuthClient { .fixture }
}

extension UserProfile {
    static let fixture = UserProfile(
        id: "fixture-user",
        email: "listener@miya.app",
        displayName: "Miya Listener",
        avatarURL: nil
    )
}

extension DependencyValues {
    var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}

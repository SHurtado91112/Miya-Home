//
//  SessionStore.swift
//  Miya
//

import Foundation

/// Owns the signed-in session: the in-memory copy, its Keychain backing, and
/// the refresh lifecycle.
///
/// An `actor`, and an *instance* rather than a `static shared` -- unlike
/// `AudioPlayerEngine`, which wraps genuinely process-global `AVPlayer` /
/// `MPNowPlayingInfoCenter` state, nothing here is global. `AuthClient.liveValue`
/// constructs one and closes over it, so the seam stays `@Dependency` and tests
/// can substitute the whole client.
actor SessionStore {
    private let keychain: KeychainClient
    private let api: MiyaAuthAPI
    private let oauth: GoogleOAuthPresenter

    private var session: Session?
    /// The in-flight refresh, if any, together with the token it presented.
    private var refreshTask: Task<Session, Error>?
    private var refreshingToken: String?

    /// Bumped if the stored shape ever changes, so an old blob is ignored
    /// rather than mis-decoded.
    private static let account = "session.v1"

    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    init(keychain: KeychainClient, api: MiyaAuthAPI, oauth: GoogleOAuthPresenter) {
        self.keychain = keychain
        self.api = api
        self.oauth = oauth
    }

    // MARK: - Sign in

    func signIn(clientID: String, redirectURI: String) async throws -> UserProfile {
        let authorization = try await oauth.authorize(clientID: clientID, redirectURI: redirectURI)
        let session = try await api.signInWithGoogle(
            code: authorization.code,
            codeVerifier: authorization.codeVerifier,
            redirectURI: authorization.redirectURI,
            nonce: authorization.nonce
        )
        persist(session)
        return session.user
    }

    // MARK: - Restore

    /// Reads the Keychain and confirms the token still works. Returns `nil`
    /// only when there is genuinely no usable session -- a network failure
    /// leaves the stored session in place and reports the cached profile, so
    /// launching out of Wi-Fi range doesn't sign the user out.
    func restore() async -> UserProfile? {
        guard let stored = loadFromKeychain() else { return nil }
        session = stored

        do {
            let token = try await validAccessToken()
            guard let token else { return nil }
            if let profile = try await api.viewer(accessToken: token) {
                session?.user = profile
                if let session { persist(session) }
                return profile
            }
            // The server doesn't recognise the token any more.
            clear()
            return nil
        } catch AuthError.sessionExpired {
            clear()
            return nil
        } catch {
            // Offline: keep what we have and let the user in on cached identity.
            return stored.user
        }
    }

    // MARK: - Tokens

    /// A usable bearer token, refreshing first if the current one is spent.
    func validAccessToken() async throws -> String? {
        guard let current = session else { return nil }
        if current.isFresh() { return current.accessToken }
        return try await refresh(presenting: current.refreshToken).accessToken
    }

    /// Marks the access token spent after the server rejected it, so the next
    /// caller refreshes instead of re-sending a token known to be bad.
    func invalidateAccessToken() {
        session?.accessTokenExpiresAt = .distantPast
    }

    /// Single-flight refresh.
    ///
    /// Home issues `loadSections` and `loadAlbums` concurrently on appear, so
    /// two callers routinely find the same expired token at the same instant.
    /// Refresh tokens are single-use and rotated server-side, so letting both
    /// redeem would spend the token twice -- the loser's request would be
    /// treated as a replay and revoke every session for that user. Callers
    /// therefore join the existing task rather than starting a second.
    private func refresh(presenting staleToken: String) async throws -> Session {
        if let refreshTask, refreshingToken == staleToken {
            return try await refreshTask.value
        }
        // Someone already rotated past this token while we were waiting; use
        // whatever the store holds now rather than redeeming a spent token.
        if refreshingToken != nil, refreshingToken != staleToken, let current = session,
           current.isFresh() {
            return current
        }

        let task = Task<Session, Error> { [api] in
            do {
                return try await api.refreshSession(refreshToken: staleToken)
            } catch let error as AuthError {
                // Only an outright refusal ends the session. A transport
                // failure means "try again later", not "sign out".
                if case .transport = error { throw error }
                throw AuthError.sessionExpired
            }
        }
        refreshTask = task
        refreshingToken = staleToken

        defer {
            refreshTask = nil
            refreshingToken = nil
        }

        do {
            let refreshed = try await task.value
            persist(refreshed)
            return refreshed
        } catch {
            if case AuthError.sessionExpired = error {
                clear()
                notifyInvalidated()
            }
            throw error
        }
    }

    // MARK: - Sign out

    func signOut() async {
        if let refreshToken = session?.refreshToken {
            // Best effort: local sign-out must succeed even if the server is
            // unreachable, otherwise the user is stuck signed in.
            try? await api.signOut(refreshToken: refreshToken)
        }
        clear()
    }

    // MARK: - Invalidation stream

    func invalidationEvents() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func notifyInvalidated() {
        for continuation in continuations.values { continuation.yield(()) }
    }

    // MARK: - Persistence

    private func persist(_ session: Session) {
        self.session = session
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? keychain.save(data, Self.account)
    }

    private func loadFromKeychain() -> Session? {
        // `try?` already flattens the client's `Data?` return, so one bind.
        guard let data = try? keychain.load(Self.account) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private func clear() {
        session = nil
        refreshTask = nil
        refreshingToken = nil
        try? keychain.delete(Self.account)
    }
}

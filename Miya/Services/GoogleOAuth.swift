//
//  GoogleOAuth.swift
//  Miya
//

import AuthenticationServices
import Foundation
import UIKit

/// Drives Google's consent screen in a system browser sheet and hands back the
/// authorization code.
///
/// `ASWebAuthenticationSession` rather than an embedded `WKWebView`: the sheet
/// is out of the app's process, so Miya cannot read the password being typed,
/// and it shares Safari's cookie jar, so someone already signed in to Google
/// gets a one-tap approval instead of a fresh login.
///
/// Every method is `async` even where nothing suspends. Swift 5 language mode
/// does not diagnose a synchronous call to a `@MainActor` member from a
/// nonisolated async context, so without a suspension point this UIKit work
/// would quietly run off the main thread -- the same trap documented for
/// `AudioPlayerEngine`.
@MainActor
final class GoogleOAuthPresenter {
    struct Authorization: Sendable {
        let code: String
        let codeVerifier: String
        let redirectURI: String
        let nonce: String
    }

    /// Held strongly: `ASWebAuthenticationSession` deallocates -- taking its
    /// sheet with it -- the moment the last reference drops.
    private var session: ASWebAuthenticationSession?
    /// Also held strongly: `presentationContextProvider` is a `weak` property,
    /// so a freshly constructed provider would be gone before it is asked for
    /// an anchor, failing with `.presentationContextNotProvided`.
    private var anchorProvider: AnchorProvider?

    /// `nonisolated` so `AuthClient.liveValue` can build one while setting up
    /// its dependency graph off the main actor. Both stored properties are
    /// assigned later, inside `present`, which is main-actor isolated.
    nonisolated init() {}

    func authorize(clientID: String, redirectURI: String) async throws -> Authorization {
        let pkce = PKCE.Challenge()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "nonce", value: pkce.nonce),
        ]
        guard let authorizationURL = components.url,
              let scheme = redirectURI.split(separator: ":").first.map(String.init)
        else {
            throw AuthError.notConfigured
        }

        let callbackURL = try await present(url: authorizationURL, scheme: scheme)

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        if let error = value("error") {
            throw error == "access_denied" ? AuthError.canceled : AuthError.server(error)
        }
        // Compare before using the code: a mismatched state means this response
        // belongs to some other authorization request.
        guard value("state") == pkce.state else {
            throw AuthError.server("Sign-in response didn't match the request.")
        }
        guard let code = value("code") else {
            throw AuthError.server("Google didn't return an authorization code.")
        }

        return Authorization(
            code: code,
            codeVerifier: pkce.verifier,
            redirectURI: redirectURI,
            nonce: pkce.nonce
        )
    }

    private func present(url: URL, scheme: String) async throws -> URL {
        // The continuation must resume exactly once. `start()` returning false
        // and the completion handler are separate paths to failure, so guard
        // them both; MainActor isolation makes the flag safe.
        var hasResumed = false

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(scheme)
            ) { callbackURL, error in
                guard !hasResumed else { return }
                hasResumed = true

                if let error {
                    let code = (error as? ASWebAuthenticationSessionError)?.code
                    continuation.resume(
                        throwing: code == .canceledLogin
                            ? AuthError.canceled
                            : AuthError.server(error.localizedDescription)
                    )
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.server("Sign-in ended unexpectedly."))
                }
            }

            let provider = AnchorProvider()
            self.anchorProvider = provider
            session.presentationContextProvider = provider
            // Left false so the sheet sees the user's existing Google cookies.
            // True would force a full password + 2FA on every single sign-in.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            if !session.start() {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(throwing: AuthError.server("Couldn't open the sign-in page."))
            }
        }
    }

    /// `ASWebAuthenticationPresentationContextProviding` is `NS_SWIFT_UI_ACTOR`
    /// in the SDK, hence `@MainActor`.
    @MainActor
    private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            // Must be a real, foreground-active window: a bare
            // ASPresentationAnchor() fails with .presentationContextInvalid.
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .keyWindow
            return window ?? ASPresentationAnchor()
        }
    }
}

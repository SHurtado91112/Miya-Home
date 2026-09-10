//
//  Session.swift
//  Miya
//

import CustomDump
import Foundation

/// The non-secret half of a signed-in identity. This is the only part that may
/// travel through TCA state and actions.
struct UserProfile: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var email: String
    var displayName: String?
    var avatarURL: URL?

    var initials: String {
        let source = displayName?.isEmpty == false ? displayName! : email
        return source.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init)
            .joined().uppercased()
    }
}

/// Credentials. Lives in the Keychain and inside `SessionStore`, and nowhere
/// else -- never in reducer state, never in an `Action`.
struct Session: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var accessTokenExpiresAt: Date
    var user: UserProfile

    /// Treat a token as spent slightly before it truly expires, so one that
    /// dies in flight doesn't produce an avoidable 401. The device clock is
    /// user-settable, so this is an optimisation -- the reactive 401 path is
    /// what actually guarantees correctness.
    func isFresh(now: Date = Date(), skew: TimeInterval = 60) -> Bool {
        accessTokenExpiresAt.timeIntervalSince(now) > skew
    }
}

/// TCA prints actions and state through CustomDump (`_printChanges`, `TestStore`
/// diffs, `reportIssue`). Without this a `Session` reaching any of those would
/// spill both tokens into the Xcode console and into CI logs.
extension Session: CustomDumpStringConvertible {
    var customDumpDescription: String {
        "Session(user: \(user.email), expires: \(accessTokenExpiresAt), tokens: <redacted>)"
    }
}

enum AuthError: Error, Equatable, LocalizedError {
    /// The user dismissed the Google sheet. Not a failure -- never alert.
    case canceled
    /// The session is genuinely dead; sign out.
    case sessionExpired
    /// No client id in Info.plist, or no server configured.
    case notConfigured
    /// The server refused, with a message safe to show.
    case server(String)
    /// The network is unreachable. Keep the session and let the user retry.
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .canceled:
            return nil
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .notConfigured:
            return "Miya isn't configured for sign-in yet. Check MiyaGoogleClientID and MIYA_SERVER_URL."
        case let .server(message):
            return message
        case let .transport(message):
            return "Couldn't reach Miya. \(message)"
        }
    }
}

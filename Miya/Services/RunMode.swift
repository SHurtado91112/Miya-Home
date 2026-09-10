//
//  RunMode.swift
//  Miya
//

import Foundation

/// How this launch is configured to reach its data.
///
/// `MIYA_SERVER_URL` is set only in the Debug scheme's `LaunchAction`, so it is
/// absent from Release builds, TestFlight, the App Store, *and* anything started
/// with `xcrun simctl launch` (pass it as `SIMCTL_CHILD_MIYA_SERVER_URL` there).
enum RunMode {
    /// Base URL of the MiyaServer to talk to, when one is configured.
    static var serverURL: URL? {
        ProcessInfo.processInfo.environment["MIYA_SERVER_URL"].flatMap(URL.init)
    }

    /// No server ⇒ run against the bundled JSON fixtures, and skip the sign-in
    /// wall so the app is still explorable.
    ///
    /// Compiled out of Release on purpose. `serverURL` is nil in *every* shipped
    /// configuration, so a runtime-only check would read "no server configured"
    /// as "no authentication required" and hand every App Store user an
    /// unauthenticated app. A Release build without a server is broken, not
    /// public.
    #if DEBUG
        static var isFixtureMode: Bool { serverURL == nil }
    #else
        static let isFixtureMode = false
    #endif

    /// The Google OAuth *iOS* client id, from `Info.plist`. Public, not a
    /// secret -- an iOS OAuth client has no client secret at all.
    static var googleClientID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "MiyaGoogleClientID") as? String
        guard let value, !value.isEmpty, !value.hasPrefix("REPLACE_WITH_") else { return nil }
        return value
    }

    /// Google's convention for an iOS client: the client id with its
    /// dot-separated components reversed, used as the redirect URL scheme.
    static var googleRedirectScheme: String? {
        googleClientID.map { $0.split(separator: ".").reversed().joined(separator: ".") }
    }

    static var googleRedirectURI: String? {
        googleRedirectScheme.map { "\($0):/oauth2redirect" }
    }
}

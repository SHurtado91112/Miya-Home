//
//  PKCE.swift
//  Miya
//

import CryptoKit
import Foundation
import Security

/// Proof Key for Code Exchange (RFC 7636) plus the two OpenID nonces the
/// authorization request needs.
///
/// PKCE is what makes a browser-based OAuth flow safe for an app that cannot
/// keep a secret: the app sends a hash of a random verifier up front, then
/// proves ownership by revealing the verifier when redeeming the code. Another
/// app that intercepts the redirect gets a code it cannot spend.
enum PKCE {
    /// One authorization attempt's worth of random values.
    struct Challenge: Sendable {
        /// Held on device, sent only when redeeming the code.
        let verifier: String
        /// Sent in the authorization URL: base64url(SHA256(verifier)).
        let challenge: String
        /// Echoed back on the redirect; guards against a response being
        /// swapped in from a different request.
        let state: String
        /// Embedded in the issued id_token by Google, verified server-side to
        /// bind that token to this exact request.
        let nonce: String

        init() {
            verifier = PKCE.randomURLSafeString()
            challenge = PKCE.s256(verifier)
            state = PKCE.randomURLSafeString()
            nonce = PKCE.randomURLSafeString()
        }
    }

    /// 32 bytes of CSPRNG output, base64url-encoded to 43 characters -- the
    /// low end of RFC 7636's 43...128 range for a code verifier.
    static func randomURLSafeString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            // SecRandomCopyBytes only fails if the system CSPRNG is unavailable.
            // Continuing with predictable values would silently void PKCE, so
            // stop instead.
            fatalError("SecRandomCopyBytes failed with status \(status)")
        }
        return Data(bytes).base64URLEncodedString()
    }

    static func s256(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

extension Data {
    /// base64url (RFC 4648 §5): standard base64 with `+`/`/` swapped for
    /// `-`/`_` and the `=` padding stripped, so the value is safe in a URL.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

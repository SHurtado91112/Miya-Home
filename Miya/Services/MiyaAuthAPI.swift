//
//  MiyaAuthAPI.swift
//  Miya
//

import Foundation

/// The three auth mutations plus `viewer`, spoken directly to `/graphql`.
///
/// Deliberately separate from `MiyaGraphQLClient`: these calls must never carry
/// a bearer token, must never be retried through the 401-refresh path (the
/// refresh *is* this), and must keep working while a refresh is in flight.
/// Folding them into the data client would make all three impossible.
struct MiyaAuthAPI: Sendable {
    let baseURL: URL

    private struct Request<V: Encodable>: Encodable {
        let query: String
        let variables: V
    }

    private struct Response<T: Decodable>: Decodable {
        let data: T?
        let errors: [GraphQLErrorDTO]?
    }

    private struct AuthPayloadDTO: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let user: UserDTO
    }

    private struct UserDTO: Decodable {
        let id: String
        let email: String
        let name: String?
        let avatarUrl: String?

        var profile: UserProfile {
            UserProfile(
                id: id,
                email: email,
                displayName: name,
                avatarURL: avatarUrl.flatMap(URL.init(string:))
            )
        }
    }

    private struct SignInData: Decodable { let signInWithGoogle: AuthPayloadDTO }
    private struct RefreshData: Decodable { let refreshSession: AuthPayloadDTO }
    private struct SignOutData: Decodable { let signOut: Bool }
    private struct ViewerData: Decodable { let viewer: UserDTO? }
    private struct Empty: Encodable {}

    // MARK: - Operations

    func signInWithGoogle(
        code: String, codeVerifier: String, redirectURI: String, nonce: String
    ) async throws -> Session {
        struct Variables: Encodable {
            let code: String
            let codeVerifier: String
            let redirectUri: String
            let nonce: String
        }
        let data: SignInData = try await execute(
            """
            mutation SignInWithGoogle(
              $code: String!, $codeVerifier: String!, $redirectUri: String!, $nonce: String!
            ) {
              signInWithGoogle(
                code: $code, codeVerifier: $codeVerifier,
                redirectUri: $redirectUri, nonce: $nonce
              ) { accessToken refreshToken expiresAt user { id email name avatarUrl } }
            }
            """,
            variables: Variables(
                code: code, codeVerifier: codeVerifier, redirectUri: redirectURI, nonce: nonce
            )
        )
        return session(from: data.signInWithGoogle)
    }

    func refreshSession(refreshToken: String) async throws -> Session {
        struct Variables: Encodable { let refreshToken: String }
        let data: RefreshData = try await execute(
            """
            mutation RefreshSession($refreshToken: String!) {
              refreshSession(refreshToken: $refreshToken) {
                accessToken refreshToken expiresAt user { id email name avatarUrl }
              }
            }
            """,
            variables: Variables(refreshToken: refreshToken)
        )
        return session(from: data.refreshSession)
    }

    func signOut(refreshToken: String) async throws {
        struct Variables: Encodable { let refreshToken: String }
        let _: SignOutData = try await execute(
            "mutation SignOut($refreshToken: String!) { signOut(refreshToken: $refreshToken) }",
            variables: Variables(refreshToken: refreshToken)
        )
    }

    /// Confirms a restored access token is still accepted, and refreshes the
    /// cached profile. `nil` means the token is no longer good.
    func viewer(accessToken: String) async throws -> UserProfile? {
        let data: ViewerData = try await execute(
            "query Viewer { viewer { id email name avatarUrl } }",
            variables: Empty(),
            accessToken: accessToken
        )
        return data.viewer?.profile
    }

    // MARK: - Transport

    private func session(from payload: AuthPayloadDTO) -> Session {
        Session(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            accessTokenExpiresAt: payload.expiresAt,
            user: payload.user.profile
        )
    }

    private func execute<V: Encodable, T: Decodable>(
        _ query: String, variables: V, accessToken: String? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent("graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(Request(query: query, variables: variables))

        let responseData: Data
        do {
            (responseData, _) = try await URLSession.shared.data(for: request)
        } catch {
            // A dropped connection must not be mistaken for a rejected
            // credential -- one is worth retrying, the other means sign out.
            throw AuthError.transport(error.localizedDescription)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds

        let decoded: Response<T>
        do {
            decoded = try decoder.decode(Response<T>.self, from: responseData)
        } catch {
            throw AuthError.server("Unexpected response from Miya.")
        }

        if let errors = decoded.errors, !errors.isEmpty {
            throw AuthError.server(errors.map(\.message).joined(separator: "\n"))
        }
        guard let data = decoded.data else {
            throw AuthError.server("Miya returned no data.")
        }
        return data
    }
}

extension JSONDecoder.DateDecodingStrategy {
    /// Strawberry emits ISO-8601 with fractional seconds; `.iso8601` alone
    /// rejects those, so try both.
    static let iso8601WithFractionalSeconds = custom { decoder in
        let text = try decoder.singleValueContainer().decode(String.self)
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }

        throw DecodingError.dataCorruptedError(
            in: try decoder.singleValueContainer(),
            debugDescription: "Not an ISO-8601 date: \(text)"
        )
    }
}

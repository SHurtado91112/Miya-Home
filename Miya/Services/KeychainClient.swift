//
//  KeychainClient.swift
//  Miya
//

import ComposableArchitecture
import Foundation
import Security

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

/// Minimal Keychain access for the one thing Miya persists: the signed-in
/// session. Deliberately untyped -- callers encode their own JSON -- so this
/// stays a thin, testable wrapper over `SecItem*`.
@DependencyClient
struct KeychainClient: Sendable {
    var load: @Sendable (_ account: String) throws -> Data?
    var save: @Sendable (_ data: Data, _ account: String) throws -> Void
    var delete: @Sendable (_ account: String) throws -> Void
}

extension KeychainClient: DependencyKey {
    private static let service = Bundle.main.bundleIdentifier ?? "com.hurtado.Miya"

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static let liveValue = KeychainClient(
        load: { account in
            var query = Self.query(account: account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            switch status {
            case errSecSuccess: return item as? Data
            case errSecItemNotFound: return nil
            default: throw KeychainError.unexpectedStatus(status)
            }
        },
        save: { data, account in
            // Delete-then-add rather than update: `SecItemUpdate` needs a
            // different query shape depending on whether the item exists, and
            // this is one item written rarely.
            SecItemDelete(Self.query(account: account) as CFDictionary)

            var attributes = Self.query(account: account)
            attributes[kSecValueData as String] = data
            // The background audio session can outlive a reboot, so the token
            // has to be readable without an unlock *after* the first one.
            // `ThisDeviceOnly` keeps it out of iCloud Keychain and encrypted
            // backups, so a restored backup can't resurrect someone's session
            // on another device.
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }
        },
        delete: { account in
            let status = SecItemDelete(Self.query(account: account) as CFDictionary)
            // Deleting something that was never there is the outcome we wanted.
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    )

    /// In-memory: previews and tests never touch the real Keychain (which on
    /// the Simulator is shared across every app and survives reinstalls).
    static let previewValue: KeychainClient = {
        let storage = LockIsolated<[String: Data]>([:])
        return KeychainClient(
            load: { account in storage.value[account] },
            save: { data, account in storage.withValue { $0[account] = data } },
            delete: { account in storage.withValue { $0[account] = nil } }
        )
    }()

    static var testValue: KeychainClient { previewValue }
}

extension DependencyValues {
    var keychain: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }
}

import Foundation
import Security

/// Read/write access to a generic password item in the user's Keychain.
/// Abstracted behind a protocol so unit tests can inject an in-memory
/// implementation without touching the user's real Keychain.
protocol AgentKeychainStorage: Sendable {
    func read(service: String, account: String) throws -> String?
    func write(_ value: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

enum AgentKeychainError: LocalizedError, Equatable {
    case osStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .osStatus(status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return "Keychain error (\(status))\(message.map { ": \($0)" } ?? "")"
        case .invalidData:
            return "Keychain item was not valid UTF-8"
        }
    }
}

/// Production AgentKeychainStorage backed by the system Security.framework.
///
/// Tries the modern "data protection" keychain
/// (`kSecUseDataProtectionKeychain = true`) first. The legacy macOS
/// `login.keychain-db` ties each item's ACL to the exact cdhash of the
/// app that created it — every rebuild produces a fresh cdhash, so users
/// were re-prompted for keychain access on every launch. The data
/// protection keychain scopes items by access group (default
/// `<team>.<bundle>` for a properly-signed app), which stays stable
/// across rebuilds.
///
/// DPK on macOS requires the `keychain-access-groups` entitlement. When
/// that's missing — or the binary is ad-hoc signed and DPK refuses the
/// item — we transparently fall back to the legacy keychain so users
/// can still save their key. The fallback path resurrects the original
/// "prompt on every cdhash change" pain, but it never blocks a save.
///
/// `read` checks DPK first, then legacy. If a legacy entry exists and
/// DPK is writable, we migrate it across and delete the legacy copy.
/// If DPK isn't writable, we leave the legacy entry alone — losing the
/// only working copy of the key would be worse than the extra prompt.
struct AgentKeychain: AgentKeychainStorage {
    func read(service: String, account: String) throws -> String? {
        if let value = try? readDataProtection(service: service, account: account) {
            return value
        }
        guard let legacy = try readLegacy(service: service, account: account) else {
            return nil
        }
        // Best-effort migration: only retire the legacy entry once we've
        // confirmed DPK accepted the value. If DPK is unavailable we keep
        // the legacy copy so the user isn't stranded.
        if (try? writeDataProtection(legacy, service: service, account: account)) != nil {
            try? deleteLegacy(service: service, account: account)
        }
        return legacy
    }

    func write(_ value: String, service: String, account: String) throws {
        do {
            try writeDataProtection(value, service: service, account: account)
            // DPK now owns the value; clear any legacy entry so the next
            // read doesn't shadow a freshly-set value with a stale one.
            try? deleteLegacy(service: service, account: account)
        } catch {
            // DPK refused — likely missing `keychain-access-groups`
            // entitlement or an ad-hoc binary. Fall through to the
            // legacy keychain so the user can still save the key.
            try writeLegacy(value, service: service, account: account)
        }
    }

    func delete(service: String, account: String) throws {
        var lastError: OSStatus?
        let dpStatus = deleteDataProtection(service: service, account: account)
        if dpStatus != errSecSuccess && dpStatus != errSecItemNotFound {
            lastError = dpStatus
        }
        let legacyStatus = deleteLegacyStatus(service: service, account: account)
        if legacyStatus != errSecSuccess && legacyStatus != errSecItemNotFound {
            lastError = legacyStatus
        }
        if let lastError {
            throw AgentKeychainError.osStatus(lastError)
        }
    }

    // MARK: - Data protection keychain

    private func readDataProtection(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AgentKeychainError.osStatus(status) }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw AgentKeychainError.invalidData
        }
        return value
    }

    private func writeDataProtection(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AgentKeychainError.osStatus(addStatus)
            }
            return
        }
        throw AgentKeychainError.osStatus(updateStatus)
    }

    private func deleteDataProtection(service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        return SecItemDelete(query as CFDictionary)
    }

    // MARK: - Legacy keychain (one-time migration source)

    private func readLegacy(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        // Legacy ACL prompts can fail with `errSecAuthFailed` /
        // `errSecInteractionNotAllowed` if the user dismisses. Swallow
        // them as "no legacy value" so the caller falls through to env
        // var / empty.
        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func writeLegacy(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AgentKeychainError.osStatus(addStatus)
            }
            return
        }
        throw AgentKeychainError.osStatus(updateStatus)
    }

    private func deleteLegacy(service: String, account: String) throws {
        let status = deleteLegacyStatus(service: service, account: account)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw AgentKeychainError.osStatus(status)
    }

    private func deleteLegacyStatus(service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary)
    }
}

/// In-memory AgentKeychainStorage for tests. Thread-safe via NSLock.
final class InMemoryAgentKeychain: AgentKeychainStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    private func key(service: String, account: String) -> String {
        "\(service)\u{1F}\(account)"
    }

    func read(service: String, account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key(service: service, account: account)]
    }

    func write(_ value: String, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key(service: service, account: account)] = value
    }

    func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key(service: service, account: account))
    }
}

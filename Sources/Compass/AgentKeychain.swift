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
/// Stores items as `kSecClassGenericPassword`.
struct AgentKeychain: AgentKeychainStorage {
    func read(service: String, account: String) throws -> String? {
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
        guard status == errSecSuccess else { throw AgentKeychainError.osStatus(status) }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw AgentKeychainError.invalidData
        }
        return value
    }

    func write(_ value: String, service: String, account: String) throws {
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

    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw AgentKeychainError.osStatus(status)
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

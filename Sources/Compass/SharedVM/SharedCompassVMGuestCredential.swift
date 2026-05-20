import Foundation
import Security

/// Compass-generated guest account credential for the Shared VM.
///
/// The headless first-boot pipeline plants a `compass` admin user inside
/// the freshly-installed guest. macOS's `sysadminctl -addUser` requires a
/// password at creation time, so Compass generates a random one host-side
/// and stores it in the host's macOS Keychain. From there, Compass:
///
///   * Writes the password byte-for-byte into a root:wheel 0600 staging
///     file the bootstrap script reads (and then deletes) on first boot.
///   * Surfaces it on demand to the user via the Sandbox UI (if they ever
///     need to interactively log into the guest console).
///   * Deletes it when `resetInstalledArtifacts` wipes the bundle, so a
///     re-install gets a fresh credential instead of inheriting the old one.
///
/// Keychain access is mediated through `Storage` so tests can swap in an
/// in-memory backend without prompting for the user's login password.
enum SharedCompassVMGuestCredential {
    /// Keychain service name. Shared across every bundle Compass might own
    /// (currently there is only one Shared VM bundle per host); the
    /// `account` field disambiguates within the service.
    static let keychainService = "com.seancheatham.Compass.SharedVM"

    /// Length (in characters) of the randomly-generated password. 32 chars
    /// from a 62-symbol alphabet yields ~190 bits of entropy, comfortably
    /// above any threat model we have for a sandboxed guest credential.
    static let defaultPasswordLength = 32

    /// Alphabet used when generating new passwords. Restricted to
    /// alphanumerics so the value can be safely embedded in shell strings,
    /// command-line arguments, and plist values without escaping.
    static let passwordAlphabet: [Character] = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    )

    // MARK: - Value types

    struct Credential: Equatable {
        var account: String
        var password: String
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case keychainFailure(operation: String, status: OSStatus)
        case missingPassword
        case randomBytesFailed(status: Int32)

        var description: String {
            switch self {
            case let .keychainFailure(operation, status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
                return "Keychain \(operation) failed: \(message)"
            case .missingPassword:
                return "Keychain entry exists but its password payload could not be decoded as UTF-8."
            case let .randomBytesFailed(status):
                return "Could not generate random bytes (SecRandomCopyBytes status \(status))."
            }
        }
    }

    // MARK: - Storage abstraction

    /// Generic-password Keychain backend, narrowed to the three operations
    /// Compass uses. Lets unit tests substitute an in-memory dictionary.
    protocol Storage {
        func store(password: String, account: String) throws
        func retrieve(account: String) throws -> String?
        func delete(account: String) throws
    }

    /// Live backend that delegates to `SecItemAdd` / `SecItemCopyMatching` /
    /// `SecItemDelete`. Each call surfaces only known-good `errSecSuccess`
    /// (and `errSecItemNotFound` from fetch/delete) as non-failures.
    struct KeychainStorage: Storage {
        let service: String

        init(service: String = SharedCompassVMGuestCredential.keychainService) {
            self.service = service
        }

        func store(password: String, account: String) throws {
            let data = Data(password.utf8)
            // Try update-in-place first so a re-issue doesn't trip
            // errSecDuplicateItem from a previous run we forgot about.
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let updateAttributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            switch updateStatus {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                break
            default:
                throw Error.keychainFailure(operation: "update", status: updateStatus)
            }

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                // Only the Compass app should pull this; require the keychain
                // be unlocked at retrieval time.
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw Error.keychainFailure(operation: "add", status: addStatus)
            }
        }

        func retrieve(account: String) throws -> String? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
                    throw Error.missingPassword
                }
                return password
            case errSecItemNotFound:
                return nil
            default:
                throw Error.keychainFailure(operation: "retrieve", status: status)
            }
        }

        func delete(account: String) throws {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let status = SecItemDelete(query as CFDictionary)
            switch status {
            case errSecSuccess, errSecItemNotFound:
                return
            default:
                throw Error.keychainFailure(operation: "delete", status: status)
            }
        }
    }

    // MARK: - High-level operations

    /// Returns the credential associated with `account`, generating + storing
    /// a fresh password if none exists yet. Subsequent calls with the same
    /// account return the same password — Compass treats the Keychain as the
    /// source of truth so the password is stable across host restarts.
    static func ensure(
        account: String,
        storage: Storage,
        passwordLength: Int = defaultPasswordLength
    ) throws -> Credential {
        if let existing = try storage.retrieve(account: account) {
            return Credential(account: account, password: existing)
        }
        let password = try generatePassword(length: passwordLength)
        try storage.store(password: password, account: account)
        return Credential(account: account, password: password)
    }

    /// Returns the credential for `account` if present, otherwise nil.
    /// Used by SandboxView when surfacing the password to the user for copy.
    static func retrieve(account: String, storage: Storage) throws -> Credential? {
        guard let password = try storage.retrieve(account: account) else {
            return nil
        }
        return Credential(account: account, password: password)
    }

    /// Removes the credential for `account`. Idempotent. Called by
    /// `SharedCompassVMBundle.resetInstalledArtifacts` so re-provisioning
    /// always issues a fresh password.
    static func remove(account: String, storage: Storage) throws {
        try storage.delete(account: account)
    }

    // MARK: - Account allocation

    /// Generates a fresh Keychain account string. Format:
    /// `guest.<uuid>` so the account survives a Compass reinstall (the UUID
    /// is persisted into the bundle's state.json) but cannot collide with
    /// any future Keychain entry Compass might add for an unrelated purpose.
    static func makeAccount() -> String {
        "guest." + UUID().uuidString.lowercased()
    }

    // MARK: - Password generation

    /// Generates a cryptographically random password drawn from
    /// `passwordAlphabet`. Throws if `SecRandomCopyBytes` fails (which
    /// indicates a system-level corepto problem; nothing for Compass to
    /// recover from).
    static func generatePassword(length: Int = defaultPasswordLength) throws -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = bytes.withUnsafeMutableBytes { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return errSecMemoryError }
            return SecRandomCopyBytes(kSecRandomDefault, length, baseAddress)
        }
        guard status == errSecSuccess else {
            throw Error.randomBytesFailed(status: status)
        }
        let alphabetCount = UInt8(passwordAlphabet.count)
        var output = ""
        output.reserveCapacity(length)
        for byte in bytes {
            output.append(passwordAlphabet[Int(byte % alphabetCount)])
        }
        return output
    }
}

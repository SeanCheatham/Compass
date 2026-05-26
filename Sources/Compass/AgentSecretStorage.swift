import Foundation

/// Read/write access to a small secret persisted somewhere outside the
/// app's defaults database. Abstracted behind a protocol so tests can
/// inject an in-memory implementation.
///
/// Compass uses this for the agent API key. The production implementation
/// stores the key as a 0600 file under `~/Library/Application Support/`
/// — much simpler than the macOS Keychain (no entitlements, no DPK quirks,
/// no `NSSecureTextField` paste-binding interactions) and adequately
/// secure for a single-user developer tool whose key is for the user's
/// own LLM endpoint. The user's home folder is already gated by macOS
/// user-account permissions.
protocol AgentSecretStorage: Sendable {
  func read(service: String, account: String) throws -> String?
  func write(_ value: String, service: String, account: String) throws
  func delete(service: String, account: String) throws
}

enum AgentSecretStorageError: LocalizedError, Equatable {
  case invalidIdentifier(String)
  case invalidData

  var errorDescription: String? {
    switch self {
    case .invalidIdentifier(let detail):
      return "Secret storage identifier was invalid: \(detail)"
    case .invalidData:
      return "Stored secret was not valid UTF-8"
    }
  }
}

/// File-backed `AgentSecretStorage` rooted at a directory the caller picks
/// (defaults to `~/Library/Application Support/Compass/secrets/`).
///
/// Each (service, account) pair maps to a single file at
/// `<root>/<service>/<account>`. Writes are atomic and tighten the file's
/// POSIX permissions to `0600` (owner read/write only) so other accounts
/// on the same machine can't read the secret. The parent directory is
/// created on demand and pinned to `0700`.
struct AgentFileSecretStorage: AgentSecretStorage {
  let root: URL
  /// `FileManager` is not `Sendable` because its underlying coordinate
  /// methods can race, but this struct is a concrete type — not a protocol
  /// existential — whose entire lifetime is scoped to a single caller's
  /// construction. The `fileManager` property is `private` and never escapes
  /// the instance, so the lack of `Sendability` is benign and intentional
  /// here, mirroring the pattern in `SharedCompassVMToolchainManager`.
  private let fileManager: FileManager

  init(root: URL = AgentFileSecretStorage.defaultRoot(), fileManager: FileManager = .default) {
    self.root = root.standardizedFileURL
    self.fileManager = fileManager
  }

  static func defaultRoot() -> URL {
    let base =
      FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first
      ?? URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/Application Support", isDirectory: true)
    return
      base
      .appendingPathComponent("Compass", isDirectory: true)
      .appendingPathComponent("secrets", isDirectory: true)
  }

  func read(service: String, account: String) throws -> String? {
    let url = try fileURL(service: service, account: account)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    guard let value = String(data: data, encoding: .utf8) else {
      throw AgentSecretStorageError.invalidData
    }
    // Trim trailing newlines that some editors append to files. Don't
    // trim leading/trailing spaces — keys legitimately use those.
    return value.trimmingCharacters(in: ["\n", "\r"])
  }

  func write(_ value: String, service: String, account: String) throws {
    let url = try fileURL(service: service, account: account)
    let parent = url.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: parent,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    // Re-tighten the parent in case it already existed with looser perms.
    try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
    let data = Data(value.utf8)
    try data.write(to: url, options: [.atomic])
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  func delete(service: String, account: String) throws {
    let url = try fileURL(service: service, account: account)
    guard fileManager.fileExists(atPath: url.path) else { return }
    try fileManager.removeItem(at: url)
  }

  private func fileURL(service: String, account: String) throws -> URL {
    let safeService = try sanitized(service, label: "service")
    let safeAccount = try sanitized(account, label: "account")
    return
      root
      .appendingPathComponent(safeService, isDirectory: true)
      .appendingPathComponent(safeAccount, isDirectory: false)
  }

  /// Reject identifiers that would escape the root (`/`, `..`) or carry
  /// shell-significant whitespace. Compass only passes constants here,
  /// but we guard anyway in case that ever changes.
  private func sanitized(_ raw: String, label: String) throws -> String {
    guard !raw.isEmpty else {
      throw AgentSecretStorageError.invalidIdentifier("\(label) is empty")
    }
    guard !raw.contains("/") && !raw.contains("\\") && raw != "." && raw != ".." else {
      throw AgentSecretStorageError.invalidIdentifier(
        "\(label) contains a path separator or relative segment"
      )
    }
    guard raw.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) })
    else {
      throw AgentSecretStorageError.invalidIdentifier(
        "\(label) contains whitespace"
      )
    }
    return raw
  }
}

/// In-memory `AgentSecretStorage` for tests. Thread-safe via `NSLock`.
final class InMemoryAgentSecretStorage: AgentSecretStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String: String] = [:]

  private func key(service: String, account: String) -> String {
    "\(service)\u{1F}\(account)"
  }

  func read(service: String, account: String) throws -> String? {
    lock.lock()
    defer { lock.unlock() }
    return storage[key(service: service, account: account)]
  }

  func write(_ value: String, service: String, account: String) throws {
    lock.lock()
    defer { lock.unlock() }
    storage[key(service: service, account: account)] = value
  }

  func delete(service: String, account: String) throws {
    lock.lock()
    defer { lock.unlock() }
    storage.removeValue(forKey: key(service: service, account: account))
  }
}

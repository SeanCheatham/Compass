import Foundation

/// Read/write access to a small secret persisted somewhere outside the
/// app's defaults database. Abstracted behind a protocol so tests can
/// inject an in-memory implementation.
///
/// Compass uses this for the agent API key. The production implementation
/// stores the key as a 0600 file under `~/Library/Application Support/`
/// — simpler than Keychain for a single-user developer tool.
public protocol AgentSecretStorage: Sendable {
  func read(service: String, account: String) throws -> String?
  func write(_ value: String, service: String, account: String) throws
  func delete(service: String, account: String) throws
}

public enum AgentSecretStorageError: LocalizedError, Equatable {
  case invalidIdentifier(String)
  case invalidData

  public var errorDescription: String? {
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
public struct AgentFileSecretStorage: AgentSecretStorage, @unchecked Sendable {
  public let root: URL
  private let fileManager: FileManager

  public init(root: URL = AgentFileSecretStorage.defaultRoot(), fileManager: FileManager = .default)
  {
    self.root = root.standardizedFileURL
    self.fileManager = fileManager
  }

  public static func defaultRoot() -> URL {
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

  public func read(service: String, account: String) throws -> String? {
    let url = try fileURL(service: service, account: account)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    guard let value = String(data: data, encoding: .utf8) else {
      throw AgentSecretStorageError.invalidData
    }
    return value.trimmingCharacters(in: ["\n", "\r"])
  }

  public func write(_ value: String, service: String, account: String) throws {
    let url = try fileURL(service: service, account: account)
    let parent = url.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: parent,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
    let data = Data(value.utf8)
    try data.write(to: url, options: [.atomic])
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  public func delete(service: String, account: String) throws {
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
public final class InMemoryAgentSecretStorage: AgentSecretStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String: String] = [:]

  private func key(service: String, account: String) -> String {
    "\(service)\u{1F}\(account)"
  }

  public func read(service: String, account: String) throws -> String? {
    lock.lock()
    defer { lock.unlock() }
    return storage[key(service: service, account: account)]
  }

  public func write(_ value: String, service: String, account: String) throws {
    lock.lock()
    defer { lock.unlock() }
    storage[key(service: service, account: account)] = value
  }

  public func delete(service: String, account: String) throws {
    lock.lock()
    defer { lock.unlock() }
    storage.removeValue(forKey: key(service: service, account: account))
  }
}

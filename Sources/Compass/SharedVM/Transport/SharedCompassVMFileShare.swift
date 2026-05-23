import Foundation
import Virtualization

/// Builders and validators for VirtioFS shares attached to the shared VM.
///
/// No VirtioFS shares are attached to the running VM today — macOS
/// guests TCC-block `AppleVirtIOFS` reads from every process — but
/// the tag-validation helper here is retained for any future
/// reattachment. Host↔guest file movement happens over vsock via
/// `SharedCompassVMWorktreeSync` instead.
enum SharedCompassVMFileShare {
  /// Default tag used by the parent workspace share.
  static let defaultWorkspacesTag = "compass-workspaces"

  /// Errors produced by the tag validator.
  enum TagValidationError: Error, Equatable, CustomStringConvertible {
    case empty
    case tooLong(byteCount: Int)
    case nonASCII
    case containsWhitespace

    var description: String {
      switch self {
      case .empty:
        return "VirtioFS tag must not be empty"
      case .tooLong(let bytes):
        return "VirtioFS tag must be at most 36 bytes, got \(bytes)"
      case .nonASCII:
        return "VirtioFS tag must contain only ASCII characters"
      case .containsWhitespace:
        return "VirtioFS tag must not contain whitespace"
      }
    }
  }

  /// Validates a VirtioFS tag against the VZ constraints we care about:
  /// ASCII-only, no whitespace, at most 36 UTF-8 bytes, non-empty.
  static func validatedTag(_ tag: String) -> Result<String, TagValidationError> {
    if tag.isEmpty {
      return .failure(.empty)
    }
    let bytes = tag.utf8.count
    if bytes > 36 {
      return .failure(.tooLong(byteCount: bytes))
    }
    for scalar in tag.unicodeScalars {
      if !scalar.isASCII {
        return .failure(.nonASCII)
      }
      if scalar.properties.isWhitespace || scalar == " " {
        return .failure(.containsWhitespace)
      }
    }
    return .success(tag)
  }

  /// Convenience wrapper that throws instead of returning a Result.
  static func ensureValidTag(_ tag: String) throws -> String {
    switch validatedTag(tag) {
    case .success(let value): return value
    case .failure(let error): throw error
    }
  }

  /// Description of a host directory to expose as a VirtioFS share.
  struct ShareTarget: Equatable {
    var tag: String
    var hostDirectoryURL: URL
    /// When true, the guest sees the share read-only.
    var readOnly: Bool

    init(tag: String, hostDirectoryURL: URL, readOnly: Bool = false) {
      self.tag = tag
      self.hostDirectoryURL = hostDirectoryURL.standardizedFileURL
      self.readOnly = readOnly
    }
  }

  /// Builds a `VZVirtioFileSystemDeviceConfiguration` for the supplied target.
  /// Validates the tag first and throws on invalid input.
  static func makeDeviceConfiguration(for target: ShareTarget) throws
    -> VZVirtioFileSystemDeviceConfiguration
  {
    let tag = try ensureValidTag(target.tag)
    let share = VZSharedDirectory(url: target.hostDirectoryURL, readOnly: target.readOnly)
    let singleDirectory = VZSingleDirectoryShare(directory: share)
    let configuration = VZVirtioFileSystemDeviceConfiguration(tag: tag)
    configuration.share = singleDirectory
    return configuration
  }
}

import Foundation

/// VirtioFS tag validation retained in case VirtioFS shares return.
///
/// Host↔guest file movement uses vsock via `SharedCompassVMWorktreeSync`.
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
}

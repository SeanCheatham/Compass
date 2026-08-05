import Foundation

/// Source languages the codemap can parse. Kept narrow on purpose — adding
/// a language requires a tree-sitter grammar dependency plus a `.scm` query,
/// so the registry stays explicit about what it supports.
public enum CodemapLanguage: String, Sendable, CaseIterable, Codable {
  case swift
  case rust

  /// Stable display name used in tool output. Distinct from `rawValue` so
  /// renaming a case doesn't churn cached files.
  public var displayName: String {
    switch self {
    case .swift: return "Swift"
    case .rust: return "Rust"
    }
  }
}

extension CodemapLanguage {
  /// Map a file path's extension to a language. Returns nil for unsupported
  /// extensions so the indexer can skip them without a separate allow-list.
  public static func forFile(at path: String) -> CodemapLanguage? {
    let ext = (path as NSString).pathExtension.lowercased()
    return extensionMap[ext]
  }

  /// Map a relative path string to a language. Convenience wrapper around
  /// `forFile(at:)` that handles trailing path components correctly when the
  /// caller already has a relative-path string in hand.
  public static func forRelativePath(_ rel: String) -> CodemapLanguage? {
    forFile(at: rel)
  }

  private static let extensionMap: [String: CodemapLanguage] = [
    "swift": .swift,
    "rs": .rust,
  ]
}

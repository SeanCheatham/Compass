import Foundation

/// Source languages the codemap can parse. Kept narrow on purpose — adding
/// a language requires a tree-sitter grammar dependency plus a `.scm` query,
/// so the registry stays explicit about what it supports.
package enum CodemapLanguage: String, Sendable, CaseIterable, Codable {
  case swift
  case tessera

  /// Stable display name used in tool output. Distinct from `rawValue` so
  /// renaming cases doesn't churn cached files.
  package var displayName: String {
    switch self {
    case .swift: return "Swift"
    case .tessera: return "Tessera"
    }
  }
}

package extension CodemapLanguage {
  /// Map a file path's extension to a language. Returns nil for unsupported
  /// extensions so the indexer can skip them without a separate allow-list.
  static func forFile(at path: String) -> CodemapLanguage? {
    let ext = (path as NSString).pathExtension.lowercased()
    return extensionMap[ext]
  }

  /// Map a relative path string to a language. Convenience wrapper around
  /// `forFile(at:)` that handles trailing path components correctly when the
  /// caller already has a relative-path string in hand.
  static func forRelativePath(_ rel: String) -> CodemapLanguage? {
    forFile(at: rel)
  }

  private static let extensionMap: [String: CodemapLanguage] = [
    "swift": .swift,
    "tes": .tessera,
  ]
}

import Foundation

/// A single declaration extracted from a source file. The kind is the
/// normalized symbol kind (`function`, `class`, …) — distinct grammars use
/// different node names so this layer collapses them.
public struct CodemapSymbol: Sendable, Codable, Equatable {
  public var kind: CodemapSymbolKind
  public var name: String
  /// 1-based line of the declaration's first character.
  public var line: Int
  /// 1-based line of the declaration's last character. Equals `line` for
  /// single-line decls.
  public var endLine: Int
}

/// Normalized symbol kinds. Picked to cover the union of what the supported
/// grammars expose — not every kind applies to every language.
public enum CodemapSymbolKind: String, Sendable, Codable, Equatable, CaseIterable {
  case function
  case method
  case `class`
  case interface
  case `struct`
  case `enum`
  case trait
  case module
  case type
  case property
  case macro
  case impl
  case `extension`
  case constant
}

/// A module/path reference pulled out of an `import` (or equivalent)
/// statement. `raw` is the literal string from source. Resolution to a
/// repo-relative path is handled later by the indexer.
public struct CodemapImport: Sendable, Codable, Equatable {
  public var raw: String
  /// 1-based line of the import statement.
  public var line: Int
}

/// What `SymbolExtractor` returns for a single file.
public struct CodemapExtraction: Sendable, Equatable {
  public var symbols: [CodemapSymbol]
  public var imports: [CodemapImport]

  public static let empty = CodemapExtraction(symbols: [], imports: [])
}

import Foundation
import SwiftTreeSitter

/// Runs the per-language tree-sitter query against a source file's text and
/// reduces the matches into normalized `CodemapSymbol` / `CodemapImport`
/// records. Construct once per language at startup via `LanguageRegistry`;
/// `extract(source:language:)` is safe to call from any task.
public struct SymbolExtractor: Sendable {
  public enum ExtractorError: Error, Equatable {
    /// The file is in a language with no `LanguageRegistry` entry — caller
    /// should treat as "skip this file" rather than surface to the user.
    case unsupportedLanguage(CodemapLanguage)
    /// The grammar refused to parse the source (out-of-memory or hard
    /// timeout). Rare in practice; treated as a soft failure by the indexer.
    case parseFailed
  }

  public let registry: LanguageRegistry

  public init(registry: LanguageRegistry = .shared) {
    self.registry = registry
  }

  /// Parse `source` and return symbols + imports. Allocates a fresh tree-
  /// sitter `Parser` per call so the extractor itself stays Sendable and the
  /// caller can fan parse work out across a task group.
  public func extract(source: String, language: CodemapLanguage) throws -> CodemapExtraction {
    guard let entry = registry.entry(for: language) else {
      throw ExtractorError.unsupportedLanguage(language)
    }

    let parser = Parser()
    try parser.setLanguage(entry.tsLanguage)
    guard let tree = parser.parse(source) else {
      throw ExtractorError.parseFailed
    }
    guard let root = tree.rootNode else {
      throw ExtractorError.parseFailed
    }

    let cursor = entry.symbolQuery.execute(node: root, in: tree)
    let nsSource = source as NSString

    var symbols: [CodemapSymbol] = []
    var imports: [CodemapImport] = []
    var seenSymbol: Set<SymbolKey> = []
    var seenImport: Set<ImportKey> = []

    while let match = cursor.next() {
      var defCapture: QueryCapture?
      var defKind: CodemapSymbolKind?
      var nameCapture: QueryCapture?
      var importCapture: QueryCapture?
      var importSourceCapture: QueryCapture?

      for capture in match.captures {
        guard let captureName = capture.name else { continue }
        if captureName == "name" {
          nameCapture = capture
        } else if captureName == "import" {
          importCapture = capture
        } else if captureName == "import.source" {
          importSourceCapture = capture
        } else if captureName.hasPrefix("def.") {
          let kindString = String(captureName.dropFirst("def.".count))
          if let kind = CodemapSymbolKind(rawValue: kindString) {
            defCapture = capture
            defKind = kind
          }
        }
      }

      if let defCapture, let defKind, let nameCapture,
        let symbol = makeSymbol(
          kind: defKind,
          defCapture: defCapture,
          nameCapture: nameCapture,
          nsSource: nsSource
        )
      {
        let key = SymbolKey(kind: symbol.kind, name: symbol.name, line: symbol.line)
        if seenSymbol.insert(key).inserted {
          symbols.append(symbol)
        }
      }

      if let importSourceCapture {
        let row = (importCapture ?? importSourceCapture).node.pointRange.lowerBound.row
        let line = Int(row) + 1
        let raw = stripImportQuoting(
          rangeText(importSourceCapture.range, in: nsSource)
        )
        let key = ImportKey(raw: raw, line: line)
        if seenImport.insert(key).inserted {
          imports.append(CodemapImport(raw: raw, line: line))
        }
      }
    }

    symbols.sort { $0.line < $1.line || ($0.line == $1.line && $0.name < $1.name) }
    imports.sort { $0.line < $1.line }
    return CodemapExtraction(symbols: symbols, imports: imports)
  }

  private func makeSymbol(
    kind: CodemapSymbolKind,
    defCapture: QueryCapture,
    nameCapture: QueryCapture,
    nsSource: NSString
  ) -> CodemapSymbol? {
    let name = rangeText(nameCapture.range, in: nsSource)
    guard !name.isEmpty else { return nil }
    let pointRange = defCapture.node.pointRange
    let startLine = Int(pointRange.lowerBound.row) + 1
    var endLine = Int(pointRange.upperBound.row) + 1
    // tree-sitter's upperBound is exclusive: a node ending at column 0 of
    // line N actually ends on line N-1. Snap it back so end is inclusive.
    if pointRange.upperBound.column == 0 && endLine > startLine {
      endLine -= 1
    }
    return CodemapSymbol(kind: kind, name: name, line: startLine, endLine: endLine)
  }

  private func rangeText(_ range: NSRange, in source: NSString) -> String {
    guard range.location != NSNotFound,
      range.location >= 0,
      range.length >= 0,
      range.location + range.length <= source.length
    else { return "" }
    return source.substring(with: range)
  }

  private func stripImportQuoting(_ raw: String) -> String {
    var s = raw
    while let first = s.first, first == "\"" || first == "'" || first == "`" {
      s.removeFirst()
    }
    while let last = s.last, last == "\"" || last == "'" || last == "`" {
      s.removeLast()
    }
    return s
  }
}

extension SymbolExtractor {
  fileprivate struct SymbolKey: Hashable {
    public let kind: CodemapSymbolKind
    public let name: String
    public let line: Int
  }

  fileprivate struct ImportKey: Hashable {
    public let raw: String
    public let line: Int
  }
}

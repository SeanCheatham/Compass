import Foundation
import SwiftTreeSitter
import TreeSitterSwift

/// Loads tree-sitter `Language`s and pre-compiles the symbol/import query
/// for each supported source language. Construction is eager so a malformed
/// query trips the first instantiation, not the first parse.
package final class LanguageRegistry: @unchecked Sendable {
  package struct Entry: @unchecked Sendable {
    let language: CodemapLanguage
    let tsLanguage: Language
    let symbolQuery: Query
  }

  package static let shared = LanguageRegistry()

  private let entries: [CodemapLanguage: Entry]

  package init() {
    var map: [CodemapLanguage: Entry] = [:]
    for codemapLanguage in CodemapLanguage.allCases where codemapLanguage != .tessera {
      let lang = Self.makeLanguage(for: codemapLanguage)
      let querySource = Self.symbolQuerySource(for: codemapLanguage)
      guard let queryData = querySource.data(using: .utf8) else {
        fatalError("codemap query for \(codemapLanguage) is not valid UTF-8")
      }
      let query: Query
      do {
        query = try Query(language: lang, data: queryData)
      } catch {
        fatalError("failed to compile codemap query for \(codemapLanguage): \(error)")
      }
      map[codemapLanguage] = Entry(
        language: codemapLanguage,
        tsLanguage: lang,
        symbolQuery: query
      )
    }
    self.entries = map
  }

  package func entry(for language: CodemapLanguage) -> Entry? {
    entries[language]
  }

  package func entry(forPath path: String) -> Entry? {
    guard let language = CodemapLanguage.forFile(at: path) else { return nil }
    return entries[language]
  }

  package struct RuntimeNodeKinds: Sendable, Equatable {
    var branchTypes: Set<String>
    var loopTypes: Set<String>
    var switchTypes: Set<String>
    var errorTypes: Set<String>
    var callTypes: Set<String>
  }

  /// Tree-sitter node names used by static control-flow analysis. Kept beside
  /// the grammar registry so adding a language has one obvious place to define
  /// both symbol indexing and flow scanning.
  package static func runtimeNodeKinds(for language: CodemapLanguage) -> RuntimeNodeKinds {
    switch language {
    case .swift:
      return RuntimeNodeKinds(
        branchTypes: ["if_statement"],
        loopTypes: ["for_statement", "while_statement", "repeat_while_statement"],
        switchTypes: ["switch_statement"],
        errorTypes: ["do_statement", "try_expression"],
        callTypes: ["call_expression"]
      )
    case .tessera:
      return RuntimeNodeKinds(
        branchTypes: ["if"],
        loopTypes: [],
        switchTypes: [],
        errorTypes: [],
        callTypes: ["call"]
      )
    }
  }

  private static func makeLanguage(for codemapLanguage: CodemapLanguage) -> Language {
    switch codemapLanguage {
    case .swift: return Language(language: tree_sitter_swift())
    case .tessera:
      fatalError("Tessera codemap extraction does not use tree-sitter")
    }
  }

  /// Tree-sitter `.scm` query body for the language. Captures the union of
  /// symbol kinds and import statements in one pass so a file is parsed once
  /// and walked once per indexing.
  ///
  /// Conventions:
  /// - `@name` — the identifier that names the declaration.
  /// - `@def.<kind>` — the wrapping declaration node; `<kind>` matches a
  ///   `CodemapSymbolKind` rawValue.
  /// - `@import.source` — the literal module/path string in an import.
  /// - `@import` — the wrapping import statement (used for line number).
  package static func symbolQuerySource(for language: CodemapLanguage) -> String {
    switch language {
    case .swift: return swiftQuery
    case .tessera: return ""
    }
  }

  private static let swiftQuery = #"""
    (import_declaration
      (identifier) @import.source) @import

    (function_declaration
      name: (simple_identifier) @name) @def.function

    (protocol_function_declaration
      name: (simple_identifier) @name) @def.method

    (init_declaration "init" @name) @def.method

    (deinit_declaration "deinit" @name) @def.method

    (class_declaration
      name: (type_identifier) @name) @def.class

    (protocol_declaration
      name: (type_identifier) @name) @def.interface

    (typealias_declaration
      name: (type_identifier) @name) @def.type

    (property_declaration
      (pattern (simple_identifier) @name)) @def.property
    """#

}

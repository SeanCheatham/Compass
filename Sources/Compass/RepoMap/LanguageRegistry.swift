import Foundation
import SwiftTreeSitter
import TreeSitterRust
import TreeSitterSwift

/// Loads tree-sitter `Language`s and pre-compiles the symbol/import query
/// for each supported source language. Construction is eager so a malformed
/// query trips the first instantiation, not the first parse.
final class LanguageRegistry: @unchecked Sendable {
  struct Entry: @unchecked Sendable {
    let language: CodemapLanguage
    let tsLanguage: Language
    let symbolQuery: Query
  }

  static let shared = LanguageRegistry()

  private let entries: [CodemapLanguage: Entry]

  init() {
    var map: [CodemapLanguage: Entry] = [:]
    for codemapLanguage in CodemapLanguage.allCases {
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

  func entry(for language: CodemapLanguage) -> Entry? {
    entries[language]
  }

  func entry(forPath path: String) -> Entry? {
    guard let language = CodemapLanguage.forFile(at: path) else { return nil }
    return entries[language]
  }

  struct RuntimeNodeKinds: Sendable, Equatable {
    var branchTypes: Set<String>
    var loopTypes: Set<String>
    var switchTypes: Set<String>
    var errorTypes: Set<String>
    var callTypes: Set<String>
  }

  /// Tree-sitter node names used by static control-flow analysis. Kept beside
  /// the grammar registry so adding a language has one obvious place to define
  /// both symbol indexing and flow scanning.
  static func runtimeNodeKinds(for language: CodemapLanguage) -> RuntimeNodeKinds {
    switch language {
    case .swift:
      return RuntimeNodeKinds(
        branchTypes: ["if_statement"],
        loopTypes: ["for_statement", "while_statement", "repeat_while_statement"],
        switchTypes: ["switch_statement"],
        errorTypes: ["do_statement", "try_expression"],
        callTypes: ["call_expression"]
      )
    case .rust:
      return RuntimeNodeKinds(
        branchTypes: ["if_expression", "if_let_expression"],
        loopTypes: ["for_expression", "while_expression", "while_let_expression", "loop_expression"],
        switchTypes: ["match_expression"],
        errorTypes: ["try_expression", "call_expression"],
        callTypes: ["call_expression", "macro_invocation"]
      )
    }
  }

  private static func makeLanguage(for codemapLanguage: CodemapLanguage) -> Language {
    switch codemapLanguage {
    case .swift: return Language(language: tree_sitter_swift())
    case .rust: return Language(language: tree_sitter_rust())
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
  static func symbolQuerySource(for language: CodemapLanguage) -> String {
    switch language {
    case .swift: return swiftQuery
    case .rust: return rustQuery
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

  private static let rustQuery = #"""
    (use_declaration
      argument: (scoped_identifier) @import.source) @import
    (use_declaration
      argument: (identifier) @import.source) @import

    (function_item
      name: (identifier) @name) @def.function

    (struct_item
      name: (type_identifier) @name) @def.struct

    (enum_item
      name: (type_identifier) @name) @def.enum

    (trait_item
      name: (type_identifier) @name) @def.trait

    (type_item
      name: (type_identifier) @name) @def.type

    (impl_item
      type: (type_identifier) @name) @def.impl

    (mod_item
      name: (identifier) @name) @def.module

    (const_item
      name: (identifier) @name) @def.constant

    (static_item
      name: (identifier) @name) @def.constant
    """#
}

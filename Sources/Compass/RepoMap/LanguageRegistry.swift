import Foundation
import SwiftTreeSitter
import TreeSitterGo
import TreeSitterJavaScript
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTSX
import TreeSitterTypeScript

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

  /// Tree-sitter node names used by the World tab's static runtime-path
  /// extractor. Kept beside the grammar registry so adding a language has one
  /// obvious place to define both symbol indexing and control-flow scanning.
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
    case .typescript, .tsx, .javascript:
      return RuntimeNodeKinds(
        branchTypes: ["if_statement"],
        loopTypes: ["for_statement", "for_in_statement", "while_statement", "do_statement"],
        switchTypes: ["switch_statement"],
        errorTypes: ["catch_clause"],
        callTypes: ["call_expression"]
      )
    case .go:
      return RuntimeNodeKinds(
        branchTypes: ["if_statement"],
        loopTypes: ["for_statement"],
        switchTypes: ["expression_switch_statement", "type_switch_statement", "select_statement"],
        errorTypes: [],
        callTypes: ["call_expression"]
      )
    case .rust:
      return RuntimeNodeKinds(
        branchTypes: ["if_expression"],
        loopTypes: ["for_expression", "while_expression", "loop_expression"],
        switchTypes: ["match_expression"],
        errorTypes: ["try_expression"],
        callTypes: ["call_expression"]
      )
    }
  }

  private static func makeLanguage(for codemapLanguage: CodemapLanguage) -> Language {
    switch codemapLanguage {
    case .swift: return Language(language: tree_sitter_swift())
    case .typescript: return Language(language: tree_sitter_typescript())
    case .tsx: return Language(language: tree_sitter_tsx())
    case .javascript: return Language(language: tree_sitter_javascript())
    case .go: return Language(language: tree_sitter_go())
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
    case .typescript: return typeScriptQuery
    case .tsx: return typeScriptQuery
    case .javascript: return javaScriptQuery
    case .go: return goQuery
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

  private static let typeScriptQuery = #"""
    (import_statement
      source: (string) @import.source) @import

    (function_declaration
      name: (identifier) @name) @def.function

    (class_declaration
      name: (type_identifier) @name) @def.class

    (abstract_class_declaration
      name: (type_identifier) @name) @def.class

    (interface_declaration
      name: (type_identifier) @name) @def.interface

    (type_alias_declaration
      name: (type_identifier) @name) @def.type

    (enum_declaration
      name: (identifier) @name) @def.enum

    (method_definition
      name: (property_identifier) @name) @def.method

    (lexical_declaration
      (variable_declarator
        name: (identifier) @name
        value: [(arrow_function) (function_expression)])) @def.function
    """#

  private static let javaScriptQuery = #"""
    (import_statement
      source: (string) @import.source) @import

    (function_declaration
      name: (identifier) @name) @def.function

    (class_declaration
      name: (identifier) @name) @def.class

    (method_definition
      name: (property_identifier) @name) @def.method

    (lexical_declaration
      (variable_declarator
        name: (identifier) @name
        value: [(arrow_function) (function_expression)])) @def.function
    """#

  private static let goQuery = #"""
    (import_spec
      path: (interpreted_string_literal) @import.source) @import

    (function_declaration
      name: (identifier) @name) @def.function

    (method_declaration
      name: (field_identifier) @name) @def.method

    (type_declaration
      (type_spec
        name: (type_identifier) @name
        type: (struct_type))) @def.struct

    (type_declaration
      (type_spec
        name: (type_identifier) @name
        type: (interface_type))) @def.interface

    (type_declaration
      (type_spec
        name: (type_identifier) @name)) @def.type
    """#

  private static let rustQuery = #"""
    (use_declaration
      argument: (_) @import.source) @import

    (function_item
      name: (identifier) @name) @def.function

    (struct_item
      name: (type_identifier) @name) @def.struct

    (enum_item
      name: (type_identifier) @name) @def.enum

    (union_item
      name: (type_identifier) @name) @def.struct

    (trait_item
      name: (type_identifier) @name) @def.trait

    (type_item
      name: (type_identifier) @name) @def.type

    (mod_item
      name: (identifier) @name) @def.module

    (macro_definition
      name: (identifier) @name) @def.macro

    (impl_item
      type: (type_identifier) @name) @def.impl
    """#
}

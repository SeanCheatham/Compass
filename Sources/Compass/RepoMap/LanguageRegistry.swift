import Foundation
import SwiftTreeSitter
import TreeSitterGo
import TreeSitterJavaScript
import TreeSitterPython
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

  private static func makeLanguage(for codemapLanguage: CodemapLanguage) -> Language {
    switch codemapLanguage {
    case .swift: return Language(language: tree_sitter_swift())
    case .typescript: return Language(language: tree_sitter_typescript())
    case .tsx: return Language(language: tree_sitter_tsx())
    case .javascript: return Language(language: tree_sitter_javascript())
    case .python: return Language(language: tree_sitter_python())
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
    case .python: return pythonQuery
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

  private static let pythonQuery = #"""
    (import_statement
      name: (dotted_name) @import.source) @import

    (import_from_statement
      module_name: (dotted_name) @import.source) @import

    (import_from_statement
      module_name: (relative_import) @import.source) @import

    (function_definition
      name: (identifier) @name) @def.function

    (class_definition
      name: (identifier) @name) @def.class
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

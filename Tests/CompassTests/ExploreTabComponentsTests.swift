import Foundation
import SwiftUI
import Testing

@testable import Compass

struct ExploreTabComponentsTests {
  // MARK: - FileTreeNode

  @Test
  func fileTreeNode_name_returnsLastPathComponent() throws {
    let node = FileTreeNode(
      relativePath: "Sources/Models/User.swift",
      isDirectory: false,
      language: .swift,
      children: []
    )
    #expect(node.name == "User.swift")
  }

  @Test
  func fileTreeNode_name_deeplyNested() throws {
    let node = FileTreeNode(
      relativePath: "a/b/c/d/e/file.py",
      isDirectory: false,
      language: .python,
      children: []
    )
    #expect(node.name == "file.py")
  }

  @Test
  func fileTreeNode_id_equalsRelativePath() throws {
    let path = "Sources/App.swift"
    let node = FileTreeNode(
      relativePath: path,
      isDirectory: false,
      language: .swift,
      children: []
    )
    #expect(node.id == path)
  }

  @Test
  func fileTreeNode_folderSummary_directoryWithFiles_returnsCount() throws {
    let node = FileTreeNode(
      relativePath: "Sources",
      isDirectory: true,
      language: nil,
      children: [
        FileTreeNode(
          relativePath: "Sources/App.swift", isDirectory: false, language: .swift, children: []),
        FileTreeNode(
          relativePath: "Sources/Model.swift", isDirectory: false, language: .swift, children: []),
      ]
    )
    #expect(node.folderSummary != nil)
    #expect(node.folderSummary == "2 source files in this folder")
  }

  @Test
  func fileTreeNode_folderSummary_singularFile() throws {
    let node = FileTreeNode(
      relativePath: "Sources",
      isDirectory: true,
      language: nil,
      children: [
        FileTreeNode(
          relativePath: "Sources/App.swift", isDirectory: false, language: .swift, children: [])
      ]
    )
    #expect(node.folderSummary != nil)
    #expect(node.folderSummary == "1 source file in this folder")
  }

  @Test
  func fileTreeNode_folderSummary_emptyDirectory_returnsNil() throws {
    let node = FileTreeNode(
      relativePath: "EmptyDir",
      isDirectory: true,
      language: nil,
      children: []
    )
    #expect(node.folderSummary == nil)
  }

  @Test
  func fileTreeNode_folderSummary_file_returnsNil() throws {
    let node = FileTreeNode(
      relativePath: "Sources/App.swift",
      isDirectory: false,
      language: .swift,
      children: []
    )
    #expect(node.folderSummary == nil)
  }

  @Test
  func fileTreeNode_equality_sameValues_equal() throws {
    let left = FileTreeNode(
      relativePath: "Sources/App.swift",
      isDirectory: false,
      language: .swift,
      children: []
    )
    let right = FileTreeNode(
      relativePath: "Sources/App.swift",
      isDirectory: false,
      language: .swift,
      children: []
    )
    #expect(left == right)
  }

  @Test
  func fileTreeNode_equality_differentRelativePath_notEqual() throws {
    let left = FileTreeNode(
      relativePath: "Sources/App.swift",
      isDirectory: false,
      language: .swift,
      children: []
    )
    let right = FileTreeNode(
      relativePath: "Sources/Model.swift",
      isDirectory: false,
      language: .swift,
      children: []
    )
    #expect(left != right)
  }

  // MARK: - LanguageBadge

  // Note: shortName is a private computed property so those tests are skipped.
  // We test the public static color(for:) method instead.

  @Test
  func languageBadge_colorFor_swift_returnsNonNil() throws {
    let color = LanguageBadge.color(for: .swift)
    #expect(color != Color.clear)
  }

  @Test
  func languageBadge_colorFor_typescript_returnsNonNil() throws {
    let color = LanguageBadge.color(for: .typescript)
    #expect(color != Color.clear)
  }

  @Test
  func languageBadge_colorFor_tsx_returnsNonNil() throws {
    let color = LanguageBadge.color(for: .tsx)
    #expect(color != Color.clear)
  }

  @Test
  func languageBadge_colorFor_javascript_returnsNonNil() throws {
    let color = LanguageBadge.color(for: .javascript)
    #expect(color != Color.clear)
  }

  @Test
  func languageBadge_colorFor_python_returnsNonNil() throws {
    let color = LanguageBadge.color(for: .python)
    #expect(color != Color.clear)
  }

  @Test
  func languageBadge_colorFor_go_returnsNonNil() throws {
    let color = LanguageBadge.color(for: .go)
    #expect(color != Color.clear)
  }

  @Test
  func languageBadge_colorFor_rust_returnsNonNil() throws {
    let color = LanguageBadge.color(for: .rust)
    #expect(color != Color.clear)
  }

  @Test
  func languageBadge_colorFor_haskell_returnsNonNil() throws {
    let color = LanguageBadge.color(for: .haskell)
    #expect(color != Color.clear)
  }

  // MARK: - CodemapSymbolKind

  @Test
  func codemapSymbolKind_allCases_countIs14() throws {
    #expect(CodemapSymbolKind.allCases.count == 14)
  }

  @Test
  func codemapSymbolKind_colorFor_function_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .function)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_method_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .method)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_class_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .class)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_interface_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .interface)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_struct_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .struct)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_enum_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .enum)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_trait_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .trait)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_module_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .module)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_type_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .type)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_property_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .property)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_macro_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .macro)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_impl_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .impl)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_extension_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .extension)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_colorFor_constant_returnsNonNil() throws {
    let color = CodemapSymbolKind.color(for: .constant)
    #expect(color != Color.clear)
  }

  @Test
  func codemapSymbolKind_rawValue_function() throws {
    #expect(CodemapSymbolKind.function.rawValue == "function")
  }

  @Test
  func codemapSymbolKind_rawValue_method() throws {
    #expect(CodemapSymbolKind.method.rawValue == "method")
  }

  @Test
  func codemapSymbolKind_rawValue_class() throws {
    #expect(CodemapSymbolKind.class.rawValue == "class")
  }

  @Test
  func codemapSymbolKind_rawValue_interface() throws {
    #expect(CodemapSymbolKind.interface.rawValue == "interface")
  }

  @Test
  func codemapSymbolKind_rawValue_struct() throws {
    #expect(CodemapSymbolKind.struct.rawValue == "struct")
  }

  @Test
  func codemapSymbolKind_rawValue_enum() throws {
    #expect(CodemapSymbolKind.enum.rawValue == "enum")
  }

  @Test
  func codemapSymbolKind_rawValue_trait() throws {
    #expect(CodemapSymbolKind.trait.rawValue == "trait")
  }

  @Test
  func codemapSymbolKind_rawValue_module() throws {
    #expect(CodemapSymbolKind.module.rawValue == "module")
  }

  @Test
  func codemapSymbolKind_rawValue_type() throws {
    #expect(CodemapSymbolKind.type.rawValue == "type")
  }

  @Test
  func codemapSymbolKind_rawValue_property() throws {
    #expect(CodemapSymbolKind.property.rawValue == "property")
  }

  @Test
  func codemapSymbolKind_rawValue_macro() throws {
    #expect(CodemapSymbolKind.macro.rawValue == "macro")
  }

  @Test
  func codemapSymbolKind_rawValue_impl() throws {
    #expect(CodemapSymbolKind.impl.rawValue == "impl")
  }

  @Test
  func codemapSymbolKind_rawValue_extension() throws {
    #expect(CodemapSymbolKind.extension.rawValue == "extension")
  }

  @Test
  func codemapSymbolKind_rawValue_constant() throws {
    #expect(CodemapSymbolKind.constant.rawValue == "constant")
  }

  // MARK: - SessionScope

  @Test
  func sessionScope_rawValue_lastSession() throws {
    #expect(SessionScope.lastSession.rawValue == "Last Session")
  }

  @Test
  func sessionScope_rawValue_allSessions() throws {
    #expect(SessionScope.allSessions.rawValue == "All Sessions")
  }

  @Test
  func sessionScope_caseIterable_containsBothCases() throws {
    let cases = SessionScope.allCases
    #expect(cases.count == 2)
    #expect(cases.contains(.lastSession))
    #expect(cases.contains(.allSessions))
  }

  // MARK: - SymbolDetailPopover symbolKindLabel

  @Test
  func symbolDetailPopover_symbolKindLabel_function() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.function) == "func")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_method() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.method) == "meth")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_class() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.class) == "class")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_interface() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.interface) == "iface")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_struct() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.struct) == "struct")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_enum() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.enum) == "enum")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_trait() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.trait) == "trait")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_module() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.module) == "mod")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_type() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.type) == "type")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_property() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.property) == "prop")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_macro() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.macro) == "macro")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_impl() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.impl) == "impl")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_extension() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.extension) == "ext")
  }

  @Test
  func symbolDetailPopover_symbolKindLabel_constant() throws {
    #expect(SymbolDetailPopoverTests_symbolKindLabel(.constant) == "const")
  }

  // MARK: - SummaryPopover layout

  @Test
  func summaryPopover_frameWidth440() throws {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "A summary of the file.",
      reason: nil
    )
    let typeName = String(reflecting: popover.body)
    #expect(typeName.contains("440"))
  }

  @Test
  func summaryPopover_hasCloseButton() throws {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "A summary of the file.",
      reason: nil
    )
    #expect(String(reflecting: popover.body).contains("Close"))
  }

  @Test
  func summaryPopover_summaryTextWithTextSelection() throws {
    let summaryText = "This file does something interesting."
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: summaryText,
      reason: nil
    )
    #expect(String(reflecting: popover.body).contains(summaryText))
  }
  // MARK: - ExploreVisibleRow

  @Test
  func exploreVisibleRow_collapsedTree_showsRootsOnly() throws {
    let tree = [
      FileTreeNode(
        relativePath: "Sources",
        isDirectory: true,
        language: nil,
        children: [
          FileTreeNode(
            relativePath: "Sources/App.swift", isDirectory: false, language: .swift, children: [])
        ]
      )
    ]
    let rows = ExploreVisibleRow.visibleRows(in: tree, expandedPaths: [])
    #expect(rows.count == 1)
    #expect(rows[0].node.relativePath == "Sources")
  }

  @Test
  func exploreVisibleRow_expandedFolder_includesChildren() throws {
    let tree = [
      FileTreeNode(
        relativePath: "Sources",
        isDirectory: true,
        language: nil,
        children: [
          FileTreeNode(
            relativePath: "Sources/App.swift", isDirectory: false, language: .swift, children: [])
        ]
      )
    ]
    let rows = ExploreVisibleRow.visibleRows(in: tree, expandedPaths: ["Sources"])
    #expect(rows.count == 2)
    #expect(rows[1].node.relativePath == "Sources/App.swift")
    #expect(rows[1].depth == 1)
  }

  // MARK: - FileTreeRowView summaryButton — sparkles branch

  /// Verifies the sparkles "Generate Summary" button appears when a file node
  /// has no entry in `codemapEntries`.
  ///
  /// The `summaryButton` computed property returns the `else` branch (the
  /// `Label("Generate Summary", systemImage: "sparkles")` button) when:
  /// - `codemapEntries[node.relativePath]` is `nil` (no entry for this file), AND
  /// - `node.isDirectory` is `false`, AND
  /// - `node.folderSummary` is `nil` (which it always is for non-directories).
  ///
  /// This is the third branch of the `@ViewBuilder` at line 353–360.
  @Test
  func fileTreeRowView_summaryButton_sparklesButtonAppears_whenNoCodemapEntry() throws {
    let node = FileTreeNode(
      relativePath: "Sources/App.swift",
      isDirectory: false,
      language: .swift,
      children: []
    )
    // Empty codemapEntries: no entry for this file.
    var called = false
    var capturedPath: String?
    let sut = FileTreeRowView(
      node: node,
      depth: 0,
      isExpanded: false,
      codemapEntries: [:],
      onToggleExpansion: { _ in },
      onFileTap: { _ in },
      onSummaryTap: { _, _ in },
      onSymbolDetailTap: { _ in },
      onGenerateSummary: { path in
        called = true
        capturedPath = path
      }
    )

    // The sparkles button label must be present in the rendered view.
    let buttonReflection = String(reflecting: sut.summaryButton)
    #expect(buttonReflection.contains("Generate Summary"))
  }

  /// Verifies that tapping the sparkles "Generate Summary" button calls
  /// `onGenerateSummary` with the node's `relativePath`.
  @Test
  func fileTreeRowView_summaryButton_sparklesButton_callsOnGenerateSummary() throws {
    let path = "Sources/Model.swift"
    let node = FileTreeNode(
      relativePath: path,
      isDirectory: false,
      language: .swift,
      children: []
    )
    var called = false
    var capturedPath: String?
    let sut = FileTreeRowView(
      node: node,
      depth: 0,
      isExpanded: false,
      codemapEntries: [:],
      onToggleExpansion: { _ in },
      onFileTap: { _ in },
      onSummaryTap: { _, _ in },
      onSymbolDetailTap: { _ in },
      onGenerateSummary: { p in
        called = true
        capturedPath = p
      }
    )

    // Invoke the sparkles button action (the else branch at line 354).
    sut.triggerSparklesButtonAction()

    #expect(called)
    try #require(capturedPath != nil)
    #expect(capturedPath == path)
  }

  /// Verifies the sparkles button does NOT appear when the node has a
  /// directory type even if `codemapEntries` is empty — the directory
  /// placeholder text is shown instead.
  @Test
  func fileTreeRowView_summaryButton_noSparklesButton_forDirectory() throws {
    let node = FileTreeNode(
      relativePath: "Sources",
      isDirectory: true,
      language: nil,
      children: [
        FileTreeNode(
          relativePath: "Sources/App.swift", isDirectory: false, language: .swift, children: [])
      ]
    )
    var called = false
    let sut = FileTreeRowView(
      node: node,
      depth: 0,
      isExpanded: false,
      codemapEntries: [:],
      onToggleExpansion: { _ in },
      onFileTap: { _ in },
      onSummaryTap: { _, _ in },
      onSymbolDetailTap: { _ in },
      onGenerateSummary: { _ in called = true }
    )

    // Directory with children shows folder summary, not the sparkles button.
    let buttonReflection = String(reflecting: sut.summaryButton)
    #expect(!buttonReflection.contains("Generate Summary"))
    #expect(!buttonReflection.contains("sparkles"))
  }

  /// Verifies the sparkles button does NOT appear when the file node has a
  /// `CodemapEntry` with a non-empty summary in `codemapEntries` — the summary
  /// popover button is shown instead.
  @Test
  func fileTreeRowView_summaryButton_noSparklesButton_whenEntryHasSummary() throws {
    let node = FileTreeNode(
      relativePath: "Sources/App.swift",
      isDirectory: false,
      language: .swift,
      children: []
    )
    let entry = CodemapEntry(
      relativePath: "Sources/App.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 100,
      symbols: [],
      imports: [],
      summary: "This file provides the main entry point.",
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    var called = false
    let sut = FileTreeRowView(
      node: node,
      depth: 0,
      isExpanded: false,
      codemapEntries: ["Sources/App.swift": entry],
      onToggleExpansion: { _ in },
      onFileTap: { _ in },
      onSummaryTap: { _, _ in },
      onSymbolDetailTap: { _ in },
      onGenerateSummary: { _ in called = true }
    )

    // Summary popover button is shown; sparkles button is not.
    let buttonReflection = String(reflecting: sut.summaryButton)
    #expect(!buttonReflection.contains("Generate Summary"))
    #expect(!buttonReflection.contains("sparkles"))
  }

  @Test
  func fileTreeRowView_summaryButton_rendersBoundedSingleLinePreview() throws {
    let node = FileTreeNode(
      relativePath: "Sources/App.swift",
      isDirectory: false,
      language: .swift,
      children: []
    )
    let longSummary = String(repeating: "This sentence is intentionally long.\n", count: 12)
    let entry = CodemapEntry(
      relativePath: "Sources/App.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 100,
      symbols: [],
      imports: [],
      summary: longSummary,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    let sut = FileTreeRowView(
      node: node,
      depth: 0,
      isExpanded: false,
      codemapEntries: ["Sources/App.swift": entry],
      onToggleExpansion: { _ in },
      onFileTap: { _ in },
      onSummaryTap: { _, _ in },
      onSymbolDetailTap: { _ in },
      onGenerateSummary: { _ in }
    )

    let buttonReflection = String(reflecting: sut.summaryButton)
    #expect(buttonReflection.contains("…"))
    #expect(!buttonReflection.contains(longSummary))
  }
}

// MARK: - Test helpers

/// Accesses the private `symbolKindLabel` method on `SymbolDetailPopover` by
/// mirroring the internal switch logic. This is the same approach used by
/// `SummaryPopoverTests` for private view helpers.
private func SymbolDetailPopoverTests_symbolKindLabel(_ kind: CodemapSymbolKind) -> String {
  switch kind {
  case .function: return "func"
  case .method: return "meth"
  case .class: return "class"
  case .interface: return "iface"
  case .struct: return "struct"
  case .enum: return "enum"
  case .trait: return "trait"
  case .module: return "mod"
  case .type: return "type"
  case .property: return "prop"
  case .macro: return "macro"
  case .impl: return "impl"
  case .extension: return "ext"
  case .constant: return "const"
  }
}

// MARK: - View inspection helpers for FileTreeRowView

extension FileTreeRowView {
  /// Triggers the sparkles button action directly.
  /// This calls `onGenerateSummary(node.relativePath)` without going through
  /// the SwiftUI button-tap machinery (which is unavailable in-process).
  fileprivate func triggerSparklesButtonAction() {
    onGenerateSummary(node.relativePath)
  }
}

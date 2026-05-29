import Foundation
import SwiftUI
@testable import Compass
import Testing

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
        FileTreeNode(relativePath: "Sources/App.swift", isDirectory: false, language: .swift, children: []),
        FileTreeNode(relativePath: "Sources/Model.swift", isDirectory: false, language: .swift, children: []),
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
        FileTreeNode(relativePath: "Sources/App.swift", isDirectory: false, language: .swift, children: []),
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
}
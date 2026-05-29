import Foundation
import Testing

@testable import Compass

struct CodemapFileSystemTests {
  // MARK: - buildTree

  @Test
  func buildTree_emptyRoot_returnsEmptyArray() throws {
    let root = try makeTempDir()
    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()
    #expect(tree.isEmpty)
  }

  @Test
  func buildTree_singleFile_returnsOneFileNode() throws {
    let root = try makeTempDir()
    try FileManager.default.createFile(atPath: root.appendingPathComponent("Foo.swift").path)
    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()
    #expect(tree.count == 1)
    #expect(tree[0].isDirectory == false)
    #expect(tree[0].language == .swift)
  }

  @Test
  func buildTree_singleDirectory_returnsOneDirectoryNode() throws {
    let root = try makeTempDir()
    try FileManager.default.createDirectory(atPath: root.appendingPathComponent("Sources").path, withIntermediateDirectories: false)
    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()
    #expect(tree.count == 1)
    #expect(tree[0].isDirectory == true)
  }

  @Test
  func buildTree_withSubdirectories_returnsNestedChildren() throws {
    let root = try makeTempDir()
    try FileManager.default.createFile(atPath: root.appendingPathComponent("Sources/Models/Foo.swift").path, withIntermediateDirectories: true)
    try FileManager.default.createFile(atPath: root.appendingPathComponent("Sources/Views/Bar.swift").path, withIntermediateDirectories: true)
    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()

    #expect(tree.count == 1)
    #expect(tree[0].relativePath == "Sources")
    #expect(tree[0].isDirectory == true)
    #expect(tree[0].children.count == 2)

    let models = tree[0].children.first { $0.relativePath == "Sources/Models" }
    #expect(models != nil)
    #expect(models!.isDirectory == true)
    #expect(models!.children.count == 1)
    #expect(models!.children[0].relativePath == "Sources/Models/Foo.swift")

    let views = tree[0].children.first { $0.relativePath == "Sources/Views" }
    #expect(views != nil)
    #expect(views!.isDirectory == true)
    #expect(views!.children.count == 1)
    #expect(views!.children[0].relativePath == "Sources/Views/Bar.swift")
  }

  @Test
  func buildTree_hiddenFilesExcluded() throws {
    let root = try makeTempDir()
    try FileManager.default.createFile(atPath: root.appendingPathComponent(".hidden.swift").path)
    try FileManager.default.createFile(atPath: root.appendingPathComponent("visible.swift").path)
    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()
    #expect(tree.count == 1)
    #expect(tree[0].relativePath == "visible.swift")
  }

  @Test
  func buildTree_dotCompassExcluded() throws {
    let root = try makeTempDir()
    try FileManager.default.createFile(atPath: root.appendingPathComponent("Sources/Foo.swift").path, withIntermediateDirectories: true)
    try FileManager.default.createFile(atPath: root.appendingPathComponent("Compass/Data.swift").path, withIntermediateDirectories: true)
    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()
    #expect(tree.count == 1)
    #expect(tree[0].relativePath == "Sources")
  }

  // MARK: - sortNodes

  @Test
  func sortNodes_directoriesBeforeFiles() throws {
    let root = try makeTempDir()
    let fs = CodemapFileSystem(rootURL: root)

    let dirNode = FileTreeNode(relativePath: "Bar", isDirectory: true, language: nil, children: [])
    let fileNode = FileTreeNode(relativePath: "Foo.swift", isDirectory: false, language: .swift, children: [])

    let sorted = fs.sortNodes([fileNode, dirNode])
    #expect(sorted[0].relativePath == "Bar")
    #expect(sorted[1].relativePath == "Foo.swift")
  }

  @Test
  func sortNodes_caseInsensitive() throws {
    let root = try makeTempDir()
    let fs = CodemapFileSystem(rootURL: root)

    let nodeC = FileTreeNode(relativePath: "C.swift", isDirectory: false, language: .swift, children: [])
    let nodeA = FileTreeNode(relativePath: "a.swift", isDirectory: false, language: .swift, children: [])

    let sorted = fs.sortNodes([nodeC, nodeA])
    #expect(sorted[0].relativePath == "a.swift")
    #expect(sorted[1].relativePath == "C.swift")
  }
}
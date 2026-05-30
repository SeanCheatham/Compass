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
    try FileManager.default.createFile(
      atPath: root.appendingPathComponent("Foo.swift").path, contents: nil)
    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()
    #expect(tree.count == 1)
    #expect(tree[0].isDirectory == false)
    #expect(tree[0].language == .swift)
  }

  @Test
  func buildTree_singleDirectory_returnsOneDirectoryNode() throws {
    let root = try makeTempDir()
    try FileManager.default.createDirectory(
      atPath: root.appendingPathComponent("Sources").path, withIntermediateDirectories: false)
    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()
    #expect(tree.count == 1)
    #expect(tree[0].isDirectory == true)
  }

  @Test
  func buildTree_withSubdirectories_returnsNestedChildren() throws {
    let root = try makeTempDir()
    let sourcesDir = root.appendingPathComponent("Sources")
    try FileManager.default.createDirectory(
      atPath: sourcesDir.path, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      atPath: sourcesDir.appendingPathComponent("Models").path,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      atPath: sourcesDir.appendingPathComponent("Views").path,
      withIntermediateDirectories: true
    )
    try FileManager.default.createFile(
      atPath: sourcesDir.appendingPathComponent("Models/Foo.swift").path,
      contents: nil
    )
    try FileManager.default.createFile(
      atPath: sourcesDir.appendingPathComponent("Views/Bar.swift").path,
      contents: nil
    )
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
    let sourcesDir = root.appendingPathComponent("Sources")
    try FileManager.default.createDirectory(
      atPath: sourcesDir.path, withIntermediateDirectories: true)
    try FileManager.default.createFile(
      atPath: sourcesDir.appendingPathComponent(".hidden.swift").path, contents: nil)
    try FileManager.default.createFile(
      atPath: sourcesDir.appendingPathComponent("visible.swift").path, contents: nil)
    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()
    #expect(tree.count == 1)
    #expect(tree[0].relativePath == "Sources")
    #expect(tree[0].isDirectory == true)
    #expect(tree[0].children.count == 1)
    #expect(tree[0].children[0].relativePath == "Sources/visible.swift")
  }

  @Test
  func buildTree_ignoredBuildDirectoryExcluded() throws {
    let root = try makeTempDir()
    let sourcesDir = root.appendingPathComponent("Sources")
    try FileManager.default.createDirectory(
      atPath: sourcesDir.path, withIntermediateDirectories: true)
    try FileManager.default.createFile(
      atPath: sourcesDir.appendingPathComponent("App.swift").path, contents: nil)
    let buildDir = root.appendingPathComponent("build")
    try FileManager.default.createDirectory(
      atPath: buildDir.path, withIntermediateDirectories: true)
    try FileManager.default.createFile(
      atPath: buildDir.appendingPathComponent("generated.o").path, contents: nil)
    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()
    #expect(tree.count == 1)
    #expect(tree[0].relativePath == "Sources")
  }

  @Test
  func buildTree_dotCompassExcluded() throws {
    let root = try makeTempDir()
    let sourcesDir = root.appendingPathComponent("Sources")
    try FileManager.default.createDirectory(
      atPath: sourcesDir.path, withIntermediateDirectories: true)
    try FileManager.default.createFile(
      atPath: sourcesDir.appendingPathComponent("Foo.swift").path, contents: nil)
    let compassDir = root.appendingPathComponent("Compass")
    try FileManager.default.createDirectory(
      atPath: compassDir.path, withIntermediateDirectories: true)
    try FileManager.default.createFile(
      atPath: compassDir.appendingPathComponent("Data.swift").path, contents: nil)
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

    // Create a file first, then a directory
    try FileManager.default.createFile(
      atPath: root.appendingPathComponent("Bar.swift").path, contents: nil)
    try FileManager.default.createDirectory(
      atPath: root.appendingPathComponent("Alpha").path, withIntermediateDirectories: false)

    let tree = fs.buildTree()
    #expect(tree.count == 2)
    // Directory comes before file
    #expect(tree[0].isDirectory == true)
    #expect(tree[0].relativePath == "Alpha")
    #expect(tree[1].isDirectory == false)
    #expect(tree[1].relativePath == "Bar.swift")
  }

  @Test
  func sortNodes_caseInsensitive() throws {
    let root = try makeTempDir()
    let fs = CodemapFileSystem(rootURL: root)

    // Create files with mixed case
    try FileManager.default.createFile(
      atPath: root.appendingPathComponent("file.swift").path, contents: nil)
    try FileManager.default.createFile(
      atPath: root.appendingPathComponent("Alpha.swift").path, contents: nil)
    try FileManager.default.createFile(
      atPath: root.appendingPathComponent("beta.swift").path, contents: nil)

    let tree = fs.buildTree()
    #expect(tree.count == 3)
    // Case-insensitive sort: Alpha < beta < file
    #expect(tree[0].relativePath == "Alpha.swift")
    #expect(tree[1].relativePath == "beta.swift")
    #expect(tree[2].relativePath == "file.swift")
  }
}

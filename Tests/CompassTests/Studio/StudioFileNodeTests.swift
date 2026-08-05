import Foundation
import Testing

@testable import Compass

@Suite("StudioFileNode")
struct StudioFileNodeTests {
  @Test
  func buildsNestedDirectoriesSortedWithFilesAfterFolders() throws {
    let roots = StudioFileNode.build(from: [
      "src/util.rs",
      "README.md",
      "src/main.rs",
      "docs/guide.md",
    ])

    #expect(roots.map(\.name) == ["docs", "src", "README.md"])
    let src = try #require(roots.first { $0.name == "src" })
    #expect(src.isDirectory)
    #expect(src.children?.map(\.name) == ["main.rs", "util.rs"])
  }

  @Test
  func promotesFileLeafWhenNestedPathArrivesLater() throws {
    // Agent may first see a path as a file, then later as a directory prefix.
    let roots = StudioFileNode.build(from: [
      "pkg",
      "pkg/mod.rs",
    ])

    #expect(roots.count == 1)
    let pkg = try #require(roots.first)
    #expect(pkg.path == "pkg")
    #expect(pkg.isDirectory)
    #expect(pkg.children?.map(\.path) == ["pkg/mod.rs"])
  }

  @Test
  func keepsDirectoryWhenFilePathCollidesAfterNesting() throws {
    let roots = StudioFileNode.build(from: [
      "pkg/mod.rs",
      "pkg",
    ])

    #expect(roots.count == 1)
    let pkg = try #require(roots.first)
    #expect(pkg.isDirectory)
    #expect(pkg.children?.map(\.path) == ["pkg/mod.rs"])
  }

  @Test
  func ignoresDuplicatePaths() {
    let roots = StudioFileNode.build(from: [
      "src/main.rs",
      "src/main.rs",
      "src/main.rs",
    ])
    #expect(roots.count == 1)
    #expect(roots.first?.children?.count == 1)
  }
}

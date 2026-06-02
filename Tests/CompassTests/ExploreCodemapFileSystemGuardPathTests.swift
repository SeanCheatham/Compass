import Foundation
import Testing

@testable import Compass

/// Guard-path tests for `CodemapFileSystem.childRelativePaths` internal branches.
///
/// These are the two silent-skip guards that are documented but not exercised
/// by the existing end-to-end `CodemapFileSystemTests`:
///
/// 1. **Symlink guard** (`directoryEntry` lines 113-114): when the directory
///    entry reports `isSymbolicLink == true`, `directoryEntry` returns `nil`
///    and the symbolic link is silently omitted from the tree with no error.
///
/// 2. **`shouldInclude` top-level exclusion guard** (lines 95-103): the
///    `RepositoryWalkRules.shouldInclude` check filters out top-level entries
///    such as `Compass`.  When it returns `false` the entry is silently
///    skipped.
struct ExploreCodemapFileSystemGuardPathTests {

  // MARK: - Guard 1: symlink silently skipped

  /// Verifies that `childRelativePaths` silently skips symbolic links.
  ///
  /// The symlink guard is in `directoryEntry` (lines 113-114): when
  /// `values.isSymbolicLink == true` the method returns `nil` and the
  /// `guard let entry = directoryEntry(at: childURL)` on line 93 makes the
  /// entry disappear from the result with no error raised.
  @Test
  func childRelativePaths_symlinkSilentlySkipped() throws {
    let root = try makeTempDir()

    // Create a regular file and a symlink to it.
    let regularFile = root.appendingPathComponent("Regular.swift")
    try createEmptyFile(regularFile)

    let symlinkPath = root.appendingPathComponent("Link.swift")
    try FileManager.default.createSymbolicLink(
      atPath: symlinkPath.path,
      withDestinationPath: regularFile.path
    )

    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()

    // The regular file must be present.
    let regularNode = tree.first { $0.relativePath == "Regular.swift" }
    try #require(regularNode != nil)

    // The symlink must NOT appear in the tree — the symlink guard swallows it.
    let symlinkNodes = tree.filter { $0.relativePath == "Link.swift" }
    #expect(symlinkNodes.isEmpty)
  }

  /// Verifies that `directoryEntry` returns `nil` for a broken symlink, so the
  /// broken symlink is also silently excluded.
  @Test
  func childRelativePaths_brokenSymlinkSilentlySkipped() throws {
    let root = try makeTempDir()

    // Create a symlink pointing to a target that does not exist.
    let brokenLink = root.appendingPathComponent("BrokenLink.swift")
    try FileManager.default.createSymbolicLink(
      atPath: brokenLink.path,
      withDestinationPath: "NonExistentTarget.swift"
    )

    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()

    // The broken symlink must not appear in the tree.
    let brokenLinkNodes = tree.filter { $0.relativePath == "BrokenLink.swift" }
    #expect(brokenLinkNodes.isEmpty)
  }

  // MARK: - Guard 2: shouldInclude top-level exclusion silently skips

  /// Verifies that a top-level `Compass` directory is silently excluded by
  /// `RepositoryWalkRules.shouldInclude` even when it contains valid files.
  ///
  /// The guard is on lines 95-103: when `shouldInclude` returns `false` the
  /// `compactMap` on line 92 returns `nil` and the entry never reaches
  /// `buildNode`.
  @Test
  func buildTree_topLevelCompassDirectorySilentlyExcluded() throws {
    let root = try makeTempDir()

    // A legitimate Sources directory with a real Swift file.
    let sourcesDir = root.appendingPathComponent("Sources")
    try FileManager.default.createDirectory(
      atPath: sourcesDir.path, withIntermediateDirectories: true)
    try createEmptyFile(sourcesDir.appendingPathComponent("App.swift"))

    // A top-level Compass directory with a file — must be excluded.
    let compassDir = root.appendingPathComponent("Compass")
    try FileManager.default.createDirectory(
      atPath: compassDir.path, withIntermediateDirectories: true)
    try createEmptyFile(compassDir.appendingPathComponent("Internal.swift"))

    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()

    // Sources must be present.
    let sourcesNode = tree.first { $0.relativePath == "Sources" }
    try #require(sourcesNode != nil)
    #expect(sourcesNode!.children.count == 1)
    #expect(sourcesNode!.children[0].relativePath == "Sources/App.swift")

    // The top-level Compass directory must NOT appear anywhere in the tree.
    let compassNodes = tree.filter { $0.relativePath == "Compass" }
    #expect(compassNodes.isEmpty)
  }

  /// Verifies that a top-level hidden entry (dot-prefix) is silently excluded
  /// by `shouldInclude`'s `hasPrefix(".")` check.
  @Test
  func buildTree_topLevelHiddenEntrySilentlyExcluded() throws {
    let root = try makeTempDir()

    // A visible source directory.
    let sourcesDir = root.appendingPathComponent("Sources")
    try FileManager.default.createDirectory(
      atPath: sourcesDir.path, withIntermediateDirectories: true)
    try createEmptyFile(sourcesDir.appendingPathComponent("App.swift"))

    // A top-level dot-prefix directory — must be excluded.
    let hiddenDir = root.appendingPathComponent(".Hidden")
    try FileManager.default.createDirectory(
      atPath: hiddenDir.path, withIntermediateDirectories: true)
    try createEmptyFile(hiddenDir.appendingPathComponent("Secret.swift"))

    let fs = CodemapFileSystem(rootURL: root)
    let tree = fs.buildTree()

    // Sources must be present.
    let sourcesNode = tree.first { $0.relativePath == "Sources" }
    try #require(sourcesNode != nil)

    // The hidden directory must NOT appear in the tree.
    let hiddenNodes = tree.filter { $0.relativePath == ".Hidden" }
    #expect(hiddenNodes.isEmpty)
  }

  // MARK: - Guard 3: non-source directory pruned from source tree

  /// Verifies that `buildSourceTree()` silently removes a directory that
  /// contains only non-source files (e.g. `.txt`, `.png`).
  ///
  /// The pruning guard is at `CodemapFileSystem.swift:44`
  /// (`guard !children.isEmpty else { return nil }`): after recursively
  /// pruning all children, if the resulting `children` array is empty the
  /// directory node itself is removed.  Line 52 then handles individual
  /// non-source files.
  @Test
  func buildSourceTree_nonSourceFileDirPruned() throws {
    let root = try makeTempDir()

    // A real source directory with a Swift file — must survive.
    let sourcesDir = root.appendingPathComponent("Sources")
    try FileManager.default.createDirectory(
      atPath: sourcesDir.path, withIntermediateDirectories: true)
    try createEmptyFile(sourcesDir.appendingPathComponent("App.swift"))

    // A Docs directory with only non-source files — must be entirely absent.
    let docsDir = root.appendingPathComponent("Docs")
    try FileManager.default.createDirectory(
      atPath: docsDir.path, withIntermediateDirectories: true)
    try createEmptyFile(docsDir.appendingPathComponent("readme.txt"))
    try createEmptyFile(docsDir.appendingPathComponent("CHANGES"))

    // An Assets directory with image files only — must also be absent.
    let assetsDir = root.appendingPathComponent("Assets")
    try FileManager.default.createDirectory(
      atPath: assetsDir.path, withIntermediateDirectories: true)
    try createEmptyFile(assetsDir.appendingPathComponent("logo.png"))

    let fs = CodemapFileSystem(rootURL: root)
    let sourceTree = fs.buildSourceTree()

    // Sources must be present.
    let sourcesNode = sourceTree.first { $0.relativePath == "Sources" }
    try #require(sourcesNode != nil)
    #expect(sourcesNode!.children.count == 1)
    #expect(sourcesNode!.children[0].relativePath == "Sources/App.swift")

    // Docs and Assets directories must NOT appear anywhere in the tree.
    let docsNodes = sourceTree.filter { $0.relativePath.hasPrefix("Docs") }
    #expect(docsNodes.isEmpty)
    let assetsNodes = sourceTree.filter { $0.relativePath.hasPrefix("Assets") }
    #expect(assetsNodes.isEmpty)
  }

  /// Verifies that `buildSourceTree()` recursively prunes a deeply nested
  /// directory branch when no source files exist at any level in that branch.
  ///
  /// The deepest common ancestor containing only non-source content is removed
  /// entirely, including all its empty intermediate parent directories.
  @Test
  func buildSourceTree_deeplyNestedEmptyDirPruned() throws {
    let root = try makeTempDir()

    // A top-level source file — survives.
    let rootFile = root.appendingPathComponent("App.swift")
    try createEmptyFile(rootFile)

    // A very deep directory chain containing only non-source files — the
    // entire branch from the deepest common ancestor down must be absent.
    let deepDir = root.appendingPathComponent(
      "Very/Deep/Dir/Structure/with/only/text/files")
    try FileManager.default.createDirectory(
      atPath: deepDir.path, withIntermediateDirectories: true)
    try createEmptyFile(deepDir.appendingPathComponent("readme.txt"))

    let fs = CodemapFileSystem(rootURL: root)
    let sourceTree = fs.buildSourceTree()

    // App.swift must be present.
    let appNode = sourceTree.first { $0.relativePath == "App.swift" }
    try #require(appNode != nil)

    // The "Very" directory and everything below it must be absent.
    let veryNodes = sourceTree.filter { $0.relativePath.hasPrefix("Very") }
    #expect(veryNodes.isEmpty)
  }

  private func createEmptyFile(_ url: URL) throws {
    try Data().write(to: url)
  }
}

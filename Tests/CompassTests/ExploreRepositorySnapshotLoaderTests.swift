import Foundation
import Testing

@testable import Compass

struct ExploreRepositorySnapshotLoaderTests {

  // MARK: - load: empty repo / codemap dir

  @Test
  func load_emptyRepoAndCodemapDir_returnsEmptySnapshot() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let codemapDir = repoURL.appendingPathComponent(".compass/codemap", isDirectory: true)
    try FileManager.default.createDirectory(at: codemapDir, withIntermediateDirectories: true)

    let snapshot = ExploreRepositorySnapshotLoader.load(repoURL: repoURL, codemapDirectory: codemapDir)

    #expect(snapshot.fileTree.isEmpty)
    #expect(snapshot.codemapEntries.isEmpty)
  }

  // MARK: - load: source files + codemap entries

  @Test
  func load_withSourceFilesAndCodemapEntries_producesSnapshotWithBoth() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let codemapDir = repoURL.appendingPathComponent(".compass/codemap", isDirectory: true)
    try FileManager.default.createDirectory(at: codemapDir, withIntermediateDirectories: true)

    // Set up a real git repo so ExploreTreeBuilder uses git-tracked paths.
    let gitInitialized = (try? initGitRepo(at: repoURL)) != nil
    try #require(gitInitialized, "git is not available; skipping")

    // Create source files tracked by git.
    try writeFile("Sources/App.swift", contents: "import Foundation\n", at: repoURL)
    try writeFile("Sources/Model.swift", contents: "struct Foo {}\n", at: repoURL)

    let codemapStore = CodemapStore(directory: codemapDir, prettyPrint: true)

    let entry1 = CodemapEntry(
      relativePath: "Sources/App.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 17,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    let entry2 = CodemapEntry(
      relativePath: "Sources/Model.swift",
      language: .swift,
      contentHash: "def456",
      sizeBytes: 16,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try codemapStore.saveEntry(entry1)
    try codemapStore.saveEntry(entry2)

    let snapshot = ExploreRepositorySnapshotLoader.load(repoURL: repoURL, codemapDirectory: codemapDir)

    // File tree must contain the tracked files.
    let treePaths = ExploreTreeBuilder.allFilePaths(in: snapshot.fileTree).sorted()
    #expect(treePaths == ["Sources/App.swift", "Sources/Model.swift"])

    // Codemap entries must be populated.
    #expect(snapshot.codemapEntries.count == 2)
    try #require(snapshot.codemapEntries["Sources/App.swift"] != nil)
    #expect(snapshot.codemapEntries["Sources/App.swift"]?.language == .swift)
    try #require(snapshot.codemapEntries["Sources/Model.swift"] != nil)
    #expect(snapshot.codemapEntries["Sources/Model.swift"]?.language == .swift)
  }

  // MARK: - load: source files, no codemap entries

  @Test
  func load_withFilesButNoCodemapEntries_producesSnapshotWithEmptyEntries() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let codemapDir = repoURL.appendingPathComponent(".compass/codemap", isDirectory: true)
    try FileManager.default.createDirectory(at: codemapDir, withIntermediateDirectories: true)

    // Use a real git repo so file tree reflects git-tracked files.
    let gitInitialized = (try? initGitRepo(at: repoURL)) != nil
    try #require(gitInitialized, "git is not available; skipping")

    try writeFile("Sources/App.swift", contents: "import Foundation\n", at: repoURL)

    // Leave codemap directory empty (no entries written).

    let snapshot = ExploreRepositorySnapshotLoader.load(repoURL: repoURL, codemapDirectory: codemapDir)

    let treePaths = ExploreTreeBuilder.allFilePaths(in: snapshot.fileTree).sorted()
    #expect(treePaths == ["Sources/App.swift"])
    #expect(snapshot.codemapEntries.isEmpty)
  }

  // MARK: - load: codemap entries, no tracked source files

  @Test
  func load_withCodemapEntriesButNoSourceFiles_producesEmptyFileTree() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let codemapDir = repoURL.appendingPathComponent(".compass/codemap", isDirectory: true)
    try FileManager.default.createDirectory(at: codemapDir, withIntermediateDirectories: true)

    // Write codemap entries for files that don't exist on disk.
    let codemapStore = CodemapStore(directory: codemapDir, prettyPrint: true)
    let entry = CodemapEntry(
      relativePath: "Sources/Missing.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 10,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try codemapStore.saveEntry(entry)

    let snapshot = ExploreRepositorySnapshotLoader.load(repoURL: repoURL, codemapDirectory: codemapDir)

    // The file tree is built from git (or CodemapFileSystem) — neither will include
    // files that don't exist on disk, so the tree is empty.
    #expect(snapshot.fileTree.isEmpty)
    // The codemap entry is still loaded because its path matches the tree traversal.
    // (In practice, since the file doesn't exist in the tree, there are no paths
    // to look up — the loop iterates over zero paths, so the entry dict stays empty.)
    #expect(snapshot.codemapEntries.isEmpty)
  }

  // MARK: - load: file tree matches git-tracked source paths

  @Test
  func load_fileTreeMatchesSourcePaths() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let codemapDir = repoURL.appendingPathComponent(".compass/codemap", isDirectory: true)
    try FileManager.default.createDirectory(at: codemapDir, withIntermediateDirectories: true)

    let gitInitialized = (try? initGitRepo(at: repoURL)) != nil
    try #require(gitInitialized, "git is not available; skipping")

    // Write both a tracked source file and a build artifact, then only stage the source.
    try writeFile("Sources/App.swift", contents: "import Foundation\n", at: repoURL)
    try writeFile("build/generated.swift", contents: "print(\"generated\")\n", at: repoURL)
    try runGit(
      "git add Sources/App.swift && "
        + "git -c user.email=t@t -c user.name=t commit -q -m init",
      at: repoURL
    )

    let snapshot = ExploreRepositorySnapshotLoader.load(repoURL: repoURL, codemapDirectory: codemapDir)

    let treePaths = ExploreTreeBuilder.allFilePaths(in: snapshot.fileTree).sorted()
    // Only the git-tracked file appears in the tree — not build/generated.swift.
    #expect(treePaths == ["Sources/App.swift"])
  }

  // MARK: - ExploreRepositorySnapshot equality

  @Test
  func snapshot_equality_equalSnapshotsAreEqual() throws {
    let tree: [FileTreeNode] = [
      FileTreeNode(
        relativePath: "Sources/App.swift",
        isDirectory: false,
        language: .swift,
        children: []
      )
    ]
    let entry = CodemapEntry(
      relativePath: "Sources/App.swift",
      language: .swift,
      contentHash: "abc",
      sizeBytes: 10,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )

    let snap1 = ExploreRepositorySnapshot(fileTree: tree, codemapEntries: ["Sources/App.swift": entry])
    let snap2 = ExploreRepositorySnapshot(fileTree: tree, codemapEntries: ["Sources/App.swift": entry])

    #expect(snap1 == snap2)
  }

  @Test
  func snapshot_equality_differentFileTreeNotEqual() throws {
    let tree1: [FileTreeNode] = [
      FileTreeNode(
        relativePath: "Sources/App.swift",
        isDirectory: false,
        language: .swift,
        children: []
      )
    ]
    let tree2: [FileTreeNode] = [
      FileTreeNode(
        relativePath: "Sources/Other.swift",
        isDirectory: false,
        language: .swift,
        children: []
      )
    ]

    let snap1 = ExploreRepositorySnapshot(fileTree: tree1, codemapEntries: [:])
    let snap2 = ExploreRepositorySnapshot(fileTree: tree2, codemapEntries: [:])

    #expect(snap1 != snap2)
  }

  // MARK: - ExploreRepositorySnapshotCache

  @Test
  func cache_storeAndRetrieve_roundTrips() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let snapshot = ExploreRepositorySnapshot(
      fileTree: [
        FileTreeNode(
          relativePath: "Sources/App.swift",
          isDirectory: false,
          language: .swift,
          children: []
        )
      ],
      codemapEntries: [:]
    )

    let cache = ExploreRepositorySnapshotCache.shared
    cache.store(snapshot, for: repoURL)

    let retrieved = cache.snapshot(for: repoURL)
    try #require(retrieved != nil)
    #expect(retrieved == snapshot)
  }

  @Test
  func cache_retrieveNonexistent_returnsNil() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let cache = ExploreRepositorySnapshotCache.shared
    let result = cache.snapshot(for: repoURL)

    #expect(result == nil)
  }
}
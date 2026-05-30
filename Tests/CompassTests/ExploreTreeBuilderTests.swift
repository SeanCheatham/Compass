import Foundation
import Testing

@testable import Compass

struct ExploreTreeBuilderTests {
  @Test
  func buildTree_fromSourcePaths_buildsNestedDirectories() throws {
    let tree = ExploreTreeBuilder.buildTree(fromSourcePaths: [
      "Sources/Compass/App.swift",
      "Tests/CompassTests/AppTests.swift",
    ])

    #expect(tree.count == 2)
    let sources = tree.first { $0.relativePath == "Sources" }
    #expect(sources?.isDirectory == true)
    #expect(sources?.children.count == 1)
    #expect(sources?.children[0].relativePath == "Sources/Compass")
    #expect(sources?.children[0].children[0].relativePath == "Sources/Compass/App.swift")
  }

  @Test
  func allFilePaths_collectsOnlyFiles() throws {
    let tree = ExploreTreeBuilder.buildTree(fromSourcePaths: [
      "Sources/App.swift",
      "Sources/Models/User.swift",
    ])
    let paths = ExploreTreeBuilder.allFilePaths(in: tree).sorted()
    #expect(paths == ["Sources/App.swift", "Sources/Models/User.swift"])
  }

  @Test
  func buildSourceTree_filtersTrackedBuildArtifactsFromGitListing() throws {
    let repoURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repoURL) }

    let initialized = (try? initGitRepo(at: repoURL)) != nil
    try #require(initialized, "git is not available; skipping")

    try writeFile(".gitignore", contents: "build/\n", at: repoURL)
    try writeFile("Sources/App.swift", contents: "print(\"hello\")\n", at: repoURL)
    try writeFile("build/generated.swift", contents: "print(\"generated\")\n", at: repoURL)
    try runGit(
      "git add .gitignore Sources/App.swift && git add -f build/generated.swift && "
        + "git -c user.email=t@t -c user.name=t commit -q -m init",
      at: repoURL
    )

    let tree = ExploreTreeBuilder.buildSourceTree(repoURL: repoURL)
    let paths = ExploreTreeBuilder.allFilePaths(in: tree).sorted()

    #expect(paths == ["Sources/App.swift"])
  }

  @Test
  func repositoryWalkRules_filtersGeneratedRelativePaths() {
    #expect(!RepositoryWalkRules.shouldInclude(relativePath: "build/generated.swift"))
    #expect(!RepositoryWalkRules.shouldInclude(relativePath: ".build/checkouts/Package.swift"))
    #expect(!RepositoryWalkRules.shouldInclude(relativePath: "Sources/.hidden.swift"))
    #expect(RepositoryWalkRules.shouldInclude(relativePath: "Sources/App.swift"))
  }

  @Test
  func snapshotCache_returnsStoredSnapshot() throws {
    let repoURL = URL(fileURLWithPath: "/tmp/example-repo")
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
    #expect(cache.snapshot(for: repoURL) == snapshot)
  }
}

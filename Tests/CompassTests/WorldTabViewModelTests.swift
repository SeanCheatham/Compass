import Foundation
import Testing

@testable import Compass

@MainActor
struct WorldTabViewModelTests {
  @Test
  func loadWithoutWorkspace_reportsUnavailable() async throws {
    let repo = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repo) }
    let model = WorldTabViewModel()

    await model.load(repoURL: repo, workspace: nil)

    #expect(model.graph == nil)
    #expect(model.errorMessage != nil)
  }

  @Test
  func loadBuildsRouteAndSupportsStepping() async throws {
    await WorldGraphCache.shared.removeAll()
    let repo = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repo) }
    let storage = repo.appendingPathComponent(".compass")
    let workspace = CompassWorkspace(repoURL: repo, storageRootURL: storage)
    let store = CodemapStore(directory: CodemapStore.defaultDirectory(forWorkspace: workspace))

    let source = """
      @main
      struct DemoApp {
        static func main() {
          if Bool.random() { helper() }
          helper()
        }
        static func helper() {}
      }
      """
    try writeIndexedSource(
      "Sources/DemoApp.swift",
      source: source,
      language: .swift,
      repo: repo,
      store: store
    )

    let model = WorldTabViewModel()
    await model.load(repoURL: repo, workspace: workspace)

    let graph = try #require(model.graph)
    #expect(!graph.entrypointIDs.isEmpty)
    #expect(!model.route.isEmpty)
    let first = model.selectedNodeID
    model.stepForward()
    #expect(model.selectedNodeID != nil)
    if model.route.count > 1 {
      #expect(model.selectedNodeID != first)
    }
  }

  @Test
  func selectBranchAddsChoiceToRoute() throws {
    let model = WorldTabViewModel()
    model.route = ["entry"]
    model.routeIndex = 0
    model.selectBranch("branch")

    #expect(model.route == ["entry", "branch"])
    #expect(model.routeIndex == 1)
    #expect(model.selectedNodeID == "branch")
  }

  private func writeIndexedSource(
    _ relativePath: String,
    source: String,
    language: CodemapLanguage,
    repo: URL,
    store: CodemapStore
  ) throws {
    try writeFile(relativePath, contents: source, at: repo)
    let extraction = try SymbolExtractor().extract(source: source, language: language)
    let hash = CodemapHash.sha256Hex(source)
    let entry = CodemapEntry(
      relativePath: relativePath,
      language: language,
      contentHash: hash,
      sizeBytes: Data(source.utf8).count,
      symbols: extraction.symbols,
      imports: extraction.imports,
      summary: "Fixture summary",
      summaryModel: nil,
      summaryContentHash: hash,
      isGenerated: false
    )
    try store.saveEntry(entry)
  }
}

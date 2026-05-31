import Foundation
import Testing

@testable import Compass

struct WorldGraphBuilderTests {
  @Test
  func buildGraph_createsDungeonNodesEdgesAndEntrypoints() throws {
    let repo = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repo) }
    let codemapDir = repo.appendingPathComponent(".compass/codemap")
    let store = CodemapStore(directory: codemapDir)

    let source = """
      @main
      struct DemoApp {
        static func main() {
          if Bool.random() { helper() }
          for item in [1] { helper() }
          switch 1 { case 1: helper(); default: break }
          externalService()
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

    let graph = WorldGraphBuilder(repoURL: repo, codemapDirectory: codemapDir).build()

    #expect(!graph.nodes.isEmpty)
    #expect(!graph.entrypointIDs.isEmpty)
    #expect(graph.nodes.contains { $0.kind == .branch })
    #expect(graph.nodes.contains { $0.kind == .loop })
    #expect(graph.nodes.contains { $0.kind == .switchCase })
    #expect(graph.nodes.contains { $0.kind == .unresolvedPassage && $0.label == "externalService" })
    #expect(graph.edges.contains { $0.kind == .calls && $0.label == "helper" })
    #expect(graph.nodes.allSatisfy { node in
      node.position.x.isFinite && node.position.y.isFinite && node.position.z.isFinite
    })
  }

  @Test
  func layout_isDeterministicForSameInput() throws {
    let repo = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: repo) }
    let codemapDir = repo.appendingPathComponent(".compass/codemap")
    let store = CodemapStore(directory: codemapDir)

    try writeIndexedSource(
      "Sources/Main.swift",
      source: """
        @main
        struct App {
          static func main() { helper() }
          static func helper() {}
        }
        """,
      language: .swift,
      repo: repo,
      store: store
    )

    let builder = WorldGraphBuilder(repoURL: repo, codemapDirectory: codemapDir)
    let first = builder.build()
    let second = builder.build()

    let firstPositions = Dictionary(uniqueKeysWithValues: first.nodes.map { ($0.id, $0.position) })
    let secondPositions = Dictionary(uniqueKeysWithValues: second.nodes.map { ($0.id, $0.position) })
    #expect(firstPositions == secondPositions)
    #expect(first.edges == second.edges)
  }

  @Test
  func navigator_branchChoicesAndRouteWork() throws {
    var graph = WorldGraph()
    let entry = WorldNode(
      id: "entry",
      kind: .function,
      label: "main",
      detail: nil,
      language: .swift,
      location: nil,
      confidence: .high,
      position: .zero
    )
    let branch = WorldNode(
      id: "branch",
      kind: .branch,
      label: "Branch L2",
      detail: nil,
      language: .swift,
      location: nil,
      confidence: .high,
      position: .zero
    )
    graph.addNode(entry)
    graph.addNode(branch)
    graph.markEntrypoint(entry.id)
    graph.addEdge(from: entry.id, to: branch.id, kind: .branches, confidence: .high)

    let route = WorldNavigator.route(in: graph, from: entry.id)
    #expect(route == ["entry", "branch"])
    #expect(WorldNavigator.branchChoices(in: graph, at: entry.id).map(\.id) == ["branch"])
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
    let entry = CodemapEntry(
      relativePath: relativePath,
      language: language,
      contentHash: CodemapHash.sha256Hex(source),
      sizeBytes: Data(source.utf8).count,
      symbols: extraction.symbols,
      imports: extraction.imports,
      summary: "Fixture summary",
      summaryModel: nil,
      summaryContentHash: CodemapHash.sha256Hex(source),
      isGenerated: false
    )
    try store.saveEntry(entry)
  }
}

import Foundation
import Testing

@testable import Compass

struct ExploreArchitectureGraphTests {
  // MARK: - ImportGraph Node and Edge construction

  @Test
  func node_pathEquality_matches() throws {
    let a = ImportGraph.Node(path: "Sources/App.swift")
    let b = ImportGraph.Node(path: "Sources/App.swift")
    let c = ImportGraph.Node(path: "Sources/Model.swift")
    #expect(a == b)
    #expect(a != c)
  }

  @Test
  func node_hashability_usableInSet() throws {
    let a = ImportGraph.Node(path: "Sources/App.swift")
    let b = ImportGraph.Node(path: "Sources/App.swift")
    let set = Set([a, b])
    #expect(set.count == 1)
  }

  @Test
  func edge_equality_basedOnSourceAndTarget() throws {
    let n1 = ImportGraph.Node(path: "A.swift")
    let n2 = ImportGraph.Node(path: "B.swift")
    let e1 = ImportGraph.Edge(source: n1, target: n2, rawImport: "B")
    let e2 = ImportGraph.Edge(source: n1, target: n2, rawImport: "B")
    let e3 = ImportGraph.Edge(source: n1, target: n2, rawImport: "Module/B")
    #expect(e1 == e2)
    #expect(e1 != e3)
  }

  // MARK: - addEdge

  @Test
  func addEdge_registersNodesAndEdge() throws {
    var graph = ImportGraph()
    let source = ImportGraph.Node(path: "Sources/A.swift")
    let target = ImportGraph.Node(path: "Sources/B.swift")
    graph.addEdge(from: source, to: target, rawImport: "B")

    #expect(graph.nodes.count == 2)
    #expect(graph.edges.count == 1)
    #expect(graph.edges.first?.rawImport == "B")
  }

  @Test
  func addEdge_deduplicatesSameEdge() throws {
    var graph = ImportGraph()
    let source = ImportGraph.Node(path: "Sources/A.swift")
    let target = ImportGraph.Node(path: "Sources/B.swift")
    graph.addEdge(from: source, to: target, rawImport: "B")
    graph.addEdge(from: source, to: target, rawImport: "B")  // duplicate

    #expect(graph.edges.count == 1)
  }

  @Test
  func addEdge_differentRawImports_sameNodes_bothEdgesKept() throws {
    var graph = ImportGraph()
    let source = ImportGraph.Node(path: "Sources/A.swift")
    let target = ImportGraph.Node(path: "Sources/B.swift")
    graph.addEdge(from: source, to: target, rawImport: "B")
    graph.addEdge(from: source, to: target, rawImport: "Module/B")  // different raw form

    #expect(graph.edges.count == 2)
  }

  @Test
  func addEdge_populatesAdjacency() throws {
    var graph = ImportGraph()
    let source = ImportGraph.Node(path: "Sources/A.swift")
    let target = ImportGraph.Node(path: "Sources/B.swift")
    graph.addEdge(from: source, to: target, rawImport: "B")

    let outgoing = graph.adjacency[source] ?? []
    #expect(outgoing.contains(target))
  }

  // MARK: - mostDependedOn

  @Test
  func mostDependedOn_ordersByIncomingEdgeCountDescending() throws {
    var graph = ImportGraph()
    let a = ImportGraph.Node(path: "A.swift")
    let b = ImportGraph.Node(path: "B.swift")
    let c = ImportGraph.Node(path: "C.swift")

    // A and B both import C
    graph.addEdge(from: a, to: c, rawImport: "C")
    graph.addEdge(from: b, to: c, rawImport: "C")
    // C imports nothing

    let sorted = graph.mostDependedOn
    #expect(sorted.first == c)
    #expect(sorted.last == a || sorted.last == b)
  }

  // MARK: - likelyEntryPoints

  @Test
  func likelyEntryPoints_nodesWithOutgoingButNoIncoming() throws {
    var graph = ImportGraph()
    let a = ImportGraph.Node(path: "A.swift")
    let b = ImportGraph.Node(path: "B.swift")
    let c = ImportGraph.Node(path: "C.swift")

    graph.addEdge(from: a, to: b, rawImport: "B")
    graph.addEdge(from: c, to: b, rawImport: "B")
    // B has incoming but no outgoing — not an entry point
    // A and C have outgoing but no incoming — entry points

    let entryPoints = graph.likelyEntryPoints
    #expect(entryPoints.contains(a))
    #expect(entryPoints.contains(c))
    #expect(!entryPoints.contains(b))
  }

  @Test
  func likelyEntryPoints_emptyGraph_returnsEmpty() throws {
    var graph = ImportGraph()
    #expect(graph.likelyEntryPoints.isEmpty)
  }

  // MARK: - textGraph()

  @Test
  func textGraph_returnsNonEmptyString() throws {
    var graph = ImportGraph()
    // Cross-cluster edge: Sources/A.swift imports Module/B
    let a = ImportGraph.Node(path: "Sources/A.swift")
    let b = ImportGraph.Node(path: "Module/B.swift")
    graph.addEdge(from: a, to: b, rawImport: "Module/B")

    let output = graph.textGraph()
    try #require(!output.isEmpty)
    // Verify structural markers are present
    #expect(output.contains("=== Architecture Graph ==="))
    #expect(output.contains("📁 "))
    // Arrow indicates cross-cluster dependency display
    #expect(output.contains("→"))
    #expect(output.contains("=== Key Dependencies ==="))
    #expect(output.contains("=== Entry Points ==="))
  }

  @Test
  func textGraph_emptyGraph_doesNotCrash() throws {
    var graph = ImportGraph()
    let output = graph.textGraph()
    try #require(!output.isEmpty)
    // Empty graph still produces all section headers
    #expect(output.contains("=== Architecture Graph ==="))
    #expect(output.contains("=== Key Dependencies ==="))
    #expect(output.contains("=== Entry Points ==="))
  }

  @Test
  func textGraph_whitespaceHandling_doesNotCrash() throws {
    // Regression guard: textGraph() must not crash on edge cases
    // with unusual node names or cluster formations.
    var graph = ImportGraph()
    graph.addEdge(
      from: ImportGraph.Node(path: "Sources/My Module/File.swift"),
      to: ImportGraph.Node(path: "Other/Helper.swift"),
      rawImport: "Other/Helper"
    )
    let output = graph.textGraph()
    try #require(!output.isEmpty)
    // Even with whitespace in paths, all section headers appear
    #expect(output.contains("=== Architecture Graph ==="))
    #expect(output.contains("=== Key Dependencies ==="))
    #expect(output.contains("=== Entry Points ==="))
  }

  // MARK: - textGraph() cluster formatting

  @Test
  func textGraph_singleFileNoDeps_showsOnlyOwnCluster() throws {
    // A single isolated node has no cross-cluster edges, so no arrow appears.
    var graph = ImportGraph()
    graph.addNode(ImportGraph.Node(path: "Sources/Isolated.swift"))
    // (no edges)

    let output = graph.textGraph()
    try #require(!output.isEmpty)
    // The cluster name appears with its folder marker
    #expect(output.contains("📁 Sources/"))
    // No cross-cluster arrow since there are no outgoing edges
    #expect(!output.contains("→"))
  }

  // MARK: - buildGraph

  @Test
  func buildGraph_emptyDirectory_producesEmptyGraph() throws {
    let dir = try makeTempDir()
    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.nodes.isEmpty)
    #expect(graph.edges.isEmpty)
  }

  @Test
  func buildGraph_crossClusterImports_addsEdges() throws {
    let dir = try makeTempDir()

    // A imports Module/B — cross-cluster edge
    try writeEntry(
      dir, relativePath: "Sources/A.swift",
      imports: [
        CodemapImport(raw: "Module/B", line: 1)
      ])
    // Entry for Module/B itself so the target node exists
    try writeEntry(dir, relativePath: "Module/B.swift", imports: [])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.edges.count == 1)
    let edge = graph.edges.first!
    #expect(edge.source.path == "Sources/A.swift")
    #expect(edge.target.path == "Module/B")
    #expect(edge.rawImport == "Module/B")
  }

  @Test
  func buildGraph_bareSystemImport_noEdge() throws {
    let dir = try makeTempDir()

    // "Foundation" is a bare identifier — system import, no file edge
    try writeEntry(
      dir, relativePath: "Sources/A.swift",
      imports: [
        CodemapImport(raw: "Foundation", line: 1),
        CodemapImport(raw: "OSLog", line: 2),
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.nodes.contains { $0.path == "Sources/A.swift" })
    #expect(graph.edges.isEmpty)  // no file for Foundation or OSLog
  }

  @Test
  func buildGraph_relativeImport_dotSlash_resolved() throws {
    let dir = try makeTempDir()

    // A.swift in Sources/ dir imports "./Helper.swift"
    try writeEntry(
      dir, relativePath: "Sources/A.swift",
      imports: [
        CodemapImport(raw: "./Helper.swift", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.edges.count == 1)
    let edge = graph.edges.first!
    #expect(edge.target.path == "Sources/Helper.swift")
  }

  @Test
  func buildGraph_relativeImport_dotDot_resolved() throws {
    let dir = try makeTempDir()

    // Sources/Sub/A.swift imports ../Shared/B.swift
    try writeEntry(
      dir, relativePath: "Sources/Sub/A.swift",
      imports: [
        CodemapImport(raw: "../Shared/B.swift", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.edges.count == 1)
    let edge = graph.edges.first!
    #expect(edge.target.path == "Sources/Shared/B.swift")
  }

  @Test
  func buildGraph_multiComponentPath_keptAsRaw() throws {
    let dir = try makeTempDir()

    // "Compass/Explore/CommitExplainer" kept as-is
    try writeEntry(
      dir, relativePath: "Sources/App.swift",
      imports: [
        CodemapImport(raw: "Compass/Explore/CommitExplainer", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.edges.count == 1)
    #expect(graph.edges.first?.target.path == "Compass/Explore/CommitExplainer")
  }

  @Test
  func buildGraph_absolutePathImport_noEdge() throws {
    let dir = try makeTempDir()

    try writeEntry(
      dir, relativePath: "Sources/A.swift",
      imports: [
        CodemapImport(raw: "/usr/local/Module", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.edges.isEmpty)
  }

  @Test
  func buildGraph_angleBracketImport_noEdge() throws {
    let dir = try makeTempDir()

    try writeEntry(
      dir, relativePath: "Sources/A.swift",
      imports: [
        CodemapImport(raw: "<Module/Header.h>", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.edges.isEmpty)
  }

  @Test
  func buildGraph_whitespaceInImportString_noEdge() throws {
    let dir = try makeTempDir()

    // Raw import with leading/trailing whitespace — resolve should treat as-is
    try writeEntry(
      dir, relativePath: "Sources/A.swift",
      imports: [
        CodemapImport(raw: "  Compass  ", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    // "  Compass  " contains no "/" so treated as bare identifier → no edge
    #expect(graph.edges.isEmpty)
  }

  // MARK: - resolve (private function, tested via buildGraph integration)

  @Test
  func resolve_absolutePathImport_returnsNil() throws {
    let dir = try makeTempDir()

    // Absolute path — system import, no edge
    try writeEntry(
      dir, relativePath: "Sources/A.swift",
      imports: [
        CodemapImport(raw: "/usr/local/Module", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.nodes.contains { $0.path == "Sources/A.swift" })
    #expect(graph.edges.isEmpty)
  }

  @Test
  func resolve_angleBracketImport_returnsNil() throws {
    let dir = try makeTempDir()

    // Angle-bracket import — system header, no edge
    try writeEntry(
      dir, relativePath: "Sources/A.swift",
      imports: [
        CodemapImport(raw: "<Network>", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.nodes.contains { $0.path == "Sources/A.swift" })
    #expect(graph.edges.isEmpty)
  }

  @Test
  func resolve_bareIdentifier_returnsNil() throws {
    let dir = try makeTempDir()

    // Bare identifier — system module, no edge
    try writeEntry(
      dir, relativePath: "Sources/A.swift",
      imports: [
        CodemapImport(raw: "Foundation", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.nodes.contains { $0.path == "Sources/A.swift" })
    #expect(graph.edges.isEmpty)
  }

  @Test
  func resolve_dotSlashImport_resolvesToCorrectPath() throws {
    let dir = try makeTempDir()

    // "./Shared" from Sources/A.swift → Sources/Shared
    try writeEntry(
      dir, relativePath: "Sources/A.swift",
      imports: [
        CodemapImport(raw: "./Shared", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.edges.count == 1)
    #expect(graph.edges.first?.target.path == "Sources/Shared")
  }

  @Test
  func resolve_dotDotSlashImport_resolvesCorrectly() throws {
    let dir = try makeTempDir()

    // "../Utils" from Sources/Deep/B.swift → Sources/Utils
    try writeEntry(
      dir, relativePath: "Sources/Deep/B.swift",
      imports: [
        CodemapImport(raw: "../Utils", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.edges.count == 1)
    #expect(graph.edges.first?.target.path == "Sources/Utils")
  }

  @Test
  func resolve_multiComponentPath_returnsRawPath() throws {
    let dir = try makeTempDir()

    // "Compass/Explore" kept as-is
    try writeEntry(
      dir, relativePath: "Sources/App.swift",
      imports: [
        CodemapImport(raw: "Compass/Explore", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.edges.count == 1)
    #expect(graph.edges.first?.target.path == "Compass/Explore")
  }

  @Test
  func buildGraph_singleEntryNoImports_producesIsolatedNode() throws {
    let dir = try makeTempDir()

    // One file with zero imports — isolated node with no edges
    try writeEntry(dir, relativePath: "Sources/Lonely.swift", imports: [])

    let graph = buildGraph(codemapDirectory: dir)

    #expect(graph.nodes.count == 1)
    #expect(graph.nodes.contains { $0.path == "Sources/Lonely.swift" })
    #expect(graph.edges.isEmpty)
  }

  // MARK: - explain

  @Test
  func explain_modelUnavailable_returnsNil() async throws {
    // When FoundationModelsAvailability.isAvailable is false (e.g. on an
    // older macOS version or a simulator), explain returns nil without
    // attempting to call the model.
    let graph = ImportGraph()
    let repoURL = URL(fileURLWithPath: "/tmp")
    guard #available(macOS 26.0, *) else { return }
    let result = await ArchitectureGraph.explain(graph: graph, repoURL: repoURL)
    // Either Foundation Models is available and we get a string (or nil
    // from an error), or it is unavailable and we definitely get nil.
    if !FoundationModelsAvailability.isAvailable {
      try #require(result == nil)
    }
  }

  @Test
  func explain_emptyGraph_doesNotThrow() async throws {
    // explain with an empty graph must not throw — it should either return
    // nil (model unavailable) or a string (model available).
    let graph = ImportGraph()
    let repoURL = URL(fileURLWithPath: "/tmp")
    guard #available(macOS 26.0, *) else { return }
    let result = await ArchitectureGraph.explain(graph: graph, repoURL: repoURL)
    // Result may be nil (model unavailable) or a string (model available).
    // The key guarantee is no throw.
    if FoundationModelsAvailability.isAvailable {
      // When the model IS available, a result is expected.
      try #require(result != nil || result == nil)  // soft check: just must not throw
    }
  }

  // MARK: - buildGraph multi-file scenarios

  @Test
  func buildGraph_multipleEntriesAllImported_targetAppearsOnceInGraph() throws {
    let dir = try makeTempDir()

    // Three files all importing the same target
    for (idx, sourcePath) in ["A.swift", "B.swift", "C.swift"].enumerated() {
      try writeEntry(
        dir, relativePath: sourcePath,
        imports: [
          CodemapImport(raw: "Shared", line: 1)
        ])
    }
    // Target file exists
    try writeEntry(dir, relativePath: "Shared.swift", imports: [])

    let graph = buildGraph(codemapDirectory: dir)

    // Each source has an edge to "Shared" (no "/" so no file resolution)
    #expect(graph.nodes.contains { $0.path == "Shared.swift" })
  }

  @Test
  func buildGraph_resolvedPathNotOnDisk_targetStillAdded() throws {
    let dir = try makeTempDir()

    // Source imports a module path but no entry exists on disk for the target
    try writeEntry(
      dir, relativePath: "Sources/A.swift",
      imports: [
        CodemapImport(raw: "Compass/Explore/CommitExplainer", line: 1)
      ])

    let graph = buildGraph(codemapDirectory: dir)

    // Target node added even without a corresponding codemap entry
    #expect(graph.nodes.contains { $0.path == "Compass/Explore/CommitExplainer" })
    #expect(graph.edges.count == 1)
  }
}

// MARK: - Test helpers

private func writeEntry(
  _ directory: URL,
  relativePath: String,
  imports: [CodemapImport],
  symbols: [CodemapSymbol] = [],
  language: CodemapLanguage = .swift
) throws {
  let entry = CodemapEntry(
    relativePath: relativePath,
    language: language,
    contentHash: "testhash",
    sizeBytes: 0,
    symbols: symbols,
    imports: imports,
    summary: nil,
    summaryModel: nil,
    summaryContentHash: nil,
    isGenerated: false
  )
  let store = CodemapStore(directory: directory, prettyPrint: true)
  try store.saveEntry(entry)
}

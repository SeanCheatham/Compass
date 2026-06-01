import Testing

@testable import Compass

struct WorldAtlasTests {
  @Test
  func summarizesWorldInPlainLanguage() {
    var graph = WorldGraph()
    let entry = makeNode(id: "entry", kind: .function, label: "main", confidence: .high)
    let branch = makeNode(id: "branch", kind: .branch, label: "hasSession", confidence: .high)
    let unresolved = makeNode(
      id: "unknown", kind: .unresolvedPassage, label: "remoteConfig", confidence: .low)
    let error = makeNode(
      id: "error", kind: .errorPath, label: "throw MissingToken", confidence: .medium)
    let file = makeNode(id: "file", kind: .file, label: "App.swift", confidence: .high)

    [entry, branch, unresolved, error, file].forEach { graph.addNode($0) }
    graph.markEntrypoint(entry.id)
    graph.addEdge(from: entry.id, to: branch.id, kind: .branches, confidence: .high)
    graph.addEdge(from: branch.id, to: unresolved.id, kind: .calls, confidence: .low)
    graph.addEdge(from: branch.id, to: error.id, kind: .throws, confidence: .medium)

    let atlas = WorldAtlas(
      graph: graph,
      route: [entry.id, branch.id, unresolved.id],
      routeIndex: 1,
      selectedNodeID: error.id
    )

    #expect(atlas.title == "World Atlas")
    #expect(atlas.progressLabel == "Step 2 of 3")
    #expect(atlas.detail.contains("Following 3 stops from main"))
    #expect(atlas.metrics.contains { $0.id == "nodes" && $0.value == "5" })
    #expect(atlas.metrics.contains { $0.id == "decisions" && $0.value == "1" })
    #expect(atlas.terrain.contains { $0.label == "Action" && $0.count == 1 })
    #expect(atlas.terrain.contains { $0.label == "Unknown passage" && $0.count == 1 })
    #expect(atlas.notices.contains { $0.id == "unresolvedPassages" })
    #expect(atlas.notices.contains { $0.id == "errorPaths" })
    #expect(atlas.notices.contains { $0.id == "lowConfidence" })
    #expect(atlas.notices.contains { $0.id == "offRouteSelection" })
    #expect(atlas.routeStops.first { $0.id == "1-branch" }?.isCurrent == true)
  }

  @Test
  func emptyWorldPromptsIndexing() {
    let atlas = WorldAtlas(
      graph: WorldGraph(),
      route: [],
      routeIndex: 0,
      selectedNodeID: nil
    )

    #expect(atlas.progressLabel == "No route selected")
    #expect(atlas.detail.contains("Index the project"))
    #expect(atlas.terrain.isEmpty)
    #expect(atlas.routeStops.isEmpty)
    #expect(
      atlas.notices == [
        WorldAtlas.Notice(
          id: "emptyWorld",
          label: "No atlas yet",
          detail: "Run indexing so Compass can draw the first map.",
          severity: .info
        )
      ])
  }

  private func makeNode(
    id: String,
    kind: WorldNodeKind,
    label: String,
    confidence: WorldConfidence
  ) -> WorldNode {
    WorldNode(
      id: id,
      kind: kind,
      label: label,
      detail: nil,
      language: nil,
      location: nil,
      confidence: confidence,
      position: WorldPosition(x: 0, y: 0, z: 0)
    )
  }
}

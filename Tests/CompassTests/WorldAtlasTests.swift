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
    #expect(atlas.spotlight.title == "Now visiting hasSession")
    #expect(atlas.spotlight.detail == "Decision - step 2 of 3")
    #expect(atlas.spotlight.tone == .ready)
    #expect(atlas.metrics.contains { $0.id == "nodes" && $0.value == "5" })
    #expect(atlas.metrics.contains { $0.id == "decisions" && $0.value == "1" })
    #expect(atlas.terrain.contains { $0.label == "Action" && $0.count == 1 })
    #expect(atlas.terrain.contains { $0.label == "Unknown passage" && $0.count == 1 })
    #expect(atlas.notices.contains { $0.id == "unresolvedPassages" })
    #expect(atlas.notices.contains { $0.id == "errorPaths" })
    #expect(atlas.notices.contains { $0.id == "lowConfidence" })
    #expect(atlas.notices.contains { $0.id == "offRouteSelection" })
    #expect(atlas.routeStops.first { $0.id == "1-branch" }?.isCurrent == true)
    #expect(!atlas.narrationIdentifier.isEmpty)
  }

  @Test
  func clipboardPayloadPackagesWorldForReuse() {
    var graph = WorldGraph()
    let entry = makeNode(id: "entry", kind: .function, label: "main", confidence: .high)
    let branch = makeNode(id: "branch", kind: .branch, label: "hasSession", confidence: .high)
    let unresolved = makeNode(
      id: "unknown", kind: .unresolvedPassage, label: "remoteConfig", confidence: .low)
    let error = makeNode(
      id: "error", kind: .errorPath, label: "throw MissingToken", confidence: .medium)

    [entry, branch, unresolved, error].forEach { graph.addNode($0) }
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
    let narration = WorldAtlasNarration(
      atlasIdentifier: atlas.narrationIdentifier,
      text: "Start at main, then inspect the session decision."
    )

    let payload = WorldAtlasClipboardPayload(atlas: atlas, narration: narration)

    #expect(!payload.isEmpty)
    #expect(payload.text.contains("Compass World Atlas Handoff"))
    #expect(payload.text.contains("Progress: Step 2 of 3"))
    #expect(payload.text.contains("Spotlight: Now visiting hasSession"))
    #expect(payload.text.contains("On-device guide:"))
    #expect(payload.text.contains("Start at main"))
    #expect(payload.text.contains("- danger: 1 Error path"))
    #expect(payload.text.contains("- Current: hasSession - Decision - step 2 of 3"))
    #expect(payload.text.count <= WorldAtlasClipboardPayload.textLimit)
  }

  @Test
  func clipboardPayloadCoversEmptyWorld() {
    let atlas = WorldAtlas(
      graph: WorldGraph(),
      route: [],
      routeIndex: 0,
      selectedNodeID: nil
    )

    let payload = WorldAtlasClipboardPayload(atlas: atlas)

    #expect(!payload.isEmpty)
    #expect(payload.text.contains("No terrain available yet."))
    #expect(payload.text.contains("No guided walk selected."))
    #expect(payload.text.count <= WorldAtlasClipboardPayload.textLimit)
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
    #expect(atlas.spotlight.title == "Build the map")
    #expect(atlas.spotlight.tone == .neutral)
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

  @Test
  func narrationIdentifierChangesWithRouteProgress() {
    let graph = makeNarrationGraph()
    let first = WorldAtlas(
      graph: graph,
      route: ["entry", "branch"],
      routeIndex: 0,
      selectedNodeID: "entry"
    )
    let second = WorldAtlas(
      graph: graph,
      route: ["entry", "branch"],
      routeIndex: 1,
      selectedNodeID: "branch"
    )

    #expect(first.narrationIdentifier != second.narrationIdentifier)
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalPolish() async throws {
    let atlas = WorldAtlas(
      graph: makeNarrationGraph(),
      route: ["entry", "branch"],
      routeIndex: 1,
      selectedNodeID: "branch"
    )

    try await withMockFoundationModels(
      response: "Start at main, then inspect the session decision."
    ) {
      let generatedNarration = await WorldAtlasNarrator.narrate(atlas: atlas)
      let narration = try #require(generatedNarration)
      #expect(narration.atlasIdentifier == atlas.narrationIdentifier)
      #expect(narration.text == "Start at main, then inspect the session decision.")
    }

    try await withMockFoundationModels(available: false) {
      let narration = await WorldAtlasNarrator.narrate(atlas: atlas)
      #expect(narration == nil)
    }
  }

  @Test
  func narratorRejectsStructuredOrLinkedOutput() async throws {
    let atlas = WorldAtlas(
      graph: makeNarrationGraph(),
      route: ["entry", "branch"],
      routeIndex: 1,
      selectedNodeID: "branch"
    )

    try await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await WorldAtlasNarrator.narrate(atlas: atlas)
      #expect(narration == nil)
    }

    try await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await WorldAtlasNarrator.narrate(atlas: atlas)
      #expect(narration == nil)
    }
  }

  @Test
  func tourScriptPackagesNarrationAndCurrentRouteStop() {
    var graph = WorldGraph()
    let entry = WorldNode(
      id: "entry",
      kind: .function,
      label: "main",
      detail: "Application entrypoint",
      language: .swift,
      location: WorldSourceLocation(filePath: "Sources/App.swift", line: 1, endLine: 4),
      confidence: .high,
      position: .zero
    )
    let branch = WorldNode(
      id: "branch",
      kind: .branch,
      label: "hasSession",
      detail: "if session exists",
      language: .swift,
      location: WorldSourceLocation(filePath: "Sources/App.swift", line: 3, endLine: 3),
      confidence: .high,
      position: .zero
    )
    graph.addNode(entry)
    graph.addNode(branch)
    graph.markEntrypoint(entry.id)
    graph.addEdge(from: entry.id, to: branch.id, kind: .branches, confidence: .high)

    let atlas = WorldAtlas(
      graph: graph,
      route: [entry.id, branch.id],
      routeIndex: 1,
      selectedNodeID: branch.id
    )
    let narration = WorldAtlasNarration(
      atlasIdentifier: atlas.narrationIdentifier,
      text: "Start at main, then inspect the session decision."
    )

    let script = WorldTourScript(
      graph: graph,
      atlas: atlas,
      route: [entry.id, branch.id],
      routeIndex: 1,
      selectedNodeID: branch.id,
      narration: narration
    )

    #expect(script.id == atlas.narrationIdentifier)
    #expect(script.overview == narration.text)
    #expect(script.progressLabel == "Step 2 of 2")
    #expect(script.steps.count == 2)
    #expect(script.currentStep?.nodeID == branch.id)
    #expect(script.currentStep?.sceneCue == .decision)
    #expect(script.currentStep?.filePath == "Sources/App.swift")
    #expect(script.currentStep?.lineLabel == "L3")
    #expect(script.currentStep?.narration.contains("Step 2 of 2 visits hasSession") == true)
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

  private func makeNarrationGraph() -> WorldGraph {
    var graph = WorldGraph()
    let entry = makeNode(id: "entry", kind: .function, label: "main", confidence: .high)
    let branch = makeNode(id: "branch", kind: .branch, label: "hasSession", confidence: .high)
    graph.addNode(entry)
    graph.addNode(branch)
    graph.markEntrypoint(entry.id)
    graph.addEdge(from: entry.id, to: branch.id, kind: .branches, confidence: .high)
    return graph
  }
}

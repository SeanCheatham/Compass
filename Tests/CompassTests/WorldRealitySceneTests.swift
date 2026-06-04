import Foundation
import RealityKit
import Testing

@testable import Compass

@MainActor
struct WorldRealitySceneTests {
  @Test
  func realityKitSceneBuildsWithoutExecutionTraces() throws {
    var graph = WorldGraph()
    let entry = WorldNode(
      id: "entry",
      kind: .function,
      label: "main",
      detail: nil,
      language: .swift,
      location: WorldSourceLocation(filePath: "Sources/App.swift", line: 1, endLine: 3),
      confidence: .high,
      position: WorldPosition(x: 0, y: 0.8, z: 0)
    )
    let branch = WorldNode(
      id: "branch",
      kind: .branch,
      label: "Branch L2",
      detail: "if ready",
      language: .swift,
      location: WorldSourceLocation(filePath: "Sources/App.swift", line: 2, endLine: 2),
      confidence: .high,
      position: WorldPosition(x: 1.2, y: 1.1, z: -2.4)
    )
    let exit = WorldNode(
      id: "exit",
      kind: .function,
      label: "finish",
      detail: nil,
      language: .swift,
      location: WorldSourceLocation(filePath: "Sources/App.swift", line: 4, endLine: 4),
      confidence: .high,
      position: WorldPosition(x: 2.2, y: 0.9, z: -3.4)
    )
    graph.addNode(entry)
    graph.addNode(branch)
    graph.addNode(exit)
    graph.markEntrypoint(entry.id)
    graph.addEdge(from: entry.id, to: branch.id, kind: .branches, confidence: .high)
    graph.addEdge(from: branch.id, to: exit.id, kind: .calls, confidence: .high)

    let scene = WorldRealitySceneFactory.makeScene(
      graph: graph,
      selectedNodeID: branch.id,
      route: [entry.id, branch.id, exit.id],
      routeIndex: 1
    )

    #expect(scene.name == "CompassWorldRoot")
    #expect(scene.children.count > 0)
    #expect(scene.findEntity(named: "WorldCamera") != nil)
    #expect(scene.findEntity(named: "WorldTerrainPlate") != nil)
    #expect(scene.findEntity(named: "WorldSkyVault") != nil)
    #expect(scene.findEntity(named: "WorldHorizonGlow") != nil)
    #expect(scene.findEntity(named: "WorldFocusLightPool") != nil)
    #expect(scene.findEntity(named: "WorldRouteRibbon") != nil)
    #expect(scene.findEntity(named: "WorldChamberPlinth-branch") != nil)
    #expect(scene.findEntity(named: "WorldChamberLightWell-branch") != nil)
    #expect(scene.findEntity(named: "WorldBranchGateLintel-branch") != nil)
    #expect(scene.findEntity(named: "WorldRouteBeacon-entry") != nil)
    #expect(scene.findEntity(named: "WorldRouteBeacon-branch") != nil)
    #expect(scene.findEntity(named: "WorldRouteBeaconVisited-entry") != nil)
    #expect(scene.findEntity(named: "WorldRouteBeaconActive-branch") != nil)
    #expect(scene.findEntity(named: "WorldRoutePortalActive-branch") != nil)
    #expect(scene.findEntity(named: "WorldRouteBeaconStep-1") != nil)
    #expect(scene.findEntity(named: "WorldRouteBeaconStep-2") != nil)
    #expect(scene.findEntity(named: "WorldRouteBeacon-exit") == nil)
    #expect(scene.findEntity(named: "WorldRouteBeaconStep-3") == nil)
  }

  @Test
  func realityKitSceneProjectsLiveActivityIntoWorldMarkers() throws {
    var graph = WorldGraph()
    let entry = WorldNode(
      id: "entry",
      kind: .file,
      label: "App.swift",
      detail: nil,
      language: .swift,
      location: WorldSourceLocation(filePath: "Sources/App.swift", line: 1, endLine: 12),
      confidence: .high,
      position: WorldPosition(x: 0, y: 0.25, z: 0)
    )
    let rustNode = WorldNode(
      id: "rust-runner",
      kind: .function,
      label: "verify",
      detail: nil,
      language: .rust,
      location: WorldSourceLocation(filePath: "src/main.rs", line: 8, endLine: 16),
      confidence: .high,
      position: WorldPosition(x: 1.4, y: 0.8, z: -2.2)
    )
    graph.addNode(entry)
    graph.addNode(rustNode)
    graph.markEntrypoint(entry.id)
    graph.addEdge(from: entry.id, to: rustNode.id, kind: .calls, confidence: .high)

    let liveLog = [
      LiveLine(
        level: .raw,
        text: "cargo_test · cargo test --workspace",
        detail: "running cargo test",
        kind: .command,
        status: .running
      ),
      LiveLine(
        level: .success,
        text: "edit_file · Sources/App.swift",
        detail: "patched startup flow",
        kind: .fileChange,
        status: .completed
      ),
    ]
    let activity = WorldLiveActivityProjection(graph: graph, liveLog: liveLog)

    #expect(activity.events.first?.operation == .fileEdit)
    #expect(activity.events.first?.targetNodeID == entry.id)
    #expect(activity.events.dropFirst().first?.operation == .rust)

    let scene = WorldRealitySceneFactory.makeScene(
      graph: graph,
      selectedNodeID: entry.id,
      route: [entry.id, rustNode.id],
      routeIndex: 0,
      activityEvents: activity.sceneEvents
    )

    #expect(scene.findEntity(named: "WorldLiveTargetPulse-fileEdit-0") != nil)
    #expect(scene.findEntity(named: "WorldLiveTargetBeam") != nil)
    #expect(scene.findEntity(named: "WorldLiveGlobalBeacon-rust-1") != nil)
    #expect(scene.findEntity(named: "WorldRustOperationTooth-0") != nil)
  }
}

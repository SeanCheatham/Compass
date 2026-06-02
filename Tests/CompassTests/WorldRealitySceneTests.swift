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
}

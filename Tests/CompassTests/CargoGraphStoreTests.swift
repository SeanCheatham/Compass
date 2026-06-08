import Foundation
import Testing

@testable import Compass

struct CargoGraphStoreTests {
  @Test func roundTripsSnapshotUnderCompassDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "CargoGraphStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = root.appending(path: "repo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    try "[workspace]\n".write(
      to: repo.appending(path: "Cargo.toml"),
      atomically: true,
      encoding: .utf8
    )
    let workspace = CompassWorkspace(repoURL: repo)
    let graph = CargoGraphData(
      workspaceRoot: "Cargo.toml",
      members: [
        CargoGraphMember(
          name: "app-core",
          manifestPath: "crates/app-core/Cargo.toml",
          kind: "lib",
          packageDir: "crates/app-core",
          srcRoot: "crates/app-core/src",
          dependencies: [],
          features: CargoGraphFeatures(default: [], named: [:])
        )
      ],
      edges: []
    )
    let store = CargoGraphStore()
    let snapshot = store.makeSnapshot(
      graph: graph,
      workspace: workspace,
      generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    try store.save(snapshot, workspace: workspace)
    let loaded = try #require(store.load(from: workspace))

    #expect(loaded == snapshot)
    #expect(
      FileManager.default.fileExists(
        atPath: workspace.compassURL.appending(path: "cargo-graph.json").path))
  }
}

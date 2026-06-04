import Foundation
import Testing

@testable import Compass

struct AgentWorkspaceOutlineToolTests {
  @Test func formatsCachedWorkspaceOutline() async throws {
    let fixture = try WorkspaceOutlineFixture()
    defer { fixture.cleanup() }
    try fixture.writeCachedGraph()

    let result = try await AgentWorkspaceOutlineTool().invoke(
      arguments: Data(#"{}"#.utf8),
      context: fixture.context()
    )

    #expect(!result.isError)
    #expect(result.content.contains("members: 1"))
    #expect(result.content.contains("app-core [lib]"))
  }

  @Test func refreshesThroughRustCargoServiceWhenRequested() async throws {
    let fixture = try WorkspaceOutlineFixture()
    defer { fixture.cleanup() }
    let service = FakeRustCargoService(data: fixture.engineResponseData())

    let result = try await AgentWorkspaceOutlineTool().invoke(
      arguments: Data(#"{"refresh":true}"#.utf8),
      context: fixture.context(rustCargoService: service)
    )
    let calls = await service.calls

    #expect(!result.isError)
    #expect(calls.map(\.command) == [.workspaceOutline])
    #expect(CargoGraphStore().load(from: fixture.workspace) != nil)
  }
}

private struct WorkspaceOutlineFixture {
  let root: URL
  let repo: URL
  let workspace: CompassWorkspace
  let graph: CargoGraphData

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "AgentWorkspaceOutlineToolTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    repo = root.appending(path: "repo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    workspace = CompassWorkspace(repoURL: repo)
    graph = CargoGraphData(
      workspaceRoot: "Cargo.toml",
      members: [
        CargoGraphMember(
          name: "app-core",
          manifestPath: "crates/app-core/Cargo.toml",
          kind: "lib",
          packageDir: "crates/app-core",
          srcRoot: "crates/app-core/src",
          dependencies: [
            CargoGraphDependency(
              name: "serde",
              kind: "external",
              version: "1",
              path: nil,
              features: []
            )
          ],
          features: CargoGraphFeatures(default: [], named: ["extra": []])
        )
      ],
      edges: []
    )
  }

  func cleanup() {
    try? FileManager.default.removeItem(at: root)
  }

  func writeCachedGraph() throws {
    let store = CargoGraphStore()
    try store.save(
      store.makeSnapshot(
        graph: graph,
        workspace: workspace,
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      ),
      workspace: workspace
    )
  }

  func context(rustCargoService: (any RustCargoServicing)? = nil) -> AgentToolContext {
    AgentToolContext(
      workingDirectory: repo,
      codemapStoreDirectory: workspace.compassURL.appending(path: "codemap", directoryHint: .isDirectory),
      rustCargoService: rustCargoService
    )
  }

  func engineResponseData() -> Data {
    let response = RustEngineResponse(
      schemaVersion: 1,
      command: "workspace-outline",
      ok: true,
      data: graph,
      errors: []
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try! encoder.encode(response)
  }
}

private actor FakeRustCargoService: RustCargoServicing {
  struct Call: Equatable {
    var command: RustEngineCommand
    var repoURL: URL
    var arguments: [String]
    var timeout: TimeInterval
  }

  let data: Data
  private(set) var calls: [Call] = []

  init(data: Data) {
    self.data = data
  }

  func run(
    command: RustEngineCommand,
    repoURL: URL,
    arguments: [String],
    timeout: TimeInterval
  ) async throws -> Data {
    calls.append(Call(command: command, repoURL: repoURL, arguments: arguments, timeout: timeout))
    return data
  }
}

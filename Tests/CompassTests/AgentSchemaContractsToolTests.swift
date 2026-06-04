import Foundation
import Testing

@testable import Compass

struct AgentSchemaContractsToolTests {
  @Test func schemaContractsToolFormatsCachedMappings() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "AgentSchemaContractsToolTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = root.appending(path: "repo", directoryHint: .isDirectory)
    let workspace = CompassWorkspace(repoURL: repo)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    let contracts = SchemaContractsData(
      schemaVersion: 1,
      contracts: [
        SchemaContract(
          schemaPath: "schemas/demo-state.schema.json",
          schemaTitle: "DemoState",
          rustType: "DemoState",
          rustFile: "crates/app-core/src/state.rs",
          line: 5,
          confidence: "high",
          fieldMapping: [
            SchemaFieldMapping(schemaField: "count", rustField: "count")
          ]
        )
      ]
    )
    try SchemaContractsStore().save(contracts, workspace: workspace)

    let result = try await AgentSchemaContractsTool().invoke(
      arguments: Data(#"{"type":"DemoState"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: repo,
        codemapStoreDirectory: workspace.compassURL.appending(path: "codemap", directoryHint: .isDirectory)
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("schemas/demo-state.schema.json"))
    #expect(result.content.contains("DemoState @ crates/app-core/src/state.rs:5"))
    #expect(result.content.contains("count->count"))
  }
}

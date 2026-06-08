import Foundation
import Testing

@testable import Compass

struct AgentRustIndexToolsTests {
  @Test func findImplsAndTraitUsersReadTraitIndex() async throws {
    let fixture = try RustIndexToolFixture()
    defer { fixture.cleanup() }
    try fixture.writeIndexes()

    let impls = try await AgentFindImplsTool().invoke(
      arguments: Data(#"{"trait":"Display"}"#.utf8),
      context: fixture.context()
    )
    let users = try await AgentTraitUsersTool().invoke(
      arguments: Data(#"{"trait":"Display"}"#.utf8),
      context: fixture.context()
    )

    #expect(!impls.isError)
    #expect(impls.content.contains("impl Display for DemoState"))
    #expect(!users.isError)
    #expect(users.content.contains("DemoState"))
  }

  @Test func importersOfUsesRustModuleIncomingEdges() async throws {
    let fixture = try RustIndexToolFixture()
    defer { fixture.cleanup() }
    try fixture.writeIndexes()
    try fixture.writeCodemapEntries()

    let result = try await AgentImportersOfTool().invoke(
      arguments: Data(#"{"path":"crates/app-core/src/lib.rs"}"#.utf8),
      context: fixture.context()
    )

    #expect(!result.isError)
    #expect(result.content.contains("crates/app-cli/src/main.rs:1"))
  }
}

private struct RustIndexToolFixture {
  let root: URL
  let repo: URL
  let workspace: CompassWorkspace

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "AgentRustIndexToolsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    repo = root.appending(path: "repo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    workspace = CompassWorkspace(repoURL: repo)
  }

  func cleanup() {
    try? FileManager.default.removeItem(at: root)
  }

  func context() -> AgentToolContext {
    AgentToolContext(
      workingDirectory: repo,
      codemapStoreDirectory: workspace.compassURL.appending(
        path: "codemap", directoryHint: .isDirectory)
    )
  }

  func writeIndexes() throws {
    let module = RustModuleIndex(
      schemaVersion: 1,
      files: [
        "crates/app-core/src/lib.rs": RustModuleFile(
          modulePath: "app_core",
          outgoing: [],
          incoming: [
            RustModuleEdge(
              toFile: nil,
              fromFile: "crates/app-cli/src/main.rs",
              raw: "use app_core::DemoState;",
              line: 1
            )
          ]
        )
      ]
    )
    let trait = RustTraitIndex(
      schemaVersion: 1,
      impls: [
        RustTraitImpl(
          traitName: "Display",
          typeName: "DemoState",
          file: "crates/app-core/src/lib.rs",
          line: 6,
          implStartLine: 6
        )
      ],
      byTrait: ["Display": ["DemoState"]],
      byType: ["DemoState": ["Display"]]
    )
    try RustCodemapEnricher.save(
      RustIndexData(moduleIndex: module, traitIndex: trait, warnings: []),
      workspace: workspace
    )
  }

  func writeCodemapEntries() throws {
    let store = CodemapStore(
      directory: workspace.compassURL.appending(path: "codemap", directoryHint: .isDirectory))
    try store.saveEntry(
      CodemapEntry(
        relativePath: "crates/app-core/src/lib.rs",
        language: .rust,
        contentHash: "core",
        sizeBytes: 1,
        symbols: [],
        imports: [],
        summary: nil,
        summaryModel: nil,
        summaryContentHash: nil,
        isGenerated: false
      )
    )
    try store.saveEntry(
      CodemapEntry(
        relativePath: "crates/app-cli/src/main.rs",
        language: .rust,
        contentHash: "cli",
        sizeBytes: 1,
        symbols: [],
        imports: [CodemapImport(raw: "app_core::DemoState", line: 1)],
        summary: nil,
        summaryModel: nil,
        summaryContentHash: nil,
        isGenerated: false
      )
    )
  }
}

import Foundation
import Testing

@testable import Compass

struct AgentToolchainToolsTests {

  @Test func testListToolchainsWithoutServiceExplainsHostRoute() async throws {
    let tool = AgentListToolchainsTool()
    let context = AgentToolContext(workingDirectory: URL(fileURLWithPath: "/tmp/work"))
    let result = try await tool.invoke(arguments: Data("{}".utf8), context: context)
    try #require(!result.isError)
    try #require(result.content.contains("native macOS host"))
  }

  @Test func testListToolchainsFormatsStatuses() async throws {
    let service = FakeToolchainService(
      statuses: [
        ToolchainStatus(
          id: "rust",
          displayName: "Rust",
          description: "Rust toolchain",
          installed: false,
          defaultProvisioned: false
        )
      ]
    )
    let tool = AgentListToolchainsTool()
    let context = AgentToolContext(
      workingDirectory: URL(fileURLWithPath: "/tmp/work"),
      toolchainService: service
    )
    let result = try await tool.invoke(arguments: Data("{}".utf8), context: context)
    try #require(!result.isError)
    try #require(result.content.contains("rust"))
    try #require(result.content.contains("missing"))
  }

  @Test func testInstallToolchainRejectsUnknownID() async throws {
    let service = FakeToolchainService(statuses: [])
    let tool = AgentInstallToolchainTool()
    let context = AgentToolContext(
      workingDirectory: URL(fileURLWithPath: "/tmp/work"),
      toolchainService: service
    )
    let args = Data(#"{"id":"unknown"}"#.utf8)
    let result = try await tool.invoke(arguments: args, context: context)
    try #require(result.isError)
    try #require(result.content.contains("Unknown toolchain"))
  }

  @Test func testInstallToolchainReportsAlreadyInstalled() async throws {
    let service = FakeToolchainService(
      statuses: [],
      installHandler: { id in
        SharedCompassVMToolchainManager.InstallReport(
          toolchainID: id,
          alreadyInstalled: true,
          logTail: ""
        )
      }
    )
    let tool = AgentInstallToolchainTool()
    let context = AgentToolContext(
      workingDirectory: URL(fileURLWithPath: "/tmp/work"),
      toolchainService: service
    )
    let args = Data(#"{"id":"rust"}"#.utf8)
    let result = try await tool.invoke(arguments: args, context: context)
    try #require(!result.isError)
    try #require(result.content.contains("already installed"))
  }

  @Test func testInstallToolchainAcceptsCommonAliasArguments() async throws {
    let service = FakeToolchainService(
      statuses: [],
      installHandler: { id in
        SharedCompassVMToolchainManager.InstallReport(
          toolchainID: id,
          alreadyInstalled: true,
          logTail: ""
        )
      }
    )
    let tool = AgentInstallToolchainTool()
    let context = AgentToolContext(
      workingDirectory: URL(fileURLWithPath: "/tmp/work"),
      toolchainService: service
    )
    let result = try await tool.invoke(
      arguments: Data(#"{"toolchain_id":"rust"}"#.utf8),
      context: context
    )
    try #require(!result.isError)
    try #require(result.content.contains("Toolchain rust is already installed"))
  }

  @Test func testToolRegistryIncludesToolchainToolsWhenServiceProvided() throws {
    let service = FakeToolchainService(statuses: [])
    let names = Set(
      ToolRegistry.tools(for: .develop, settings: AgentRuntimeSettings(), toolchainService: service)
        .map { $0.spec.name }
    )
    try #require(names.contains("list_toolchains"))
    try #require(names.contains("install_toolchain"))
  }

  @Test func testToolRegistryOmitsToolchainToolsOnHostRoute() throws {
    let names = Set(ToolRegistry.tools(for: .develop).map { $0.spec.name })
    try #require(!names.contains("list_toolchains"))
    try #require(!names.contains("install_toolchain"))
  }
}

private struct FakeToolchainService: SharedVMToolchainService {
  var statuses: [ToolchainStatus]
  var installHandler: (@Sendable (String) throws -> SharedCompassVMToolchainManager.InstallReport)?

  func listToolchains(runner: any AgentBashRunner) async throws -> [ToolchainStatus] {
    statuses
  }

  func installToolchain(
    id: String,
    runner: any AgentBashRunner,
    progress: @Sendable (Double) async -> Void
  ) async throws -> SharedCompassVMToolchainManager.InstallReport {
    if let installHandler {
      return try installHandler(id)
    }
    throw SharedCompassVMToolchainManager.ManagerError.unknownToolchainID(id)
  }
}

import Foundation
import Testing

@testable import Compass

struct AgentRustVerifyToolsTests {
  @Test func scaffoldCheckFormatsFailedChecks() async throws {
    let service = FakeRustVerifyService(
      data: encodeVerifyEnvelope(
        command: "scaffold-check",
        data: ScaffoldCheckData(
          status: "fail",
          scaffoldVersion: 1,
          capabilities: ScaffoldCapabilities(
            xtaskVerify: true,
            visualVerify: true,
            schemaContracts: true,
            desktopHandshake: true
          ),
          checks: [
            ScaffoldCheck(
              id: "member_crates_app_cli",
              status: "fail",
              message: "required member crates/app-cli is missing.",
              path: "crates/app-cli/Cargo.toml"
            ),
            ScaffoldCheck(
              id: "workspace_manifest",
              status: "pass",
              message: "root Cargo.toml declares a workspace.",
              path: "Cargo.toml"
            ),
          ]
        )
      )
    )
    let result = try await AgentScaffoldCheckTool().invoke(
      arguments: Data(#"{}"#.utf8),
      context: AgentToolContext(
        workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        rustCargoService: service
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("scaffold-check: fail"))
    #expect(result.content.contains("member_crates_app_cli"))
    #expect(result.content.contains("crates/app-cli/Cargo.toml"))
  }

  @Test func coverageGapsFormatsOverallPercent() async throws {
    let service = FakeRustVerifyService(
      data: encodeVerifyEnvelope(
        command: "coverage-gaps",
        data: CoverageGapsData(
          overallLinePercent: 72.5,
          files: [],
          logTail: "summary"
        )
      )
    )
    let result = try await AgentCoverageGapsTool().invoke(
      arguments: Data(#"{}"#.utf8),
      context: AgentToolContext(
        workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        rustCargoService: service
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("72.5%"))
  }

  @Test func visualVerifyFormatsScreenshotPath() async throws {
    let service = FakeRustVerifyService(
      data: encodeVerifyEnvelope(
        command: "visual-verify",
        data: VisualVerifyData(
          ok: true,
          screenshotPath: ".compass/visual-verify/latest.png",
          logTail: "ok"
        )
      )
    )
    let result = try await AgentVisualVerifyTool().invoke(
      arguments: Data(#"{}"#.utf8),
      context: AgentToolContext(
        workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        rustCargoService: service
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains(".compass/visual-verify/latest.png"))
  }

  @Test func registryAddsScaffoldCheckOnlyWhenRustServiceExists() throws {
    let defaultNames = Set(ToolRegistry.tools(for: .critic).map(\.spec.name))
    let service = FakeRustVerifyService(
      data: encodeVerifyEnvelope(
        command: "scaffold-check",
        data: ScaffoldCheckData(
          status: "pass",
          scaffoldVersion: 1,
          capabilities: ScaffoldCapabilities(
            xtaskVerify: true,
            visualVerify: true,
            schemaContracts: true,
            desktopHandshake: true
          ),
          checks: []
        )
      )
    )
    let enabledNames = Set(
      ToolRegistry.tools(
        for: .critic,
        settings: AgentRuntimeSettings(),
        rustCargoService: service
      ).map(\.spec.name)
    )

    #expect(!defaultNames.contains(AgentScaffoldCheckTool.toolName))
    #expect(enabledNames.contains(AgentScaffoldCheckTool.toolName))
    #expect(!enabledNames.contains(AgentVisualVerifyTool.toolName))
  }
}

private func encodeVerifyEnvelope<T: Codable & Equatable>(command: String, data: T) -> Data {
  let response = RustEngineResponse(
    schemaVersion: 1,
    command: command,
    ok: true,
    data: data,
    errors: []
  )
  return try! JSONEncoder().encode(response)
}

private actor FakeRustVerifyService: RustCargoServicing {
  let data: Data

  init(data: Data) {
    self.data = data
  }

  func run(
    command: RustEngineCommand,
    repoURL: URL,
    arguments: [String],
    timeout: TimeInterval
  ) async throws -> Data {
    data
  }
}

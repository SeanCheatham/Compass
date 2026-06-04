import Foundation
import Testing

@testable import Compass

struct AgentCargoDiagnosticToolTests {
  @Test func cargoCheckFormatsStructuredDiagnostics() async throws {
    let service = FakeRustDiagnosticsService(data: diagnosticEnvelope(command: "cargo-check"))
    let result = try await AgentCargoCheckTool().invoke(
      arguments: Data(#"{"package":"app-core","timeoutMs":5000}"#.utf8),
      context: AgentToolContext(
        workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        rustCargoService: service
      )
    )
    let calls = await service.calls

    #expect(!result.isError)
    #expect(result.content.contains("cargo-check: exit 101"))
    #expect(result.content.contains("[E0425]"))
    #expect(calls.first?.command == .cargoCheck)
    #expect(calls.first?.arguments == ["--package", "app-core"])
  }

  @Test func cargoCheckFormatsAuditMetadataWhenPresent() async throws {
    let service = FakeRustDiagnosticsService(
      data: diagnosticEnvelope(
        command: "cargo-check",
        audit: RustEngineAudit(
          repo: "/tmp/repo",
          argv: ["cargo", "check", "--workspace", "--message-format=json", "--all-features"],
          durationMs: 77,
          toolchain: RustEngineToolchain(rustc: nil, cargo: "cargo 1.91.0")
        ),
        repairHints: [
          RustRepairHint(
            id: "missing-cargo-manifest",
            severity: "error",
            message: "Cargo.toml is missing from the repository root.",
            suggestedCommand: "cargo init --lib"
          )
        ]
      )
    )
    let result = try await AgentCargoCheckTool().invoke(
      arguments: Data(#"{}"#.utf8),
      context: AgentToolContext(
        workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        rustCargoService: service
      )
    )

    #expect(!result.isError)
    #expect(
      result.content.contains(
        "audit argv: cargo check --workspace --message-format=json --all-features"))
    #expect(result.content.contains("audit duration: 77ms"))
    #expect(result.content.contains("Repair hints:"))
    #expect(result.content.contains("missing-cargo-manifest"))
    #expect(result.content.contains("suggested: cargo init --lib"))
  }


  @Test func cargoTestFormatsFailures() async throws {
    let payload = CargoTestData(
      exitCode: 101,
      passed: 2,
      failed: 1,
      failures: [
        CargoTestFailure(
          testName: "state_roundtrip",
          message: "thread 'state_roundtrip' panicked",
          file: "crates/app-core/tests/state_tests.rs",
          line: 10
        )
      ]
    )
    let service = FakeRustDiagnosticsService(data: encodeEnvelope(command: "cargo-test", data: payload))
    let result = try await AgentCargoTestTool().invoke(
      arguments: Data(#"{"filter":"state","all_features":true}"#.utf8),
      context: AgentToolContext(
        workingDirectory: URL(fileURLWithPath: "/tmp/repo"),
        rustCargoService: service
      )
    )
    let calls = await service.calls

    #expect(!result.isError)
    #expect(result.content.contains("passed: 2, failed: 1"))
    #expect(result.content.contains("state_roundtrip"))
    #expect(calls.first?.command == .cargoTest)
    #expect(calls.first?.arguments == ["--filter", "state", "--all-features"])
  }

  @Test func registryAddsRustDiagnosticToolsOnlyWhenServiceExists() throws {
    let defaultNames = Set(ToolRegistry.tools(for: .develop).map(\.spec.name))
    let service = FakeRustDiagnosticsService(data: diagnosticEnvelope(command: "cargo-check"))
    let enabledNames = Set(
      ToolRegistry.tools(
        for: .develop,
        settings: AgentRuntimeSettings(),
        rustCargoService: service
      ).map(\.spec.name)
    )

    #expect(!defaultNames.contains(AgentCargoCheckTool.toolName))
    #expect(enabledNames.contains(AgentCargoCheckTool.toolName))
    #expect(enabledNames.contains(AgentClippyLintTool.toolName))
    #expect(enabledNames.contains(AgentCargoTestTool.toolName))
  }
}

private func diagnosticEnvelope(
  command: String,
  audit: RustEngineAudit? = nil,
  repairHints: [RustRepairHint] = []
) -> Data {
  encodeEnvelope(
    command: command,
    audit: audit,
    repairHints: repairHints,
    data: CargoCheckData(
      exitCode: 101,
      diagnostics: [
        RustDiagnostic(
          level: "error",
          code: "E0425",
          message: "cannot find value `missing_value` in this scope",
          package: "app-core",
          file: "crates/app-core/src/lib.rs",
          line: 2,
          column: 5,
          label: nil,
          rendered: nil
        )
      ],
      summary: RustDiagnosticSummary(errors: 1, warnings: 0, cratesAffected: ["app-core"])
    )
  )
}

private func encodeEnvelope<T: Codable & Equatable>(
  command: String,
  audit: RustEngineAudit? = nil,
  repairHints: [RustRepairHint] = [],
  data: T
) -> Data {
  let response = RustEngineResponse(
    schemaVersion: 1,
    command: command,
    ok: true,
    audit: audit,
    repairHints: repairHints,
    data: data,
    errors: []
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return try! encoder.encode(response)
}

private actor FakeRustDiagnosticsService: RustCargoServicing {
  struct Call: Equatable {
    var command: RustEngineCommand
    var arguments: [String]
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
    calls.append(Call(command: command, arguments: arguments))
    return data
  }
}

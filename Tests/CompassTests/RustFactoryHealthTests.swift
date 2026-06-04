import Foundation
import Testing

@testable import Compass

struct RustFactoryHealthTests {
  @Test func allHealthySummaryIsReady() throws {
    let health = RustFactoryHealth(inputs: healthyInputs())

    #expect(health.status == .healthy)
    #expect(health.title == "Rust Factory Healthy")
    #expect(health.checks.allSatisfy { $0.status == .healthy })
  }

  @Test func engineMissingShowsDeterministicAction() throws {
    var inputs = healthyInputs()
    inputs.engineBinaryURL = nil

    let health = RustFactoryHealth(inputs: inputs)

    #expect(health.status == .failed)
    #expect(health.title == "Rust Factory Needs Repair")
    #expect(health.nextAction == "./scripts/build-compass-engine.sh")
  }

  @Test func scaffoldDriftUsesRepairHint() throws {
    var inputs = healthyInputs()
    inputs.scaffold = RustEngineResponse(
      schemaVersion: 1,
      command: "scaffold-check",
      ok: true,
      repairHints: [
        RustRepairHint(
          id: "generated-scaffold-missing-member",
          severity: "error",
          message: "Generated scaffold is missing required member manifest xtask/Cargo.toml.",
          suggestedCommand: nil
        )
      ],
      data: ScaffoldCheckData(
        status: "fail",
        scaffoldVersion: 1,
        capabilities: capabilities(),
        checks: [
          ScaffoldCheck(
            id: "member_xtask",
            status: "fail",
            message: "required member xtask is missing.",
            path: "xtask/Cargo.toml"
          )
        ]
      ),
      errors: []
    )

    let health = RustFactoryHealth(inputs: inputs)

    #expect(health.status == .failed)
    #expect(health.detail.contains("required member xtask"))
    #expect(health.nextAction == "scaffold_check")
  }

  @Test func visualUnavailableCanRemainWarningWhenNonVisualChecksAreHealthy() throws {
    var inputs = healthyInputs()
    inputs.visual = nil
    inputs.scaffold = RustEngineResponse(
      schemaVersion: 1,
      command: "scaffold-check",
      ok: true,
      data: ScaffoldCheckData(
        status: "pass",
        scaffoldVersion: 1,
        capabilities: ScaffoldCapabilities(
          xtaskVerify: true,
          visualVerify: false,
          schemaContracts: true,
          desktopHandshake: false
        ),
        checks: []
      ),
      errors: []
    )

    let health = RustFactoryHealth(inputs: inputs)

    #expect(health.status == .warning)
    #expect(health.checks.first { $0.id == "visual" }?.status == .warning)
    #expect(health.detail.contains("not advertised"))
  }

  @Test func missingSmokeReportIsPartialNotFailure() throws {
    var inputs = healthyInputs()
    inputs.smokeReport = nil
    inputs.smokeReportURL = nil

    let health = RustFactoryHealth(inputs: inputs)

    #expect(health.status == .unknown)
    #expect(health.checks.first { $0.id == "smoke-report" }?.nextAction?.contains("factory-smoke") == true)
  }

  @Test func storeRoundTripsUnderCompassWorkspace() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    let health = RustFactoryHealth(inputs: healthyInputs())
    let store = RustFactoryHealthStore()

    try store.save(health, workspace: workspace)
    let loaded = try #require(store.load(from: workspace))

    #expect(store.url(for: workspace).lastPathComponent == RustFactoryHealthStore.filename)
    #expect(loaded == health)
  }

  private func healthyInputs() -> RustFactoryHealth.Inputs {
    RustFactoryHealth.Inputs(
      engineBinaryURL: URL(fileURLWithPath: "/tmp/compass-engine"),
      ping: RustEngineResponse(
        schemaVersion: 1,
        command: "ping",
        ok: true,
        data: RustEnginePingData(version: "0.1.0", rustc: "rustc 1.91.0", repo: "/tmp/repo"),
        errors: []
      ),
      scaffold: RustEngineResponse(
        schemaVersion: 1,
        command: "scaffold-check",
        ok: true,
        data: ScaffoldCheckData(
          status: "pass",
          scaffoldVersion: 1,
          capabilities: capabilities(),
          checks: []
        ),
        errors: []
      ),
      cargoGraph: cargoGraph(),
      cargoDiagnostics: diagnostic(exitCode: 0),
      clippy: diagnostic(exitCode: 0),
      coverage: RustEngineResponse(
        schemaVersion: 1,
        command: "coverage-gaps",
        ok: true,
        data: CoverageGapsData(overallLinePercent: 81.5, files: [], logTail: ""),
        errors: []
      ),
      visual: RustEngineResponse(
        schemaVersion: 1,
        command: "visual-verify",
        ok: true,
        data: VisualVerifyData(ok: true, screenshotPath: "/tmp/screenshot.png", logTail: ""),
        errors: []
      ),
      smokeReport: RustFactorySmokeReport(
        status: .passed,
        projectPath: "/tmp/repo",
        guestWorkspacePath: "/Users/compass/worktree",
        sshDestination: "compass@127.0.0.1",
        reportPath: "/tmp/smoke.json",
        screenshotPath: "/tmp/smoke.png",
        commands: [],
        error: nil
      ),
      smokeReportURL: URL(fileURLWithPath: "/tmp/smoke.json"),
      generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }

  private func diagnostic(exitCode: Int) -> RustEngineResponse<CargoCheckData> {
    RustEngineResponse(
      schemaVersion: 1,
      command: "cargo-check",
      ok: true,
      data: CargoCheckData(
        exitCode: exitCode,
        diagnostics: [],
        summary: RustDiagnosticSummary(errors: exitCode == 0 ? 0 : 1, warnings: 0, cratesAffected: [])
      ),
      errors: []
    )
  }

  private func capabilities() -> ScaffoldCapabilities {
    ScaffoldCapabilities(
      xtaskVerify: true,
      visualVerify: true,
      schemaContracts: true,
      desktopHandshake: true
    )
  }

  private func cargoGraph() -> CargoGraphData {
    CargoGraphData(
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
  }
}

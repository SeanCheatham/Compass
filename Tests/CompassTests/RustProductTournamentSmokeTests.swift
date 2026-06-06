import Foundation
import Testing

@testable import Compass

struct RustProductTournamentSmokeTests {

  @Test func parserIgnoresNormalLaunchArguments() throws {
    let options = RustProductTournamentSmokeOptions.parse(
      arguments: ["/Applications/Compass.app/Contents/MacOS/Compass"],
      environment: [:]
    )
    try #require(options == nil)
  }

  @Test func parserAcceptsExplicitProjectReportAndTimeout() throws {
    let options = try #require(
      RustProductTournamentSmokeOptions.parse(
        arguments: [
          "Compass",
          RustProductTournamentSmokeOptions.flag,
          RustProductTournamentSmokeOptions.projectDirFlag,
          "/tmp/project",
          RustProductTournamentSmokeOptions.reportFlag,
          "/tmp/report.json",
          RustProductTournamentSmokeOptions.timeoutFlag,
          "90",
        ],
        environment: [:]
      ))

    try #require(options.projectURL.path == "/tmp/project")
    try #require(options.reportURL.path == "/tmp/report.json")
    try #require(options.timeoutSeconds == 90)
  }

  @Test func parserUsesEnvironmentFallbacksAndClampsTinyTimeout() throws {
    let options = try #require(
      RustProductTournamentSmokeOptions.parse(
        arguments: ["Compass", RustProductTournamentSmokeOptions.flag],
        environment: [
          "COMPASS_RUST_PRODUCT_TOURNAMENT_SMOKE_PROJECT": "/tmp/env-project",
          "COMPASS_RUST_PRODUCT_TOURNAMENT_SMOKE_REPORT": "/tmp/env-report.json",
          "COMPASS_RUST_PRODUCT_TOURNAMENT_SMOKE_TIMEOUT": "2",
        ]
      ))

    try #require(options.projectURL.path == "/tmp/env-project")
    try #require(options.reportURL.path == "/tmp/env-report.json")
    try #require(options.timeoutSeconds == 30)
  }

  @Test func smokeCommandReportRecordsCommandCategory() throws {
    let report = RustProductTournamentSmokeCommandReport(
      command: RustProjectScaffold.productTournamentSmokeWithScreenshotCommand,
      category: .productTournamentSmoke,
      exitCode: 0,
      durationSeconds: 0.25,
      audit: nil,
      stdoutTail: "{}",
      stderrTail: ""
    )

    let data = try JSONEncoder().encode(report)
    let decoded = try JSONDecoder().decode(RustProductTournamentSmokeCommandReport.self, from: data)
    try #require(decoded == report)
  }

  @Test func smokeCommandReportPreservesEngineAudit() throws {
    let report = RustProductTournamentSmokeCommandReport(
      command: RustVerifyCommands.compassEngine(.cargoCheck, arguments: ["--all-features"]),
      category: .compassEngine,
      exitCode: 0,
      durationSeconds: 0.25,
      audit: RustEngineAudit(
        repo: "/tmp/repo",
        argv: ["cargo", "check", "--workspace", "--message-format=json", "--all-features"],
        durationMs: 42,
        toolchain: RustEngineToolchain(rustc: "rustc 1.91.0", cargo: "cargo 1.91.0")
      ),
      stdoutTail: "{}",
      stderrTail: ""
    )

    let data = try JSONEncoder().encode(report)
    let decoded = try JSONDecoder().decode(RustProductTournamentSmokeCommandReport.self, from: data)

    try #require(decoded.audit?.argv?.first == "cargo")
    try #require(decoded.audit?.durationMs == 42)
  }
}

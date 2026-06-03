import Foundation
import Testing

@testable import Compass

struct RustFactorySmokeTests {

  @Test func parserIgnoresNormalLaunchArguments() throws {
    let options = RustFactorySmokeOptions.parse(
      arguments: ["/Applications/Compass.app/Contents/MacOS/Compass"],
      environment: [:]
    )
    try #require(options == nil)
  }

  @Test func parserAcceptsExplicitProjectReportAndTimeout() throws {
    let options = try #require(
      RustFactorySmokeOptions.parse(
        arguments: [
          "Compass",
          RustFactorySmokeOptions.flag,
          RustFactorySmokeOptions.projectDirFlag,
          "/tmp/project",
          RustFactorySmokeOptions.reportFlag,
          "/tmp/report.json",
          RustFactorySmokeOptions.timeoutFlag,
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
      RustFactorySmokeOptions.parse(
        arguments: ["Compass", RustFactorySmokeOptions.flag],
        environment: [
          "COMPASS_RUST_FACTORY_SMOKE_PROJECT": "/tmp/env-project",
          "COMPASS_RUST_FACTORY_SMOKE_REPORT": "/tmp/env-report.json",
          "COMPASS_RUST_FACTORY_SMOKE_TIMEOUT": "2",
        ]
      ))

    try #require(options.projectURL.path == "/tmp/env-project")
    try #require(options.reportURL.path == "/tmp/env-report.json")
    try #require(options.timeoutSeconds == 30)
  }
}

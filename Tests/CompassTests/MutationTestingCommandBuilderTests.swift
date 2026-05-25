import Foundation
import XCTest

@testable import Compass

final class MutationTestingCommandBuilderTests: XCTestCase {
  func testSwiftVerifyFilterMapsToMuterCommand() {
    let command = MutationTestingCommandBuilder.build(
      language: .swift,
      verifyCommand: "swift test --filter AgentMutationTestingPlanTests"
    )
    XCTAssertEqual(
      command,
      "test -f muter.conf.json || muter init; muter run --skip-update-check -- -F AgentMutationTestingPlanTests"
    )
  }

  func testSwiftBuildVerifyDoesNotSupportMutationTesting() {
    XCTAssertFalse(
      MutationTestingCommandBuilder.verifySupportsMutationTesting(
        language: .swift,
        verifyCommand: "swift build 2>&1"
      )
    )
    XCTAssertNil(
      MutationTestingCommandBuilder.build(
        language: .swift,
        verifyCommand: "swift build 2>&1"
      )
    )
  }

  func testPythonPytestVerifyMapsToMutmutRunner() {
    let command = MutationTestingCommandBuilder.build(
      language: .python,
      verifyCommand: "pytest -q tests/unit"
    )
    XCTAssertEqual(command, "mutmut run --runner='pytest -q tests/unit'")
  }

  func testRustVerifyMapsToCargoMutants() {
    let command = MutationTestingCommandBuilder.build(
      language: .rust,
      verifyCommand: "cargo test parser::"
    )
    XCTAssertEqual(command, "cargo mutants --no-shuffle -j 1")
  }

  func testGoVerifyMapsToGoMutestingPackages() {
    let command = MutationTestingCommandBuilder.build(
      language: .go,
      verifyCommand: "go test ./internal/..."
    )
    XCTAssertEqual(command, "go-mutesting -test.timeout=30s ./internal/...")
  }

  func testJavaScriptRequiresPackageManifestHint() {
    XCTAssertNil(
      MutationTestingCommandBuilder.build(
        language: .typeScriptJavaScript,
        verifyCommand: "npm test"
      )
    )
    XCTAssertEqual(
      MutationTestingCommandBuilder.build(
        language: .typeScriptJavaScript,
        verifyCommand: "npm test",
        manifestHints: [.packageJSON]
      ),
      "npx stryker run --force"
    )
  }

  func testEnvironmentOverrideWins() {
    let command = MutationTestingCommandBuilder.build(
      language: .swift,
      verifyCommand: "swift test",
      environment: [
        MutationTestingCommandBuilder.environmentCommandKey: "custom-mutation-runner --fast"
      ]
    )
    XCTAssertEqual(command, "custom-mutation-runner --fast")
  }

  func testExtractFlagValueHandlesEqualsForm() {
    XCTAssertEqual(
      MutationTestingCommandBuilder.extractFlagValue(
        from: "swift test --filter=FooTests",
        flags: ["--filter", "-F"]
      ),
      "FooTests"
    )
  }

  func testExtractGoTestPackages() {
    XCTAssertEqual(
      MutationTestingCommandBuilder.extractGoTestPackages(from: "go test ./pkg/..."),
      "./pkg/..."
    )
  }
}

final class MutationTestingPolicyTests: XCTestCase {
  func testAutoModeRunsOnEverySuccessfulSessionByDefault() {
    XCTAssertTrue(
      MutationTestingPolicy.shouldRunAutomatically(
        sessionNumber: 3,
        estimatedDifficulty: .medium,
        environment: [:]
      )
    )
  }

  func testManualModeSkipsAutomaticRuns() {
    XCTAssertFalse(
      MutationTestingPolicy.shouldRunAutomatically(
        sessionNumber: 2,
        estimatedDifficulty: .high,
        environment: [MutationTestingPolicy.modeEnvironmentKey: "manual"]
      )
    )
  }

  func testCadenceSkipsIntermediateSessions() {
    XCTAssertFalse(
      MutationTestingPolicy.shouldRunAutomatically(
        sessionNumber: 2,
        estimatedDifficulty: .medium,
        environment: [MutationTestingPolicy.cadenceEnvironmentKey: "3"]
      )
    )
    XCTAssertTrue(
      MutationTestingPolicy.shouldRunAutomatically(
        sessionNumber: 3,
        estimatedDifficulty: .medium,
        environment: [MutationTestingPolicy.cadenceEnvironmentKey: "3"]
      )
    )
  }

  func testMinimumDifficultyThreshold() {
    XCTAssertFalse(
      MutationTestingPolicy.shouldRunAutomatically(
        sessionNumber: 1,
        estimatedDifficulty: .low,
        environment: [MutationTestingPolicy.minDifficultyEnvironmentKey: "high"]
      )
    )
    XCTAssertTrue(
      MutationTestingPolicy.shouldRunAutomatically(
        sessionNumber: 1,
        estimatedDifficulty: .high,
        environment: [MutationTestingPolicy.minDifficultyEnvironmentKey: "high"]
      )
    )
  }
}

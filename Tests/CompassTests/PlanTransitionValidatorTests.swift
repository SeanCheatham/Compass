import Foundation
import Testing

@testable import CompassCore

@Suite("PlanTransitionValidator")
struct PlanTransitionValidatorTests {
  @Test
  func rejectsMissingExplicitPathsUnlessMarkedAsNewFile() throws {
    let tempURL = try makePlanValidatorTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let cliSrc = tempURL.appending(path: "packages/cli/src", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cliSrc, withIntermediateDirectories: true)
    try "export const main = true;\n".write(
      to: cliSrc.appending(path: "main.ts"),
      atomically: true,
      encoding: .utf8
    )
    try "import './main';\n".write(
      to: cliSrc.appending(path: "main.test.ts"),
      atomically: true,
      encoding: .utf8
    )
    try """
    {
      "name": "@compass-test/cli",
      "type": "module",
      "bin": {
        "compass-test": "./src/main.ts"
      }
    }
    """.write(
      to: tempURL.appending(path: "packages/cli/package.json"),
      atomically: true,
      encoding: .utf8
    )

    let invalid = planState(
      """
      ## Outcome
      Update `packages/cli/src/cli.ts` so the CLI prints a queue summary.

      ## Acceptance checks
      - CLI output includes the queue summary.
      """
    )

    #expect(throws: PlanTransitionValidationError.self) {
      try PlanTransitionValidator.validate(from: .empty, to: invalid, repoURL: tempURL)
    }

    do {
      try PlanTransitionValidator.validate(from: .empty, to: invalid, repoURL: tempURL)
      Issue.record("Expected missing path rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .ungroundedPaths)
      #expect(error.message.contains("packages/cli/src/cli.ts"))
      #expect(error.message.contains("main.ts"))
    }

    let duplicateEntryPoint = planState(
      """
      ## Outcome
      Create new file `packages/cli/src/cli.ts` as a tiny wrapper around main.

      ## Acceptance checks
      - The new wrapper file exists.
      """
    )

    do {
      try PlanTransitionValidator.validate(from: .empty, to: duplicateEntryPoint, repoURL: tempURL)
      Issue.record("Expected duplicate entry point rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .ungroundedPaths)
      #expect(error.message.contains("duplicate package entry points"))
      #expect(error.message.contains("packages/cli/package.json"))
      #expect(error.message.contains("bin.compass-test"))
      #expect(error.message.contains("packages/cli/src/main.ts"))
    }

    let explicitNewUtilityFile = planState(
      """
      ## Outcome
      Create new file `packages/core/src/utils/activity.ts` for reusable activity helpers.

      ## Acceptance checks
      - The new activity helper file exists.
      """
    )

    try PlanTransitionValidator.validate(
      from: .empty,
      to: explicitNewUtilityFile,
      repoURL: tempURL
    )
  }

  @Test
  func rejectsGenericVerifyForCLIBehaviorWithoutTestProof() throws {
    let weak = planState(
      """
      ## Outcome
      Update the CLI so it prints a useful one-line ledger summary.

      ## Acceptance checks
      - The CLI can print a useful one-line ledger summary from sample entries.
      """
    )

    do {
      try PlanTransitionValidator.validate(from: .empty, to: weak)
      Issue.record("Expected weak verify rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .weakVerifyCoverage)
      #expect(error.message.contains("does not include a CLI test"))
      #expect(error.message.contains("packages/cli/src/main.test.ts"))
    }

    let grounded = planState(
      """
      ## Outcome
      Update the CLI and `packages/cli/src/main.test.ts` so it prints a useful one-line ledger summary.

      ## Acceptance checks
      - The CLI test asserts the one-line ledger summary from sample entries.
      """
    )

    try PlanTransitionValidator.validate(from: .empty, to: grounded)
  }
}

private func planState(_ plan: String, verify: String = "pnpm verify") -> PlanState {
  PlanState(
    completed: [],
    immediate: PlanNext(
      plan: plan,
      verify: verify,
      verifyTimeoutMs: 600_000,
      estimatedDifficulty: .low,
      selectedBecause: "This is a focused test packet.",
      source: .repository
    )
  )
}

private func makePlanValidatorTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "PlanTransitionValidatorTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

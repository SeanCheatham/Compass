import Foundation
import Testing

@testable import CompassCore

@Suite("PlanTransitionValidator")
struct PlanTransitionValidatorTests {
  @Test
  func rejectsDroppingExistingBriefFields() throws {
    let current = PlanState(
      completed: [],
      immediate: nil,
      brief: PlanStrategicContext(
        summary: "Build a tiny activity-ledger feature.",
        targetUsers: ["Solo builders"],
        desiredOutcomes: ["Core logic summarizes done and pending activity counts."],
        constraints: ["Keep the slice dependency-free."],
        acceptanceSignals: ["Core and CLI tests cover the ledger summary."]
      )
    )
    let next = PlanState(
      completed: [],
      immediate: PlanNext(
        plan: """
          ## Outcome
          Update `packages/cli/src/main.ts` and `packages/cli/src/main.test.ts` so the CLI prints a useful one-line ledger summary.

          ## Acceptance checks
          - The CLI test asserts the one-line ledger summary from sample entries.
          """,
        verify: "pnpm verify",
        verifyTimeoutMs: 600_000,
        estimatedDifficulty: .low,
        selectedBecause: "This is a focused test packet.",
        source: .repository
      ),
      brief: PlanStrategicContext(
        summary: "Build a tiny activity-ledger feature.",
        targetUsers: [],
        desiredOutcomes: [],
        constraints: [],
        acceptanceSignals: []
      )
    )

    do {
      try PlanTransitionValidator.validate(from: current, to: next)
      Issue.record("Expected brief preservation rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .invalidStateMutation)
      #expect(error.missingLabels.contains("brief.targetUsers"))
      #expect(error.missingLabels.contains("brief.desiredOutcomes"))
      #expect(error.missingLabels.contains("brief.constraints"))
      #expect(error.missingLabels.contains("brief.acceptanceSignals"))
      #expect(error.message.contains("Keep `brief` stable"))
      #expect(error.message.contains("Set `state.brief` exactly"))
      #expect(
        error.message.contains(
          #""acceptanceSignals":["Core and CLI tests cover the ledger summary."]"#))
    }
  }

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

    let wrongTestPath = planState(
      """
      ## Outcome
      Update `packages/cli/test/main.test.ts` to cover loud CLI output.

      ## Acceptance checks
      - `packages/cli/test/main.test.ts` covers loud CLI output.
      """
    )

    do {
      try PlanTransitionValidator.validate(from: .empty, to: wrongTestPath, repoURL: tempURL)
      Issue.record("Expected missing test path rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .ungroundedPaths)
      #expect(error.message.contains("packages/cli/test/main.test.ts"))
      #expect(error.message.contains("same filename exists at: packages/cli/src/main.test.ts"))
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
      #expect(
        error.message.contains(
          "Replace `packages/cli/src/cli.ts` with `packages/cli/src/main.ts`"
        ))
      #expect(error.message.contains("Do not resubmit the same new-file path"))
    }

    let explicitEntrypointMove = planState(
      """
      ## Outcome
      Change `bin.compass-test` from `packages/cli/src/main.ts` to `packages/cli/src/cli.ts`, then create new file `packages/cli/src/cli.ts` as the replacement CLI entry point.

      ## Acceptance checks
      - The package bin routes compass-test through the replacement entry point.
      """
    )

    try PlanTransitionValidator.validate(
      from: .empty,
      to: explicitEntrypointMove,
      repoURL: tempURL
    )

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

  @Test
  func jsonFormatCLIProofGuidanceNamesSplitArgvTest() throws {
    let weak = planState(
      """
      ## Outcome
      Add support for `--format json` to the CLI.

      ## Acceptance checks
      - Running `main(["--format", "json", "Ship", "it"])` returns JSON output.
      """
    )

    do {
      try PlanTransitionValidator.validate(from: .empty, to: weak)
      Issue.record("Expected weak verify rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .weakVerifyCoverage)
      #expect(error.message.contains("packages/cli/src/main.test.ts"))
      #expect(error.message.contains(#"main(["--format", "json", "Ship", "it"])"#))
      #expect(error.message.contains("parsed JSON title is `Ship it`"))
    }
  }

  @Test
  func rejectsTestOnlyVerifyForCLIImplementationWork() throws {
    let implementation = planState(
      """
      ## Outcome
      Implement a split-argv `--limit <number>` option in the CLI.

      ## Acceptance checks
      - `main(["--limit", "4", "Ship", "it"])` parses the real split argv entries and returns `4 open / 4 total`.
      - Update `packages/cli/src/main.test.ts` with the split argv assertion.
      """,
      verify: "pnpm test -- --coverage"
    )

    do {
      try PlanTransitionValidator.validate(from: .empty, to: implementation)
      Issue.record("Expected test-only verify rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .weakVerifyCoverage)
      #expect(error.rejectedVerify == "pnpm test -- --coverage")
      #expect(error.message.contains("test-only verify command"))
      #expect(error.message.contains("use `pnpm verify`"))
    }
  }

  @Test
  func acceptsCoverageVerifyForTestOnlyCLISlice() throws {
    let testOnly = planState(
      """
      ## Outcome
      Add regression coverage in `packages/cli/src/main.test.ts` for the existing CLI split argv behavior.

      ## Acceptance checks
      - The CLI test calls `main(["--format", "json", "Ship", "it"])` and asserts the parsed title is `Ship it`.
      """,
      verify: "pnpm test -- --coverage"
    )

    try PlanTransitionValidator.validate(from: .empty, to: testOnly)
  }

  @Test
  func acceptsDocumentationOnlyGrepVerify() throws {
    let docsOnly = planState(
      """
      ## Outcome
      Add a documentation-only README note for maintainers.

      ## Acceptance checks
      - README.md contains `Compass local-model smoke note.`
      """,
      verify: #"grep -q "Compass local-model smoke note." README.md"#
    )

    try PlanTransitionValidator.validate(
      from: .empty,
      to: docsOnly,
      forgeProfile: .typeScriptPnpmVite
    )
  }

  @Test
  func rejectsGrepVerifyForCLIImplementationWork() throws {
    let implementation = planState(
      """
      ## Outcome
      Implement a split-argv `--limit <number>` option in the CLI.

      ## Acceptance checks
      - The CLI can parse `main(["--limit", "4", "Ship", "it"])`.
      """,
      verify: #"grep -q "--limit" README.md"#
    )

    do {
      try PlanTransitionValidator.validate(
        from: .empty,
        to: implementation,
        forgeProfile: .typeScriptPnpmVite
      )
      Issue.record("Expected coverage verify rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .coverageRequirement)
      #expect(error.rejectedVerify == #"grep -q "--limit" README.md"#)
      #expect(error.message.contains("pnpm verify"))
    }
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

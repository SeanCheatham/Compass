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
        summary: "Build a tiny display-name Tessera app.",
        targetUsers: ["Solo builders"],
        desiredOutcomes: ["The app renders a friendly display label."],
        constraints: ["Keep the slice dependency-free."],
        acceptanceSignals: ["Tessera tests cover the display label."]
      )
    )
    let next = PlanState(
      completed: [],
      immediate: PlanNext(
        plan: """
          ## Outcome
          Update `src/display-name.tes` and `tests/display-name.json` so the app renders a useful display label.

          ## Acceptance checks
          - The Tessera test asserts the display label from a sample context.
          """,
        verify: "tessera verify . --json",
        verifyTimeoutMs: 600_000,
        estimatedDifficulty: .low,
        selectedBecause: "This is a focused Tessera test packet.",
        source: .repository
      ),
      brief: PlanStrategicContext(
        summary: "Build a tiny display-name Tessera app.",
        targetUsers: [],
        desiredOutcomes: [],
        constraints: [],
        acceptanceSignals: []
      )
    )

    do {
      try PlanTransitionValidator.validate(from: current, to: next, forgeProfile: .tesseraApp)
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
          #""acceptanceSignals":["Tessera tests cover the display label."]"#))
    }
  }

  @Test
  func rejectsMissingExplicitPathsUnlessMarkedAsNewFile() throws {
    let tempURL = try makePlanValidatorTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let src = tempURL.appending(path: "src", directoryHint: .isDirectory)
    let tests = tempURL.appending(path: "tests", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
    try "(def display ((name Text)) (concat name \"!\"))\n(display user.name)\n".write(
      to: src.appending(path: "display-name.tes"),
      atomically: true,
      encoding: .utf8
    )
    try #"{"name":"display-name","source":"display-name","context":"user","expect":"Ada!"}"#
      .write(
        to: tests.appending(path: "display-name.json"),
        atomically: true,
        encoding: .utf8
      )

    let invalid = planState(
      """
      ## Outcome
      Update `src/title.tes` so the app prints a queue summary.

      ## Acceptance checks
      - `tests/title.json` covers the new display output.
      """
    )

    do {
      try PlanTransitionValidator.validate(from: .empty, to: invalid, repoURL: tempURL)
      Issue.record("Expected missing path rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .ungroundedPaths)
      #expect(error.message.contains("src/title.tes"))
      #expect(error.message.contains("display-name.tes"))
    }

    let wrongTestPath = planState(
      """
      ## Outcome
      Update `src/display-name.tes` to render a loud label.

      ## Acceptance checks
      - `specs/display-name.json` covers loud display output.
      """
    )

    do {
      try PlanTransitionValidator.validate(from: .empty, to: wrongTestPath, repoURL: tempURL)
      Issue.record("Expected missing test path rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .ungroundedPaths)
      #expect(error.message.contains("specs/display-name.json"))
      #expect(error.message.contains("same filename exists at: tests/display-name.json"))
    }

    let explicitNewFile = planState(
      """
      ## Outcome
      Create new file `src/format-label.tes` for reusable label formatting.

      ## Acceptance checks
      - The new format-label source file exists.
      """
    )

    try PlanTransitionValidator.validate(
      from: .empty,
      to: explicitNewFile,
      repoURL: tempURL
    )
  }

  @Test
  func rejectsRetiredPackageTermsForTesseraHandoffs() throws {
    let legacyVerify = planState(
      """
      ## Outcome
      Update `src/display-name.tes` so the app renders a useful display label.

      ## Acceptance checks
      - `tests/display-name.json` covers the display label.
      """,
      verify: "pnpm verify"
    )

    do {
      try PlanTransitionValidator.validate(
        from: .empty,
        to: legacyVerify,
        forgeProfile: .tesseraApp
      )
      Issue.record("Expected legacy verify rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .coverageRequirement)
      #expect(error.rejectedVerify == "pnpm verify")
      #expect(error.message.contains("tessera verify . --json"))
    }

    let legacyPlan = planState(
      """
      ## Outcome
      Update `packages/cli/src/main.ts` so the CLI prints a useful one-line ledger summary.

      ## Acceptance checks
      - `packages/cli/src/main.test.ts` covers the new CLI behavior.
      """
    )

    do {
      try PlanTransitionValidator.validate(
        from: .empty,
        to: legacyPlan,
        forgeProfile: .tesseraApp
      )
      Issue.record("Expected legacy handoff rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .weakHandoff)
      #expect(error.message.contains("Tessera files"))
      #expect(error.message.contains("src/*.tes"))
      #expect(error.message.contains("tests/*.json"))
    }
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
      forgeProfile: .tesseraApp
    )
  }

  @Test
  func rejectsGrepVerifyForTesseraImplementationWork() throws {
    let implementation = planState(
      """
      ## Outcome
      Update `src/display-name.tes` to render a useful display label.

      ## Acceptance checks
      - `tests/display-name.json` covers the new display output.
      """,
      verify: #"grep -q "display" src/display-name.tes"#
    )

    do {
      try PlanTransitionValidator.validate(
        from: .empty,
        to: implementation,
        forgeProfile: .tesseraApp
      )
      Issue.record("Expected coverage verify rejection.")
    } catch let error as PlanTransitionValidationError {
      #expect(error.reason == .coverageRequirement)
      #expect(error.rejectedVerify == #"grep -q "display" src/display-name.tes"#)
      #expect(error.message.contains("tessera verify . --json"))
    }
  }
}

private func planState(_ plan: String, verify: String = "tessera verify . --json") -> PlanState {
  PlanState(
    completed: [],
    immediate: PlanNext(
      plan: plan,
      verify: verify,
      verifyTimeoutMs: 600_000,
      estimatedDifficulty: .low,
      selectedBecause: "This is a focused Tessera test packet.",
      source: .repository
    )
  )
}

private func makePlanValidatorTempDirectory() throws -> URL {
  try makeCompassTestDirectory(named: "PlanTransitionValidatorTests")
}

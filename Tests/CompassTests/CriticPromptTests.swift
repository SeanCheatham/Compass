import Foundation
import Testing

@testable import Compass

struct CriticPromptTests {
  private func makePlanNext(
    plan: String = "Refactor the parser",
    verify: String = "swift test"
  ) -> PlanNext {
    PlanNext(plan: plan, verify: verify, verifyTimeoutMs: nil, estimatedDifficulty: .medium)
  }

  private func makeDevelopSummary(
    status: DevelopSummary.Status = .succeeded,
    summary: String = "Refactor done.",
    feedback: String = "Next plan should cover the call sites."
  ) -> DevelopSummary {
    DevelopSummary(status: status, summary: summary, feedback: feedback)
  }

  @Test func testCriticPromptCarriesPlanAndVerifyAndDiff() throws {
    let prompt = Prompts.criticPrompt(
      next: makePlanNext(plan: "Plan body XYZ"),
      developSummary: makeDevelopSummary(summary: "Summary body 123"),
      verifyCommand: "swift test --filter Parser",
      verifyExitCode: 0,
      verifyOutput: "ok 5 tests passed",
      gitDiff: "diff --git a/x b/x\n+let foo = 1\n",
      priorCritiques: [],
      lessons: "",
      vision: "",
      iteration: 1,
      maxIterations: 3
    )
    try #require(prompt.contains("Plan body XYZ"))
    try #require(prompt.contains("Summary body 123"))
    try #require(prompt.contains("swift test --filter Parser"))
    try #require(prompt.contains("passed (exit 0)"))
    try #require(prompt.contains("ok 5 tests passed"))
    try #require(prompt.contains("+let foo = 1"))
  }

  @Test func testCriticPromptReportsBypassedVerifyClearly() throws {
    let prompt = Prompts.criticPrompt(
      next: makePlanNext(),
      developSummary: makeDevelopSummary(),
      verifyCommand: "swift test",
      verifyExitCode: nil,
      verifyOutput: "",
      gitDiff: "",
      priorCritiques: [],
      lessons: "",
      vision: "",
      iteration: 1,
      maxIterations: 3
    )
    try #require(prompt.contains("bypassVerify"))
    try #require(prompt.contains("Verify result: was skipped"))
    try #require(prompt.contains("explicitly bypassed"))
  }

  @Test func testCriticPromptIncludesReviewBriefFromExecutableHandoff() throws {
    let prompt = Prompts.criticPrompt(
      next: makePlanNext(
        plan: """
          ## Outcome
          Make parser errors readable to non-engineers.

          ## Why it matters
          Users can decide whether to retry or change their draft.

          ## Acceptance checks
          - Empty input explains that there is nothing to parse.
          - Invalid syntax names the first broken section.
          """,
        verify: "swift test --filter Parser"
      ),
      developSummary: makeDevelopSummary(summary: "Parser errors now explain the failure."),
      verifyCommand: "swift test --filter Parser",
      verifyExitCode: 0,
      verifyOutput: "ok",
      gitDiff:
        "diff --git a/Sources/Parser.swift b/Sources/Parser.swift\n+let message = \"Readable\"\n",
      priorCritiques: [],
      lessons: "",
      vision: "",
      iteration: 1,
      maxIterations: 3
    )

    try #require(prompt.contains("## Review brief"))
    try #require(prompt.contains("Primary question: did this diff deliver the planned outcome"))
    try #require(prompt.contains("Review the acceptance checks before style preferences"))
    try #require(prompt.contains("Handoff status: Executable handoff"))
    try #require(prompt.contains("Planned outcome: Make parser errors readable to non-engineers."))
    try #require(
      prompt.contains("Why it matters: Users can decide whether to retry or change their draft."))
    try #require(prompt.contains("Acceptance checks to audit:"))
    try #require(prompt.contains("- Empty input explains that there is nothing to parse."))
    try #require(prompt.contains("Verify meaning: Runs Swift tests"))
    try #require(prompt.contains("focused on Parser"))
    try #require(prompt.contains("Verify result: passed (exit 0)."))
    try #require(prompt.contains("Diff signal: review only the diff below"))
  }

  @Test func testCriticPromptCountsIterationsTowardCap() throws {
    let prompt = Prompts.criticPrompt(
      next: makePlanNext(),
      developSummary: makeDevelopSummary(),
      verifyCommand: "swift test",
      verifyExitCode: 0,
      verifyOutput: "",
      gitDiff: "",
      priorCritiques: [],
      lessons: "",
      vision: "",
      iteration: 3,
      maxIterations: 3
    )
    try #require(
      prompt.contains("critic review 3 of at most 3"),
      "Critic must know it's the final review so it can be decisive"
    )
    try #require(prompt.contains("accept and proceed regardless"))
  }

  @Test func testCriticPromptIncludesPriorCritiquesWhenPresent() throws {
    let prompt = Prompts.criticPrompt(
      next: makePlanNext(),
      developSummary: makeDevelopSummary(),
      verifyCommand: "swift test",
      verifyExitCode: 0,
      verifyOutput: "",
      gitDiff: "",
      priorCritiques: ["Missing test for the empty case."],
      lessons: "",
      vision: "",
      iteration: 2,
      maxIterations: 3
    )
    try #require(prompt.contains("Missing test for the empty case."))
    try #require(prompt.contains("Review 1:"))
  }

  @Test func testCriticPromptForbidsMutatingCommandsExplicitly() throws {
    // The bash tool itself cannot enforce intent; the prompt has to
    // tell the model not to commit / write / sed-in-place.
    let prompt = Prompts.criticPrompt(
      next: makePlanNext(),
      developSummary: makeDevelopSummary(),
      verifyCommand: "swift test",
      verifyExitCode: 0,
      verifyOutput: "",
      gitDiff: "",
      priorCritiques: [],
      lessons: "",
      vision: "",
      iteration: 1,
      maxIterations: 3
    )
    try #require(prompt.contains("CANNOT edit, write, or commit"))
    try #require(prompt.contains("no `git commit`"))
  }

  @Test func testCriticPromptIncludesSuggestedRustReviewProbesForRustDiffs() throws {
    let prompt = Prompts.criticPrompt(
      next: makePlanNext(verify: "cargo llvm-cov test --summary-only"),
      developSummary: makeDevelopSummary(),
      verifyCommand: "cargo llvm-cov test --summary-only",
      verifyExitCode: 0,
      verifyOutput: "overall line coverage: 88.1%",
      gitDiff: """
        diff --git a/Cargo.toml b/Cargo.toml
        +members = ["crates/app-core"]
        diff --git a/schemas/demo-state.schema.json b/schemas/demo-state.schema.json
        +{"type":"object"}
        """,
      priorCritiques: [],
      lessons: "",
      vision: "",
      forgeProfile: .rustCargo,
      iteration: 1,
      maxIterations: 3
    )

    try #require(prompt.contains("## Suggested Rust review probes"))
    try #require(prompt.contains("Suggested Rust review probes:"))
    try #require(prompt.contains("workspace_outline"))
    try #require(prompt.contains("schema_contracts"))
    try #require(prompt.contains("cargo_check"))
    try #require(prompt.contains("clippy_lint"))
    try #require(prompt.contains("coverage_gaps"))
    try #require(prompt.contains("scaffold_check"))
  }

  @Test func testCriticPromptOmitsRustReviewProbesForNonRustProfiles() throws {
    let prompt = Prompts.criticPrompt(
      next: makePlanNext(verify: "swift test"),
      developSummary: makeDevelopSummary(),
      verifyCommand: "swift test",
      verifyExitCode: 0,
      verifyOutput: "ok",
      gitDiff: """
        diff --git a/Cargo.toml b/Cargo.toml
        +edition = "2021"
        """,
      priorCritiques: [],
      lessons: "",
      vision: "",
      forgeProfile: .swiftSPM,
      iteration: 1,
      maxIterations: 3
    )

    try #require(!prompt.contains("Suggested Rust review probes"))
  }

  @Test func testCriticPromptChecksFeatureMatrixBugClassAndArtifacts() throws {
    let prompt = Prompts.criticPrompt(
      next: makePlanNext(),
      developSummary: makeDevelopSummary(),
      verifyCommand: "cargo test",
      verifyExitCode: 0,
      verifyOutput: "",
      gitDiff: "",
      priorCritiques: [],
      lessons: "",
      vision: "",
      iteration: 1,
      maxIterations: 3
    )
    try #require(prompt.contains("all-features"))
    try #require(prompt.contains("sibling call sites"))
    try #require(prompt.contains("generated build outputs"))
  }

  @Test func testCriticPromptRequiresConcreteRequestChangesFeedback() throws {
    let prompt = Prompts.criticPrompt(
      next: makePlanNext(),
      developSummary: makeDevelopSummary(),
      verifyCommand: "swift test",
      verifyExitCode: 0,
      verifyOutput: "",
      gitDiff: "diff --git a/Sources/Foo.swift b/Sources/Foo.swift\n+let broken = true\n",
      priorCritiques: [],
      lessons: "",
      vision: "",
      iteration: 1,
      maxIterations: 3
    )

    try #require(prompt.contains("concrete punch list"))
    try #require(prompt.contains("Do not use `fix it`"))
    try #require(prompt.contains("placeholder"))
    try #require(prompt.contains("if you cannot name a concrete"))
    try #require(prompt.contains("approve instead of requesting changes"))
  }

  @Test func testCriticPromptIncludesCopyableVerdictShapes() throws {
    let prompt = Prompts.criticPrompt(
      next: makePlanNext(),
      developSummary: makeDevelopSummary(),
      verifyCommand: "swift test",
      verifyExitCode: 0,
      verifyOutput: "",
      gitDiff: "diff --git a/File.swift b/File.swift\n",
      priorCritiques: [],
      lessons: "",
      vision: "",
      iteration: 1,
      maxIterations: 3
    )

    try #require(prompt.contains("Copy exactly one of these shapes"))
    try #require(prompt.contains("\"verdict\": \"approve\""))
    try #require(prompt.contains("\"feedback\": \"\""))
    try #require(prompt.contains("\"verdict\": \"request_changes\""))
    try #require(prompt.contains("<specific failing behavior or file>"))
    try #require(!prompt.contains("approve|request_changes"))
  }

  @Test func testCriticVerdictDecodesApproveAndRequestChangesSnakeCase() throws {
    let approve = #"{"verdict":"approve","summary":"looks good","feedback":""}"#
    let reject = #"{"verdict":"request_changes","summary":"missing tests","feedback":"add one"}"#
    let approved = #"{"verdict":"approved","summary":"looks good","feedback":""}"#
    let camelReject = #"{"verdict":"requestChanges","summary":"missing tests","feedback":"add one"}"#
    let v1 = try JSONDecoder().decode(CriticVerdict.self, from: Data(approve.utf8))
    let v2 = try JSONDecoder().decode(CriticVerdict.self, from: Data(reject.utf8))
    let v3 = try JSONDecoder().decode(CriticVerdict.self, from: Data(approved.utf8))
    let v4 = try JSONDecoder().decode(CriticVerdict.self, from: Data(camelReject.utf8))
    try #require(v1.verdict == .approve)
    try #require(v2.verdict == .requestChanges)
    try #require(v3.verdict == .approve)
    try #require(v4.verdict == .requestChanges)
    try #require(v2.feedback == "add one")
  }

  @Test func testDevelopPromptInjectsCriticFeedbackSectionWhenPresent() throws {
    let withFeedback = Prompts.developPrompt(
      next: PlanNext(
        plan: "p", verify: "swift build", verifyTimeoutMs: nil, estimatedDifficulty: nil),
      lessons: "",
      vision: "",
      attempt: 2,
      priorIssues: [],
      criticFeedback: ["Add a test for the empty list case."]
    )
    try #require(withFeedback.contains("Critic feedback from prior passes"))
    try #require(withFeedback.contains("Add a test for the empty list case."))
  }

  @Test func testDevelopPromptForbidsGeneratedArtifactsAndAsksForPatternSweep() throws {
    let prompt = Prompts.developPrompt(
      next: PlanNext(
        plan: "p", verify: "swift build", verifyTimeoutMs: nil, estimatedDifficulty: nil),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )
    try #require(prompt.contains("Do not commit generated build outputs"))
    try #require(prompt.contains("target/"))
    try #require(prompt.contains("sibling call sites"))
  }

  @Test func testDevelopPromptOmitsCriticFeedbackSectionWhenAbsent() throws {
    let withoutFeedback = Prompts.developPrompt(
      next: PlanNext(
        plan: "p", verify: "swift build", verifyTimeoutMs: nil, estimatedDifficulty: nil),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )
    try #require(!withoutFeedback.contains("Critic feedback from prior passes"))
  }
}

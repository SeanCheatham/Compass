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

  @Test func testCriticPromptCarriesPlanAndVerifyAndDiff() {
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
    #require(prompt.contains("Plan body XYZ"))
    #require(prompt.contains("Summary body 123"))
    #require(prompt.contains("swift test --filter Parser"))
    #require(prompt.contains("passed (exit 0)"))
    #require(prompt.contains("ok 5 tests passed"))
    #require(prompt.contains("+let foo = 1"))
  }

  @Test func testCriticPromptReportsBypassedVerifyClearly() {
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
    #require(prompt.contains("bypassVerify"))
  }

  @Test func testCriticPromptCountsIterationsTowardCap() {
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
    #require(
      prompt.contains("critic review 3 of at most 3"),
      "Critic must know it's the final review so it can be decisive"
    )
    #require(prompt.contains("accept and proceed regardless"))
  }

  @Test func testCriticPromptIncludesPriorCritiquesWhenPresent() {
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
    #require(prompt.contains("Missing test for the empty case."))
    #require(prompt.contains("Review 1:"))
  }

  @Test func testCriticPromptForbidsMutatingCommandsExplicitly() {
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
    #require(prompt.contains("CANNOT edit, write, or commit"))
    #require(prompt.contains("no `git commit`"))
  }

  @Test func testCriticVerdictDecodesApproveAndRequestChangesSnakeCase() throws {
    let approve = #"{"verdict":"approve","summary":"looks good","feedback":""}"#
    let reject = #"{"verdict":"request_changes","summary":"missing tests","feedback":"add one"}"#
    let v1 = try JSONDecoder().decode(CriticVerdict.self, from: Data(approve.utf8))
    let v2 = try JSONDecoder().decode(CriticVerdict.self, from: Data(reject.utf8))
    #require(v1.verdict == .approve)
    #require(v2.verdict == .requestChanges)
    #require(v2.feedback == "add one")
  }

  @Test func testDevelopPromptInjectsCriticFeedbackSectionWhenPresent() {
    let withFeedback = Prompts.developPrompt(
      next: PlanNext(
        plan: "p", verify: "swift build", verifyTimeoutMs: nil, estimatedDifficulty: nil),
      lessons: "",
      vision: "",
      attempt: 2,
      priorIssues: [],
      criticFeedback: ["Add a test for the empty list case."]
    )
    #require(withFeedback.contains("Critic feedback from prior passes"))
    #require(withFeedback.contains("Add a test for the empty list case."))
  }

  @Test func testDevelopPromptOmitsCriticFeedbackSectionWhenAbsent() {
    let withoutFeedback = Prompts.developPrompt(
      next: PlanNext(
        plan: "p", verify: "swift build", verifyTimeoutMs: nil, estimatedDifficulty: nil),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )
    #require(!withoutFeedback.contains("Critic feedback from prior passes"))
  }
}
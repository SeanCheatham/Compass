import Testing

@testable import Compass

struct DevelopFeedbackValidatorTests {
  @Test func rejectsEmptyGenericAndTinyFeedback() throws {
    let cases: [(String, DevelopFeedbackValidationError.Reason)] = [
      ("", .empty),
      ("done", .placeholder),
      ("OK", .placeholder),
      ("All good.", .placeholder),
      ("compile failed", .tooShort),
    ]

    for (feedback, reason) in cases {
      do {
        try DevelopFeedbackValidator.validate(
          DevelopSummary(status: .succeeded, summary: "Attempted the slice.", feedback: feedback)
        )
        Issue.record("Expected feedback `\(feedback)` to be rejected.")
      } catch let error as DevelopFeedbackValidationError {
        try #require(error.reason == reason)
      }
    }
  }

  @Test func acceptsConcreteSuccessAndFailureHandoffs() throws {
    try DevelopFeedbackValidator.validate(
      DevelopSummary(
        status: .succeeded,
        summary: "Queued draft readiness is visible in run controls.",
        feedback:
          "Run controls now show queued draft readiness; no follow-up unless the copy needs tuning."
      )
    )

    try DevelopFeedbackValidator.validate(
      DevelopSummary(
        status: .failed,
        summary: "The implementation could not compile.",
        feedback:
          "Swift compile still fails in PlanReliabilityFeedback; next Plan should repair the changed initializer."
      )
    )
  }
}

struct CriticFeedbackValidatorTests {
  @Test func allowsApproveWithoutFeedback() throws {
    try CriticFeedbackValidator.validate(
      CriticVerdict(verdict: .approve, summary: "No blocking issues found.", feedback: "")
    )
  }

  @Test func rejectsRequestChangesWithoutConcreteFeedback() throws {
    let cases: [(String, CriticFeedbackValidationError.Reason)] = [
      ("", .empty),
      ("needs work", .placeholder),
      ("fix it", .placeholder),
      ("missing tests", .tooShort),
    ]

    for (feedback, reason) in cases {
      do {
        try CriticFeedbackValidator.validate(
          CriticVerdict(verdict: .requestChanges, summary: "Issue found.", feedback: feedback)
        )
        Issue.record("Expected critic feedback `\(feedback)` to be rejected.")
      } catch let error as CriticFeedbackValidationError {
        try #require(error.reason == reason)
      }
    }
  }

  @Test func acceptsConcreteRequestChangesFeedback() throws {
    try CriticFeedbackValidator.validate(
      CriticVerdict(
        verdict: .requestChanges,
        summary: "The fallback path is untested.",
        feedback:
          "Add a DraftReadinessGuide fallback test covering empty queues before approving."
      )
    )
  }
}

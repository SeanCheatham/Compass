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

struct DevelopVerifyBypassValidatorTests {
  @Test func ignoresNormalVerifyRuns() throws {
    try DevelopVerifyBypassValidator.validate(
      DevelopSummary(
        status: .succeeded,
        summary: "Implemented the slice.",
        feedback: "Draft readiness now appears in run controls; no follow-up unless copy needs tuning.",
        bypassVerify: false
      )
    )
  }

  @Test func rejectsBypassWithoutVerifySpecificReason() throws {
    let cases: [(summary: String, feedback: String, reason: DevelopVerifyBypassValidationError.Reason)] = [
      (
        "Implemented the slice.",
        "Draft readiness now appears in run controls; no follow-up unless copy needs tuning.",
        .missingReason
      ),
      (
        "Implemented the slice and skipped verify.",
        "Verify was skipped; next Plan can continue with the queue.",
        .genericReason
      ),
      (
        "Implemented the slice and skipped verify.",
        "Verify is unavailable in this environment; next Plan can continue with the queue.",
        .genericReason
      ),
    ]

    for testCase in cases {
      do {
        try DevelopVerifyBypassValidator.validate(
          DevelopSummary(
            status: .succeeded,
            summary: testCase.summary,
            feedback: testCase.feedback,
            bypassVerify: true
          )
        )
        Issue.record("Expected bypass feedback `\(testCase.feedback)` to be rejected.")
      } catch let error as DevelopVerifyBypassValidationError {
        try #require(error.reason == testCase.reason)
      }
    }
  }

  @Test func acceptsConcreteVerifyCommandBypassReason() throws {
    try DevelopVerifyBypassValidator.validate(
      DevelopSummary(
        status: .succeeded,
        summary: "Implemented the slice; the planned verify command targets a deleted test suite.",
        feedback:
          "Verify command is wrong because DraftReadinessOldTests no longer exists; next Plan should replace it with DraftRefinementTests.",
        bypassVerify: true
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

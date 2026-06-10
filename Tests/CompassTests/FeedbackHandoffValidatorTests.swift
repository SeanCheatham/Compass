import Testing

@testable import CompassCore

@Suite("FeedbackHandoffValidator")
struct FeedbackHandoffValidatorTests {
  @Test
  func rejectsSucceededDevelopFeedbackThatLeavesImplementationWork() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Updated the core utility.",
      feedback: "Next step: Update the CLI to use the new utility and print the summary.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected unfinished success feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.message.contains("status=succeeded"))
      #expect(error.message.contains("planned work remains"))
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackThatOnlyAsksToRunVerify() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Edited the utility.",
      feedback: "Run `pnpm verify` to check if the changes pass the verification process.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected run-verify feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("pnpm verify") == true)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackWithNextActionWork() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Created the utility file.",
      feedback: "Next action: Update the CLI in packages/cli/src/main.ts to use the summary.",
      bypassVerify: false
    )

    #expect(throws: DevelopFeedbackValidationError.self) {
      try DevelopFeedbackValidator.validate(summary)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackStartingWithImperativeWork() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Created the utility file.",
      feedback: "Update the CLI in packages/cli/src/main.ts and add a test for the summary.",
      bypassVerify: false
    )

    #expect(throws: DevelopFeedbackValidationError.self) {
      try DevelopFeedbackValidator.validate(summary)
    }
  }

  @Test
  func acceptsSucceededDevelopFeedbackWithVerifiedResult() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Updated the CLI and tests.",
      feedback: "Verified pnpm verify passes with the CLI summary assertion in main.test.ts.",
      bypassVerify: false
    )

    try DevelopFeedbackValidator.validate(summary)
  }
}

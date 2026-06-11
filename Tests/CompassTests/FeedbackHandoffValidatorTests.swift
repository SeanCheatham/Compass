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
  func rejectsSucceededDevelopFeedbackWithBareNextWork() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Moved the existing summarizeCLI function to packages/cli/src/summarize.ts.",
      feedback:
        "Next, create tests for the new `summarizeCLI` function in `packages/cli/src/summarize.test.ts`.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected bare next-work feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("Next, create tests") == true)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackWithNextDiscoveryWork() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Requested the current package.json to determine the next verification command.",
      feedback: "Next action: Choose the relevant verify command from the scripts in package.json.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected next-discovery feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("Choose the relevant verify command") == true)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackThatOnlyReadsForNextSteps() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Read the current scripts from package.json to determine the next steps.",
      feedback: "Read the current scripts to determine the next steps.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected read-for-next-steps feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("determine the next steps") == true)
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
  func rejectsSucceededDevelopFeedbackStartingWithEditAndPrepare() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Moved existing logic to packages/cli/src/summarize.ts.",
      feedback: "Edit the existing file with the new logic and prepare for adding a test function next.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected edit-and-prepare feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("prepare for adding a test") == true)
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

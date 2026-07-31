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
      feedback: "Run `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` to check if the changes pass the verification process.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected run-verify feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace") == true)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackThatOnlyAsksToRunVerification() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Implemented the CLI flag.",
      feedback: "Run the verification command to ensure the implementation is correct.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected run-verification feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("verification command") == true)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackWithNextRunVerification() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Updated the CLI entrypoint.",
      feedback: "Next, run the verification command before reporting success.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected next-run feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("Next, run") == true)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackThatAsksToVerifyChanges() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Created the summarize helper.",
      feedback: "Verify the changes with `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace`.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected verify-changes feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("Verify the changes") == true)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackWithFutureWorkPhrase() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Read package.json to understand current scripts.",
      feedback: "Now I will create the `summarize.ts` file and move the existing logic there.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected future-work feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("Now I will create") == true)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackWithNextActionWork() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Created the utility file.",
      feedback: "Next action: Update the CLI in crates/app-cli/src/main.rs to use the summary.",
      bypassVerify: false
    )

    #expect(throws: DevelopFeedbackValidationError.self) {
      try DevelopFeedbackValidator.validate(summary)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackWithProceedWork() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Moved the existing logic from main.ts to summarize.ts.",
      feedback: "Proceed to create the test file next.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected proceed-work feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("Proceed to create") == true)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackWithBareNextWork() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Moved the existing summarizeCLI function to crates/app-cli/src/summarize.rs.",
      feedback:
        "Next, create tests for the new `summarizeCLI` function in `crates/app-cli/tests/summarize.rs`.",
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
      feedback: "Update the CLI in crates/app-cli/src/main.rs and add a test for the summary.",
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
      summary: "Moved existing logic to crates/app-cli/src/summarize.rs.",
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
  func rejectsSucceededDevelopFeedbackThatReportsVerifyFailure() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Added the CLI JSON flag and touched the tests.",
      feedback: "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace now fails due to type errors. Resolve the type errors before proceeding.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected verify-failure feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("fails") == true)
    }
  }

  @Test
  func rejectsSucceededDevelopFeedbackThatReportsSyntaxError() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Updated the CLI entrypoint.",
      feedback: "Fix the syntax error in crates/app-cli/src/main.rs and then run cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace again.",
      bypassVerify: false
    )

    do {
      try DevelopFeedbackValidator.validate(summary)
      Issue.record("Expected syntax-error feedback rejection.")
    } catch let error as DevelopFeedbackValidationError {
      #expect(error.reason == .unfinishedSuccess)
      #expect(error.feedback?.contains("Fix the syntax error") == true)
    }
  }

  @Test
  func acceptsSucceededDevelopFeedbackAboutFixedFailingTest() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Updated the CLI and tests.",
      feedback: "Fixed the failing CLI assertion and verified cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes.",
      bypassVerify: false
    )

    try DevelopFeedbackValidator.validate(summary)
  }

  @Test
  func acceptsSucceededDevelopFeedbackWithVerifiedResult() throws {
    let summary = DevelopSummary(
      status: .succeeded,
      summary: "Updated the CLI and tests.",
      feedback: "Verified cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes with the CLI summary assertion in main.test.ts.",
      bypassVerify: false
    )

    try DevelopFeedbackValidator.validate(summary)
  }
}

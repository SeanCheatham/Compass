import Foundation
import Testing
@testable import Compass
@testable import CompassCore

@Suite("Prompt nudges")
struct PromptNudgeTests {
@Test
  func modelDownloadingGuidesDoNotReportBlocked() {
    let snapshot = LocalModelSnapshot(
      runtimeName: LocalModelCatalog.runtimeName,
      modelID: LocalModelCatalog.blessedModelID,
      status: .downloading,
      progressFraction: 0.42,
      errorMessage: nil,
      directory: URL(fileURLWithPath: "/tmp/CompassModel")
    )
    let settings = AgentRuntimeSettings(textProvider: .mlx)

    let settingsGuide = AgentSettingsGuide(settings: settings, modelSnapshot: snapshot)
    #expect(settingsGuide.title == "Local Model Downloading")
    #expect(settingsGuide.actionLabel == "Downloading 42%")
    #expect(settingsGuide.tone == .optionalAttention)
    #expect(settingsGuide.rows.contains { $0.id == "mlxAssist" && $0.status == .attention })
    #expect(!settingsGuide.actionLabel.localizedCaseInsensitiveContains("blocked"))

  }
@Test
  func promptsDoNotMentionRemovedDirections() throws {
    let state = PlanProposal(from: PlanState.empty)
    let next = PlanNext(
      plan: "## Outcome\nAdd a Rust slice\n\n## Acceptance checks\n- cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes",
      verify: "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace",
      estimatedDifficulty: .low
    )
    let developSummary = DevelopSummary(
      status: .succeeded,
      summary: "Implemented the slice",
      feedback: "Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace",
      bypassVerify: false,
      lessonEdits: []
    )
    let prompts = [
      try Prompts.planPrompt(
        state: state,
        completedCount: 0,
        drafts: "",
        feedback: "",
        lessons: "",
        vision: "",
        focus: .feature,
      ),
      Prompts.developPrompt(
        next: next,
        lessons: "",
        vision: "",
        attempt: 1,
        priorIssues: []
      ),
      Prompts.criticPrompt(
        next: next,
        developSummary: developSummary,
        verifyCommand: "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace",
        verifyExitCode: 0,
        verifyOutput: "ok",
        gitDiff: "",
        priorCritiques: [],
        lessons: "",
        vision: "",
        iteration: 1,
        maxIterations: 2
      ),
      Prompts.agentSystemPrompt(
        phase: .develop,
        workingDirectoryPath: "/tmp/workspace"
      ),
    ].joined(separator: "\n")

    for removed in [
      "PMF",
      "Product Tournament",
      "MiniMax",
      "Foundation Models",
      "native tool calling",
      "remote providers",
      "TypeScript",
      "pnpm",
      "Vitest",
      "Vite",
    ] {
      #expect(!prompts.contains(removed))
    }
    #expect(prompts.contains("local software factory"))
    #expect(prompts.contains("Rust"))
    #expect(prompts.contains(GeneratedProjectQuality.standardVerifyCommand))
    #expect(prompts.contains("develop_continue"))
    #expect(prompts.contains("develop_submit"))
    #expect(prompts.contains("OpenAI-compatible"))
  }
@Test
  func developFirstAttemptPromptPrioritizesAcceptanceTestFiles() {
    let next = PlanNext(
      plan: """
        ## Outcome
        Implement `--streak` in `crates/cli/src/main.rs` with a core helper.

        ## Acceptance checks
        - `crates/core/src/lib.rs` covers the streak helper.
        - `crates/cli/tests/cli.rs` calls `main(["--streak", "done", "done"])`.
        """,
      verify: "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace",
      estimatedDifficulty: .low
    )

    let prompt = Prompts.developPrompt(
      next: next,
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )

    #expect(prompt.contains("Inspect the files implied by the Outcome and Acceptance checks"))
    #expect(prompt.contains("crates/cli/src/main.rs"))
    #expect(prompt.contains("crates/cli/tests/cli.rs"))
    #expect(prompt.contains("crates/core/src/lib.rs"))
    #expect(prompt.contains("crates/core/src/lib.rs"))
    #expect(prompt.contains("source-only edit"))
  }
@Test
  func developRetryPromptPrioritizesSuggestedTestTargets() {
    let next = PlanNext(
      plan: """
        ## Outcome
        Add signal board formatting

        ## Acceptance checks
        - `crates/cli/tests/cli.rs` calls `main(["--signal", "api:green"])`.
        """,
      verify: "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace",
      estimatedDifficulty: .low
    )

    let prompt = Prompts.developPrompt(
      next: next,
      lessons: "",
      vision: "",
      attempt: 2,
      priorIssues: [
        """
        Verify passed for `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace`, but coverage shows changed source files were not exercised.

        Suggested test targets:
        - `crates/core/tests/signal_board.rs` (write_file) should import and execute `crates/core/src/signal_board.rs`.
        """
      ]
    )

    #expect(prompt.contains("read and edit one of those exact"))
    #expect(
      prompt.contains("Do not start\na retry by rereading Cargo.toml")
        || prompt.contains("Do not start a retry by rereading Cargo.toml")
    )
    #expect(prompt.contains("Do not submit success or rerun verify until you have changed a file"))
    #expect(prompt.contains("crates/core/tests/signal_board.rs"))
  }
@Test
  func developRetryPromptPrioritizesRequestedTestFiles() {
    let next = PlanNext(
      plan: """
        ## Outcome
        Add JSON output support to the CLI.

        ## Acceptance checks
        - `crates/cli/tests/cli.rs` calls `main(["--format", "json", "Ship", "it"])`.
        """,
      verify: "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace",
      estimatedDifficulty: .low
    )

    let prompt = Prompts.developPrompt(
      next: next,
      lessons: "",
      vision: "",
      attempt: 4,
      priorIssues: [
        """
        Verify passed for `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace`, but the accepted plan or brief explicitly requires test changes and no test/spec file changed.

        Requested test file(s):
        - `crates/cli/tests/cli.rs`
        """
      ]
    )

    #expect(prompt.contains("If the prior issue lists Requested test file(s)"))
    #expect(prompt.contains("make your first write/edit target"))
    #expect(prompt.contains("Do not edit source files again until that requested test"))
    #expect(prompt.contains("crates/cli/tests/cli.rs"))
  }
@Test
  func coverageRepairNudgeNamesExactRustVerifyCommand() {
    let error = PlanTransitionValidationError(
      message: "Verify command must collect coverage.",
      reason: .coverageRequirement,
      missingLabels: ["Coverage-ready verify command"],
      rejectedVerify: "cargo test --workspace"
    )

    let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .plan)

    #expect(nudge.eventText == "plan_submit rejected")
    #expect(nudge.userMessage.contains("`cargo test --workspace`"))
    #expect(nudge.userMessage.contains(GeneratedProjectQuality.standardVerifyCommand))
  }
@Test
  func weakCLIProofNudgeShowsRepeatedSplitArgvShape() {
    let error = PlanTransitionValidationError(
      message:
        "Plan selected generic `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` for repeated `--signal` CLI behavior without a CLI test.",
      reason: .weakVerifyCoverage,
      rejectedVerify: "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
    )

    let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .plan)

    #expect(nudge.eventText == "plan_submit rejected")
    #expect(nudge.userMessage.contains("Do not resubmit the same Acceptance checks unchanged"))
    #expect(nudge.userMessage.contains("crates/cli/tests/cli.rs"))
    #expect(
      nudge.userMessage.contains(
        #"["--signal", "api:green", "--signal", "db:red"]"#
      )
    )
  }
@Test
  func unfinishedDevelopSuccessNudgeTellsAgentToContinueOrFail() {
    let error = DevelopFeedbackValidationError(
      message:
        "Develop reported status=succeeded, but feedback says planned work remains: `Run cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace`.",
      reason: .unfinishedSuccess,
      feedback: "Run `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` to check if the changes pass."
    )

    let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .develop)

    #expect(nudge.eventText == "develop_submit feedback rejected")
    #expect(nudge.userMessage.contains("Do not resubmit that success packet"))
    #expect(nudge.userMessage.contains("Return `develop_continue`"))
    #expect(nudge.userMessage.contains("status=failed"))
    #expect(nudge.userMessage.contains("status=blocked"))
    #expect(nudge.userMessage.contains("Return status=succeeded only after"))
    #expect(nudge.userMessage.contains("Detected missing verification command"))
    #expect(nudge.userMessage.contains(#""tool": "bash""#))
    #expect(nudge.userMessage.contains("cargo test --workspace"))
    #expect(nudge.userMessage.contains("Do not call `read_file`"))
  }
@Test
  func macOSVMPromptAndToolsAreRustGenerated() {
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/example/repo"
    )
    let toolNames = Set(ToolRegistry.tools(for: .develop).map(\.spec.name))

    #expect(prompt.contains("embedded macOS VM"))
    #expect(prompt.contains("Working directory: /workspace"))
    #expect(!prompt.contains("/Users/example/repo"))
    #expect(prompt.contains("/workspace"))
    #expect(prompt.contains("Rust toolchain"))
    #expect(prompt.contains("Swift toolchain"))
    #expect(!toolNames.contains("list_toolchains"))
    #expect(!toolNames.contains("install_toolchain"))
  }
}

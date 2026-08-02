import Foundation
import Testing

@testable import Compass
@testable import CompassCore

@Suite("Factory pivot")
struct FactoryPivotTests {
  @Test
  func factoryStateCreatesAndEncodesNewShape() throws {
    let state = PlanState.empty

    #expect(state.schemaVersion == 1)
    #expect(state.brief == .empty)
    #expect(state.queue.isEmpty)
    #expect(state.immediate == nil)
    #expect(state.completed.isEmpty)
    #expect(state.openQuestions.isEmpty)
    #expect(state.products == GeneratedProducts.default)

    let data = try JSONEncoder().encode(state)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"brief\""))
    #expect(json.contains("\"queue\""))
    #expect(json.contains("\"immediate\""))
    #expect(json.contains("\"products\""))
    #expect(!json.contains("\"strategicContext\""))
    #expect(!json.contains("\"candidates\""))
  }

  @Test
  func factoryStateDecodesLegacyPlanningShape() throws {
    let legacy = """
      {
        "completed": ["first"],
        "strategicContext": {
          "thesis": "Ship a tiny app",
          "principles": ["Be useful"],
          "risks": ["Verify with tests"]
        },
        "candidates": [
          {
            "id": "slice-one",
            "title": "Add the first slice",
            "outcome": "The workspace has a runnable check",
            "why": "It gives Develop a finish line",
            "category": "test",
            "origin": "plan",
            "priority": "high",
            "status": "available",
            "evidence": [],
            "blockedBy": []
          }
        ]
      }
      """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(PlanState.self, from: legacy)

    #expect(decoded.schemaVersion == 1)
    #expect(decoded.completed == ["first"])
    #expect(decoded.brief.summary == "Ship a tiny app")
    #expect(decoded.brief.desiredOutcomes == ["Be useful"])
    #expect(decoded.brief.acceptanceSignals == ["Verify with tests"])
    #expect(decoded.queue.map(\.id) == ["slice-one"])
  }

  @Test
  func planQueueDecodesHumanEnumAliases() throws {
    let payload = """
      {
        "state": {
          "immediate": {
            "plan": "## Outcome\\nAdd loud CLI output.\\n\\n## Acceptance checks\\n- cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes",
            "verify": "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace",
            "verifyTimeoutMs": 600000,
            "estimatedDifficulty": "low",
            "selectedBecause": "First useful slice.",
            "source": "repository",
            "candidateID": null
          },
          "queue": [
            {
              "id": "1",
              "title": "Update CLI implementation",
              "outcome": "Handle the --loud flag.",
              "why": "Implements the requested behavior.",
              "category": "Development",
              "origin": "User request",
              "priority": "High",
              "status": "Open",
              "evidence": [],
              "blockedBy": []
            },
            {
              "id": "2",
              "title": "Update tests",
              "outcome": "Cover loud output.",
              "why": "Protects the new behavior.",
              "category": "Testing",
              "origin": "repo",
              "priority": "Medium",
              "status": "In progress",
              "evidence": [],
              "blockedBy": []
            }
          ],
          "brief": {
            "summary": "Add loud CLI output.",
            "targetUsers": [],
            "desiredOutcomes": [],
            "constraints": [],
            "acceptanceSignals": []
          },
          "openQuestions": []
        },
        "lessonEdits": []
      }
      """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(PlanRunResult.self, from: payload)

    #expect(decoded.state.candidates.map(\.category) == [PlanCandidate.Category.feature, .test])
    #expect(decoded.state.candidates.map(\.origin) == [PlanCandidate.Origin.user, .repository])
    #expect(decoded.state.candidates.map(\.priority) == [PlanCandidate.Priority.high, .medium])
    #expect(decoded.state.candidates.map(\.status) == [PlanCandidate.Status.available, .active])
  }

  @Test
  func applyingPlanProposalPreservesOmittedBriefFields() {
    let current = PlanState(
      completed: [],
      immediate: nil,
      brief: PlanStrategicContext(
        summary: "Build decision notes.",
        targetUsers: ["Product teams"],
        desiredOutcomes: ["List decision records"],
        constraints: ["No new dependencies"],
        acceptanceSignals: ["cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes"]
      )
    )
    let proposal = PlanProposal(
      immediate: PlanNext(
        plan: "## Outcome\nAdd decision records\n\n## Acceptance checks\n- cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes",
        verify: "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
      ),
      candidates: [],
      strategicContext: PlanStrategicContext(summary: "Build decision notes."),
      openQuestions: []
    )

    let next = proposal.applying(to: current)

    #expect(next.brief.summary == "Build decision notes.")
    #expect(next.brief.targetUsers == ["Product teams"])
    #expect(next.brief.desiredOutcomes == ["List decision records"])
    #expect(next.brief.constraints == ["No new dependencies"])
    #expect(next.brief.acceptanceSignals == ["cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes"])
  }

  @Test
  func hybridRuntimeReadiness() {
    let cloud = AgentRuntimeSettings(
      textProvider: .openAICompatible,
      baseURL: URL(string: "https://api.example.com/v1")!,
      apiKey: "sk-test",
      model: "example-model"
    )
    #expect(cloud.textProvider == .openAICompatible)
    #expect(cloud.textProvider.requiresCredentials == true)
    #expect(AgentCapability.allCases == [.text])
    #expect(AgentProviderKind.allCases == [.openAICompatible, .mlx])
    #expect(cloud.model(for: .plan) == "example-model")
    #expect(cloud.isTextCapabilityRunnable(localModelReady: false))
    #expect(cloud.isTextCapabilityRunnable(localModelReady: true))
    #expect(cloud.hasCloudCredentials)

    let local = AgentRuntimeSettings(textProvider: .mlx)
    #expect(local.textProvider == .mlx)
    #expect(local.textProvider.requiresCredentials == false)
    #expect(local.model(for: .plan) == LocalModelCatalog.blessedModelID)
    #expect(local.isTextCapabilityRunnable(localModelReady: true))
    #expect(!local.isTextCapabilityRunnable(localModelReady: false))
  }

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
  func rustScaffoldHasCargoWorkspaceAndCrates() throws {
    let files = RustProjectScaffold.files(
      options: .init(projectName: "My Factory App")
    )
    let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.contents) })

    #expect(byPath.keys.contains("Cargo.toml"))
    #expect(byPath.keys.contains("rust-toolchain.toml"))
    #expect(byPath.keys.contains("crates/core/Cargo.toml"))
    #expect(byPath.keys.contains("crates/cli/Cargo.toml"))
    #expect(byPath.keys.contains("crates/core/src/lib.rs"))
    #expect(byPath.keys.contains("crates/cli/src/main.rs"))
    #expect(byPath.keys.contains("crates/cli/tests/cli.rs"))
    #expect(byPath.keys.contains("crates/ffi/Cargo.toml"))
    #expect(byPath.keys.contains("apps/macos/Package.swift"))
    #expect(byPath.keys.contains("apps/macos/Sources/AppFFI/Placeholder.swift"))
    #expect(byPath.keys.contains("apps/macos/Sources/app_ffiFFI/shim.c"))
    #expect(byPath.keys.contains("apps/macos/Sources/app_ffiFFI/include/.gitkeep"))
    #expect(byPath.keys.contains("apps/macos/Tests/GeneratedAppTests/GreetingFFITests.swift"))
    #expect(byPath.keys.contains("apps/macos/Info.plist"))
    #expect(byPath.keys.contains("scripts/generate-bindings.sh"))
    #expect(byPath.keys.contains("scripts/bundle-macos.sh"))
    #expect(byPath.keys.contains("scripts/verify-macos.sh"))

    let app = try #require(byPath["apps/macos/Sources/GeneratedApp/GeneratedApp.swift"])
    #expect(app.contains("import AppFFI"))
    #expect(!byPath.keys.contains("apps/macos/Sources/GeneratedApp/GreetingBridge.swift"))

    let ffi = try #require(byPath["crates/ffi/src/lib.rs"])
    #expect(ffi.contains("uniffi::Record"))
    #expect(ffi.contains("uniffi::Error"))
    #expect(ffi.contains("Result<String, GreetingError>"))

    let verify = try #require(byPath["scripts/verify-macos.sh"])
    #expect(verify.contains("swift test"))
    #expect(verify.contains("swift-format"))

    let workspace = try #require(byPath["Cargo.toml"])
    #expect(workspace.contains("crates/core"))
    #expect(workspace.contains("crates/cli"))
    #expect(workspace.contains("crates/ffi"))

    let readme = try #require(byPath["README.md"])
    #expect(readme.contains("cargo llvm-cov"))
    #expect(readme.contains("verify-macos"))
  }

  @Test
  func rustScaffoldCliOnlyOmitsMacOS() throws {
    let files = RustProjectScaffold.files(
      options: .init(projectName: "CLI Only", products: [.cli])
    )
    let paths = Set(files.map(\.path))
    #expect(paths.contains("crates/core/Cargo.toml"))
    #expect(paths.contains("crates/cli/Cargo.toml"))
    #expect(!paths.contains("crates/ffi/Cargo.toml"))
    #expect(!paths.contains("apps/macos/Package.swift"))
    #expect(!paths.contains("scripts/verify-macos.sh"))
  }

  @Test
  func rustScaffoldMacOSOnlyOmitsCLI() throws {
    let files = RustProjectScaffold.files(
      options: .init(projectName: "Mac Only", products: [.macos])
    )
    let paths = Set(files.map(\.path))
    #expect(paths.contains("crates/core/Cargo.toml"))
    #expect(paths.contains("crates/ffi/Cargo.toml"))
    #expect(paths.contains("apps/macos/Package.swift"))
    #expect(!paths.contains("crates/cli/Cargo.toml"))
  }

  @Test
  func rustScaffoldDetectsGeneratedWorkspace() throws {
    let tempURL = FileManager.default.temporaryDirectory
      .appending(path: "CompassRustScaffoldTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: tempURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try RustProjectScaffold.write(
      to: tempURL,
      options: .init(projectName: "Detected App", products: [.cli])
    )

    #expect(RustProjectScaffold.isGeneratedWorkspace(at: tempURL))
    #expect(RepositoryManifestHint.cargoToml.language == .rust)
  }

  @Test
  func generatedVerifyGateAcceptsCompassStandardVerify() {
    let standardVerify =
      GeneratedProjectQuality.standardVerifyCommand
    #expect(
      GeneratedVerifyValidator.coverageViolation(verify: standardVerify) == nil
    )
    #expect(
      GeneratedVerifyValidator.coverageViolation(verify: "cargo llvm-cov --workspace --summary-only")
        == nil
    )
    #expect(
      GeneratedVerifyValidator.coverageViolation(verify: "cargo test --workspace") == nil
    )

    let violation = GeneratedVerifyValidator.coverageViolation(verify: "echo ok")
    #expect(violation != nil)
    #expect(violation?.contains("llvm-cov") == true)
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
  func droppedBriefNudgeTellsPlanToResubmitWithoutTools() {
    let error = PlanTransitionValidationError(
      message: """
        Plan tried to drop non-empty brief fields: brief.acceptanceSignals.

        Set `state.brief` exactly to this current brief in the next `plan_submit`:
        ```json
        {"acceptanceSignals":["cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes"],"constraints":[],"desiredOutcomes":[],"summary":"Build the slice.","targetUsers":[]}
        ```
        """,
      reason: .invalidStateMutation,
      missingLabels: ["brief.acceptanceSignals"]
    )

    let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .plan)

    #expect(nudge.eventText == "plan_submit rejected")
    #expect(nudge.userMessage.contains("Do not call another tool"))
    #expect(nudge.userMessage.contains("copy the current `state.brief` exactly"))
    #expect(nudge.userMessage.contains(#""acceptanceSignals":["cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes"]"#))
  }

  @Test
  func ungroundedPathNudgeTellsPlanToResubmitWithoutTools() {
    let error = PlanTransitionValidationError(
      message: """
        Plan named file paths that do not exist in the repo:
        - crates/cli/test/cli.rs (nearest existing directory: packages/cli; entries: package.json, src/, tsconfig.json; same filename exists at: crates/cli/tests/cli.rs)

        Repair the handoff without calling another tool.
        """,
      reason: .ungroundedPaths
    )

    let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .plan)

    #expect(nudge.eventText == "plan_submit rejected")
    #expect(nudge.userMessage.contains("Do not call another tool"))
    #expect(nudge.userMessage.contains("same-filename match"))
    #expect(nudge.userMessage.contains("crates/cli/tests/cli.rs"))
    #expect(nudge.userMessage.contains("create new file <path>"))
  }

  @Test
  func planQueueDecodeNudgeTellsPlanToUseEmptyQueueWithoutTools() throws {
    let invalidPayload = """
      {
        "state": {
          "immediate": {
            "plan": "## Outcome\\nAdd decision records.\\n\\n## Acceptance checks\\n- cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes",
            "verify": "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace",
            "verifyTimeoutMs": 600000,
            "estimatedDifficulty": "low",
            "selectedBecause": "First useful slice.",
            "source": "repository",
            "candidateID": null
          },
          "queue": [
            { "title": "Wire the web UI later" }
          ],
          "brief": {
            "summary": "Build decision notes.",
            "targetUsers": [],
            "desiredOutcomes": [],
            "constraints": [],
            "acceptanceSignals": []
          },
          "openQuestions": []
        },
        "lessonEdits": []
      }
      """.data(using: .utf8)!

    do {
      _ = try JSONDecoder().decode(PlanRunResult.self, from: invalidPayload)
      Issue.record("Expected invalid queue payload to fail decoding.")
    } catch {
      let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .plan)

      #expect(nudge.eventText == "phase payload contract rejected")
      #expect(nudge.userMessage.contains("Plan queue repair"))
      #expect(nudge.userMessage.contains(#"set `"queue": []`"#))
      #expect(nudge.userMessage.contains("Do not call a tool just to repair queue JSON"))
      #expect(nudge.userMessage.contains("Do not call another tool"))
      #expect(nudge.userMessage.contains("`id`, `title`, `outcome`"))
    }
  }

  @Test
  func planQueueEnumDecodeNudgeNamesAllowedValues() throws {
    let invalidPayload = """
      {
        "state": {
          "immediate": {
            "plan": "## Outcome\\nAdd decision records.\\n\\n## Acceptance checks\\n- cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes",
            "verify": "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace",
            "verifyTimeoutMs": 600000,
            "estimatedDifficulty": "low",
            "selectedBecause": "First useful slice.",
            "source": "repository",
            "candidateID": null
          },
          "queue": [
            {
              "id": "security-work",
              "title": "Review security",
              "outcome": "Review the slice.",
              "why": "The model invented an unsupported category.",
              "category": "Security",
              "origin": "user",
              "priority": "high",
              "status": "available",
              "evidence": [],
              "blockedBy": []
            }
          ],
          "brief": {
            "summary": "Build decision notes.",
            "targetUsers": [],
            "desiredOutcomes": [],
            "constraints": [],
            "acceptanceSignals": []
          },
          "openQuestions": []
        },
        "lessonEdits": []
      }
      """.data(using: .utf8)!

    do {
      _ = try JSONDecoder().decode(PlanRunResult.self, from: invalidPayload)
      Issue.record("Expected invalid queue enum payload to fail decoding.")
    } catch {
      let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .plan)

      #expect(nudge.eventText == "phase payload contract rejected")
      #expect(nudge.userMessage.contains("Plan enum repair"))
      #expect(nudge.userMessage.contains("`category`: feature, test, cleanup"))
      #expect(nudge.userMessage.contains("`status`: available, active"))
      #expect(nudge.userMessage.contains("Do not call a tool just to repair queue JSON"))
    }
  }

  @Test
  func weakCLIProofNudgeTellsPlanToRepairWithoutTools() {
    let error = PlanTransitionValidationError(
      message: """
        Plan selected generic `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` for new CLI behavior, but the handoff does not include a CLI test or direct proof.

        `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` only proves this packet if Develop also adds or updates a test for the claimed CLI behavior, such as `crates/cli/tests/cli.rs`.
        """,
      reason: .weakVerifyCoverage,
      rejectedVerify: "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
    )

    let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .plan)

    #expect(nudge.eventText == "plan_submit rejected")
    #expect(nudge.userMessage.contains("Do not call another tool"))
    #expect(nudge.userMessage.contains("crates/cli/tests/cli.rs"))
    #expect(nudge.userMessage.contains(#"["--format", "json", "Ship", "it"]"#))
    #expect(nudge.userMessage.contains("parsed JSON title is `Ship it`"))
    #expect(nudge.userMessage.contains("Keep `state.immediate.verify` as `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace`"))
    #expect(nudge.userMessage.contains("narrow the Outcome to core-only work"))
    #expect(nudge.userMessage.contains("exactly one repair"))
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
  func containerRuntimePromptAndToolsAreRustGenerated() {
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/example/repo"
    )
    let toolNames = Set(ToolRegistry.tools(for: .develop).map(\.spec.name))

    #expect(prompt.contains("containerized Linux runtime"))
    #expect(prompt.contains("Working directory: /workspace"))
    #expect(!prompt.contains("/Users/example/repo"))
    #expect(prompt.contains("/workspace"))
    #expect(prompt.contains("Docker, Xcode"))
    #expect(prompt.contains("Homebrew are unavailable"))
    #expect(!toolNames.contains("list_toolchains"))
    #expect(!toolNames.contains("install_toolchain"))
  }

  @Test
  func continuationParserAcceptsValidContinuePerPhase() throws {
    let tools: Set<String> = ["read_file", "bash"]
    for phase in AgentContinuationPhase.allCases {
      let json = """
        {
          "kind": "\(phase.continueKind)",
          "tool": "read-file",
          "arguments": { "path": "package.json" },
          "reason": "Need scripts.",
          "note": "  If scripts exist, choose the matching verify command.  "
        }
        """
      let parsed = try AgentContinuationParser.parse(
        json,
        phase: phase,
        availableToolNames: tools
      )
      guard case .continueTool(let toolName, let arguments, let reason, let note) = parsed.action else {
        Issue.record("Expected continue action")
        return
      }
      #expect(toolName == "read_file")
      #expect(String(decoding: arguments, as: UTF8.self).contains("package.json"))
      #expect(reason == "Need scripts.")
      #expect(note == "If scripts exist, choose the matching verify command.")
    }
  }

  @Test
  func continuationParserUnwrapsSingleJSONCodeFence() throws {
    let json = """
      ```json
      {
        "kind": "plan_continue",
        "tool": "read_file",
        "arguments": {
          "path": "package.json"
        },
        "reason": "Need current package scripts."
      }
      ```
      """
    let parsed = try AgentContinuationParser.parse(
      json,
      phase: .plan,
      availableToolNames: ["read_file"]
    )

    guard case .continueTool(let toolName, let arguments, let reason, let note) = parsed.action else {
      Issue.record("Expected continue action")
      return
    }
    #expect(toolName == "read_file")
    #expect(String(decoding: arguments, as: UTF8.self).contains("package.json"))
    #expect(reason == "Need current package scripts.")
    #expect(note == nil)
  }

  @Test
  func continuationParserSanitizesAndRejectsNotes() throws {
    let emptyNote = try AgentContinuationParser.parse(
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"note":"   "}"#,
      phase: .develop,
      availableToolNames: ["read_file"]
    )
    guard case .continueTool(_, _, _, let empty) = emptyNote.action else {
      Issue.record("Expected continue action")
      return
    }
    #expect(empty == nil)

    let longNote = String(repeating: "x", count: AgentContinuationParser.noteCharacterLimit + 20)
    let longJSON = """
      {"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"note":"\(longNote)"}
      """
    let truncated = try AgentContinuationParser.parse(
      longJSON,
      phase: .develop,
      availableToolNames: ["read_file"]
    )
    guard case .continueTool(_, _, _, let note) = truncated.action else {
      Issue.record("Expected continue action")
      return
    }
    #expect(note?.count == AgentContinuationParser.noteCharacterLimit)

    #expect(throws: AgentContinuationParseError.noteNotString) {
      try AgentContinuationParser.parse(
        #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"note":{"next":"edit"}}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
  }

  @Test
  func continuationParserAcceptsValidSubmitPerPhase() throws {
    let payloads: [AgentContinuationPhase: String] = [
      .plan: #"{"state":{"immediate":null,"queue":[],"brief":{"summary":"","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}"#,
      .develop: #"{"status":"succeeded","summary":"Done","feedback":"Verified cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace","bypassVerify":false,"lessonEdits":[]}"#,
      .critic: #"{"verdict":"approve","summary":"No blockers","feedback":""}"#,
      .delegate: #"{"findings":"No blockers found."}"#,
    ]

    for phase in AgentContinuationPhase.allCases {
      let json = #"{"kind":"\#(phase.submitKind)","payload":\#(payloads[phase]!)}"#
      let parsed = try AgentContinuationParser.parse(
        json,
        phase: phase,
        availableToolNames: []
      )
      guard case .submit(let payload) = parsed.action else {
        Issue.record("Expected submit action")
        return
      }
      #expect(!payload.isEmpty)
    }
  }

  @Test
  func continuationParserRejectsMalformedAndInvalidContinuations() {
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse("not json", phase: .develop, availableToolNames: [])
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        """
        Here is the JSON:
        ```json
        {"kind":"develop_continue","tool":"read_file","arguments":{}}
        ```
        """,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        #"{"kind":"plan_continue","tool":"read_file","arguments":{}}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        #"{"kind":"develop_continue","tool":"missing","arguments":{}}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        #"{"kind":"develop_continue","tool":"read_file","arguments":[]}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
  }

  @Test
  func continuationParserExplainsBacktickTemplateLiteralJSON() {
    do {
      _ = try AgentContinuationParser.parse(
        """
        {
          "kind": "develop_continue",
          "tool": "edit_file",
          "arguments": {
            "path": "crates/cli/src/main.rs",
            "startLine": 1,
            "endLine": 1,
            "content": `const one = 1;
        const two = 2;`
          }
        }
        """,
        phase: .develop,
        availableToolNames: ["edit_file"]
      )
      Issue.record("Expected malformed JSON error")
    } catch let error as AgentContinuationParseError {
      let message = error.errorDescription ?? ""
      #expect(message.contains("backtick/template-literal strings are invalid"))
      #expect(message.contains("replacementLines as an array with one source line per string"))
      #expect(message.contains("Do not wrap content in backticks"))
    } catch {
      Issue.record("Expected AgentContinuationParseError, got \(error)")
    }
  }

  @Test
  func executorRunsToolObservationThenSubmitWithFakeRuntime() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try "export const answer = 42\n".write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current exports.","note":"after-read-note: edit this file if it exports answer."}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Read the file.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema
      )
    )

    #expect(result.iterations == 2)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 2)
    #expect(prompts[1].contains("export const answer"))
    #expect(prompts[1].contains("### Assistant Note (unverified)"))
    #expect(prompts[1].contains("after-read-note: edit this file if it exports answer."))
    if let observationRange = prompts[1].range(of: "### Compass Observation"),
      let noteRange = prompts[1].range(
        of: "### Assistant Note (unverified)",
        range: observationRange.upperBound..<prompts[1].endIndex
      )
    {
      let observationSection = String(prompts[1][observationRange.upperBound..<noteRange.lowerBound])
      #expect(!observationSection.contains("after-read-note"))
    } else {
      Issue.record("Expected separate observation and note sections")
    }
  }

  @Test
  func executorReturnsToolFailureObservationAndCanRecover() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"missing.ts"},"reason":"Need current contents."}"#,
      #"{"kind":"develop_submit","payload":{"status":"blocked","summary":"The file is missing.","feedback":"Plan should pick an existing file or create missing.ts explicitly.","bypassVerify":true,"lessonEdits":[]}}"#,
    ])
    _ = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema
      )
    )

    let prompts = await runtime.capturedPrompts()
    #expect(prompts[1].contains(#""isError" : true"#) || prompts[1].contains(#""isError":true"#))
    #expect(prompts[1].contains("File not found"))
  }

  @Test
  func executorEscalatesRepeatedIdenticalToolFailures() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    export function one() { return 1; }
    export function two() { return 2; }
    export function three() { return 3; }
    """.write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )
    let invalidEdit =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"index.ts","startLine":1,"endLine":1,"content":"import { next } from './next';\n\nexport function replacement() {\n  return next();\n}\n\nexport function extra() {\n  return 42;\n}"},"reason":"Replace the module."}"#

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current exports."}"#,
      invalidEdit,
      invalidEdit,
      #"{"kind":"develop_submit","payload":{"status":"blocked","summary":"The edit range needs correction.","feedback":"Use a different edit_file range based on read_file output.","bypassVerify":true,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool(), AgentEditFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("You repeated the exact same failed `edit_file` call 2 times"))
    #expect(prompts[3].contains("Do not call `edit_file` again with the same arguments"))
    #expect(prompts[3].contains("use its concrete repair shape"))
    #expect(prompts[3].contains("whole-file replacement"))
    #expect(prompts[3].contains("Do not submit"))
    #expect(prompts[3].contains("failed/blocked"))
    #expect(prompts[3].contains("previous edit range was wrong"))
    #expect(prompts[3].contains(#""path":"index.ts""#))
  }

  @Test
  func executorEscalatesRepeatedPartialRewriteFailureFamily() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    import { current } from "./current";
    export function one() { return 1; }
    export function two() { return 2; }
    export function three() { return 3; }
    export function four() { return 4; }
    export function five() { return 5; }
    """.write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )
    let replacement = """
    import { next } from './next';

    export function replacement() {
      return next();
    }

    export function extra() {
      return 42;
    }
    """
    let partialRewriteAtTop =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"index.ts","startLine":1,"endLine":1,"content":\#(jsonStringLiteral(replacement))},"reason":"Rewrite the module."}"#
    let partialRewriteShifted =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"index.ts","startLine":2,"endLine":2,"content":\#(jsonStringLiteral(replacement))},"reason":"Try a nearby range."}"#

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current exports."}"#,
      partialRewriteAtTop,
      partialRewriteShifted,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Could not repair the edit shape.","feedback":"The edit kept moving the same partial rewrite to nearby ranges.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool(), AgentEditFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("You repeated `edit_file` failures in the same repair family"))
    #expect(prompts[3].contains("Failure family: partial whole-file rewrite"))
    #expect(prompts[3].contains("Changing only `startLine`/`endLine`"))
    #expect(prompts[3].contains("use the full file range"))
    #expect(prompts[3].contains("Do not move the same multi-line replacement"))
    #expect(prompts[3].contains("Latest failure"))
    #expect(prompts[3].contains(#""path":"index.ts""#))
  }

  @Test
  func executorEscalatesRepeatedBodyOnlyFunctionReplacementFamily() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    export function main(argv = process.argv.slice(2)): string {
      const title = argv.join(" ").trim() || "First Compass task";
      return title;
    }

    console.log(main());
    """.write(
      to: tempURL.appending(path: "main.ts"),
      atomically: true,
      encoding: .utf8
    )
    let bodyOnly = """
      const count = Number.parseInt(argv[0] ?? "1", 10);
      const title = argv.slice(1).join(" ").trim() || "First Compass task";
      return `${count}: ${title}`;
    """
    let replaceDeclarationOnly =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"main.ts","startLine":1,"endLine":1,"content":\#(jsonStringLiteral(bodyOnly))},"reason":"Replace main logic."}"#
    let replaceDeclarationAndBody =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"main.ts","startLine":1,"endLine":3,"content":\#(jsonStringLiteral(bodyOnly))},"reason":"Try a wider range."}"#

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"main.ts"},"reason":"Need current main function."}"#,
      replaceDeclarationOnly,
      replaceDeclarationAndBody,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Could not repair the function edit.","feedback":"The edit kept replacing a declaration with body-only lines.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool(), AgentEditFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("You repeated `edit_file` failures in the same repair family"))
    #expect(prompts[3].contains("Failure family: body-only function declaration replacement"))
    #expect(prompts[3].contains("include the complete function declaration"))
    #expect(prompts[3].contains("edit only the body lines inside the function"))
    #expect(prompts[3].contains("Do not replace a function declaration line"))
    #expect(prompts[3].contains("Concrete repair arguments from the latest Compass Observation"))
    #expect(prompts[3].contains("Use these as the `arguments` for the next `edit_file` call"))
    #expect(prompts[3].contains(#""path":"main.ts""#))
    #expect(prompts[3].contains(#""startLine":1"#))
    #expect(prompts[3].contains(#""endLine":4"#))
    #expect(prompts[3].contains("export function main(argv = process.argv.slice(2)): string {"))
  }

  @Test
  func executorEscalatesRepeatedReadOnlyDevelopLoopBeforeSubmitRejection() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    export function main(argv = process.argv.slice(2)): string {
      return argv.join(" ");
    }
    """.write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )

    let readIndex =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current line numbers before editing."}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      readIndex,
      readIndex,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Did not edit the CLI.","feedback":"The model repeated reads instead of calling edit_file.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[2].contains("You repeated successful read-only Develop tool calls"))
    #expect(prompts[2].contains("Do not call `read_file` again with the same arguments"))
    #expect(prompts[2].contains("Choose exactly one next action"))
    #expect(prompts[2].contains("Call `edit_file` or `write_file`"))
    #expect(prompts[2].contains("status=failed or status=blocked"))
    #expect(prompts[2].contains(#""path":"index.ts""#))
  }

  @Test
  func executorEscalatesAlternatingReadOnlyDevelopLoop() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let readSource =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/src/main.rs"},"reason":"Need current CLI logic before editing."}"#
    let readTest =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/tests/cli.rs"},"reason":"Need current tests before editing."}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      readSource,
      readTest,
      readSource,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Did not edit the CLI.","feedback":"The model alternated reads instead of calling edit_file.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])
    let counter = ToolInvocationCounter()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [FakeReadFileTool(counter: counter)],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    #expect(counter.value == 3)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("You repeated successful read-only Develop tool calls"))
    #expect(prompts[3].contains("read-only tool calls in a row without changing files"))
    #expect(prompts[3].contains("seen 2 time(s) in that streak"))
    #expect(prompts[3].contains("Do not keep calling\n`read_file`")
      || prompts[3].contains("Do not keep calling `read_file`"))
    #expect(prompts[3].contains("Call `edit_file` or `write_file`"))
    #expect(prompts[3].contains(#""path":"crates/cli/src/main.rs""#))
  }

  @Test
  func executorRejectsToolCallAfterPlanSubmitRejection() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let planSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Build decision notes.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts."}"#
    let validator = RejectFirstPlanSubmitValidator()
    let runtime = FakeLocalModelRuntime(outputs: [
      planSubmit,
      readPackage,
      planSubmit,
    ])
    let counter = ToolInvocationCounter()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [FakeReadFileTool(counter: counter)],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 3,
        validateSubmitResult: { data in
          try validator.validate(data)
        }
      )
    )

    #expect(result.iterations == 3)
    #expect(counter.value == 0)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Your previous `plan_submit` payload could not be used"))
    #expect(prompts[1].contains("Required next shape:"))
    #expect(prompts[1].contains(#"{"kind":"plan_submit","payload":{...}}"#))
    #expect(!prompts[1].contains(#"Required shape:\n{"kind":"plan_continue""#))
    #expect(prompts[1].contains("Do not call `plan_continue`"))
    #expect(
      prompts[2].contains(
        "Your previous `plan_submit` was rejected because Compass rejected its payload"
      ))
    #expect(prompts[2].contains("The next action must repair that submit envelope"))
    #expect(prompts[2].contains("Compass did not run `read_file`"))
    #expect(prompts[2].contains("Do not call `read_file`, `list_files`, `bash`"))
    #expect(prompts[2].contains("For Plan, repair `state.immediate.plan` directly"))
    #expect(
      prompts[2].contains("Include both the target test file path and the concrete invocation"))
    #expect(prompts[2].contains(#"{"kind":"plan_submit","payload":{...}}"#))
    #expect(prompts[2].contains("Your previous Plan payload claimed new CLI behavior without proof"))
    #expect(prompts[2].contains("Do not call another tool to repair this"))
    #expect(prompts[2].contains(#"["--format", "json", "Ship", "it"]"#))
    #expect(prompts[2].contains(#""path":"package.json""#))
  }

  @Test
  func executorEscalatesRepeatedToolCallsAfterMalformedContinuationRejection() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try #"{"scripts":{"verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"}}"#.write(
      to: tempURL.appending(path: "package.json"),
      atomically: true,
      encoding: .utf8
    )

    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts."}"#
    let planSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Build decision notes.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      "not valid continuation json",
      readPackage,
      readPackage,
      planSubmit,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[1].contains("Your previous response could not be used"))
    #expect(prompts[3].contains("malformed Plan continuation response"))
    #expect(prompts[3].contains("called\n`read_file` with the same arguments 2 times")
      || prompts[3].contains("called `read_file` with the same arguments 2 times"))
    #expect(prompts[3].contains("did not repair the rejected continuation"))
    #expect(prompts[3].contains("Do not call `read_file`, `list_files`, or reread"))
    #expect(prompts[3].contains("Return `plan_submit` with a corrected `payload`"))
    #expect(prompts[3].contains("Latest continuation repair to apply now"))
    #expect(prompts[3].contains("Invalid response"))
    #expect(prompts[3].contains(#""path":"package.json""#))
  }

  @Test
  func executorEscalatesRepeatedSubmitRejections() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let weakPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Add JSON CLI output.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      weakPlanSubmit,
      weakPlanSubmit,
      weakPlanSubmit,
    ])
    let validator = RejectFirstTwoPlanSubmitValidator()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 3,
        validateSubmitResult: { data in
          try validator.validate(data)
        }
      )
    )

    #expect(result.iterations == 3)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Your previous Plan payload claimed new CLI behavior without proof"))
    #expect(prompts[2].contains("Compass rejected `plan_submit` for the same reason 2 times"))
    #expect(prompts[2].contains("Do not return the same payload again"))
    #expect(prompts[2].contains("Plan repair checklist"))
    #expect(prompts[2].contains("Do not resubmit the same `state.immediate.plan`"))
    #expect(prompts[2].contains("Keep `state.immediate.verify` as `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace`"))
    #expect(prompts[2].contains(#"["--format", "json", "Ship", "it"]"#))
    #expect(prompts[2].contains("Latest rejected-payload repair to apply now"))
  }

  @Test
  func executorGivesConcreteVerifyCommandAfterUnfinishedDevelopSuccess() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try #"{"scripts":{"verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"}}"#.write(
      to: tempURL.appending(path: "package.json"),
      atomically: true,
      encoding: .utf8
    )

    let unfinishedSubmit =
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Edited main.ts.","feedback":"Run `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` to check if the changes meet the acceptance criteria.","bypassVerify":false,"lessonEdits":[]}}"#
    let readPackage =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current package scripts."}"#
    let runVerify =
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run the missing verification command before submitting success."}"#
    let finishedSubmit =
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Verified the completed packet.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace; no follow-up work remains.","bypassVerify":false,"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      unfinishedSubmit,
      readPackage,
      readPackage,
      runVerify,
      finishedSubmit,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          AgentReadFileTool(),
          FakeBashTool(output: "[stdout]\nAll checks passed.\n\n[exit 0]\n\n[next]\nSubmit success."),
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 5,
        validateSubmitResult: { data in
          let summary = try JSONDecoder().decode(DevelopSummary.self, from: data)
          try DevelopFeedbackValidator.validate(summary)
        }
      )
    )

    #expect(result.iterations == 5)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 5)
    #expect(prompts[1].contains("Detected missing verification command"))
    #expect(prompts[1].contains(#""tool": "bash""#))
    #expect(prompts[1].contains("cargo clippy"))
    #expect(prompts[1].contains("Do not call `read_file`"))
    #expect(prompts[3].contains("If the rejected payload said a verify command still needs to run"))
    #expect(prompts[3].contains("Do not call `read_file`, `list_files`, or reread"))
  }

  @Test
  func executorRejectsFailedDevelopSubmitAfterSuccessfulVerify() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run verification."}"#,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Typecheck failed due to a missing summarizeQueue import.","feedback":"Fix the summarizeQueue import before trying again.","bypassVerify":false,"lessonEdits":[]}}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Verification passed after the requested changes.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace; the packet is ready for Plan.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [FakeBashTool(output: "[stdout]\nAll checks passed.\n\n[exit 0]\n\n[next]\nSubmit success.")],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("Compass already observed this verify command pass"))
    #expect(prompts[2].contains("status=failed, bypassVerify=false"))
    #expect(prompts[2].contains("return `develop_submit` again with"))
  }

  @Test
  func executorClearsSuccessfulVerifyAfterFileMutation() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run baseline verification."}"#,
      #"{"kind":"develop_continue","tool":"write_file","arguments":{"path":"generated.ts","content":"export const generated = true;\n"},"reason":"Repair missing acceptance check: generated.ts must exist after verify."}"#,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"A later file mutation still needs verification.","feedback":"Run cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace after generated.ts was created.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          FakeBashTool(output: "[stdout]\nBaseline passed.\n\n[exit 0]\n\n[next]\nSubmit success."),
          AgentWriteFileTool(),
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("failed"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("You just changed files with `write_file` after Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("That earlier verify result no longer proves the current worktree"))
    #expect(prompts[2].contains("call `bash` with `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` again"))
    #expect(!prompts[2].contains("Compass already observed this verify command pass"))
  }

  @Test
  func executorRejectsGenericFileMutationAfterSuccessfulVerify() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run verification."}"#,
      #"{"kind":"develop_continue","tool":"write_file","arguments":{"path":"generated.ts","content":"export const generated = true;\n"},"reason":"Create the file after verify."}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"The packet was already verified.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace; no follow-up work remains.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          FakeBashTool(output: "[stdout]\nAll checks passed.\n\n[exit 0]\n\n[next]\nSubmit success."),
          AgentWriteFileTool(),
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(!FileManager.default.fileExists(atPath: tempURL.appending(path: "generated.ts").path))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("A generic `write_file` call after a"))
    #expect(prompts[2].contains("passing verify would invalidate that proof"))
    #expect(prompts[2].contains("retry `write_file` only with a `reason`"))
    #expect(prompts[2].contains("explicitly names the missing acceptance check"))
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
  }

  @Test
  func executorRejectsRepeatedVerifyAfterSuccessfulVerifyWithoutMutation() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let bashCounter = ToolInvocationCounter()
    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run verification."}"#,
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run the missing verification command before submitting success."}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Verification passed for the requested packet.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace; no follow-up work remains.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          FakeBashTool(
            output: "[stdout]\nAll checks passed.\n\n[exit 0]\n\n[next]\nSubmit success.",
            counter: bashCounter
          )
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(bashCounter.value == 1)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("Compass already observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` exit 0"))
    #expect(prompts[2].contains("Do not rerun verify against the same worktree"))
    #expect(prompts[2].contains("call `edit_file` or `write_file` now"))
  }

  @Test
  func executorRejectsFailedSubmitAfterMutationInvalidatesFailedVerify() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let bashCounter = ToolInvocationCounter()
    let bashResults = ToolResultQueue([
      .failure("[stderr]\nRust compile error before repair.\n\n[exit 1]", kind: .bashFailure),
      .ok("[stdout]\nAll checks passed after repair.\n\n[exit 0]\n\n[next]\nSubmit success."),
    ])
    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run verification."}"#,
      #"{"kind":"develop_continue","tool":"write_file","arguments":{"path":"generated.ts","content":"export const generated = true;\n"},"reason":"Repair failed verification output."}"#,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Rust compile errors during verification still block the packet.","feedback":"Review Rust compile errors from cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace before trying again.","bypassVerify":false,"lessonEdits":[]}}"#,
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Rerun verification after the accepted repair."}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Verification passed after the repair.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace after the accepted repair; no follow-up work remains.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          FakeSequencedBashTool(results: bashResults, counter: bashCounter),
          AgentWriteFileTool(),
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 5
      )
    )

    #expect(bashCounter.value == 2)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 5)
    #expect(prompts[2].contains("You just changed files with `write_file` after Compass observed `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` fail"))
    #expect(prompts[2].contains("That earlier failure no longer proves the current worktree"))
    #expect(prompts[3].contains("Compass previously observed this verify command fail"))
    #expect(prompts[3].contains("Do not submit status=failed from stale"))
    #expect(prompts[3].contains("call `bash` with `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` again"))
  }

  @Test
  func executorCompactsContinuationHistoryWithoutCountingAnAgentIteration() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    for index in 1...5 {
      try "export const answer\(index) = \(index)\n".write(
        to: tempURL.appending(path: "file\(index).ts"),
        atomically: true,
        encoding: .utf8
      )
    }

    let continues = (1...5).map { index in
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"file\#(index).ts"},"reason":"Read pass \#(index)."}"#
    }
    let summary = """
      Goal / Current Phase
      Develop is reading small fixture files before deciding.

      Established Facts
      Older summary from compactor.

      Files / Symbols
      Small fixture files have been read in prior turns.

      Errors / Repairs
      None.

      Current Step / Next Action
      Continue from the latest raw observation.
      """
    let runtime = FakeLocalModelRuntime(outputs: continues + [
      summary,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Compaction preserved enough context.","feedback":"Verified with cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        settings: AgentRuntimeSettings(contextWindowTokens: 300),
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 6
      )
    )

    #expect(result.iterations == 6)
    #expect(result.tokenUsage.compactionCount == 1)
    #expect(result.tokenUsage.summaryTokens > 0)

    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 7)
    #expect(prompts[5].contains("## Raw History To Compact"))
    #expect(prompts[5].contains("## Latest Raw History Kept Verbatim"))

    let finalPrompt = prompts[6]
    #expect(finalPrompt.contains("## Compacted History"))
    #expect(finalPrompt.contains("lower authority than real `Compass Observation` entries"))
    #expect(finalPrompt.contains("Older summary from compactor"))
    #expect(finalPrompt.contains("Read pass 5."))
    #expect(!finalPrompt.contains("Read pass 1."))
  }

  @Test
  func executorRepairsMalformedOutput() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      "I am done.",
      #"{"kind":"critic_submit","payload":{"verdict":"approve","summary":"No blockers.","feedback":""}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .critic,
        runtime: runtime,
        tools: [],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.criticSchema
      )
    )

    #expect(result.iterations == 2)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts[1].contains("could not be used"))
    #expect(prompts[1].contains("critic_submit"))
  }

  @Test
  func executorEscalatesRepeatedMalformedSubmitJSONAcrossToolReads() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try #"{"scripts":{"verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"}}"#.write(
      to: tempURL.appending(path: "package.json"),
      atomically: true,
      encoding: .utf8
    )

    let malformedPlanSubmit = """
      ```json
      {
        "kind": "plan_submit",
        "payload": {
          "state": {
            "immediate": {
              "plan": "## Outcome\\nAdd count support.\\n\\n## Acceptance checks\\n- main(["--count", "3", "Ship", "it"]) returns 3 open / 3 total.",
              "verify": "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
            },
            "queue": [],
            "brief": {
              "summary": "Add count support.",
              "targetUsers": [],
              "desiredOutcomes": [],
              "constraints": [],
              "acceptanceSignals": []
            },
            "openQuestions": []
          },
          "lessonEdits": []
        }
      }
      ```
      """
    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts."}"#
    let validPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Build decision notes.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      malformedPlanSubmit,
      readPackage,
      malformedPlanSubmit,
      validPlanSubmit,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("Compass rejected malformed `plan_submit` JSON 2 times"))
    #expect(prompts[3].contains("This is a JSON syntax problem"))
    #expect(prompts[3].contains("Do not call\n`read_file`")
      || prompts[3].contains("Do not call `read_file`"))
    #expect(prompts[3].contains("quotes inside string fields must be escaped"))
    #expect(prompts[3].contains("For Plan, do not call more tools"))
    #expect(prompts[3].contains("Return exactly one valid JSON object now"))
  }

  @Test
  func executorRejectsToolCallAfterMalformedSubmitJSON() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let malformedPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"main(["--done", "1", "Ship", "it"]) returns 0 open / 1 total."}}}}"#
    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need scripts after the rejected submit."}"#
    let validPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Add separate --done argv support.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      malformedPlanSubmit,
      readPackage,
      validPlanSubmit,
    ])
    let counter = ToolInvocationCounter()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [FakeReadFileTool(counter: counter)],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(counter.value == 0)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[2].contains("Your previous `plan_submit` was rejected because the JSON was malformed"))
    #expect(prompts[2].contains("Compass did not run `read_file`"))
    #expect(prompts[2].contains("must not call tools"))
    #expect(prompts[2].contains(#"{"kind":"plan_submit","payload":{...}}"#))
  }

  @Test
  func executorEscalatesRepeatedToolCallAfterMalformedSubmitJSON() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let malformedPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"main(["--done", "1", "Ship", "it"]) returns 0 open / 1 total."}}}}"#
    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need scripts after the rejected submit."}"#
    let validPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Add separate --done argv support.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      malformedPlanSubmit,
      readPackage,
      readPackage,
      validPlanSubmit,
    ])
    let counter = ToolInvocationCounter()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [FakeReadFileTool(counter: counter)],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    #expect(counter.value == 0)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("tried the same blocked `read_file` call 2 times"))
    #expect(prompts[3].contains("Compass will keep rejecting tools"))
    #expect(prompts[3].contains("The continuation-contract `read_file package.json` shape is only an example"))
    #expect(prompts[3].contains("Your next response must be `plan_submit`, not `plan_continue`"))
    #expect(prompts[3].contains("For Plan, repair `state.immediate.plan` directly"))
    #expect(prompts[3].contains(#""path":"package.json""#))
  }

  @Test
  func executorRejectsProceduralFailedDevelopSubmitAfterMalformedContinuation() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let malformedEdit = """
      ```json
      {
        "kind": "develop_continue",
        "tool": "edit_file",
        "arguments": {
          "path": "crates/cli/src/main.rs",
          "startLine": 4,
          "endLine": 15,
          "content": `export function main() {
        return "bad";
      }`
        },
        "reason": "Repair the CLI entrypoint."
      }
      ```
      """
    let proceduralFailure =
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Failed to parse and apply the edit_file content due to malformed JSON.","feedback":"Correct the JSON formatting and try again.","bypassVerify":false,"lessonEdits":[]}}"#
    let terminalFailure =
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Could not complete the requested CLI change within the iteration budget.","feedback":"The --count implementation was not completed before the Develop iteration budget ended.","bypassVerify":false,"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      malformedEdit,
      proceduralFailure,
      terminalFailure,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentEditFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("iteration budget"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("JSON strings must use double quotes"))
    #expect(prompts[2].contains("reported status=failed after Compass had already rejected"))
    #expect(prompts[2].contains("This is not a terminal Develop result"))
    #expect(prompts[2].contains("Return a valid `develop_continue` with corrected JSON now"))
    #expect(prompts[2].contains("use `replacementLines` as an array of strings"))
  }

  @Test
  func executorNudgesReadOnlyDetourAfterMalformedDevelopContinuation() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let malformedEdit = """
      ```json
      {
        "kind": "develop_continue",
        "tool": "edit_file",
        "arguments": {
          "path": "crates/cli/src/main.rs",
          "startLine": 4,
          "endLine": 15,
          "content": `export function main() {
        return "bad";
      }`
        },
        "reason": "Repair the CLI entrypoint."
      }
      ```
      """
    let readPackage =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts after the malformed edit."}"#
    let terminalFailure =
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Could not complete the requested CLI change within the iteration budget.","feedback":"The implementation was not completed before the Develop iteration budget ended.","bypassVerify":false,"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      malformedEdit,
      readPackage,
      terminalFailure,
    ])
    let counter = ToolInvocationCounter()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [FakeReadFileTool(counter: counter)],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(counter.value == 1)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[2].contains("You called read-only inspection tool `read_file`"))
    #expect(prompts[2].contains("reading more files does not repair malformed JSON"))
    #expect(prompts[2].contains("repair the rejected continuation now"))
    #expect(prompts[2].contains("using `edit_file` and `replacementLines` as an array of strings"))
    #expect(prompts[2].contains("Do not reread `package.json`"))
    #expect(prompts[2].contains("Latest malformed-continuation repair to apply now"))
    #expect(prompts[2].contains(#""path":"package.json""#))
  }

  @Test
  func executorStopsAtMaxIterationsAndWallClock() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let malformedRuntime = FakeLocalModelRuntime(outputs: ["nope"])
    await #expect(throws: AgentExecutionError.self) {
      try await AgentExecutor().run(
        testConfiguration(
          phase: .develop,
          runtime: malformedRuntime,
          tools: [],
          workingDirectory: tempURL,
          submitResultSchema: Prompts.developSchema,
          maxIterations: 1
        )
      )
    }

    let slowRuntime = FakeLocalModelRuntime(outputs: ["nope", "nope"], delayNanoseconds: 20_000_000)
    await #expect(throws: AgentExecutionError.self) {
      try await AgentExecutor().run(
        testConfiguration(
          phase: .develop,
          runtime: slowRuntime,
          tools: [],
          workingDirectory: tempURL,
          submitResultSchema: Prompts.developSchema,
          maxIterations: 4,
          wallClockTimeout: 0.001
        )
      )
    }
  }

  @Test
  func localModelLeaseAllowsOneLoadedModelAndUnloadsAfterIdle() async throws {
    await LocalModelLease.shared.resetForTesting()
    await LocalModelLease.shared.setIdleTimeoutForTesting(seconds: 0.01)
    try await LocalModelLease.shared.beginRun(modelID: "model-a")
    await #expect(throws: LocalModelRuntimeError.self) {
      try await LocalModelLease.shared.beginRun(modelID: "model-b")
    }
    await LocalModelLease.shared.endRun(modelID: "model-a")
    var snapshot = await LocalModelLease.shared.snapshot()
    let deadline = Date().addingTimeInterval(1)
    while snapshot.loadedModelID != nil, Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
      snapshot = await LocalModelLease.shared.snapshot()
    }
    #expect(snapshot.loadedModelID == nil)
    #expect(snapshot.activeRunCount == 0)
    await LocalModelLease.shared.resetForTesting()
  }

  @Test
  func localModelCatalogMissingAndReadyStates() throws {
    let missingURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: missingURL) }
    LocalModelCatalog.withTestingModelDirectory(missingURL) {
      #expect(!LocalModelCatalog.isBlessedModelReady())
      #expect(LocalModelCatalog.snapshot().status == .missing)
    }

    let readyURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: readyURL) }
    try "{}".write(to: readyURL.appending(path: "config.json"), atomically: true, encoding: .utf8)
    try "{}".write(to: readyURL.appending(path: "tokenizer.json"), atomically: true, encoding: .utf8)
    try Data([0]).write(to: readyURL.appending(path: "model.safetensors"))
    LocalModelCatalog.withTestingModelDirectory(readyURL) {
      #expect(LocalModelCatalog.isBlessedModelReady())
      #expect(LocalModelCatalog.snapshot().status == .ready)
    }
  }
}

private actor FakeLocalModelRuntime: LocalModelGenerating {
  private var outputs: [String]
  private var requests: [LocalModelGenerationRequest] = []
  private let delayNanoseconds: UInt64

  init(outputs: [String], delayNanoseconds: UInt64 = 0) {
    self.outputs = outputs
    self.delayNanoseconds = delayNanoseconds
  }

  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
    requests.append(request)
    if delayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: delayNanoseconds)
    }
    guard !outputs.isEmpty else {
      throw LocalModelRuntimeError.generationFailed("Fake runtime has no queued output.")
    }
    let text = outputs.removeFirst()
    return LocalModelGenerationResult(
      text: text,
      tokenUsage: .estimated(
        inputCharacters: request.systemPrompt.count + request.prompt.count,
        outputCharacters: text.count
      )
    )
  }

  func capturedPrompts() -> [String] {
    requests.map(\.prompt)
  }
}

private final class RejectFirstPlanSubmitValidator: @unchecked Sendable {
  private let lock = NSLock()
  private var attempts = 0

  func validate(_ data: Data) throws {
    lock.lock()
    attempts += 1
    let attempt = attempts
    lock.unlock()

    if attempt == 1 {
      throw PlanTransitionValidationError(
        message:
          "Plan selected generic `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` for new CLI behavior, but the handoff does not include a CLI test or direct proof.",
        reason: .weakVerifyCoverage,
        rejectedVerify: "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
      )
    }
    _ = try JSONDecoder().decode(PlanRunResult.self, from: data)
  }
}

private final class RejectFirstTwoPlanSubmitValidator: @unchecked Sendable {
  private let lock = NSLock()
  private var attempts = 0

  func validate(_ data: Data) throws {
    lock.lock()
    attempts += 1
    let attempt = attempts
    lock.unlock()

    if attempt <= 2 {
      throw PlanTransitionValidationError(
        message:
          "Plan selected generic `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` for new CLI behavior, but the handoff does not include a CLI test or direct proof.",
        reason: .weakVerifyCoverage,
        rejectedVerify: "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
      )
    }
    _ = try JSONDecoder().decode(PlanRunResult.self, from: data)
  }
}

private final class ToolInvocationCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func increment() {
    lock.lock()
    count += 1
    lock.unlock()
  }
}

private final class ToolResultQueue: @unchecked Sendable {
  private let lock = NSLock()
  private var results: [AgentToolInvocationResult]

  init(_ results: [AgentToolInvocationResult]) {
    self.results = results
  }

  func next() -> AgentToolInvocationResult {
    lock.lock()
    defer { lock.unlock() }
    guard !results.isEmpty else {
      return .failure("Fake bash result queue exhausted.", kind: .unknown)
    }
    return results.removeFirst()
  }
}

private struct FakeBashTool: AgentTool {
  var output: String
  var counter: ToolInvocationCounter? = nil

  var spec: AgentToolSpec {
    AgentToolSpec(
      name: AgentBashTool.toolName,
      description: "Fake bash tool.",
      parameters: AgentToolParametersSchema(literal: [
        "type": "object",
        "additionalProperties": true,
      ])
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    counter?.increment()
    return .ok(output)
  }
}

private struct FakeReadFileTool: AgentTool {
  var counter: ToolInvocationCounter? = nil

  var spec: AgentToolSpec {
    AgentToolSpec(
      name: AgentReadFileTool.toolName,
      description: "Fake read file tool.",
      parameters: AgentToolParametersSchema(literal: [
        "type": "object",
        "additionalProperties": true,
      ])
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    counter?.increment()
    return .ok("fake file contents")
  }
}

private struct FakeSequencedBashTool: AgentTool {
  var results: ToolResultQueue
  var counter: ToolInvocationCounter? = nil

  var spec: AgentToolSpec {
    AgentToolSpec(
      name: AgentBashTool.toolName,
      description: "Fake sequenced bash tool.",
      parameters: AgentToolParametersSchema(literal: [
        "type": "object",
        "additionalProperties": true,
      ])
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    counter?.increment()
    return results.next()
  }
}

private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "CompassFactoryPivotTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func jsonStringLiteral(_ value: String) -> String {
  let data = (try? JSONEncoder().encode(value)) ?? Data(#""""#.utf8)
  return String(decoding: data, as: UTF8.self)
}

private func testConfiguration(
  phase: AgentPhase,
  settings: AgentRuntimeSettings = AgentRuntimeSettings(),
  runtime: any LocalModelGenerating,
  tools: [AgentTool],
  workingDirectory: URL,
  submitResultSchema: String,
  maxIterations: Int = 8,
  wallClockTimeout: TimeInterval = 60,
  validateSubmitResult: (@Sendable (Data) throws -> Void)? = nil
) -> AgentExecutionConfiguration {
  AgentExecutionConfiguration(
    settings: settings,
    phase: phase,
    systemPrompt: Prompts.agentSystemPrompt(
      phase: phase,
      workingDirectoryPath: workingDirectory.path,
      executionEnvironment: .host
    ),
    userPrompt: "Test phase packet.",
    tools: tools,
    modelRuntime: runtime,
    submitResultSchema: AgentToolParametersSchema(json: Data(submitResultSchema.utf8)),
    workingDirectory: workingDirectory,
    validateSubmitResult: validateSubmitResult ?? { data in
      switch phase {
      case .plan:
        _ = try JSONDecoder().decode(PlanRunResult.self, from: data)
      case .develop:
        _ = try JSONDecoder().decode(DevelopSummary.self, from: data)
      case .critic:
        _ = try JSONDecoder().decode(CriticVerdict.self, from: data)
      }
    },
    maxIterations: maxIterations,
    wallClockTimeout: wallClockTimeout
  )
}

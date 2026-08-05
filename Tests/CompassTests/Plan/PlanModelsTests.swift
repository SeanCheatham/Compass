import Foundation
import Testing
@testable import Compass
@testable import CompassCore

@Suite("Plan models")
struct PlanModelsTests {
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
}

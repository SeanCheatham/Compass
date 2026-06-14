import Foundation

extension Prompts {
  package static func developPrompt(
    next: PlanNext,
    lessons: String,
    assumptions: String = "",
    vision: String,
    attempt: Int,
    priorIssues: [String],
    criticFeedback: [String] = [],
    hostXcodeBuildTestEnabled: Bool = false,
    forgeProfile: ForgeProfile? = nil
  ) -> String {
    let criticSection =
      criticFeedback.isEmpty
      ? ""
      : "\n\n## Critic Feedback\n"
        + criticFeedback.enumerated()
        .map { "Review \($0.offset + 1):\n\($0.element)" }
        .joined(separator: "\n\n")
    let tesseraMode = (forgeProfile ?? ForgeProfile.generatedProjectDefault) == .tesseraApp
    let verificationRule = tesseraMode
      ? "Run embedded Tessera verification with `{\"action\":\"verify\"}` before finishing unless the requested proof itself is wrong or out of scope."
      : "Run the verify command before finishing unless the command itself is wrong or out of scope."
    let mutationRule = tesseraMode
      ? "Mutate Tessera project resources only through the `tessera` tool actions `write_resource`, `edit_resource`, and `format_source`; do not use shell or generic file mutation tools."
      : "Before `edit_file`, read the exact target file in this Develop session. If a path is missing, use `list_files` or `glob` to find the existing target; use `write_file` only when the plan explicitly requires a new file."
    let cleanWorkspaceRule = tesseraMode
      ? "Leave only intentional Tessera source, test, context, or manifest changes."
      : "Leave only intentional source, test, context, manifest, or documentation changes. Do not use bash for Git commits; the container may not have Git."
    let workflowVerifyStep = tesseraMode
      ? "Run `tessera` with `{\"action\":\"verify\"}` and fix failures."
      : "Run verify and fix failures."
    let proofSection = tesseraMode
      ? """
        ## Tessera Proof
        Planned proof label: `\(next.verify)`
        Run it through the Compass `tessera` tool with `{"action":"verify"}`.
        """
      : """
        ## Verify
        ```bash
        \(next.verify)
        ```
        """

    return """
      You are the Develop agent in Compass, a local software factory. Implement exactly the
      immediate packet below. Keep the change small, deterministic, and Tessera-first.

      Hard rules:
      - Generated Compass output is Tessera by default.
      - Use `tessera.json`, `src/*.tes`, `contexts/*.json`, and `tests/*.json` for generated
        app work.
      - Prefer expression-oriented Tessera changes over new host capabilities. If you add a
        manifest entrypoint or capability, update `tessera.json` and matching tests/contexts
        in the same change before submitting.
      - Do not push, commit, or use destructive git operations. Compass commits verified
        Develop changes from the host after this phase succeeds.
      - \(verificationRule)
      - For generated Tessera projects, use the Compass `tessera` tool with
        `{"action":"verify"}`, `{"action":"inspect_project"}`,
        `{"action":"run_test","test_path":"tests/<name>.json"}`,
        `{"action":"check_source","path":"src/<name>.tes"}`, or
        `{"action":"run_entrypoint","entrypoint":"<name>"}` instead of depending on a
        `tessera` binary in shell PATH.
      - \(mutationRule)
      - \(cleanWorkspaceRule)
      - Do not commit generated outputs or caches: `target/`, `.build/`, `build/`,
        logs, or editor artifacts.
      - Generated Tessera workspaces use `src/*.tes`, `contexts/*.json`, `tests/*.json`,
        and `tessera.json`. Use those paths when creating or editing generated work.
      - End with one `develop_submit` JSON envelope.

      \(lessonEditsGuidance())

      \(developAttemptInstructions(
        attempt: attempt,
        priorIssues: priorIssues,
        workflowVerifyStep: workflowVerifyStep
      ))

      ## Handoff
      \(developHandoffSection(next: next))

      ## Plan
      \(next.plan)

      \(proofSection)

      ## Lessons
      \(fencedOrEmpty(lessons, empty: "_(no lessons yet)_"))

      ## Assumptions
      \(fencedOrEmpty(assumptions, empty: "_(no assumptions recorded)_"))

      ## Project context
      \(fencedOrEmpty(vision, empty: "_(no project context set)_"))\(criticSection)

      Finish with exactly this envelope:
      {
        "kind": "develop_submit",
        "payload": {
          "status": "succeeded",
          "summary": "<what changed or what blocked the work>",
          "feedback": "<smallest next action or no follow-up; verified the requested Tessera proof>",
          "bypassVerify": false,
          "lessonEdits": []
        }
      }

      Use `develop_continue` to request one Compass tool at a time while implementing.
      """
  }

  private static func developHandoffSection(next: PlanNext) -> String {
    let digest = PlanHandoffDigest(plan: next.plan)
    let verify = PlanVerifyCommandSummary(command: next.verify)
    var lines = [
      "Handoff status: \(digest.title). \(digest.detail)",
      "Verify meaning: \(verify.title). \(verify.detail)",
    ]
    if let outcome = digest.outcome {
      lines.append("Outcome: \(outcome)")
    }
    if let whyItMatters = digest.whyItMatters {
      lines.append("Why it matters: \(whyItMatters)")
    }
    if !digest.acceptanceChecks.isEmpty {
      lines.append("Acceptance checks:")
      lines += digest.acceptanceChecks.map { "- \($0)" }
    }
    return lines.joined(separator: "\n")
  }

  private static func developAttemptInstructions(
    attempt: Int,
    priorIssues: [String],
    workflowVerifyStep: String
  ) -> String {
    if attempt <= 1 {
      return """
        Workflow:
        1. Inspect the files implied by the Outcome and Acceptance checks before editing.
           For generated Tessera work, behavior usually means one `src/*.tes` file plus
           a matching `tests/*.json` case and, when needed, a `contexts/*.json` fixture.
        2. If Acceptance checks mention tests, read or create the matching test JSON and
           make the test/context change in the same implementation pass. Do not submit success
           after a source-only edit when the handoff asks for tests.
        3. If a planned path is uncertain or missing, list files or glob for the correct
           generated workspace location before editing.
        4. Implement the packet without broadening scope.
        5. \(workflowVerifyStep)
        6. Return a concrete summary and feedback.
        """
    }
    let issues =
      priorIssues.isEmpty
      ? "_(no captured prior issue text)_" : priorIssues.joined(separator: "\n\n")
    return """
      This is Develop attempt \(attempt). First address the prior issue(s), then rerun verify.
      If the prior issue lists Suggested test targets, read and edit one of those exact
      test files before inspecting unrelated files or running verify again.
      If the prior issue lists Requested test file(s), make your first write/edit target
      one of those test files. Do not edit source files again until that requested test
      file has changed in this attempt.
      Do not submit success or rerun verify until you have changed a file that directly
      addresses the prior issue.

      ```
      \(issues)
      ```
      """
  }
}

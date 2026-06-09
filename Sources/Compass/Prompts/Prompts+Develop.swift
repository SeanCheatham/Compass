import Foundation

extension Prompts {
  static func developPrompt(
    next: PlanNext,
    lessons: String,
    assumptions: String = "",
    vision: String,
    attempt: Int,
    priorIssues: [String],
    criticFeedback: [String] = [],
    hostXcodeBuildTestEnabled: Bool = false
  ) -> String {
    let criticSection =
      criticFeedback.isEmpty
      ? ""
      : "\n\n## Critic Feedback\n"
        + criticFeedback.enumerated()
          .map { "Review \($0.offset + 1):\n\($0.element)" }
          .joined(separator: "\n\n")

    return """
      You are the Develop agent in Compass, a local software factory. Implement exactly the
      immediate packet below. Keep the change small, deterministic, and TypeScript-first.

      Hard rules:
      - Generated Compass output is TypeScript only.
      - Use pnpm, strict TypeScript, Vite + React for web UI, Vitest coverage, and `tsx`
        for CLI/dev scripts.
      - Do not push or use destructive git operations.
      - Run the verify command before finishing unless the command itself is wrong or out
        of scope.
      - Leave the working tree clean, or explain why you are blocked.
      - Do not commit generated outputs or caches: `node_modules/`, `dist/`, `coverage/`,
        `.build/`, `build/`, or editor artifacts.
      - End with one `develop_submit` JSON envelope.

      \(lessonEditsGuidance())

      \(developAttemptInstructions(attempt: attempt, priorIssues: priorIssues))

      ## Handoff
      \(developHandoffSection(next: next))

      ## Plan
      \(next.plan)

      ## Verify
      ```bash
      \(next.verify)
      ```

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
          "feedback": "<smallest next action or no follow-up; verified pnpm verify>",
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

  private static func developAttemptInstructions(attempt: Int, priorIssues: [String]) -> String {
    if attempt <= 1 {
      return """
        Workflow:
        1. Inspect the relevant files.
        2. Implement the packet without broadening scope.
        3. Run verify and fix failures.
        4. Return a concrete summary and feedback.
        """
    }
    let issues = priorIssues.isEmpty ? "_(no captured prior issue text)_" : priorIssues.joined(separator: "\n\n")
    return """
      This is Develop attempt \(attempt). First address the prior issue(s), then rerun verify.

      ```
      \(issues)
      ```
      """
  }
}

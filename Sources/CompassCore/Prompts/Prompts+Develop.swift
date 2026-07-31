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
      immediate packet below. Keep the change small, deterministic, and Rust-first.

      Hard rules:
      - Generated Compass output is Rust only.
      - Use the Cargo workspace layout (`crates/app-core`, `crates/app-cli`), `cargo fmt`,
        Clippy (`-D warnings`), and `cargo test` for verification.
      - Prefer existing crate dependencies and simple Rust over new crates. If
        you add a new dependency, update the owning `Cargo.toml` and tests in the same
        change before submitting.
      - Do not push or use destructive git operations.
      - Run the verify command before finishing unless the command itself is wrong or out
        of scope.
      - Leave the working tree clean, or explain why you are blocked.
      - Do not commit generated outputs or caches: `target/`, `coverage/`, `.build/`,
        `build/`, or editor artifacts.
      - Generated Rust workspaces use `crates/app-core/src` and `crates/app-cli/src`.
        Do not invent top-level `src/...` paths unless `list_files`
        or `glob` proves they exist.
      - Before `edit_file`, read the exact target file in this Develop session. If a path
        is missing, use `list_files` or `glob` to find the existing target; use
        `write_file` only when the plan explicitly requires a new file.
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
          "feedback": "<smallest next action or no follow-up; verified \(GeneratedProjectQuality.standardVerifyCommand)>",
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
        1. Inspect the files implied by the Outcome and Acceptance checks before editing.
           For generated Rust work, CLI argv or flag behavior usually means
           `crates/app-cli/src/main.rs` (or `lib.rs`) plus a test in
           `crates/app-cli/tests/` or a `#[cfg(test)]` module; core helpers usually mean
           `crates/app-core/src/lib.rs` plus matching unit or integration tests.
        2. If Acceptance checks mention tests, read or create the matching test file and
           make the test change in the same implementation pass. Do not submit success
           after a source-only edit when the handoff asks for tests.
        3. If a planned path is uncertain or missing, list files or glob for the correct
           generated workspace location before editing.
        4. Implement the packet without broadening scope.
        5. Run verify and fix failures.
        6. Return a concrete summary and feedback.
        """
    }
    let issues = priorIssues.isEmpty ? "_(no captured prior issue text)_" : priorIssues.joined(separator: "\n\n")
    return """
      This is Develop attempt \(attempt). First address the prior issue(s), then rerun verify.
      If the prior issue lists Suggested test targets, read and edit one of those exact
      test files before inspecting unrelated files or running verify again. Do not start
      a retry by rereading Cargo.toml unless the prior issue is about workspace scripts.
      If the prior issue lists Requested test file(s), make your first write/edit target
      one of those test files. Do not edit source files again until that requested test
      file has changed in this attempt.
      If a tool says a Cargo manifest already points to an existing entry point, read
      and edit that existing file instead of creating a duplicate entry point.
      Do not submit success or rerun verify until you have changed a file that directly
      addresses the prior issue.

      ```
      \(issues)
      ```
      """
  }
}

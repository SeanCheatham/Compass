import Foundation

extension Prompts {
  static func criticPrompt(
    next: PlanNext,
    developSummary: DevelopSummary,
    verifyCommand: String,
    verifyExitCode: Int?,
    verifyOutput: String,
    gitDiff: String,
    priorCritiques: [String],
    lessons: String,
    assumptions: String = "",
    vision: String,
    iteration: Int,
    maxIterations: Int
  ) -> String {
    let verifyStatus: String
    if let code = verifyExitCode {
      verifyStatus = code == 0 ? "passed (exit 0)" : "exited with code \(code)"
    } else {
      verifyStatus = "was skipped (Develop requested bypassVerify=true)"
    }
    let priorBlock: String
    if priorCritiques.isEmpty {
      priorBlock = "_(this is the first critic review for this Develop pass)_"
    } else {
      let formatted = priorCritiques.enumerated()
        .map { "Review \($0.offset + 1):\n\($0.element)" }
        .joined(separator: "\n\n")
      priorBlock = """
        ```
        \(formatted)
        ```
        """
    }
    return """
      You are the Critic agent in Compass's software factory (see the system
      message for how the loop works).

      A separate Develop agent just finished implementing the plan below
      and its post-checks (Verify command + clean working tree) passed.
      Your job is an adversarial review: independently judge whether the
      diff actually delivers the planned increment and is fit to land,
      then either approve or request changes.

      You have read-only file access plus `bash` so you can run extra
      checks (re-run a specific test, run a linter, inspect git history,
      grep for related callers). You CANNOT edit, write, or commit. Do
      not run mutating shell commands (no `git commit`, no `git push`,
      no file rewrites via `sed -i` or shell redirection into tracked
      files). Treat this as a code-review session, not a second Develop
      pass.

      This is critic review \(iteration) of at most \(maxIterations). On
      the final review Compass will accept and proceed regardless of
      verdict, so be decisive: request_changes only when there is a
      real, fixable problem the next Develop pass can act on.

      What to look for:
      - Does the diff implement the plan, or does it miss / overshoot it?
      - Are there obvious bugs the verify command wouldn't catch
        (logic errors in untested branches, leaked resources, race
        conditions, broken edge cases)?
      - Does the diff break invariants stated in the lessons?
      - Does the diff rely on a denied assumption or lean too heavily on
        an implicit assumption that should have been verified?
      - Are new code paths exercised by tests or just by the verify
        smoke command?
      - If the change touched feature-gated, optional-provider, platform-specific,
        or conditional-compilation code, did Verify cover the relevant matrix
        (for Rust/Cargo, default tests plus all-features when appropriate)?
      - If you find one instance of a bug class, search for sibling call sites
        before requesting changes so the feedback asks Develop to fix the whole
        local pattern.
      - Are generated build outputs or caches accidentally included in the diff?
      - Are there leftover TODOs, dead code, or unrelated changes that
        shouldn't be in this commit?

      Finish by calling the `submit_result` tool exactly once with:
      - `verdict`: `"approve"` or `"request_changes"`.
      - `summary`: 1-3 sentences for the human reviewer / log.
      - `feedback`: when requesting changes, a concrete punch list the
        Develop agent can act on in one more pass. Lead with the most
        important item; reference file paths and line numbers from the
        diff. Empty string when approving.

      ## Plan that was implemented
      \(next.plan)

      ## Verify command and outcome
      Command:
      ```bash
      \(verifyCommand)
      ```
      Verify \(verifyStatus).
      Output (tail):
      \(fencedOrEmpty(verifyOutput, empty: "_(no captured output)_"))

      ## Develop summary (from the agent that just ran)
      Status: \(developSummary.status.rawValue)
      Summary: \(developSummary.summary)
      Handoff feedback: \(developSummary.feedback)

      ## Diff under review
      Output of `git diff` against the pre-Develop SHA. This is what
      would be committed if you approve.
      \(fencedOrEmpty(gitDiff, empty: "_(diff is empty — the Develop pass may have been a no-op)_"))

      ## Prior critic reviews for this Develop pass
      \(priorBlock)

      ## Lessons
      \(fencedOrEmpty(lessons, empty: "_(no lessons yet)_"))

      ## Assumptions
      \(fencedOrEmpty(assumptions, empty: "_(no assumptions recorded)_"))

      ## Vision
      \(fencedOrEmpty(vision, empty: "_(no vision set)_"))

      Call submit_result when you have decided.
      """
  }
}

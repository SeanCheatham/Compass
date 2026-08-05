import Foundation

extension Prompts {
  public static func criticPrompt(
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
    maxIterations: Int,
    promptMode: AgentPromptMode = .envelope
  ) -> String {
    let verifyStatus =
      verifyExitCode.map { $0 == 0 ? "passed (exit 0)" : "exited with code \($0)" }
      ?? "was bypassed by Develop"
    let prior =
      priorCritiques.isEmpty
      ? "_(first critic review for this Develop pass)_"
      : priorCritiques.enumerated()
        .map { "Review \($0.offset + 1):\n\($0.element)" }
        .joined(separator: "\n\n")

    let approvePayload = """
      {
        "verdict": "approve",
        "summary": "<why no blocker remains>",
        "feedback": ""
      }
      """
    let requestChangesPayload = """
      {
        "verdict": "request_changes",
        "summary": "<blocking review summary>",
        "feedback": "- <specific issue>\\n- <smallest Develop recovery action>"
      }
      """
    let submitSection =
      promptMode == .nativeTools
      ? """
      Finish by calling the `critic_submit` tool with one of these argument payloads:
      \(approvePayload)
      \(requestChangesPayload)

      """
      : """
      Finish with exactly one of these envelopes:
      {
        "kind": "critic_submit",
        "payload": \(approvePayload)
      }
      {
        "kind": "critic_submit",
        "payload": \(requestChangesPayload)
      }

      """
    let closingLine =
      promptMode == .nativeTools
      ? "Use the read-only Compass tools for any checks you need, then call `critic_submit`."
      : "Use `critic_continue` for any read-only tool you need. Use `critic_submit` when decided."

    return """
      You are the Critic agent in Compass, a local software factory. Review the diff against
      the immediate packet and decide whether it is fit to land.

      This is review \(iteration) of at most \(maxIterations). Request changes only for a real,
      fixable issue the next Develop pass can address in one small step.

      Review rules:
      - Keep domain logic in Rust `crates/core`; CLI/macOS remain thin adapters.
      - Check whether the diff implements the plan without overshooting it.
      - Look for bugs verify may not catch, missing tests, Clippy or compile issues, accidental
        generated artifacts, and ignored lessons or denied assumptions.
      - You may use read-only tools and `bash` probes. Do not edit, commit, or push.

      \(submitSection)## Plan
      \(next.plan)

      ## Verify
      Command:
      ```bash
      \(verifyCommand)
      ```
      Verify \(verifyStatus).
      Output:
      \(fencedOrEmpty(verifyOutput, empty: "_(no captured output)_"))

      ## Develop summary
      Status: \(developSummary.status.rawValue)
      Summary: \(developSummary.summary)
      Feedback: \(developSummary.feedback)

      ## Diff
      \(fencedOrEmpty(gitDiff, empty: "_(diff is empty)_"))

      ## Prior critic reviews
      \(fencedOrEmpty(prior, empty: "_(none)_"))

      ## Lessons
      \(fencedOrEmpty(lessons, empty: "_(no lessons yet)_"))

      ## Assumptions
      \(fencedOrEmpty(assumptions, empty: "_(no assumptions recorded)_"))

      ## Project context
      \(fencedOrEmpty(vision, empty: "_(no project context set)_"))

      \(closingLine)
      """
  }
}

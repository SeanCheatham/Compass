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
    let criticSection: String
    if criticFeedback.isEmpty {
      criticSection = ""
    } else {
      let formatted = criticFeedback.enumerated()
        .map { "Review \($0.offset + 1):\n\($0.element)" }
        .joined(separator: "\n\n")
      criticSection = """


        ## Critic feedback from prior passes
        A separate Critic agent reviewed your previous Develop output and
        requested changes. Treat the items below as the priority for this
        pass — addressing them is the path to approval. Stay within the
        plan; do not expand scope.

        ```
        \(formatted)
        ```
        """
    }
    return developPromptBody(
      next: next,
      lessons: lessons,
      assumptions: assumptions,
      vision: vision,
      attempt: attempt,
      priorIssues: priorIssues,
      criticSection: criticSection,
      hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled
    )
  }

  private static func developPromptBody(
    next: PlanNext,
    lessons: String,
    assumptions: String,
    vision: String,
    attempt: Int,
    priorIssues: [String],
    criticSection: String,
    hostXcodeBuildTestEnabled: Bool
  ) -> String {
    let hostXcodeVerifyNote =
      next.requiresHostXcode
      ? """
      This increment's verify runs on the host: call `host_xcode` with the
      matching `action` and pass only the xcodebuild flags in `arguments` (the tool
      supplies `build`/`test`).
      """
      : """
      If you need to probe SwiftPM or Xcode builds before finishing, still use
      `host_xcode` even when verify is compile-only in the guest.
      """
    let hostXcodeWorkflow =
      hostXcodeBuildTestEnabled
      ? """

      Host Apple platform workflow:
      The Shared VM guest has Command Line Tools only — not full Xcode. Keep
      edits in the normal file tools here, but run Swift/macOS/iOS build and test
      on the host via `host_xcode` (status/build/test). Please do not use `bash` for Xcode-only commands;
      `host_xcode` is for build/test checks only.
      do not use `bash` for `swift test`, `xcodebuild`, or
      other Apple-platform compile/test commands because they fail or mislead in
      the guest (e.g. missing `_TestingInterop`).
      \(hostXcodeVerifyNote)
      """
      : ""
    return """
      You are the Develop agent in Compass's software factory (see the system
      message for how the loop works).

      Implement exactly the plan below. You may read, edit, and run shell
      commands (including the verify command). Keep the change scoped to the plan.

      Hard rules:
      - Do not push or use destructive git operations.
      - In Shared VM git workspaces, make local commits for your completed changes.
      - Run the verify command before finishing.
      - Leave the working tree clean, or explain why you are blocked.
      - Do not commit generated build outputs or caches (`target/`, `.build/`,
        `build/`, `DerivedData/`, `node_modules/`, `coverage/`, object files,
        archives, etc.). If a build creates them, remove them from the change
        set and add/update `.gitignore`.
      - When fixing a bug class reported by post-checks or Critic, search for
        sibling call sites with the same pattern and fix the whole local class,
        not only the cited line.
      - End the phase by calling `submit_result` exactly once.

      \(lessonEditsGuidance())

      Develop workspace:
      Compass runs your tools in the working directory from the system message
      (often a Shared VM clone of the repo). In the normal Shared VM route this
      is a real git checkout: inspect history with git as needed and commit your
      changes locally before calling `submit_result`, but do not push. After the
      retry budget Compass pushes your committed guest HEAD to a host-side
      exchange repo and fast-forwards the host checkout. On the rare host route,
      `bash` may commit in-place on the user's branch.
      \(hostXcodeWorkflow)

      \(developAttemptInstructions(attempt: attempt, priorIssues: priorIssues))

      ## Plan to implement
      \(next.plan)

      ## Verify command
      ```bash
      \(next.verify)
      ```

      ## Lessons
      \(fencedOrEmpty(lessons, empty: "_(no lessons yet)_"))

      ## Assumptions
      \(fencedOrEmpty(assumptions, empty: "_(no assumptions recorded)_"))

      ## Vision
      \(fencedOrEmpty(vision, empty: "_(no vision set)_"))\(criticSection)

      submit_result arguments:
      - `status`: `succeeded`, `blocked`, or `failed`.
      - `summary`: concise human summary of what happened.
      - `feedback`: short handoff note for the next planning pass.
      - `bypassVerify`: true only if the verify command itself is wrong or out of scope.
      - `lessonEdits`: exact find/replace edits against the lessons content
        shown above, or [].
      """
  }

  private static func developAttemptInstructions(attempt: Int, priorIssues: [String]) -> String {
    if attempt <= 1 {
      return """
        Workflow:
        1. Explore as needed to understand the surrounding code.
        2. Implement the plan and keep the change scoped.
        3. Run the verify command and fix failures.
        4. Call submit_result with a useful `feedback` handoff for the next Plan pass.
        """
    }

    let partitioned = Dictionary(grouping: priorIssues) { issue in
      issue.hasPrefix("[verify]") ? "verify" : "git"
    }
    var parts: [String] = []
    if let verifyItems = partitioned["verify"], !verifyItems.isEmpty {
      parts.append("**Verify failures:**\n" + verifyItems.joined(separator: "\n"))
    }
    if let gitItems = partitioned["git"], !gitItems.isEmpty {
      parts.append("**Git-status issues:**\n" + gitItems.joined(separator: "\n"))
    }
    let issues =
      parts.isEmpty
      ? priorIssues.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n")
      : parts.joined(separator: "\n\n")
    return """
      Retry \(attempt):
      Your previous attempt left these post-check failures unresolved:

      \(issues)

      Fix them now. Do not expand scope. Finish with verify passing, a clean
      working tree, and a submit_result call carrying the feedback handoff.
      """
  }
}

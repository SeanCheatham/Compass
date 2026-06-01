import Foundation

extension Prompts {
  static func reflectPrompt(
    state: PlanProposal,
    lessons: String,
    assumptions: String = "",
    vision: String,
    recentSessions: [SessionRecord],
    iteration: Int,
    hostXcodeBuildTestEnabled: Bool = false
  ) throws -> String {
    let promptState = hostXcodeBuildTestEnabled ? state : state.removingHostXcodeRequirement()
    let stateJSON = try CompassWorkspace.encodeProposal(promptState)
    let sessionsJSON = try encodeSessions(recentSessions)
    let sessionBrief = ReflectSessionBrief(sessions: recentSessions).text
    let hostXcodeGuidance =
      hostXcodeBuildTestEnabled
      ? """
      When preserving or rewriting `immediate`, keep `requiresHostXcode` true
      for Swift/macOS/iOS verify that would otherwise use `swift test` or
      `xcodebuild` in the guest. Host verify must be `xcodebuild ... build|test`.
      """
      : ""
    return """
      You are the Reflect agent in Compass's software factory (see the system
      message for how the loop works).

      Run a course-correction pass for factory session \(iteration) before
      Plan chooses the next increment. You have read
      access to the repository plus `bash` for probing (build, test, git
      inspection — do not edit files or commit). Decide whether the project
      is still on course toward the vision.

      Finish by calling the `submit_result` tool with these arguments:
      - `state`: null if everything is on course.
      - `state`: a planning update if `midTerm` and/or `longTerm` should be
        rewritten. Completed history is managed by Compass and is not part of
        this payload. Preserve `immediate` unless there is a concrete reason
        to adjust it.
      - `summary`: a concise explanation of the reflection result.
      - `lessonEdits`: exact find/replace edits against the lessons content
        shown below, or `[]` when nothing durable should be recorded.

      \(lessonEditsGuidance())

      Keep this tight. Do not rewrite state defensively.
      \(hostXcodeGuidance)

      ## Recent session brief
      \(sessionBrief)

      ## Current planning state
      ```json
      \(stateJSON)
      ```

      ## Recent sessions, most recent first
      ```json
      \(sessionsJSON)
      ```

      ## Lessons
      \(fencedOrEmpty(lessons, empty: "_(no lessons yet)_"))

      ## Assumptions
      \(fencedOrEmpty(assumptions, empty: "_(no assumptions recorded)_"))

      ## Vision
      \(fencedOrEmpty(vision, empty: "_(no vision set)_"))
      """
  }
}

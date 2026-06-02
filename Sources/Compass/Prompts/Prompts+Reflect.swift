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
    let stateJSON = try CompassWorkspace.encodeProposal(promptState.promptDigest())
    let sessionsJSON = try encodeSessions(Array(recentSessions.prefix(5)))
    let sessionBrief = ReflectSessionBrief(sessions: recentSessions).text
    let lessonsDigest = reflectCompactPromptBlock(lessons, maxLines: 8, maxCharacters: 1800)
    let assumptionsDigest = reflectCompactPromptBlock(assumptions, maxLines: 8, maxCharacters: 1800)
    let visionDigest = reflectCompactPromptBlock(vision, maxLines: 10, maxCharacters: 2400)
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
      - `state`: a planning update if `candidates`, `strategicContext`, or
        `openQuestions` should be rewritten. Completed history is managed by
        Compass and is not part of this payload. Preserve `immediate` unless
        there is a concrete reason to adjust it.
      - `summary`: a concise explanation of the reflection result.
      - `lessonEdits`: exact find/replace edits against the lessons content
        shown below, or `[]` when nothing durable should be recorded.

      Copy this shape when no planning update is needed:
      {
        "state": null,
        "summary": "<why the current plan is still on course>",
        "lessonEdits": []
      }

      If planning needs revision, replace `state: null` with an object
      containing all required keys:
      {
        "state": {
          "immediate": null,
          "candidates": [],
          "strategicContext": {
            "thesis": "<durable product intent>",
            "principles": [],
            "constraints": [],
            "nonGoals": [],
            "risks": []
          },
          "openQuestions": []
        },
        "summary": "<what changed and why>",
        "lessonEdits": []
      }
      When preserving a non-null `immediate`, copy the full current immediate
      object, including `plan`, `verify`, `verifyTimeoutMs`, `estimatedDifficulty`,
      and `requiresHostXcode` if that field is present. Do not include completed
      history.

      \(lessonEditsGuidance())

      Keep this tight. Do not rewrite state defensively. Do not copy shipped
      history into candidates or strategicContext.
      \(hostXcodeGuidance)

      ## Recent session brief
      \(sessionBrief)

      ## Current planning state
      Compact digest only. Use recent sessions and plan history rather than
      copying shipped archives back into state.

      ```json
      \(stateJSON)
      ```

      ## Recent sessions, most recent first
      ```json
      \(sessionsJSON)
      ```

      ## Lessons
      \(fencedOrEmpty(lessonsDigest, empty: "_(no lessons yet)_"))

      ## Assumptions
      \(fencedOrEmpty(assumptionsDigest, empty: "_(no assumptions recorded)_"))

      ## Vision
      \(fencedOrEmpty(visionDigest, empty: "_(no vision set)_"))
      """
  }

  private static func reflectCompactPromptBlock(
    _ text: String,
    maxLines: Int,
    maxCharacters: Int
  ) -> String {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var seen = Set<String>()
    var lines: [String] = []
    for rawLine in normalized.components(separatedBy: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }
      guard !seen.contains(line) else { continue }
      seen.insert(line)
      lines.append(line)
      if lines.count >= maxLines { break }
    }
    let joined = lines.joined(separator: "\n")
    guard joined.count > maxCharacters else { return joined }
    return String(joined.prefix(max(0, maxCharacters - 3)))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

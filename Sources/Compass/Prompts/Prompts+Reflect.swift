import Foundation

extension Prompts {
  static func reflectPrompt(
    state: PlanProposal,
    lessons: String,
    assumptions: String = "",
    vision: String,
    recentSessions: [SessionRecord],
    iteration: Int,
    productTournamentConfig: ProductTournamentConfig = .empty,
    productTournamentEvidenceIndex: ProductTournamentEvidenceIndex = .empty,
    hostXcodeBuildTestEnabled: Bool = false
  ) throws -> String {
    let promptState = hostXcodeBuildTestEnabled ? state : state.removingHostXcodeRequirement()
    let stateJSON = try CompassWorkspace.encodeProposal(promptState.promptDigest())
    let sessionsJSON = try encodeSessions(Array(recentSessions.prefix(5)))
    let sessionBrief = ReflectSessionBrief(sessions: recentSessions).text
    let lessonsDigest = reflectCompactPromptBlock(lessons, maxLines: 8, maxCharacters: 1800)
    let assumptionsDigest = reflectCompactPromptBlock(assumptions, maxLines: 8, maxCharacters: 1800)
    let visionDigest = reflectCompactPromptBlock(vision, maxLines: 10, maxCharacters: 2400)
    let productTournamentDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: productTournamentConfig,
      evidenceIndex: productTournamentEvidenceIndex
    )
    let hostXcodeGuidance =
      hostXcodeBuildTestEnabled
      ? """
      When preserving or rewriting `immediate`, keep `requiresHostXcode` true
      for Swift/macOS/iOS verify that would otherwise use `swift test` or
      `xcodebuild` in the guest. Host verify must be `xcodebuild ... build|test`.
      """
      : ""
    return """
      You are the Reflect agent in Compass's Product Tournament work loop (see the system
      message for how the loop works).

      Run a course-correction pass for Product Tournament session \(iteration) before
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
      - `tournamentDecisionUpdates`: tournament experiment decision updates
        justified by Product Tournament evidence, or `[]` when no experiment
        decision should change. Reflect may update tournament state through this
        field but must not mutate code.

      Copy this shape when no planning update is needed:
      {
        "state": null,
        "summary": "<why the current plan is still on course>",
        "lessonEdits": [],
        "tournamentDecisionUpdates": []
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
        "lessonEdits": [],
        "tournamentDecisionUpdates": []
      }
      When preserving a non-null `immediate`, copy the full current immediate
      object, including `plan`, `verify`, `verifyTimeoutMs`, `estimatedDifficulty`,
      and `requiresHostXcode` if that field is present. Do not include completed
      history.

      \(lessonEditsGuidance())

      Keep this tight. Do not rewrite state defensively. Do not copy shipped
      history into candidates or strategicContext.
      Preserve Compass's pivot: generated-output projects are Rust/Cargo only.
      Swift/TypeScript/JavaScript state is legacy imported-repo context unless
      the repository being reflected is Compass itself.
      Treat product tournament evidence as advisory tournament evidence. Extract
      durable tournament lessons only from repeated or clearly consequential
      findings, distinguish persona-specific objections from cross-cohort risks,
      and suggest pain, contender, round, experiment, or scenario edits only
      when the evidence supports them. Product risk should not automatically
      fail normal Develop post-checks.
      For tournament decisions, be skeptical of one-off persona feedback. Pay
      attention to repeated objections across scenarios, separate pain validity
      from contender validity, recommend eliminating contenders that repeatedly
      fail to beat current alternatives, and recommend promotion only when both
      tournament evidence and normal Verify support it.
      When Product Tournament Context includes `round_2_evidence_lock`, treat
      `paused_sibling_experiments` as intentionally paused while the selected
      Round 2 contender proves core technology. Do not recommend planning
      revisions or tournamentDecisionUpdates that restart sibling evidence unless
      new transition evidence says the tournament should leave the current
      Round 2 target.
      Allowed experiment decision transitions are:
      - not_run -> continue
      - continue -> continue | narrow | pivot | kill | promote
      - narrow -> continue | pivot | kill | promote
      - pivot -> continue | kill
      - kill -> archived
      - promote -> promoted
      Include a non-empty decision summary for kill, promote, archived, and
      promoted decisions, and list supporting evidence run ids when available.
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

      ## Product Tournament Context
      \(productTournamentDigest)
      """
  }

  private static func reflectCompactPromptBlock(
    _ text: String,
    maxLines: Int,
    maxCharacters: Int
  ) -> String {
    let normalized =
      text
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

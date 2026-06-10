import Foundation

extension Prompts {
  static func planPrompt(
    state: PlanProposal,
    completedCount: Int,
    drafts: String,
    feedback: String,
    lessons: String,
    assumptions: String = "",
    vision: String,
    focus: PlanFocus,
    forgeProfile: ForgeProfile? = nil,
    coverageSnapshot: CoverageSnapshot? = nil,
    hostXcodeBuildTestEnabled: Bool = false
  ) throws -> String {
    let stateJSON = try CompassWorkspace.encodeProposal(state.promptDigest())
    return """
      You are the Plan agent in Compass, a local software factory. Compass does most of the
      deterministic work; your job is narrow decomposition and selection.

      Choose exactly one small implementation packet for the next Develop pass. Do not edit
      files or commit. Use read-only tools and `bash` probes when they help ground the choice.

      Factory rules:
      - Generated Compass output is TypeScript only.
      - New generated projects use pnpm workspaces, strict TypeScript, Vite + React in
        `packages/web`, Vitest coverage, and `tsx` for CLI/dev scripts.
      - Prefer `pnpm verify` as the verify command. Do not use bare `pnpm test`.
        For focused test slices use `pnpm test -- --coverage`; for compile-only
        or docs-only slices use `pnpm typecheck` or `pnpm build`.
      - Keep `brief` stable and short: summary, target users, desired outcomes, constraints,
        and acceptance signals.
      - Keep `queue` to at most six actionable work items. Mark obsolete work stale or drop it.
      - Pick one `immediate` item with a concrete Markdown handoff and a real verify command.
      - Use `immediate: null` only when there is no useful draft, feedback, queue item, or
        repository-originated cleanup/test/docs slice.
      - Acceptance checks describe observable behavior or state. Put shell commands only in
        `immediate.verify`.
      - Completed history is managed by Compass. It currently has \(completedCount) completed
        iteration(s). Use `plan_history` when old shipped work matters.

      \(forgeProfileSection(forgeProfile: forgeProfile))

      \(forgeCoveragePlanningRules(forgeProfile: forgeProfile))

      \(lessonEditsGuidance())

      \(focus.promptGuidance)

      Finish with exactly this envelope:
      {
        "kind": "plan_submit",
        "payload": {
          "state": {
            "immediate": {
              "plan": "## Outcome\\n<what changes>\\n\\n## Why it matters\\n<why now>\\n\\n## Acceptance checks\\n- <observable result>",
              "verify": "pnpm verify",
              "verifyTimeoutMs": 600000,
              "estimatedDifficulty": "low",
              "selectedBecause": "<why this is next>",
              "source": "candidate",
              "candidateID": null
            },
            "queue": [],
            "brief": {
              "summary": "<software task context>",
              "targetUsers": [],
              "desiredOutcomes": [],
              "constraints": [],
              "acceptanceSignals": []
            },
            "openQuestions": []
          },
          "lessonEdits": []
        }
      }

      ## Current factory state
      ```json
      \(stateJSON)
      ```

      ## Drafts
      \(fencedOrEmpty(drafts, empty: "_(no new drafts)_"))

      ## Feedback
      \(fencedOrEmpty(compactPromptBlock(feedback, maxLines: 8, maxCharacters: 1800), empty: "_(no feedback)_"))

      ## Lessons
      \(fencedOrEmpty(compactPromptBlock(lessons, maxLines: 8, maxCharacters: 1800), empty: "_(no lessons yet)_"))

      ## Assumptions
      \(fencedOrEmpty(compactPromptBlock(assumptions, maxLines: 8, maxCharacters: 1800), empty: "_(no assumptions recorded)_"))

      ## Project context
      \(fencedOrEmpty(compactPromptBlock(vision, maxLines: 10, maxCharacters: 2400), empty: "_(no project context set)_"))

      ## Coverage
      \(coverageSnapshot?.formattedForPrompt() ?? "_(no coverage snapshot yet)_")

      Use `plan_continue` for any read-only tool you need. Use `plan_submit` when you have selected the next packet.
      """
  }

  static func compactPromptBlock(
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
      guard !line.isEmpty, seen.insert(line).inserted else { continue }
      lines.append(line)
      if lines.count >= maxLines { break }
    }
    let joined = lines.joined(separator: "\n")
    guard joined.count > maxCharacters else { return joined }
    return String(joined.prefix(max(0, maxCharacters - 3)))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

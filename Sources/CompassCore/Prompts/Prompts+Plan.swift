import Foundation

extension Prompts {
  public static func planPrompt(
    state: PlanProposal,
    completedCount: Int,
    drafts: String,
    feedback: String,
    lessons: String,
    assumptions: String = "",
    vision: String,
    focus: PlanFocus,
    coverageSnapshot: CoverageSnapshot? = nil,
    mutationSnapshot: MutationSnapshot? = nil,
    promptMode: AgentPromptMode = .envelope
  ) throws -> String {
    let stateJSON = try CompassWorkspace.encodeProposal(state.promptDigest())
    let submitExample = """
      {
        "state": {
          "immediate": {
            "plan": "## Outcome\\n<what changes>\\n\\n## Why it matters\\n<why now>\\n\\n## Acceptance checks\\n- <observable result>",
            "verify": "\(GeneratedProjectQuality.standardVerifyCommand)",
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
      """
    let submitSection =
      promptMode == .nativeTools
      ? """
      Finish by calling the `plan_submit` tool with these arguments:
      \(submitExample)

      """
      : """
      Finish with exactly this envelope:
      {
        "kind": "plan_submit",
        "payload": \(submitExample)
      }

      """
    let closingLine =
      promptMode == .nativeTools
      ? "Use the read-only Compass tools to ground your choice, then call `plan_submit`."
      : "Use `plan_continue` for any read-only tool you need. Use `plan_submit` when you have selected the next packet."
    return """
      You are the Plan agent in Compass, a local software factory. Compass does most of the
      deterministic work; your job is narrow decomposition and selection.

      Choose exactly one small implementation packet for the next Develop pass. Do not edit
      files or commit. Use read-only tools and `bash` probes when they help ground the choice.

      Factory rules:
      - Generated Compass projects require Rust `crates/core` plus products `cli` and/or `macos`.
      - Layout: `crates/core` (domain), optional `crates/cli`, optional `crates/ui` + `crates/ffi` + `apps/macos`.
        Prefer `\(GeneratedProjectQuality.standardVerifyCommand)` as the Rust verify command
        (includes `crates/ui` simulation tests when macOS is enabled).
        When `macos` is enabled, host/VM also runs `\(GeneratedProjectQuality.macosVerifyCommand)`.
        Headed launch/screenshot is opt-in via `\(GeneratedProjectQuality.macosUIFidelityEnvironmentKey)=1`.
        For focused test slices use `cargo test --workspace` or
        `\(GeneratedProjectQuality.coverageCollectCommand)`; for compile-only slices
        use `cargo check --workspace` or `cargo clippy --workspace`.
      - Prefer dependency-free implementation packets. If the next slice needs a new
        crate dependency, the handoff must explicitly include the owning `Cargo.toml`
        update and tests.
      - Keep `brief` stable and short: summary, target users, desired outcomes, constraints,
        and acceptance signals.
      - Keep `queue` to at most six actionable work items. Mark obsolete work stale or drop it.
        For a simple first slice, use `"queue": []`. Only include queued follow-ups when
        they are concrete, and every queue item has `id`, `title`, `outcome`, `why`,
        `category`, `origin`, `priority`, `status`, `evidence`, and `blockedBy`.
        Queue enum values are lowercase: `category` is one of `feature`, `test`,
        `cleanup`, `docs`, `bugHunt`, `reliability`, `exploration`; `origin` is one
        of `draft`, `feedback`, `repository`, `plan`, `lesson`, `user`; `priority`
        is one of `low`, `medium`, `high`; `status` is one of `available`, `active`,
        `blocked`, `deferred`, `done`, `stale`.
      - Pick one `immediate` item with a concrete Markdown handoff and a real verify command.
      - Name likely target files in the handoff. Use `crates/core/src` for domain logic,
        `crates/cli/src` for CLI behavior, `crates/ui` for ViewState/Actions/simulation,
        `crates/ffi` for UniFFI exports, and `apps/macos` only for thin SwiftUI binder work
        (no domain or UI policy in Swift).
        Put Rust integration tests in `crates/*/tests/`; unit tests belong in `#[cfg(test)]`
        modules inside the crate sources.
      - Do not name a file path as an existing target unless a read-only tool proved it
        exists. If a path is intentionally new, say `create new file <path>` in the
        handoff.
      - If the Outcome or Acceptance checks claim new CLI behavior, include the
        matching test file/update in the handoff or choose a verify command that directly
        exercises that behavior. The standard verify command only proves new behavior when
        the packet adds or updates tests for it.
      - Use `immediate: null` only when there is no useful draft, feedback, queue item, or
        repository-originated cleanup/test/docs slice.
      - Acceptance checks describe observable behavior or state. Put shell commands only in
        `immediate.verify`.
      - Completed history is managed by Compass. It currently has \(completedCount) completed
        iteration(s). Use `plan_history` when old shipped work matters.

      \(generatedProjectConventionsSection())

      \(generatedCoveragePlanningRules())

      \(lessonEditsGuidance())

      \(focus.promptGuidance)

      \(submitSection)## Current factory state
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

      ## Mutation testing
      \(mutationSnapshot?.formattedForPrompt() ?? "_(no mutation snapshot yet)_")

      \(closingLine)
      """
  }

  public static func compactPromptBlock(
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

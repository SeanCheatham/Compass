import Foundation

extension Prompts {
  static func sharedVMApplePlatformPlanningRuleWhenHostXcodeDisabled(
    forgeProfile: ForgeProfile?
  ) -> String {
    guard forgeProfile == .swiftSPM else { return "" }
    return """
      - This Swift repo runs in the Shared VM with Command Line Tools only.
        Enable **Host Xcode Build/Test** in Compass before planning `swift test`
        or `xcodebuild` verify; until then use guest `swift build` or compile-only
        targets for verify.
      """
  }

  /// Instruction appended to the live conversation when the executor
  /// needs to compact the message history. The model is asked to drop
  /// what it was doing and emit a plain-text summary that the next
  /// iteration can resume from.
  static let conversationSummarizationInstruction = """
    STOP. Do not call any tools. Do not continue the task.

    The context window is filling up. Write a compact summary of THIS conversation so far so the agent can resume in a fresh window. Cover, in order:

    1. The user's original goal and any constraints (from the very first user message).
    2. What has been completed or established (decisions, facts learned, files inspected).
    3. Notable file paths, line ranges, and code snippets that the resumed agent will need to act on (quote sparingly but precisely — paths and symbols beat prose).
    4. Errors encountered, why they happened, and how they were addressed (or not).
    5. The current in-flight step: what was just attempted, what tool result is pending, and what the immediate next action should be.

    Be terse but specific. Reply ONLY with the summary as plain text — no preamble, no tool call, no `submit_result`. The next turn will receive only this summary plus the original task.
    """

  static func forgeProfileSection(forgeProfile: ForgeProfile?) -> String {
    guard let forgeProfile else {
      return """
        ## Forge profile
        _(not detected — Compass supports Swift/SwiftPM, Go modules, Cargo, and TypeScript/Vitest projects)_
        """
    }
    return """
      ## Forge profile
      Active profile: **\(forgeProfile.displayName)** (`\(forgeProfile.rawValue)`)

      \(forgeProfile.planningGuidance)
      """
  }

  static func forgeCoveragePlanningRules(forgeProfile: ForgeProfile?) -> String {
    guard let forgeProfile else { return "" }
    return """
      - Forge profile coverage rule (\(forgeProfile.displayName)): \
      \(forgeProfile.coverageRequirementHint)
      - When Plan focus is `test` or `bugHunt`, prefer increments that raise \
      coverage on the lowest-covered files listed in the Coverage section.
      """
  }

  static func encodeSessions(_ sessions: [SessionRecord]) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(sessions)
    return String(decoding: data, as: UTF8.self)
  }

  static func fencedOrEmpty(_ text: String, empty: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return empty }
    return """
      ```
      \(trimmed)
      ```
      """
  }
}

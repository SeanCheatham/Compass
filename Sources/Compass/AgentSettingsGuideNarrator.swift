import Foundation

struct AgentSettingsGuideNarration: Equatable, Sendable {
  var guideIdentifier: String
  var text: String
}

enum AgentSettingsGuideNarrator {
  static let maxCharacters = 360

  static func narrate(guide: AgentSettingsGuide) async -> AgentSettingsGuideNarration? {
    guard FoundationModelsAvailability.isAvailable else { return nil }

    if #available(macOS 26.0, *) {
      guard
        let generated = await FoundationModelsAvailability._streamText(
          prompt: prompt(for: guide)
        )
      else {
        return nil
      }
      let text = sanitized(generated)
      guard !text.isEmpty else { return nil }
      return AgentSettingsGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for guide: AgentSettingsGuide) -> String {
    """
    You are Compass explaining agent settings to a non-engineer.
    Use only the facts below. Do not invent commands, files, accounts, costs, timing, or outcomes.
    Return one calm paragraph under 50 words. No Markdown.

    Status: \(guide.title)
    Detail: \(guide.detail)
    Action: \(guide.actionLabel)
    Rows: \(guide.rows.map { "\($0.label) - \($0.status.rawValue) - \($0.detail)" }.joined(separator: " | "))
    """
  }

  private static func sanitized(_ text: String) -> String {
    let normalized = StringUtils.boundedText(
      text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " "),
      limit: maxCharacters
    )
    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))

    guard
      !normalized.contains("{"),
      !normalized.contains("}"),
      !normalized.contains("```"),
      !normalized.hasPrefix("- "),
      !normalized.hasPrefix("* "),
      !normalized.lowercased().contains("http://"),
      !normalized.lowercased().contains("https://")
    else {
      return ""
    }
    return normalized
  }
}

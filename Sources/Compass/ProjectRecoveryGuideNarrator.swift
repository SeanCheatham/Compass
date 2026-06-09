import Foundation

struct ProjectRecoveryGuideNarration: Equatable, Sendable {
  var guideIdentifier: String
  var text: String
}

enum ProjectRecoveryGuideNarrator {
  static let maxCharacters = 340

  static func narrate(guide: ProjectRecoveryGuide) async -> ProjectRecoveryGuideNarration? {
    guard guide.allowsNarration else { return nil }
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
      return ProjectRecoveryGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for guide: ProjectRecoveryGuide) -> String {
    """
    You are Compass explaining how to recover a stalled local software-factory run to a non-engineer.
    Use only the facts below. Do not invent files, commands, credentials, outcomes, or next steps.
    Return one calm paragraph under 45 words. No Markdown.

    Recovery title: \(guide.title)
    Steps: \(guide.steps.map { "\($0.title) - \($0.detail)" }.joined(separator: " | "))
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

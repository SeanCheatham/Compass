import Foundation

struct SandboxReadinessGuideNarration: Equatable, Sendable {
  var guideIdentifier: String
  var text: String
}

enum SandboxReadinessGuideNarrator {
  static let maxCharacters = 360

  static func narrate(
    guide: SandboxReadinessGuide
  ) async -> SandboxReadinessGuideNarration? {
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
      return SandboxReadinessGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for guide: SandboxReadinessGuide) -> String {
    """
    You are Compass explaining Shared VM sandbox readiness to a non-engineer.
    Use only the facts below. Do not invent commands, accounts, files, timing, credentials, or outcomes.
    Return one calm paragraph under 50 words. No Markdown.

    Status: \(guide.title)
    Detail: \(guide.detail)
    Action: \(guide.actionLabel)
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

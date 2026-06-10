import Foundation

struct ProjectIntakeGuideNarration: Equatable, Sendable {
  var guideIdentifier: String
  var text: String
}

enum ProjectIntakeGuideNarrator {
  static let maxCharacters = 320

  static func narrate(guide: ProjectIntakeGuide) async -> ProjectIntakeGuideNarration? {
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
      return ProjectIntakeGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for guide: ProjectIntakeGuide) -> String {
    """
    You are Compass helping a non-engineer start with project intake.
    Use only the facts below. Do not invent repository paths, commands, files, accounts, setup results, timing, or outcomes.
    Return one warm, concrete sentence under 40 words. No Markdown.

    Status: \(guide.statusLabel)
    Detail: \(guide.detail)
    Recommended action: \(guide.actionLabel)
    Project count: \(guide.projectCount)
    Steps: \(guide.steps.map { "\($0.title) - \($0.detail)" }.joined(separator: " | "))
    Good project signals: \(guide.signals.map { "\($0.label) - \($0.detail)" }.joined(separator: " | "))
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

    let lowercased = normalized.lowercased()
    guard
      !normalized.contains("{"),
      !normalized.contains("}"),
      !normalized.contains("```"),
      !normalized.hasPrefix("- "),
      !normalized.hasPrefix("* "),
      !lowercased.contains("http://"),
      !lowercased.contains("https://")
    else {
      return ""
    }

    return normalized
  }
}

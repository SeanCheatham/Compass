import Foundation

public struct DraftReadinessGuideNarration: Equatable, Sendable {
  public var guideIdentifier: String
  public var text: String
}

public enum DraftReadinessGuideNarrator {
  public static let maxCharacters = 300

  public static func narrate(guide: DraftReadinessGuide) async -> DraftReadinessGuideNarration? {
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
      return DraftReadinessGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  public static func prompt(for guide: DraftReadinessGuide) -> String {
    """
    You are Compass coaching a rough planning draft for a non-engineer.
    Use only the facts below. Do not invent files, commands, acceptance criteria, deadlines, or outcomes.
    Return one calm sentence under 35 words that asks the most helpful follow-up question. No Markdown.

    Draft: \(guide.draftPreview)
    Status: \(guide.title)
    Detail: \(guide.detail)
    Score: \(guide.scoreLabel)
    Present signals: \(guide.satisfiedSignalText)
    Missing signals: \(guide.missingSignalText)
    Follow-up questions:
    \(guide.coachingPrompts.map { "\($0.question) \($0.detail)" }.joined(separator: "\n"))
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

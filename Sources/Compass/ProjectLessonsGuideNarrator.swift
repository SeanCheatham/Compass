import Foundation

struct ProjectLessonsGuideNarration: Equatable, Sendable {
  var guideIdentifier: String
  var text: String
}

enum ProjectLessonsGuideNarrator {
  static let maxCharacters = 320

  static func narrate(guide: ProjectLessonsGuide) async -> ProjectLessonsGuideNarration? {
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
      return ProjectLessonsGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for guide: ProjectLessonsGuide) -> String {
    """
    You are Compass explaining project lessons to a non-engineer.
    Use only the facts below. Do not invent files, commands, results, decisions, constraints, or future requirements.
    Return one warm, concrete sentence under 40 words. No Markdown.

    Lessons: \(guide.lessonsPreview)
    Status: \(guide.title)
    Detail: \(guide.detail)
    Score: \(guide.scoreLabel)
    Present signals: \(guide.satisfiedSignalText)
    Missing signals: \(guide.missingSignalText)
    Next action: \(guide.nextAction.title) - \(guide.nextAction.detail)
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

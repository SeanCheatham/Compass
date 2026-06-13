import Foundation

package struct ProjectVisionGuideNarration: Equatable, Sendable {
  package var guideIdentifier: String
  package var text: String
}

package enum ProjectVisionGuideNarrator {
  package static let maxCharacters = 320

  package static func narrate(guide: ProjectVisionGuide) async -> ProjectVisionGuideNarration? {
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
      return ProjectVisionGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  package static func prompt(for guide: ProjectVisionGuide) -> String {
    """
    You are Compass coaching a project vision for a non-engineer.
    Use only the facts below. Do not invent users, requirements, constraints, outcomes, files, commands, or timing.
    Return one warm, concrete sentence under 40 words. No Markdown.

    Vision: \(guide.visionPreview)
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

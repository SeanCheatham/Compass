import Foundation

package struct LiveTimelineGuideNarration: Equatable, Sendable {
  package var guideIdentifier: String
  package var text: String
}

package enum LiveTimelineGuideNarrator {
  package static let maxCharacters = 340

  package static func narrate(guide: LiveTimelineGuide) async -> LiveTimelineGuideNarration? {
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
      return LiveTimelineGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  package static func prompt(for guide: LiveTimelineGuide) -> String {
    """
    You are Compass explaining the Live timeline to a non-engineer.
    Use only the facts below. Do not invent project facts, commands, files, outcomes, or next steps.
    Return one calm sentence under 45 words. No Markdown.

    Status: \(guide.title)
    Detail: \(guide.detail)
    Badge: \(guide.statusLabel)
    Evidence: \(guide.evidenceCoverage.label) - \(guide.evidenceCoverage.detail)
    Checkpoints: \(guide.checkpoints.map { "\($0.label) - \($0.detail)" }.joined(separator: " | "))
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
      !normalized.lowercased().contains("http://"),
      !normalized.lowercased().contains("https://")
    else {
      return ""
    }
    return normalized
  }
}

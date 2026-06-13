import Foundation

package struct DraftIntakeGuideNarration: Equatable, Sendable {
  package var guideIdentifier: String
  package var text: String
}

package enum DraftIntakeGuideNarrator {
  package static let maxCharacters = 340

  package static func narrate(guide: DraftIntakeGuide) async -> DraftIntakeGuideNarration? {
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
      return DraftIntakeGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  package static func prompt(for guide: DraftIntakeGuide) -> String {
    """
    You are Compass explaining queued planning drafts to a non-engineer.
    Use only the facts below. Do not invent files, commands, timing, outcomes, or success criteria.
    Return one calm paragraph under 45 words. No Markdown.

    Queue title: \(guide.title)
    Queue detail: \(guide.detail)
    Queue score: \(guide.scoreLabel)
    Next action: \(guide.nextAction.title) - \(guide.nextAction.detail)
    Queue scope: \(guide.totalEntryCount) total drafts; \(guide.hiddenEntryCount) outside the visible checklist.
    Drafts:
    \(guide.entries.map(entrySummary).joined(separator: "\n"))
    """
  }

  private static func entrySummary(_ entry: DraftIntakeGuide.Entry) -> String {
    """
    Draft \(entry.number): \(entry.draft) | Status: \(entry.readiness.title) | Present: \(entry.satisfiedSignalText) | Missing: \(entry.missingSignalText)
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

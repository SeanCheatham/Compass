import Foundation

struct AssumptionReviewGuideNarration: Equatable, Sendable {
  var guideIdentifier: String
  var text: String
}

enum AssumptionReviewGuideNarrator {
  static let maxCharacters = 360

  static func narrate(guide: AssumptionReviewGuide) async -> AssumptionReviewGuideNarration? {
    guard guide.tone != .empty else { return nil }
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
      return AssumptionReviewGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for guide: AssumptionReviewGuide) -> String {
    """
    You are Compass explaining its assumption memory to a non-engineer.
    Use only the facts below. Do not invent project facts, deadlines, files, or outcomes.
    Return one calm paragraph under 55 words. No Markdown.

    Status: \(guide.title)
    Detail: \(guide.detail)
    Prompt effect: \(guide.promptEffect)
    Steps: \(guide.steps.map { "\($0.label) - \($0.detail)" }.joined(separator: " | "))
    Review queue: \(guide.queue.map { "\($0.label) - \($0.detail)" }.joined(separator: " | "))
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

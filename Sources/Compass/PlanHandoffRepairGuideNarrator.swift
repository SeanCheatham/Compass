import Foundation

struct PlanHandoffRepairGuideNarration: Equatable, Sendable {
  var guideIdentifier: String
  var text: String
}

enum PlanHandoffRepairGuideNarrator {
  static let maxCharacters = 340

  static func narrate(
    guide: PlanHandoffRepairGuide
  ) async -> PlanHandoffRepairGuideNarration? {
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
      return PlanHandoffRepairGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for guide: PlanHandoffRepairGuide) -> String {
    """
    You are Compass explaining how Plan should repair an Immediate Work handoff for a non-engineer.
    Use only the facts below. Do not invent files, commands, credentials, outcomes, timing, or next steps.
    Return one calm paragraph under 45 words. No Markdown.

    Status: \(guide.title)
    Readiness: \(guide.scoreLabel)
    Detail: \(guide.detail)
    Checklist: \(guide.steps.map { "\($0.title) - satisfied: \($0.isSatisfied) - \($0.detail)" }.joined(separator: " | "))
    Suggested verify: \(guide.suggestedVerifyCommand ?? "none")
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

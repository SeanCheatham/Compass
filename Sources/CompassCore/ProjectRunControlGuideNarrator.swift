import Foundation

public struct ProjectRunControlGuideNarration: Equatable, Sendable {
  public var guideIdentifier: String
  public var text: String
}

public enum ProjectRunControlGuideNarrator {
  public static let maxCharacters = 320

  public static func narrate(guide: ProjectRunControlGuide) async -> ProjectRunControlGuideNarration? {
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
      return ProjectRunControlGuideNarration(
        guideIdentifier: guide.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  public static func prompt(for guide: ProjectRunControlGuide) -> String {
    """
    You are Compass explaining run controls to a non-engineer.
    Use only the facts below. Do not invent files, commands, credentials, timing, outcomes, or next steps.
    Return one calm sentence under 35 words. No Markdown.

    Readiness: \(guide.readiness.title) - \(guide.readiness.detail)
    Run signal: \(guide.decisionBadge.label) - \(guide.decisionBadge.detail)
    Primary explanation: \(guide.primaryHelp)
    Primary action: \(guide.primaryOption.title) - \(guide.primaryOption.detail)
    Next run preview: \(guide.previewSteps.map { "\($0.title) - \($0.detail)" }.joined(separator: " | "))
    Available modes: \(guide.options.map { "\($0.title) - \($0.detail) - enabled: \($0.isEnabled)" }.joined(separator: " | "))
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

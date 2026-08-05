import Foundation

/// Rewrites raw agent thinking into a single spoken sentence for Studio's
/// audible narration. Uses the shared assist text path (local-first) and
/// falls back to a truncated verbatim line when no model is available.
public enum StudioThinkingNarrator {
  public static let maxSpokenCharacters = 220
  public static let maxInputCharacters = 1500

  public static func narrate(thinking: String) async -> String? {
    let input = boundedInput(thinking)
    guard !input.isEmpty else { return nil }
    guard FoundationModelsAvailability.isAvailable else { return nil }
    guard let generated = await FoundationModelsAvailability._streamText(prompt: prompt(for: input))
    else { return nil }
    let text = sanitized(generated)
    return text.isEmpty ? nil : text
  }

  /// Spoken text when no model is available: first line, whitespace-collapsed,
  /// code-ish tokens stripped, bounded for a single utterance.
  public static func fallbackSpokenText(for thinking: String) -> String {
    sanitized(boundedInput(thinking))
  }

  public static func prompt(for thinking: String) -> String {
    """
    You are the voice of a software agent working in an IDE. Rewrite its private \
    thought below as one short spoken sentence for someone listening, not reading. \
    Use plain words. Do not read out code, symbols, file paths, or line numbers — \
    describe the intent instead. Under 30 words. No Markdown. No preamble.

    Agent thought:
    \(thinking)
    """
  }

  static func boundedInput(_ thinking: String) -> String {
    StringUtils.boundedText(
      thinking.trimmingCharacters(in: .whitespacesAndNewlines),
      limit: maxInputCharacters
    )
  }

  static func sanitized(_ text: String) -> String {
    let normalized = StringUtils.boundedText(
      text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " "),
      limit: maxSpokenCharacters
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

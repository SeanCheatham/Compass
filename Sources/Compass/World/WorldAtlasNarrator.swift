import Foundation

struct WorldAtlasNarration: Equatable, Sendable {
  var atlasIdentifier: String
  var text: String
}

enum WorldAtlasNarrator {
  static let maxCharacters = 240

  static func narrate(atlas: WorldAtlas) async -> WorldAtlasNarration? {
    guard !atlas.terrain.isEmpty else { return nil }
    guard FoundationModelsAvailability.isAvailable else { return nil }

    if #available(macOS 26.0, *) {
      guard
        let generated = await FoundationModelsAvailability._streamText(
          prompt: prompt(for: atlas)
        )
      else {
        return nil
      }
      let text = sanitized(generated)
      guard !text.isEmpty else { return nil }
      return WorldAtlasNarration(
        atlasIdentifier: atlas.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for atlas: WorldAtlas) -> String {
    """
    You are Compass's World guide for a non-engineer.
    Use only the facts below. Do not invent files, functions, risks, or outcomes.
    Return one calm paragraph under 42 words. No Markdown.
    Do not use fantasy, adventure, game, maze, or welcome language.

    Summary: \(atlas.detail)
    Progress: \(atlas.progressLabel)
    Metrics: \(atlas.metrics.map { "\($0.label): \($0.value)" }.joined(separator: ", "))
    Terrain: \(atlas.terrain.prefix(6).map { "\($0.label): \($0.count) - \($0.detail)" }.joined(separator: " | "))
    Notices: \(atlas.notices.prefix(5).map { "\($0.label) - \($0.detail)" }.joined(separator: " | "))
    Walk: \(atlas.routeStops.prefix(6).map { "\($0.isCurrent ? "Current" : "Stop"): \($0.label) (\($0.detail))" }.joined(separator: " | "))
    """
  }

  private static func sanitized(_ text: String) -> String {
    let normalized = fittedPlainText(
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

  private static func fittedPlainText(_ text: String, limit: Int) -> String {
    let normalized = StringUtils.boundedText(text, limit: Int.max)
    guard normalized.count > limit else { return normalized }
    let prefix = normalized.prefix(limit)
    if let lastSentence = prefix.lastIndex(where: { ".!?".contains($0) }),
      lastSentence > prefix.startIndex
    {
      return String(prefix[...lastSentence]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let lastSpace = prefix.lastIndex(where: { $0 == " " }), lastSpace > prefix.startIndex {
      return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
    return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

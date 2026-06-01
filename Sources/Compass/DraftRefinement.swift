import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

struct DraftRefinement: Equatable, Sendable {
  enum Source: String, Equatable, Sendable {
    case generated
    case deterministic
  }

  var originalDraft: String
  var refinedText: String
  var source: Source

  init(originalDraft: String, refinedText: String, source: Source) {
    self.originalDraft = originalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    self.refinedText = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
    self.source = source
  }
}

struct DraftRefinementContext: Equatable, Hashable, Sendable {
  static let valueMaxCharacters = 160

  var repoName: String
  var immediatePlan: String
  var midTermPlan: String
  var longTermPlan: String
  var primaryLanguage: String

  init(
    repoName: String,
    immediatePlan: String = "",
    midTermPlan: String = "",
    longTermPlan: String = "",
    primaryLanguage: String = ""
  ) {
    self.repoName = Self.bounded(repoName)
    self.immediatePlan = Self.bounded(immediatePlan)
    self.midTermPlan = Self.bounded(midTermPlan)
    self.longTermPlan = Self.bounded(longTermPlan)
    self.primaryLanguage = Self.bounded(primaryLanguage)
  }

  init(
    repoName: String,
    state: PlanState,
    languageProfile: RepositoryLanguageProfile = .empty
  ) {
    self.init(
      repoName: repoName,
      immediatePlan: state.immediate?.plan ?? "",
      midTermPlan: state.midTerm,
      longTermPlan: state.longTerm,
      primaryLanguage: languageProfile.primaryLanguage == .unknown
        ? ""
        : languageProfile.primaryLanguage.displayName
    )
  }

  @MainActor
  init(project: CompassProject) {
    self.init(
      repoName: project.displayName,
      state: project.state,
      languageProfile: project.languageProfile
    )
  }

  var cacheIdentifier: String {
    [
      repoName,
      immediatePlan,
      midTermPlan,
      longTermPlan,
      primaryLanguage,
    ]
    .map(Self.normalizedPlainText)
    .joined(separator: "\n")
  }

  var promptText: String {
    """
    Repository: \(repoName.isEmpty ? "unknown" : repoName)
    Immediate plan: \(immediatePlan.isEmpty ? "none" : immediatePlan)
    Mid-term direction: \(midTermPlan.isEmpty ? "none" : midTermPlan)
    Long-term direction: \(longTermPlan.isEmpty ? "none" : longTermPlan)
    Primary language: \(primaryLanguage.isEmpty ? "unknown" : primaryLanguage)
    """
  }

  var noInventionSourceText: String {
    [
      repoName,
      immediatePlan,
      midTermPlan,
      longTermPlan,
      primaryLanguage,
    ]
    .joined(separator: " ")
  }

  private static func bounded(_ text: String) -> String {
    fittedPlainText(normalizedPlainText(text), maxCharacters: valueMaxCharacters)
  }

  private static func fittedPlainText(_ text: String, maxCharacters: Int) -> String {
    let normalized = normalizedPlainText(text)
    guard normalized.count > maxCharacters else { return normalized }

    let prefix = normalized.prefix(maxCharacters)
    if let lastSpace = prefix.lastIndex(where: { $0 == " " }), lastSpace > prefix.startIndex {
      return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func normalizedPlainText(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct DraftRefinementPreviewKey: Equatable, Hashable, Sendable {
  var trimmedDraft: String
  var contextIdentifier: String

  init(trimmedDraft: String, context: DraftRefinementContext) {
    self.trimmedDraft = DraftRefinementService.normalizeDraft(trimmedDraft)
    self.contextIdentifier = context.cacheIdentifier
  }
}

struct DraftRefinementPreviewPlan: Equatable, Sendable {
  enum Visibility: Equatable, Sendable {
    case hiddenEmptyDraft
    case cached
    case debounce
  }

  var visibility: Visibility
  var cacheKey: DraftRefinementPreviewKey?
  var delayNanoseconds: UInt64

  var shouldShowPreviewSurface: Bool {
    switch visibility {
    case .hiddenEmptyDraft:
      return false
    case .cached, .debounce:
      return true
    }
  }
}

enum DraftRefinementPreviewPlanner {
  static let debounceDelayNanoseconds: UInt64 = 600_000_000

  static func plan(
    draft: String,
    context: DraftRefinementContext,
    cachedKeys: Set<DraftRefinementPreviewKey>
  ) -> DraftRefinementPreviewPlan {
    let trimmedDraft = DraftRefinementService.normalizeDraft(draft)
    guard !trimmedDraft.isEmpty else {
      return DraftRefinementPreviewPlan(
        visibility: .hiddenEmptyDraft,
        cacheKey: nil,
        delayNanoseconds: 0
      )
    }

    let key = DraftRefinementPreviewKey(trimmedDraft: trimmedDraft, context: context)
    if cachedKeys.contains(key) {
      return DraftRefinementPreviewPlan(
        visibility: .cached,
        cacheKey: key,
        delayNanoseconds: 0
      )
    }

    return DraftRefinementPreviewPlan(
      visibility: .debounce,
      cacheKey: key,
      delayNanoseconds: debounceDelayNanoseconds
    )
  }
}

enum DraftRefinementService {
  static let refinedTextMaxCharacters = 900

  static var isPreviewAvailable: Bool {
    true
  }

  private static var isGeneratedPreviewAvailable: Bool {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        return FoundationModelDraftRefinementGenerator.isAvailable
      }
    #endif

    return false
  }

  static func makeRefinement(
    draft: String,
    context: DraftRefinementContext
  ) async -> DraftRefinement? {
    let trimmedDraft = normalizeDraft(draft)
    guard !trimmedDraft.isEmpty else { return nil }

    #if canImport(FoundationModels)
      if #available(macOS 26.0, *), isGeneratedPreviewAvailable {
        if let generated = try? await FoundationModelDraftRefinementGenerator.generate(
          draft: trimmedDraft,
          context: context
        ) {
          return generated
        }
      }
    #endif

    return deterministicRefinement(draft: trimmedDraft, context: context)
  }

  static func deterministicRefinement(
    draft: String,
    context: DraftRefinementContext
  ) -> DraftRefinement? {
    let trimmedDraft = normalizeDraft(draft)
    guard !trimmedDraft.isEmpty else { return nil }

    var refined =
      PlainTextListPrefix.cleanedLine(trimmedDraft)

    if refined.count > refinedTextMaxCharacters {
      refined = fittedPlainText(refined, maxCharacters: refinedTextMaxCharacters)
    }

    refined = sentenceCased(refined)
    refined = withTerminalPunctuation(refined)

    guard
      validateNoInvention(
        refined: refined,
        draft: trimmedDraft,
        context: context
      )
    else {
      return DraftRefinement(
        originalDraft: trimmedDraft,
        refinedText: trimmedDraft,
        source: .deterministic
      )
    }

    return DraftRefinement(
      originalDraft: trimmedDraft,
      refinedText: refined,
      source: .deterministic
    )
  }

  static func parseGeneratedRefinement(
    _ raw: String,
    draft: String,
    context: DraftRefinementContext
  ) -> DraftRefinement? {
    let trimmedDraft = normalizeDraft(draft)
    guard !trimmedDraft.isEmpty else { return nil }

    if let refined = parseJSONRefinement(raw) {
      return validateGenerated(refined: refined, draft: trimmedDraft, context: context)
    }

    let lines =
      raw
      .replacingOccurrences(of: "\r", with: "\n")
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    if let labeledLine = lines.first(where: { $0.lowercased().hasPrefix("refined:") }) {
      return validateGenerated(
        refined: stripLabel(from: labeledLine),
        draft: trimmedDraft,
        context: context
      )
    }

    let collapsed = lines.joined(separator: " ")
    if collapsed.lowercased().hasPrefix("refined:") {
      return validateGenerated(
        refined: stripLabel(from: collapsed),
        draft: trimmedDraft,
        context: context
      )
    }

    guard lines.count == 1 else { return nil }
    return validateGenerated(
      refined: lines[0],
      draft: trimmedDraft,
      context: context
    )
  }

  static func normalizeDraft(_ text: String) -> String {
    normalizePlainText(text)
  }

  private static func validateGenerated(
    refined: String,
    draft: String,
    context: DraftRefinementContext
  ) -> DraftRefinement? {
    let clean = normalizePlainText(refined).trimmingCharacters(
      in: CharacterSet(charactersIn: "\"\'` "))
    guard (3...refinedTextMaxCharacters).contains(clean.count),
      wordCount(clean) <= 140,
      isUsableGeneratedText(clean),
      validateNoInvention(refined: clean, draft: draft, context: context)
    else {
      return nil
    }

    return DraftRefinement(
      originalDraft: draft,
      refinedText: clean,
      source: .generated
    )
  }

  private static func parseJSONRefinement(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    let allowedKeys = Set(["refined", "refinedText"])
    let keys = Set(object.keys)
    guard keys.count == 1, keys.isSubset(of: allowedKeys) else { return nil }
    return (object["refined"] ?? object["refinedText"]) as? String
  }

  private static func validateNoInvention(
    refined: String,
    draft: String,
    context: DraftRefinementContext
  ) -> Bool {
    let source = normalizePlainText([draft, context.noInventionSourceText].joined(separator: " "))
    let refined = normalizePlainText(refined)

    guard
      doesNotAddPatternMatches(
        from: refined,
        source: source,
        pattern: #"(?<![A-Za-z0-9])#?\d[\d,]*(?:\.\d+)?%?(?![A-Za-z0-9])"#
      )
    else {
      return false
    }

    guard
      doesNotAddPatternMatches(
        from: refined,
        source: source,
        pattern:
          #"[A-Za-z0-9_./-]+\.(?:swift|ts|tsx|js|jsx|json|md|txt|yml|yaml|toml|lock|py|go|rs|sh|zsh|html|css|scss|plist|xcodeproj|xcworkspace|m|mm|h|hpp|cpp|c|sql)"#
      )
    else {
      return false
    }

    guard
      doesNotAddPatternMatches(
        from: refined,
        source: source,
        pattern: #"[A-Za-z0-9_-]+/[A-Za-z0-9_./-]+"#
      )
    else {
      return false
    }

    guard
      doesNotAddPatternMatches(
        from: refined,
        source: source,
        pattern:
          #"(?<![A-Za-z0-9_.-])(?:README|LICENSE|Makefile|Dockerfile|Gemfile|Podfile|Rakefile)(?![A-Za-z0-9_.-])"#
      )
    else {
      return false
    }

    let guardedWords = [
      "completed",
      "delivered",
      "done",
      "finish",
      "finished",
      "fixed",
      "implemented",
      "must",
      "never",
      "passed",
      "passing",
      "resolved",
      "shipped",
      "succeeded",
      "successful",
      "verified",
    ]
    guard doesNotAddGuardedWords(guardedWords, refined: refined, source: source) else {
      return false
    }

    let numberWords = [
      "zero",
      "one",
      "two",
      "three",
      "four",
      "five",
      "six",
      "seven",
      "eight",
      "nine",
      "ten",
    ]
    return doesNotAddGuardedWords(numberWords, refined: refined, source: source)
  }

  private static func doesNotAddPatternMatches(
    from refined: String,
    source: String,
    pattern: String
  ) -> Bool {
    let sourceTokens = Set(matches(in: source.lowercased(), pattern: pattern))
    for token in matches(in: refined.lowercased(), pattern: pattern) {
      guard sourceTokens.contains(token) else { return false }
    }
    return true
  }

  private static func doesNotAddGuardedWords(
    _ words: [String],
    refined: String,
    source: String
  ) -> Bool {
    let refined = refined.lowercased()
    let source = source.lowercased()
    for word in words {
      guard containsWord(word, in: refined) else { continue }
      guard containsWord(word, in: source) else { return false }
    }
    return true
  }

  private static func matches(in text: String, pattern: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return []
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      guard let tokenRange = Range(match.range, in: text) else { return nil }
      return String(text[tokenRange]).lowercased()
    }
  }

  private static func containsWord(_ word: String, in text: String) -> Bool {
    let escaped = NSRegularExpression.escapedPattern(for: word)
    let pattern = #"(?<![A-Za-z0-9])"# + escaped + #"(?![A-Za-z0-9])"#
    return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static func stripLabel(from line: String) -> String {
    guard let colon = line.firstIndex(of: ":") else { return line }
    return String(line[line.index(after: colon)...])
  }

  private static func normalizePlainText(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func fittedPlainText(_ text: String, maxCharacters: Int) -> String {
    let normalized = normalizePlainText(text)
    guard normalized.count > maxCharacters else { return normalized }

    let prefix = normalized.prefix(maxCharacters)
    if let lastSpace = prefix.lastIndex(where: { $0 == " " }), lastSpace > prefix.startIndex {
      return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
  }

  private static func isUsableGeneratedText(_ text: String) -> Bool {
    let lowercased = text.lowercased()
    guard !lowercased.contains("```"),
      !lowercased.contains("http://"),
      !lowercased.contains("https://"),
      !text.contains("{"),
      !text.contains("}")
    else {
      return false
    }
    return true
  }

  private static func sentenceCased(_ text: String) -> String {
    guard let first = text.first else { return text }
    return String(first).uppercased() + text.dropFirst()
  }

  private static func withTerminalPunctuation(_ text: String) -> String {
    guard let last = text.last else { return text }
    if ".!?".contains(last) {
      return text
    }
    return "\(text)."
  }
}

#if canImport(FoundationModels)
  @available(macOS 26.0, *)
  private enum FoundationModelDraftRefinementGenerator {
    static var isAvailable: Bool {
      FoundationModelsAvailability.isAvailable
    }

    static func generate(
      draft: String,
      context: DraftRefinementContext
    ) async throws -> DraftRefinement? {
      try await FoundationModelsSessionGate.shared.withExclusiveAccess {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(
          model: model,
          instructions: """
            You refine a user's Compass draft into one queued instruction.
            Return exactly one line in this format: "Refined: ...".
            Use only facts present in the supplied draft and context.
            Do not invent file paths, commands, tests, outcomes, counts, deadlines, constraints, or acceptance criteria.
            Preserve uncertainty and keep the request as a future instruction, not completed work.
            """)

        let response = try await session.respond(
          to: """
            Draft:
            \(draft)

            Repository context:
            \(context.promptText)

            Rewrite the draft as one clear instruction under 80 words.
            """,
          options: GenerationOptions(temperature: 0.35, maximumResponseTokens: 160)
        )

        return DraftRefinementService.parseGeneratedRefinement(
          response.content,
          draft: draft,
          context: context
        )
      }
    }
  }
#endif

import Foundation

struct PlanVerifyMetadata: Equatable {
  static let defaultTimeoutMs = 10 * 60 * 1000

  var timeoutMs: Int?

  var label: String {
    let explicitTimeoutMs = timeoutMs.flatMap { $0 > 0 ? $0 : nil }
    let displayTimeoutMs = explicitTimeoutMs ?? Self.defaultTimeoutMs
    let prefix = explicitTimeoutMs == nil ? "Default timeout" : "Timeout"

    return "\(prefix) \(Self.compactDurationLabel(for: displayTimeoutMs))"
  }

  private static func compactDurationLabel(for timeoutMs: Int) -> String {
    let seconds = max(1, timeoutMs / 1000 + (timeoutMs % 1000 == 0 ? 0 : 1))

    if seconds >= 60, seconds % 60 == 0 {
      return "\(seconds / 60)m"
    }

    return "\(seconds)s"
  }
}

struct PlanVerifyCommandSummary: Equatable, Sendable {
  static let commandLimit = 180
  static let detailLimit = 220

  var command: String?
  var title: String
  var detail: String
  var systemImage: String

  init(command rawCommand: String?) {
    command = StringUtils.boundedText(rawCommand ?? "", limit: Self.commandLimit).nilIfEmpty

    guard let command else {
      title = "No verification selected"
      detail = "Plan has not chosen the check Compass should run after building."
      systemImage = "questionmark.circle"
      return
    }

    let normalized = Self.normalizedCommand(command)
    let lowercased = normalized.lowercased()

    if lowercased.contains("swift test") {
      let collectsCoverage = lowercased.contains("--enable-code-coverage")
      title = collectsCoverage ? "Runs Swift coverage" : "Runs Swift tests"
      detail = Self.testDetail(
        framework: "Swift",
        filter: Self.argumentValue(after: "--filter", in: normalized),
        collectsCoverage: collectsCoverage
      )
      systemImage = "checkmark.seal"
    } else if lowercased.contains("xcodebuild"), lowercased.contains(" test") {
      title = "Runs Xcode tests"
      detail = Self.testDetail(
        framework: "Xcode",
        filter: Self.argumentValue(after: "-only-testing", in: normalized)
      )
      systemImage = "checkmark.seal"
    } else if lowercased.contains("xcodebuild"), lowercased.contains(" build") {
      title = "Builds with Xcode"
      detail = "Compass will ask Xcode to compile the selected scheme and fail if it does not build."
      systemImage = "hammer"
    } else if lowercased.contains("swift build") {
      title = "Builds the Swift package"
      if let target = Self.argumentValue(after: "--target", in: normalized) {
        detail = "Compass will compile the \(target) target and fail on build errors."
      } else {
        detail = "Compass will compile the Swift package and fail on build errors."
      }
      systemImage = "hammer"
    } else if lowercased.contains("cargo test") {
      title = "Runs Rust tests"
      detail = lowercased.contains("--all-features")
        ? "Compass will run the Rust test suite with all feature flags enabled."
        : "Compass will run the Rust test suite."
      systemImage = "checkmark.seal"
    } else if lowercased.contains("cargo llvm-cov") {
      title = "Runs Rust coverage"
      detail = "Compass will run Rust tests through cargo-llvm-cov and report coverage."
      systemImage = "chart.bar.doc.horizontal"
    } else if Self.containsAny(
      lowercased,
      [
        "pytest",
        "python -m unittest",
        "python3 -m unittest",
      ])
    {
      let collectsCoverage = lowercased.contains("--cov") || lowercased.contains("coverage")
      title = collectsCoverage ? "Runs Python coverage" : "Runs Python tests"
      if lowercased.contains("pytest") {
        detail = collectsCoverage
          ? "Compass will run pytest with Python coverage enabled."
          : "Compass will run the Python test suite with pytest."
      } else {
        detail = "Compass will run the Python unittest suite."
      }
      systemImage = "checkmark.seal"
    } else if Self.containsAny(
      lowercased,
      [
        "vitest",
        "npm test",
        "npm run test",
        "pnpm test",
        "pnpm run test",
        "yarn test",
        "yarn run test",
      ])
    {
      let collectsCoverage = lowercased.contains("coverage")
      title = collectsCoverage ? "Runs JavaScript coverage" : "Runs JavaScript tests"
      detail = collectsCoverage
        ? "Compass will run the project's JavaScript or TypeScript tests with coverage enabled."
        : "Compass will run the project's JavaScript or TypeScript test command."
      systemImage = "checkmark.seal"
    } else if Self.containsAny(
      lowercased,
      [
        "npm run build",
        "pnpm build",
        "pnpm run build",
        "yarn build",
        "yarn run build",
      ])
    {
      title = "Builds the web project"
      detail = "Compass will run the project's build script and fail on compile or bundling errors."
      systemImage = "hammer"
    } else if Self.containsAny(lowercased, ["lint", "clippy", "swiftlint"]) {
      title = "Runs quality checks"
      detail = "Compass will run the project's lint or static-analysis command."
      systemImage = "list.bullet.clipboard"
    } else {
      title = "Runs verification"
      detail = "Compass will run the planned command and treat a non-zero exit as a failed check."
      systemImage = "terminal"
    }

    detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
  }

  private static func testDetail(
    framework: String,
    filter: String?,
    collectsCoverage: Bool = false
  ) -> String {
    let coverageSuffix = collectsCoverage ? " Coverage collection is enabled." : ""
    if let filter, !filter.isEmpty {
      return "Compass will run \(framework) tests focused on \(filter).\(coverageSuffix)"
    }
    return "Compass will run the \(framework) test suite.\(coverageSuffix)"
  }

  private static func normalizedCommand(_ command: String) -> String {
    command
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func argumentValue(after flag: String, in command: String) -> String? {
    let parts = command.split(separator: " ").map(String.init)
    for index in parts.indices {
      let part = parts[index]
      if part == flag, parts.index(after: index) < parts.endIndex {
        return cleanedArgumentValue(parts[parts.index(after: index)])
      }
      let prefix = "\(flag)="
      if part.hasPrefix(prefix) {
        return cleanedArgumentValue(String(part.dropFirst(prefix.count)))
      }
      let colonPrefix = "\(flag):"
      if part.hasPrefix(colonPrefix) {
        return cleanedArgumentValue(String(part.dropFirst(colonPrefix.count)))
      }
    }
    return nil
  }

  private static func cleanedArgumentValue(_ value: String) -> String {
    StringUtils.boundedText(
      value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`")),
      limit: 90
    )
  }

  private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
    needles.contains { text.contains($0) }
  }
}

struct PlanHandoffDigest: Equatable, Sendable {
  static let textLimit = 180
  static let checkLimit = 3

  var status: Status
  var title: String
  var detail: String
  var systemImage: String
  var outcome: String?
  var whyItMatters: String?
  var acceptanceChecks: [String]
  var commandOnlyAcceptanceChecks: [String]
  var vagueAcceptanceChecks: [String]
  var missingPieces: [MissingPiece]

  init(plan rawPlan: String?) {
    let plan = Self.normalizedBody(rawPlan ?? "")
    guard !plan.isEmpty else {
      status = .missingPlan
      title = "No handoff yet"
      detail = "Plan has not selected an implementation slice for Develop."
      systemImage = "tray"
      outcome = nil
      whyItMatters = nil
      acceptanceChecks = []
      commandOnlyAcceptanceChecks = []
      vagueAcceptanceChecks = []
      missingPieces = [.outcome, .acceptanceChecks]
      return
    }

    let sections = Self.sections(in: plan)
    outcome = Self.firstMeaningfulLine(in: sections[.outcome] ?? [])
      ?? Self.fallbackOutcome(in: plan)
    whyItMatters = Self.firstMeaningfulLine(in: sections[.whyItMatters] ?? [])
    let cleanedAcceptanceChecks = (sections[.acceptanceChecks] ?? [])
      .map(Self.cleanedContentLine)
      .filter { !$0.isEmpty }
    commandOnlyAcceptanceChecks =
      cleanedAcceptanceChecks
      .filter(Self.isCommandOnlyAcceptanceCheck)
      .prefix(Self.checkLimit)
      .map { StringUtils.boundedText($0, limit: Self.textLimit) }
    vagueAcceptanceChecks =
      cleanedAcceptanceChecks
      .filter { !Self.isCommandOnlyAcceptanceCheck($0) }
      .filter(Self.isVagueAcceptanceCheck)
      .prefix(Self.checkLimit)
      .map { StringUtils.boundedText($0, limit: Self.textLimit) }
    acceptanceChecks =
      cleanedAcceptanceChecks
      .filter { !Self.isCommandOnlyAcceptanceCheck($0) }
      .filter { !Self.isVagueAcceptanceCheck($0) }
      .prefix(Self.checkLimit)
      .map { StringUtils.boundedText($0, limit: Self.textLimit) }

    var missing: [MissingPiece] = []
    if outcome == nil {
      missing.append(.outcome)
    }
    if acceptanceChecks.isEmpty {
      missing.append(.acceptanceChecks)
    }
    if whyItMatters == nil {
      missing.append(.whyItMatters)
    }
    missingPieces = missing

    if outcome != nil, !acceptanceChecks.isEmpty {
      status = .ready
      title = "Executable handoff"
      detail = acceptanceChecks.count == 1
        ? "Outcome and one acceptance check give Develop a clear finish line."
        : "Outcome and \(acceptanceChecks.count) acceptance checks give Develop a clear finish line."
      systemImage = "checklist.checked"
    } else {
      status = .needsDetail
      title = "Handoff needs detail"
      detail = "Missing \(missing.requiredLabels.joined(separator: " and ")) before Develop has a clear finish line."
      systemImage = "list.bullet.clipboard"
    }
  }

  enum Status: String, Equatable, Sendable {
    case ready
    case needsDetail
    case missingPlan
  }

  enum MissingPiece: String, Equatable, Sendable {
    case outcome
    case whyItMatters
    case acceptanceChecks

    var label: String {
      switch self {
      case .outcome:
        return "Outcome"
      case .whyItMatters:
        return "Why it matters"
      case .acceptanceChecks:
        return "Acceptance checks"
      }
    }

    var isRequired: Bool {
      switch self {
      case .outcome, .acceptanceChecks:
        return true
      case .whyItMatters:
        return false
      }
    }
  }

  private enum SectionKey: Hashable {
    case outcome
    case whyItMatters
    case acceptanceChecks
  }

  private static func sections(in plan: String) -> [SectionKey: [String]] {
    var result: [SectionKey: [String]] = [:]
    var activeSection: SectionKey?

    for rawLine in plan.components(separatedBy: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }

      if let heading = sectionHeading(in: line) {
        activeSection = heading.key
        if let remainder = heading.remainder {
          result[heading.key, default: []].append(remainder)
        }
        continue
      }

      guard let activeSection else { continue }
      result[activeSection, default: []].append(line)
    }

    return result
  }

  private static func sectionHeading(in rawLine: String) -> (key: SectionKey, remainder: String?)? {
    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    let strippedMarkdown = line.trimmingCharacters(
      in: CharacterSet(charactersIn: "#* ")
    )
    let separators = [":", "-"]

    for separator in separators {
      if let range = strippedMarkdown.range(of: separator) {
        let candidate = normalizedHeading(String(strippedMarkdown[..<range.lowerBound]))
        if let key = sectionKey(for: candidate) {
          let remainder = cleanedContentLine(String(strippedMarkdown[range.upperBound...]))
            .nilIfEmpty
          return (key, remainder)
        }
      }
    }

    if let key = sectionKey(for: normalizedHeading(strippedMarkdown)) {
      return (key, nil)
    }

    return nil
  }

  private static func sectionKey(for heading: String) -> SectionKey? {
    switch heading {
    case "outcome", "result":
      return .outcome
    case "why it matters", "why this matters", "why", "reason", "value":
      return .whyItMatters
    case "acceptance",
      "acceptance checks",
      "acceptance criteria",
      "checks",
      "definition of done",
      "done signal",
      "done signals",
      "done when",
      "finish line",
      "success",
      "success signal",
      "success signals",
      "success looks like",
      "verification criteria":
      return .acceptanceChecks
    default:
      return nil
    }
  }

  private static func normalizedHeading(_ text: String) -> String {
    text
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: " :.-"))
  }

  private static func firstMeaningfulLine(in lines: [String]) -> String? {
    lines
      .map(cleanedContentLine)
      .first { !$0.isEmpty }
      .map { StringUtils.boundedText($0, limit: Self.textLimit) }
  }

  private static func fallbackOutcome(in plan: String) -> String? {
    for rawLine in plan.components(separatedBy: "\n") {
      let line = cleanedContentLine(rawLine)
      guard !line.isEmpty, sectionHeading(in: line) == nil else { continue }
      return StringUtils.boundedText(line, limit: Self.textLimit)
    }
    return nil
  }

  private static func normalizedBody(_ rawPlan: String) -> String {
    rawPlan
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func cleanedContentLine(_ rawLine: String) -> String {
    StringUtils.boundedText(PlainTextListPrefix.cleanedLine(rawLine), limit: Self.textLimit)
  }

  private static func isCommandOnlyAcceptanceCheck(_ line: String) -> Bool {
    guard let command = commandCandidate(fromAcceptanceLine: line) else { return false }
    if PlanVerifyCommandPolicy.isPlaceholder(command) {
      return true
    }

    let normalized =
      command
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

    if commandOnlyVerifyPhrases.contains(normalized) {
      return true
    }

    for prefix in commandOnlyVerifyPhrases where normalized.hasPrefix("\(prefix) ") {
      let suffix = String(normalized.dropFirst(prefix.count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if suffix.rangeOfCharacter(from: shellArgumentCharacters) != nil {
        return true
      }
    }

    return false
  }

  private static func isVagueAcceptanceCheck(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.contains("<") || trimmed.contains(">") {
      return true
    }
    let key = acceptanceQualityKey(line)
    if vagueAcceptanceCheckKeys.contains(key) {
      return true
    }
    if key.hasPrefix("the planned ") && key.hasSuffix(" is implemented") {
      return true
    }
    if key.hasPrefix("the change ") && key.hasSuffix(" is implemented") {
      return true
    }
    return false
  }

  private static func acceptanceQualityKey(_ line: String) -> String {
    var key = line
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    key = key.trimmingCharacters(
      in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    )
    return key.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }

  private static func commandCandidate(fromAcceptanceLine line: String) -> String? {
    var candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let labels = [
      "verify command:",
      "verification command:",
      "test command:",
      "command:",
      "verify:",
      "verification:",
      "tests:",
      "run:",
    ]

    for label in labels {
      if candidate.lowercased().hasPrefix(label) {
        candidate = String(candidate.dropFirst(label.count))
          .trimmingCharacters(in: .whitespacesAndNewlines)
        break
      }
    }

    if candidate.lowercased().hasPrefix("run ") {
      candidate = String(candidate.dropFirst(4))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return candidate.nilIfEmpty
  }

  private static let commandOnlyVerifyPhrases: Set<String> = [
    "bun test",
    "cargo llvm-cov",
    "cargo test",
    "npm run build",
    "npm run test",
    "npm test",
    "pnpm build",
    "pnpm run build",
    "pnpm run test",
    "pnpm test",
    "pytest",
    "python -m pytest",
    "python -m unittest",
    "python3 -m pytest",
    "python3 -m unittest",
    "swift build",
    "swift test",
    "vitest",
    "vitest run",
    "xcodebuild",
    "yarn build",
    "yarn run build",
    "yarn run test",
    "yarn test",
  ]

  private static let vagueAcceptanceCheckKeys: Set<String> = [
    "all done",
    "all good",
    "all set",
    "complete",
    "completed",
    "done",
    "everything works",
    "fixed",
    "implemented",
    "implementation complete",
    "implementation is complete",
    "it is complete",
    "it is done",
    "it is implemented",
    "it works",
    "looks good",
    "planned behavior is implemented",
    "the change is complete",
    "the change is done",
    "the change works",
    "the feature works",
    "the implementation is complete",
    "the planned behavior is implemented",
    "the planned change is implemented",
    "the task is complete",
    "the work is complete",
    "works",
  ]

  private static let shellArgumentCharacters = CharacterSet(
    charactersIn: #"./\-:=|&"'`$*[]()"#
  )
}

private extension Array where Element == PlanHandoffDigest.MissingPiece {
  var requiredLabels: [String] {
    filter { $0.isRequired }.map(\.label)
  }
}

struct PlanWorkflowOverview: Equatable {
  static let defaultExcerptLimit = 220

  var completedCount: Int
  var immediate: Section
  var candidates: Section
  var strategicContext: Section

  var sections: [Section] {
    [immediate, candidates, strategicContext]
  }

  init(
    state: PlanState,
    languageProfile: RepositoryLanguageProfile? = nil,
    launchPlan: AgentExecutionLaunchPlan? = nil,
    excerptLimit: Int = Self.defaultExcerptLimit
  ) {
    completedCount = state.completed.count
    immediate = Section(
      kind: .immediate,
      title: "Immediate Work",
      label: "Current",
      systemImage: "target",
      rawBody: state.immediate?.plan ?? "",
      emptyMessage: "No immediate plan. The Product Tournament is ready for the next scoped implementation.",
      verifyCommand: state.immediate?.verify,
      verifyTimeoutLabel: state.immediate.map {
        PlanVerifyMetadata(timeoutMs: $0.verifyTimeoutMs).label
      },
      estimatedDifficulty: state.immediate?.estimatedDifficulty,
      completedCount: completedCount,
      excerptLimit: excerptLimit
    )
    candidates = Section(
      kind: .candidates,
      title: "Candidate Directions",
      label: "Candidates",
      systemImage: "point.3.connected.trianglepath.dotted",
      rawBody: state.candidatesMarkdown,
      emptyMessage: "No candidate directions yet. Plan can originate the next useful slice from the repo, drafts, feedback, or focus.",
      completedCount: completedCount,
      excerptLimit: excerptLimit
    )
    strategicContext = Section(
      kind: .strategicContext,
      title: "Strategic Context",
      label: "Context",
      systemImage: "mountain.2.fill",
      rawBody: state.strategicContextMarkdown,
      emptyMessage: "No strategic context yet. Add durable thesis, principles, constraints, risks, or non-goals when they become clear.",
      completedCount: completedCount,
      excerptLimit: excerptLimit
    )
  }

  struct Section: Identifiable, Equatable {
    var kind: Kind
    var title: String
    var label: String
    var systemImage: String
    var body: String
    var excerpt: String?
    var emptyMessage: String
    var verifyCommand: String?
    var verifyTimeoutLabel: String?
    var estimatedDifficulty: PlanNext.Difficulty?
    var completedCount: Int

    var id: Kind { kind }

    var isEmpty: Bool {
      body.isEmpty
    }

    var estimatedDifficultyLabel: String? {
      estimatedDifficulty?.rawValue.capitalized
    }

    init(
      kind: Kind,
      title: String,
      label: String,
      systemImage: String,
      rawBody: String,
      emptyMessage: String,
      verifyCommand: String? = nil,
      verifyTimeoutLabel: String? = nil,
      estimatedDifficulty: PlanNext.Difficulty? = nil,
      completedCount: Int,
      excerptLimit: Int
    ) {
      let body = PlanWorkflowOverview.normalizedMarkdownBody(rawBody)
      self.kind = kind
      self.title = title
      self.label = label
      self.systemImage = systemImage
      self.body = body
      self.excerpt = PlanWorkflowOverview.boundedExcerpt(for: body, limit: excerptLimit)
      self.emptyMessage = emptyMessage
      self.verifyCommand = verifyCommand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      self.verifyTimeoutLabel = verifyTimeoutLabel
      self.estimatedDifficulty = estimatedDifficulty
      self.completedCount = completedCount
    }
  }

  enum Kind: String, Equatable {
    case immediate
    case candidates
    case strategicContext
  }

  enum TimelineDestination: String, CaseIterable, Equatable {
    case immediate = "plan-immediate"
    case candidates = "plan-candidates"
    case strategicContext = "plan-strategic-context"

    var itemID: String {
      rawValue
    }

    var overviewKind: Kind {
      switch self {
      case .immediate:
        return .immediate
      case .candidates:
        return .candidates
      case .strategicContext:
        return .strategicContext
      }
    }
  }

  private static func normalizedMarkdownBody(_ rawBody: String) -> String {
    let normalizedNewlines =
      rawBody
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalizedNewlines.components(separatedBy: "\n")

    var normalizedLines: [String] = []
    var previousWasBlank = false

    for rawLine in lines {
      let line = collapsedHorizontalWhitespace(in: rawLine)
        .trimmingCharacters(in: .whitespaces)

      if line.isEmpty {
        if !normalizedLines.isEmpty, !previousWasBlank {
          normalizedLines.append("")
          previousWasBlank = true
        }
        continue
      }

      normalizedLines.append(line)
      previousWasBlank = false
    }

    while normalizedLines.last == "" {
      normalizedLines.removeLast()
    }

    return normalizedLines.joined(separator: "\n")
  }

  private static func boundedExcerpt(for body: String, limit: Int) -> String? {
    let denseBody =
      body
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")

    guard !denseBody.isEmpty else {
      return nil
    }

    guard limit > 0, denseBody.count > limit else {
      return denseBody
    }

    guard limit > 3 else {
      return String(denseBody.prefix(limit))
    }

    let prefixLimit = max(0, limit - 3)
    let prefix =
      denseBody
      .prefix(prefixLimit)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(prefix)..."
  }

  private static func collapsedHorizontalWhitespace(in line: String) -> String {
    var result = ""
    var previousWasSpace = false

    for character in line {
      if character == " " || character == "\t" {
        if !previousWasSpace {
          result.append(" ")
          previousWasSpace = true
        }
      } else {
        result.append(character)
        previousWasSpace = false
      }
    }

    return result
  }
}

struct PlanTournamentBrief: Equatable, Sendable {
  static let detailLimit = 260
  static let labelLimit = 90

  var status: Status
  var title: String
  var detail: String
  var primaryActionLabel: String
  var proofLabel: String
  var proofDetail: String
  var proofCommand: String?
  var handoffDigest: PlanHandoffDigest
  var routeLabel: String
  var routeDetail: String
  var chips: [Chip]

  var narrationIdentifier: String {
    [
      status.rawValue,
      title,
      detail,
      primaryActionLabel,
      proofLabel,
      proofDetail,
      proofCommand ?? "",
      handoffDigest.title,
      handoffDigest.detail,
      handoffDigest.outcome ?? "",
      handoffDigest.acceptanceChecks.joined(separator: "|"),
      routeLabel,
      routeDetail,
      chips.map { "\($0.systemImage):\($0.label)" }.joined(separator: "|"),
    ].joined(separator: "\n")
  }

  init(
    state: PlanState,
    reliabilityFeedback: PlanReliabilityFeedback,
    launchPlan: AgentExecutionLaunchPlan,
    languageProfile: RepositoryLanguageProfile,
    forgeProfile: ForgeProfile? = nil
  ) {
    let routeSummary = Self.routeSummary(for: launchPlan)
    routeLabel = routeSummary.label
    routeDetail = routeSummary.detail
    handoffDigest = PlanHandoffDigest(plan: state.immediate?.plan)
    let repairGuide = PlanHandoffRepairGuide(
      plan: state.immediate?.plan,
      verify: state.immediate?.verify,
      languageProfile: languageProfile,
      forgeProfile: forgeProfile
    )

    if let notice = reliabilityFeedback.notices.first {
      status = notice.severity == .paused ? .paused : .needsAttention
      title = notice.severity == .paused ? "Develop Is Ready" : "Tournament Needs Attention"
      detail = Self.bounded("\(notice.title): \(notice.detail)")
      primaryActionLabel = notice.actionLabel
    } else if let immediate = state.immediate {
      if repairGuide.status == .ready {
        status = .ready
        title = "Ready To Build"
        detail = Self.bounded("Next slice: \(Self.firstMeaningfulLine(in: immediate.plan))")
        primaryActionLabel = "Run Develop"
      } else {
        status = .planning
        title = "Clarify Before Building"
        detail = Self.bounded(repairGuide.detail)
        primaryActionLabel = "Run Plan"
      }
    } else if let candidate = state.actionableCandidates.first {
      status = .planning
      title = "Ready To Choose The Next Slice"
      detail = Self.bounded(
        "No immediate implementation is selected. An available candidate starts with: \(candidate.title)"
      )
      primaryActionLabel = "Run Plan"
    } else if let context = Self.firstMeaningfulLine(in: state.strategicContextMarkdown).nilIfEmpty {
      status = .planning
      title = "Ready To Turn Strategy Into Work"
      detail = Self.bounded(
        "No immediate implementation is selected. Strategic context is available: \(context)"
      )
      primaryActionLabel = "Run Plan"
    } else {
      status = .idle
      title = "Waiting For Direction"
      detail = "Add a draft or update the vision so Compass can pick the next useful slice."
      primaryActionLabel = "Add Draft"
    }

    if let immediate = state.immediate {
      let proof = PlanVerifyCommandSummary(command: immediate.verify)
      proofLabel = proof.title
      proofDetail = proof.detail
      proofCommand = proof.command
    } else {
      let proof = PlanVerifyCommandSummary(command: nil)
      proofLabel = proof.title
      proofDetail = "No verification command has been selected yet."
      proofCommand = nil
    }

    chips = Self.chips(
      state: state,
      launchPlan: launchPlan,
      languageProfile: languageProfile,
      routeSummary: routeSummary
    )
  }

  enum Status: String, Equatable, Sendable {
    case ready
    case paused
    case needsAttention
    case planning
    case idle
  }

  struct Chip: Equatable, Sendable {
    var label: String
    var systemImage: String
  }

  private struct RouteSummary {
    var label: String
    var detail: String
  }

  private static func chips(
    state: PlanState,
    launchPlan: AgentExecutionLaunchPlan,
    languageProfile: RepositoryLanguageProfile,
    routeSummary: RouteSummary
  ) -> [Chip] {
    var chips: [Chip] = [
      Chip(
        label: "\(state.completed.count) completed",
        systemImage: "checkmark.circle"
      ),
      Chip(label: routeSummary.label, systemImage: "macwindow.on.rectangle"),
    ]

    if languageProfile.primaryLanguage != .unknown {
      chips.append(
        Chip(
          label: languageProfile.primaryLanguage.displayName,
          systemImage: "curlybraces"
        )
      )
    }

    if let immediate = state.immediate {
      if let difficulty = immediate.estimatedDifficulty {
        chips.append(
          Chip(
            label: "\(difficulty.rawValue.capitalized) difficulty",
            systemImage: "gauge.with.dots.needle.bottom.50percent"
          )
        )
      }
      chips.append(
        Chip(
          label: PlanVerifyMetadata(timeoutMs: immediate.verifyTimeoutMs).label,
          systemImage: "timer"
        )
      )
    }

    return chips
  }

  private static func routeSummary(for launchPlan: AgentExecutionLaunchPlan) -> RouteSummary {
    if launchPlan.isVMRoute {
      return RouteSummary(
        label: "Private workspace",
        detail: "Develop will run inside your isolated private workspace."
      )
    }

    if let fallbackReason = launchPlan.fallbackReason {
      return RouteSummary(
        label: "This Mac",
        detail: bounded(
          "Compass is using this Mac because \(AgentExecutionLaunchPlan.userFacingFallbackReason(fallbackReason))"
        )
      )
    }

    return RouteSummary(
      label: "This Mac",
      detail: "This run will use the project folder on this Mac directly."
    )
  }

  private static func firstMeaningfulLine(in markdown: String) -> String {
    let normalized =
      markdown
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")

    for rawLine in normalized {
      let line = plainTextLine(rawLine)
      if !line.isEmpty, !isSectionHeading(line) {
        return bounded(line, limit: Self.labelLimit)
      }
    }
    return ""
  }

  private static func plainTextLine(_ rawLine: String) -> String {
    var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    while let first = line.first, "-*#0123456789. )[]".contains(first) {
      line.removeFirst()
      line = line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return StringUtils.boundedText(line, limit: Self.labelLimit)
  }

  private static func isSectionHeading(_ line: String) -> Bool {
    let normalized = line.lowercased()
      .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    return [
      "outcome",
      "why it matters",
      "acceptance checks",
      "plan",
      "implementation",
      "verify",
    ].contains(normalized)
  }

  private static func bounded(_ text: String, limit: Int = Self.detailLimit) -> String {
    StringUtils.boundedText(text, limit: limit)
  }
}

struct PlanTournamentBriefClipboardPayload: Equatable, Sendable {
  static let textLimit = 2_800

  var text: String

  init(brief: PlanTournamentBrief) {
    var sections: [String] = [
      "Compass Product Tournament Brief Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded current-state context. Do not invent files, "
        + "commands, credentials, outcomes, deadlines, or extra scope.",
      "- Use the action, proof, handoff, and runtime fields to decide the next safe step.",
      "- If the status needs attention or planning, repair the named issue before Develop.",
      "",
      "Status: \(brief.title) (\(brief.status.rawValue))",
      "Action: \(brief.primaryActionLabel)",
      "Detail: \(brief.detail)",
      "",
      "Proof:",
      "\(brief.proofLabel): \(brief.proofDetail)",
      brief.proofCommand ?? "No verification command selected.",
      "",
      "Runtime:",
      "\(brief.routeLabel): \(brief.routeDetail)",
      "",
      "Handoff:",
      "Status: \(brief.handoffDigest.title)",
      brief.handoffDigest.detail,
    ]

    if let outcome = brief.handoffDigest.outcome {
      sections.append("Outcome: \(outcome)")
    }
    if let whyItMatters = brief.handoffDigest.whyItMatters {
      sections.append("Why it matters: \(whyItMatters)")
    }
    if !brief.handoffDigest.acceptanceChecks.isEmpty {
      sections.append("Acceptance checks:")
      sections.append(contentsOf: brief.handoffDigest.acceptanceChecks.map { "- \($0)" })
    }
    if !brief.handoffDigest.missingPieces.isEmpty {
      sections.append("Missing handoff detail:")
      sections.append(contentsOf: brief.handoffDigest.missingPieces.map { "- \($0.label)" })
    }
    if !brief.chips.isEmpty {
      sections.append("")
      sections.append("Context:")
      sections.append(contentsOf: brief.chips.map { "- \($0.label)" })
    }

    text = PlanTournamentBriefClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private enum PlanTournamentBriefClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct PlanTournamentBriefNarration: Equatable, Sendable {
  var briefIdentifier: String
  var text: String
}

enum PlanTournamentBriefNarrator {
  static let maxCharacters = 320

  static func narrate(brief: PlanTournamentBrief) async -> PlanTournamentBriefNarration? {
    guard FoundationModelsAvailability.isAvailable else { return nil }

    if #available(macOS 26.0, *) {
      guard let generated = await FoundationModelsAvailability._streamText(
        prompt: prompt(for: brief)
      ) else {
        return nil
      }
      let text = sanitized(generated)
      guard !text.isEmpty else { return nil }
      return PlanTournamentBriefNarration(
        briefIdentifier: brief.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for brief: PlanTournamentBrief) -> String {
    """
    You write a calm plain-language status brief for a non-engineer using Compass.
    Use only the facts below. Do not invent files, commands, outcomes, deadlines, or
    promises.
    Return one paragraph under 55 words. No Markdown.

    Status: \(brief.status.rawValue)
    Title: \(brief.title)
    Current detail: \(brief.detail)
    Suggested action: \(brief.primaryActionLabel)
    Verification: \(brief.proofLabel) - \(brief.proofDetail)
    Command: \(brief.proofCommand ?? "none")
    Handoff: \(brief.handoffDigest.title) - \(brief.handoffDigest.detail)
    Runtime: \(brief.routeLabel) - \(brief.routeDetail)
    Context: \(brief.chips.map(\.label).joined(separator: ", "))
    """
  }

  private static func sanitized(_ text: String) -> String {
    let normalized = StringUtils.boundedText(text, limit: maxCharacters)
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

extension PlanWorkflowOverview.Kind {
  var timelineDestination: PlanWorkflowOverview.TimelineDestination {
    switch self {
    case .immediate:
      return .immediate
    case .candidates:
      return .candidates
    case .strategicContext:
      return .strategicContext
    }
  }

  var timelineItemID: String {
    timelineDestination.itemID
  }

  init?(timelineItemID: String) {
    guard let destination = PlanWorkflowOverview.TimelineDestination(rawValue: timelineItemID)
    else {
      return nil
    }

    self = destination.overviewKind
  }
}

extension PlanWorkflowOverview.Section {
  var timelineDestination: PlanWorkflowOverview.TimelineDestination {
    kind.timelineDestination
  }

  var timelineItemID: String {
    kind.timelineItemID
  }
}

extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

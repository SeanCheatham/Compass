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
      title = "Runs Swift tests"
      detail = Self.testDetail(
        framework: "Swift",
        filter: Self.argumentValue(after: "--filter", in: normalized)
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
    } else if lowercased.contains("go test") {
      title = "Runs Go tests"
      detail = lowercased.contains("./...")
        ? "Compass will run Go tests across every package in the module."
        : "Compass will run the selected Go tests."
      systemImage = "checkmark.seal"
    } else if Self.containsAny(lowercased, ["vitest", "npm test", "pnpm test", "yarn test"]) {
      title = "Runs JavaScript tests"
      detail = "Compass will run the project's JavaScript or TypeScript test command."
      systemImage = "checkmark.seal"
    } else if Self.containsAny(lowercased, ["npm run build", "pnpm build", "yarn build"]) {
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

  private static func testDetail(framework: String, filter: String?) -> String {
    if let filter, !filter.isEmpty {
      return "Compass will run \(framework) tests focused on \(filter)."
    }
    return "Compass will run the \(framework) test suite."
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
      missingPieces = [.outcome, .acceptanceChecks]
      return
    }

    let sections = Self.sections(in: plan)
    outcome = Self.firstMeaningfulLine(in: sections[.outcome] ?? [])
      ?? Self.fallbackOutcome(in: plan)
    whyItMatters = Self.firstMeaningfulLine(in: sections[.whyItMatters] ?? [])
    acceptanceChecks = (sections[.acceptanceChecks] ?? [])
      .map(Self.cleanedContentLine)
      .filter { !$0.isEmpty }
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
    case "why it matters", "why this matters", "why":
      return .whyItMatters
    case "acceptance checks", "acceptance criteria", "done when", "definition of done":
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
    var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    while let first = line.first, "-*0123456789. )[]".contains(first) {
      line.removeFirst()
      line = line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return StringUtils.boundedText(line, limit: Self.textLimit)
  }
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
  var midTerm: Section
  var longTerm: Section

  var sections: [Section] {
    [immediate, midTerm, longTerm]
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
      emptyMessage: "No immediate plan. The factory is ready for the next scoped implementation.",
      verifyCommand: state.immediate?.verify,
      verifyTimeoutLabel: state.immediate.map {
        PlanVerifyMetadata(timeoutMs: $0.verifyTimeoutMs).label
      },
      estimatedDifficulty: state.immediate?.estimatedDifficulty,
      completedCount: completedCount,
      excerptLimit: excerptLimit
    )
    midTerm = Section(
      kind: .midTerm,
      title: "Queued Direction",
      label: "Next Up",
      systemImage: "point.3.connected.trianglepath.dotted",
      rawBody: state.midTerm,
      emptyMessage: "No mid-term queue. Future planning has no staged direction yet.",
      completedCount: completedCount,
      excerptLimit: excerptLimit
    )
    longTerm = Section(
      kind: .longTerm,
      title: "Strategic Arc",
      label: "Destination",
      systemImage: "mountain.2.fill",
      rawBody: state.longTerm,
      emptyMessage: "No long-term arc. Add the larger product direction when it becomes clear.",
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
    case midTerm
    case longTerm
  }

  enum TimelineDestination: String, CaseIterable, Equatable {
    case immediate = "plan-immediate"
    case midTerm = "plan-mid-term"
    case longTerm = "plan-long-term"

    var itemID: String {
      rawValue
    }

    var overviewKind: Kind {
      switch self {
      case .immediate:
        return .immediate
      case .midTerm:
        return .midTerm
      case .longTerm:
        return .longTerm
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

struct PlanFactoryBrief: Equatable, Sendable {
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
    languageProfile: RepositoryLanguageProfile
  ) {
    let routeSummary = Self.routeSummary(for: launchPlan)
    routeLabel = launchPlan.effectiveRouteTitle
    routeDetail = routeSummary.detail
    handoffDigest = PlanHandoffDigest(plan: state.immediate?.plan)

    if let notice = reliabilityFeedback.notices.first {
      status = notice.severity == .paused ? .paused : .needsAttention
      title = notice.severity == .paused ? "Develop Is Ready" : "Factory Needs Attention"
      detail = Self.bounded("\(notice.title): \(notice.detail)")
      primaryActionLabel = notice.actionLabel
    } else if let immediate = state.immediate {
      if handoffDigest.status == .ready {
        status = .ready
        title = "Ready To Build"
        detail = Self.bounded("Next slice: \(Self.firstMeaningfulLine(in: immediate.plan))")
        primaryActionLabel = "Run Develop"
      } else {
        status = .planning
        title = "Clarify Before Building"
        detail = Self.bounded(handoffDigest.detail)
        primaryActionLabel = "Run Plan"
      }
    } else if let queued = Self.firstMeaningfulLine(in: state.midTerm).nilIfEmpty {
      status = .planning
      title = "Ready To Choose The Next Slice"
      detail = Self.bounded(
        "No immediate implementation is selected. The queue starts with: \(queued)"
      )
      primaryActionLabel = "Run Plan"
    } else if let arc = Self.firstMeaningfulLine(in: state.longTerm).nilIfEmpty {
      status = .planning
      title = "Ready To Turn Strategy Into Work"
      detail = Self.bounded(
        "No immediate implementation is selected. The strategic arc is: \(arc)"
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
        label: "Shared VM",
        detail: "Develop will run inside the Shared VM workspace."
      )
    }

    if let fallbackReason = launchPlan.fallbackReason {
      return RouteSummary(
        label: "Native macOS fallback",
        detail: bounded("Shared VM is not the active route: \(fallbackReason)")
      )
    }

    return RouteSummary(
      label: "Native macOS",
      detail: "This run will use the host repository directly."
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

struct PlanFactoryBriefNarration: Equatable, Sendable {
  var briefIdentifier: String
  var text: String
}

enum PlanFactoryBriefNarrator {
  static let maxCharacters = 320

  static func narrate(brief: PlanFactoryBrief) async -> PlanFactoryBriefNarration? {
    guard FoundationModelsAvailability.isAvailable else { return nil }

    if #available(macOS 26.0, *) {
      guard let generated = await FoundationModelsAvailability._streamText(
        prompt: prompt(for: brief)
      ) else {
        return nil
      }
      let text = sanitized(generated)
      guard !text.isEmpty else { return nil }
      return PlanFactoryBriefNarration(
        briefIdentifier: brief.narrationIdentifier,
        text: text
      )
    }

    return nil
  }

  static func prompt(for brief: PlanFactoryBrief) -> String {
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
    case .midTerm:
      return .midTerm
    case .longTerm:
      return .longTerm
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

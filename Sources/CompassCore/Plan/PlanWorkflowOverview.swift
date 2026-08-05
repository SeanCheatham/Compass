import Foundation

public struct PlanVerifyCommandSummary: Equatable, Sendable {
  public static let commandLimit = 180
  public static let detailLimit = 220

  public var command: String?
  public var title: String
  public var detail: String
  public var systemImage: String

  public init(command rawCommand: String?) {
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
      detail =
        "Compass will ask Xcode to compile the selected scheme and fail if it does not build."
      systemImage = "hammer"
    } else if lowercased.contains("swift build") {
      title = "Builds the Swift package"
      if let target = Self.argumentValue(after: "--target", in: normalized) {
        detail = "Compass will compile the \(target) target and fail on build errors."
      } else {
        detail = "Compass will compile the Swift package and fail on build errors."
      }
      systemImage = "hammer"
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
        detail =
          collectsCoverage
          ? "Compass will run pytest with Python coverage enabled."
          : "Compass will run the Python test suite with pytest."
      } else {
        detail = "Compass will run the Python unittest suite."
      }
      systemImage = "checkmark.seal"
    } else if Self.containsAny(
      lowercased,
      [
        "cargo test",
        "cargo llvm-cov",
      ])
    {
      let collectsCoverage = lowercased.contains("llvm-cov")
      title = collectsCoverage ? "Runs Rust coverage" : "Runs Rust tests"
      detail =
        collectsCoverage
        ? "Compass will run the Rust workspace tests with llvm-cov coverage enabled."
        : "Compass will run the Rust workspace test suite with cargo test."
      systemImage = "checkmark.seal"
    } else if Self.containsAny(
      lowercased,
      [
        "cargo build",
        "cargo check",
        "cargo fmt",
      ])
    {
      title = "Builds the Rust workspace"
      detail = "Compass will compile or format-check the Rust workspace and fail on errors."
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

public struct PlanHandoffDigest: Equatable, Sendable {
  public static let textLimit = 180
  public static let checkLimit = 3

  public var status: Status
  public var title: String
  public var detail: String
  public var systemImage: String
  public var outcome: String?
  public var whyItMatters: String?
  public var acceptanceChecks: [String]
  public var commandOnlyAcceptanceChecks: [String]
  public var vagueAcceptanceChecks: [String]
  public var missingPieces: [MissingPiece]

  public init(plan rawPlan: String?) {
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
    outcome =
      Self.firstMeaningfulLine(in: sections[.outcome] ?? [])
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
      detail =
        acceptanceChecks.count == 1
        ? "Outcome and one acceptance check give Develop a clear finish line."
        : "Outcome and \(acceptanceChecks.count) acceptance checks give Develop a clear finish line."
      systemImage = "checklist.checked"
    } else {
      status = .needsDetail
      title = "Handoff needs detail"
      detail =
        "Missing \(missing.requiredLabels.joined(separator: " and ")) before Develop has a clear finish line."
      systemImage = "list.bullet.clipboard"
    }
  }

  public enum Status: String, Equatable, Sendable {
    case ready
    case needsDetail
    case missingPlan
  }

  public enum MissingPiece: String, Equatable, Sendable {
    case outcome
    case whyItMatters
    case acceptanceChecks

    public var label: String {
      switch self {
      case .outcome:
        return "Outcome"
      case .whyItMatters:
        return "Why it matters"
      case .acceptanceChecks:
        return "Acceptance checks"
      }
    }

    public var isRequired: Bool {
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
    var key =
      line
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
    "npm run build",
    "npm run test",
    "npm test",
    "cargo build",
    "cargo check",
    "cargo clippy",
    "cargo fmt",
    "cargo llvm-cov",
    "cargo test",
    "pytest",
    "python -m pytest",
    "python -m unittest",
    "python3 -m pytest",
    "python3 -m unittest",
    "swift build",
    "swift test",
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

extension Array where Element == PlanHandoffDigest.MissingPiece {
  fileprivate var requiredLabels: [String] {
    filter { $0.isRequired }.map(\.label)
  }
}

extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

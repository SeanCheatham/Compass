import Foundation

struct MarketBacktestCase: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var name: String
  var era: String
  var category: String
  var initialPain: String
  var initialContender: String
  var knownOutcome: KnownProductOutcome
  var outcomeSummary: String
  var hiddenOutcomeNotes: String

  init(
    id: String,
    name: String,
    era: String,
    category: String,
    initialPain: String,
    initialContender: String,
    knownOutcome: KnownProductOutcome,
    outcomeSummary: String,
    hiddenOutcomeNotes: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "market-backtest-case")
    self.name = ProductTournamentModelText.cleanedText(name, fallback: "Market backtest", limit: 180)
    self.era = ProductTournamentModelText.cleanedText(era, fallback: "unknown era", limit: 80)
    self.category = ProductTournamentModelText.cleanedText(category, fallback: "product", limit: 120)
    self.initialPain = ProductTournamentModelText.cleanedText(
      initialPain,
      fallback: "Unresolved market pain.",
      limit: 800
    )
    self.initialContender = ProductTournamentModelText.cleanedText(
      initialContender,
      fallback: "Initial product contender.",
      limit: 800
    )
    self.knownOutcome = knownOutcome
    self.outcomeSummary = ProductTournamentModelText.cleanedText(
      outcomeSummary,
      fallback: "Known outcome held out for calibration.",
      limit: 800
    )
    self.hiddenOutcomeNotes = ProductTournamentModelText.cleanedText(
      hiddenOutcomeNotes,
      fallback: "Hidden calibration notes.",
      limit: 800
    )
  }
}

enum KnownProductOutcome: String, Codable, CaseIterable, Equatable, Sendable {
  case breakout
  case durableNiche = "durable_niche"
  case pivoted
  case failed
  case featureAbsorbed = "feature_absorbed"

  var rank: Int {
    switch self {
    case .breakout: return 4
    case .durableNiche: return 3
    case .pivoted: return 2
    case .featureAbsorbed: return 1
    case .failed: return 0
    }
  }
}

struct MarketBacktestRun: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var caseID: String
  var predictedOutcome: KnownProductOutcome
  var actualOutcome: KnownProductOutcome
  var confidence: Int
  var strongestReasons: [String]
  var missedRisks: [String]
  var overconfidenceFlags: [String]
  var compilerInputSummary: String
  var outcomeMatched: Bool
  var calibrationDelta: Int
  var createdAt: Double

  init(
    id: String,
    caseID: String,
    predictedOutcome: KnownProductOutcome,
    actualOutcome: KnownProductOutcome,
    confidence: Int,
    strongestReasons: [String],
    missedRisks: [String],
    overconfidenceFlags: [String] = [],
    compilerInputSummary: String,
    createdAt: Double
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "market-backtest-run")
    self.caseID = ProductTournamentModelText.identifier(caseID, fallback: "market-backtest-case")
    self.predictedOutcome = predictedOutcome
    self.actualOutcome = actualOutcome
    self.confidence = min(5, max(1, confidence))
    self.strongestReasons = ProductTournamentModelText.cleanedList(strongestReasons, limit: 260)
    self.missedRisks = ProductTournamentModelText.cleanedList(missedRisks, limit: 260)
    self.overconfidenceFlags = ProductTournamentModelText.cleanedList(
      overconfidenceFlags,
      limit: 260
    )
    self.compilerInputSummary = ProductTournamentModelText.cleanedText(
      compilerInputSummary,
      fallback: "Backtest compiler input.",
      limit: 1_200
    )
    self.outcomeMatched = predictedOutcome == actualOutcome
    self.calibrationDelta = abs(predictedOutcome.rank - actualOutcome.rank)
    self.createdAt = createdAt
  }

  var digestLine: String {
    let risks = missedRisks.isEmpty ? "none" : missedRisks.prefix(3).joined(separator: ", ")
    return
      "\(caseID): predicted \(predictedOutcome.rawValue), actual \(actualOutcome.rawValue), confidence \(confidence)/5, delta \(calibrationDelta), missed \(risks)"
  }
}

struct MarketCalibrationAggregate: Codable, Equatable, Sendable {
  static let empty = MarketCalibrationAggregate(runs: [])

  var runCount: Int
  var correctCount: Int
  var accuracyPercent: Int
  var overconfidenceCount: Int
  var overconfidenceRatePercent: Int
  var mostCommonMissedMarketForce: String?
  var bestPredictiveSignal: String?
  var warning: String?

  init(runs: [MarketBacktestRun]) {
    runCount = runs.count
    correctCount = runs.filter(\.outcomeMatched).count
    accuracyPercent = Self.percent(correctCount, of: runCount)
    let overconfident = runs.filter { !$0.outcomeMatched && $0.confidence >= 4 }
    overconfidenceCount = overconfident.count
    overconfidenceRatePercent = Self.percent(overconfidenceCount, of: runCount)
    mostCommonMissedMarketForce = Self.mostCommon(
      runs.flatMap(\.missedRisks).map(Self.normalized)
    )
    bestPredictiveSignal = Self.mostCommon(
      runs.filter(\.outcomeMatched)
        .flatMap(\.strongestReasons)
        .map(Self.normalized)
    )
    if let missed = mostCommonMissedMarketForce, overconfidenceCount > 0 {
      warning =
        "Synthetic market has historically overestimated \(missed) in comparable backtests."
    } else if overconfidenceCount > 0 {
      warning =
        "Synthetic market has produced overconfident misses in comparable backtests."
    } else {
      warning = nil
    }
  }

  private static func percent(_ value: Int, of total: Int) -> Int {
    guard total > 0 else { return 0 }
    return Int((Double(value) / Double(total) * 100).rounded())
  }

  private static func mostCommon(_ values: [String]) -> String? {
    Dictionary(grouping: values.filter { !$0.isEmpty }, by: { $0 })
      .map { value, group in (value: value, count: group.count) }
      .sorted { lhs, rhs in
        if lhs.count == rhs.count { return lhs.value < rhs.value }
        return lhs.count > rhs.count
      }
      .first?
      .value
  }

  private static func normalized(_ value: String) -> String {
    value
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }
}

struct MarketBacktestRunner {
  var now: () -> Date

  init(now: @escaping () -> Date = Date.init) {
    self.now = now
  }

  func run(_ backtestCase: MarketBacktestCase) -> MarketBacktestRun {
    let prediction = prediction(for: backtestCase)
    let input = compilerInputSummary(for: backtestCase)
    let delta = abs(prediction.outcome.rank - backtestCase.knownOutcome.rank)
    let missedRisks =
      prediction.outcome == backtestCase.knownOutcome
      ? []
      : prediction.missedRisks + missedRisk(for: backtestCase.knownOutcome)
    let flags =
      delta > 0 && prediction.confidence >= 4
      ? ["overconfident \(prediction.outcome.rawValue) vs \(backtestCase.knownOutcome.rawValue)"]
      : []
    return MarketBacktestRun(
      id: "market-backtest-\(backtestCase.id)-\(Int(now().timeIntervalSince1970))",
      caseID: backtestCase.id,
      predictedOutcome: prediction.outcome,
      actualOutcome: backtestCase.knownOutcome,
      confidence: prediction.confidence,
      strongestReasons: prediction.reasons,
      missedRisks: missedRisks,
      overconfidenceFlags: flags,
      compilerInputSummary: input,
      createdAt: now().timeIntervalSince1970
    )
  }

  func run(_ cases: [MarketBacktestCase]) -> [MarketBacktestRun] {
    cases.map(run)
  }

  func compilerInputSummary(for backtestCase: MarketBacktestCase) -> String {
    [
      "Backtest case \(backtestCase.name) (\(backtestCase.era))",
      "Category: \(backtestCase.category)",
      "Initial pain: \(backtestCase.initialPain)",
      "Initial contender: \(backtestCase.initialContender)",
    ].joined(separator: "\n")
  }

  private func prediction(for backtestCase: MarketBacktestCase)
    -> (outcome: KnownProductOutcome, confidence: Int, reasons: [String], missedRisks: [String])
  {
    let text =
      "\(backtestCase.name) \(backtestCase.category) \(backtestCase.initialPain) \(backtestCase.initialContender)"
      .lowercased()
    if text.contains("meeting summarizer") || text.contains("generic") || text.contains("crowded") {
      return (
        .failed,
        4,
        ["weak differentiation", "crowded acquisition channel"],
        ["incumbent bundling"]
      )
    }
    if text.contains("wiki") || text.contains("search assistant") {
      return (
        .featureAbsorbed,
        4,
        ["incumbent gravity", "feature-level workflow"],
        ["distribution channel"]
      )
    }
    if text.contains("ci") || text.contains("flake") || text.contains("developer") {
      return (
        .durableNiche,
        4,
        ["urgent budget owner", "recurring operational pain"],
        ["platform expansion ceiling"]
      )
    }
    if text.contains("habit") || text.contains("coach") || text.contains("consumer") {
      return (
        .failed,
        4,
        ["retention risk", "weak budget owner"],
        ["novelty decay"]
      )
    }
    if text.contains("spreadsheet") || text.contains("weekly reporting") {
      return (
        .durableNiche,
        3,
        ["recurring workflow", "clear operator pain"],
        ["buyer urgency"]
      )
    }
    return (.pivoted, 2, ["uncertain market pressure"], ["unclear urgency"])
  }

  private func missedRisk(for outcome: KnownProductOutcome) -> [String] {
    switch outcome {
    case .breakout: return ["breakout pull"]
    case .durableNiche: return ["niche durability"]
    case .pivoted: return ["positioning drift"]
    case .failed: return ["urgency"]
    case .featureAbsorbed: return ["incumbent gravity"]
    }
  }
}

enum MarketBacktestFixtures {
  static let compactCases: [MarketBacktestCase] = [
    MarketBacktestCase(
      id: "team-wiki-search-assistant",
      name: "team wiki search assistant",
      era: "modern saas",
      category: "knowledge management",
      initialPain: "Teams cannot find decisions buried in stale wiki pages.",
      initialContender: "AI search assistant that answers from internal documentation.",
      knownOutcome: .featureAbsorbed,
      outcomeSummary: "The capability was absorbed by incumbent wiki and suite search products.",
      hiddenOutcomeNotes: "Incumbent bundling mattered more than standalone workflow pull."
    ),
    MarketBacktestCase(
      id: "spreadsheet-weekly-reporting",
      name: "spreadsheet automation for weekly reporting",
      era: "modern saas",
      category: "operations",
      initialPain: "Managers spend Friday collecting spreadsheet updates for weekly reporting.",
      initialContender: "Workflow automation that compiles updates and exceptions.",
      knownOutcome: .durableNiche,
      outcomeSummary: "The product found a durable niche in teams with recurring reporting rituals.",
      hiddenOutcomeNotes: "The market stayed narrower than a broad collaboration platform."
    ),
    MarketBacktestCase(
      id: "generic-ai-meeting-summarizer",
      name: "generic AI meeting summarizer",
      era: "modern ai",
      category: "productivity",
      initialPain: "People miss action items from meetings.",
      initialContender: "Generic meeting summarizer with action items and searchable notes.",
      knownOutcome: .failed,
      outcomeSummary: "Weak differentiation and crowded distribution made the product fade.",
      hiddenOutcomeNotes: "Incumbents and calendar suites bundled enough of the feature."
    ),
    MarketBacktestCase(
      id: "developer-ci-flake-triage",
      name: "developer CI flake triage",
      era: "modern devtools",
      category: "developer tools",
      initialPain: "Engineering teams lose release time to flaky CI failures.",
      initialContender: "Triage assistant that clusters flaky tests and suggests owners.",
      knownOutcome: .durableNiche,
      outcomeSummary: "Urgent developer pain supported a durable niche with budget potential.",
      hiddenOutcomeNotes: "The ceiling was narrower than a breakout platform."
    ),
    MarketBacktestCase(
      id: "consumer-ai-habit-coach",
      name: "consumer habit tracker with AI coach",
      era: "modern consumer ai",
      category: "consumer wellness",
      initialPain: "Consumers want help sticking to goals after the first week.",
      initialContender: "Habit tracker with an AI coach that suggests daily routines.",
      knownOutcome: .failed,
      outcomeSummary: "Retention decayed after novelty and no strong budget owner emerged.",
      hiddenOutcomeNotes: "Second-use and renewal pressure broke the story."
    ),
  ]
}

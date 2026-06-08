import Foundation

struct SyntheticCohort: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var marketID: String
  var contenderID: String
  var name: String
  var actorIDs: [String]
  var adoptionTimelineID: String
  var sizeLabel: String
  var lifecycleScenarioIDs: [String]
  var status: SyntheticCohortStatus

  init(
    id: String,
    marketID: String,
    contenderID: String,
    name: String,
    actorIDs: [String],
    adoptionTimelineID: String,
    sizeLabel: String,
    lifecycleScenarioIDs: [String],
    status: SyntheticCohortStatus = .draft
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "synthetic-cohort")
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.contenderID = ProductTournamentModelText.identifier(contenderID, fallback: "contender")
    self.name = ProductTournamentModelText.cleanedText(
      name,
      fallback: "Synthetic lifecycle cohort",
      limit: 180
    )
    self.actorIDs = ProductTournamentModelText.cleanedList(actorIDs, limit: 120)
    self.adoptionTimelineID = ProductTournamentModelText.identifier(
      adoptionTimelineID,
      fallback: "adoption-timeline"
    )
    self.sizeLabel = ProductTournamentModelText.cleanedText(
      sizeLabel,
      fallback: "Small synthetic cohort",
      limit: 120
    )
    self.lifecycleScenarioIDs = ProductTournamentModelText.cleanedList(
      lifecycleScenarioIDs,
      limit: 140
    )
    self.status = status
  }
}

enum SyntheticCohortStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case draft
  case running
  case completed
  case needsRevision = "needs_revision"
  case failed
}

struct LifecycleScenario: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var cohortID: String
  var stageID: String
  var title: String
  var dayOffset: Int
  var trigger: String
  var task: String
  var passSignal: String
  var failSignal: String

  init(
    id: String,
    cohortID: String,
    stageID: String,
    title: String,
    dayOffset: Int,
    trigger: String,
    task: String,
    passSignal: String,
    failSignal: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "lifecycle-scenario")
    self.cohortID = ProductTournamentModelText.identifier(cohortID, fallback: "synthetic-cohort")
    self.stageID = ProductTournamentModelText.identifier(stageID, fallback: "adoption-stage")
    self.title = ProductTournamentModelText.cleanedText(
      title,
      fallback: "Lifecycle scenario",
      limit: 180
    )
    self.dayOffset = dayOffset
    self.trigger = ProductTournamentModelText.cleanedText(
      trigger,
      fallback: "Lifecycle stage trigger",
      limit: 400
    )
    self.task = ProductTournamentModelText.cleanedText(
      task,
      fallback: "Evaluate whether the product survives this lifecycle stage.",
      limit: 900
    )
    self.passSignal = ProductTournamentModelText.cleanedText(
      passSignal,
      fallback: "The product creates durable market pull.",
      limit: 500
    )
    self.failSignal = ProductTournamentModelText.cleanedText(
      failSignal,
      fallback: "The market falls back to the current alternative.",
      limit: 500
    )
  }
}

struct LifecycleRunRecord: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var cohortID: String
  var scenarioID: String
  var marketID: String
  var contenderID: String
  var actorID: String
  var stageID: String
  var outcome: LifecycleOutcome
  var scores: LifecycleScores
  var churnReason: String?
  var retainedReason: String?
  var objections: [String]
  var createdAt: Double

  init(
    id: String,
    cohortID: String,
    scenarioID: String,
    marketID: String,
    contenderID: String,
    actorID: String,
    stageID: String,
    outcome: LifecycleOutcome,
    scores: LifecycleScores,
    churnReason: String? = nil,
    retainedReason: String? = nil,
    objections: [String] = [],
    createdAt: Double
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "lifecycle-run")
    self.cohortID = ProductTournamentModelText.identifier(cohortID, fallback: "synthetic-cohort")
    self.scenarioID = ProductTournamentModelText.identifier(
      scenarioID,
      fallback: "lifecycle-scenario"
    )
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.contenderID = ProductTournamentModelText.identifier(contenderID, fallback: "contender")
    self.actorID = ProductTournamentModelText.identifier(actorID, fallback: "actor")
    self.stageID = ProductTournamentModelText.identifier(stageID, fallback: "adoption-stage")
    self.outcome = outcome
    self.scores = scores
    self.churnReason = ProductTournamentModelText.optionalCleanedText(churnReason, limit: 500)
    self.retainedReason = ProductTournamentModelText.optionalCleanedText(retainedReason, limit: 500)
    self.objections = ProductTournamentModelText.cleanedList(objections, limit: 300)
    self.createdAt = createdAt
  }

  var summaryRecord: LifecycleRunSummary {
    LifecycleRunSummary(record: self)
  }
}

enum LifecycleOutcome: String, Codable, CaseIterable, Equatable, Sendable {
  case activated
  case retained
  case shared
  case expanded
  case paid
  case renewed
  case stalled
  case churned
}

struct LifecycleScores: Codable, Equatable, Sendable {
  var activation: Int
  var repeatedUse: Int
  var habitFit: Int
  var collaborationPull: Int
  var paymentReadiness: Int
  var renewalReadiness: Int
  var churnRisk: Int

  init(
    activation: Int,
    repeatedUse: Int,
    habitFit: Int,
    collaborationPull: Int,
    paymentReadiness: Int,
    renewalReadiness: Int,
    churnRisk: Int
  ) {
    self.activation = Self.clamped(activation)
    self.repeatedUse = Self.clamped(repeatedUse)
    self.habitFit = Self.clamped(habitFit)
    self.collaborationPull = Self.clamped(collaborationPull)
    self.paymentReadiness = Self.clamped(paymentReadiness)
    self.renewalReadiness = Self.clamped(renewalReadiness)
    self.churnRisk = Self.clamped(churnRisk)
  }

  private static func clamped(_ value: Int) -> Int {
    min(5, max(0, value))
  }
}

struct LifecycleRunSummary: Codable, Equatable, Identifiable, Sendable {
  var id: String { runID }
  var runID: String
  var cohortID: String
  var scenarioID: String
  var marketID: String
  var contenderID: String
  var actorID: String
  var stageID: String
  var outcome: LifecycleOutcome
  var scores: LifecycleScores
  var churnReason: String?
  var retainedReason: String?
  var strongestObjection: String
  var createdAt: Double

  init(record: LifecycleRunRecord) {
    runID = record.id
    cohortID = record.cohortID
    scenarioID = record.scenarioID
    marketID = record.marketID
    contenderID = record.contenderID
    actorID = record.actorID
    stageID = record.stageID
    outcome = record.outcome
    scores = record.scores
    churnReason = record.churnReason
    retainedReason = record.retainedReason
    strongestObjection = record.objections.first ?? record.churnReason ?? ""
    createdAt = record.createdAt
  }

  var isRepeatedUseProof: Bool {
    outcome == .retained || outcome == .shared || outcome == .expanded || outcome == .renewed
  }

  var isBudgetOrRenewalProof: Bool {
    outcome == .paid || outcome == .renewed
  }

  var digestLine: String {
    let reason = retainedReason ?? churnReason ?? strongestObjection
    return
      "lifecycle \(runID); contender \(contenderID); stage \(stageID); outcome \(outcome.rawValue); repeat \(scores.repeatedUse)/5; payment \(scores.paymentReadiness)/5; churn \(scores.churnRisk)/5; reason \(reason)"
  }
}

struct LifecycleProofDebt: Codable, Equatable, Sendable {
  var contenderID: String
  var activationCount: Int
  var retainedCount: Int
  var churnedCount: Int
  var repeatedUseProofCount: Int
  var renewalProofCount: Int
  var paymentProofCount: Int
  var unresolvedChurnReasons: [String]

  init(contenderID: String, summaries: [LifecycleRunSummary]) {
    self.contenderID = contenderID
    activationCount = summaries.filter { $0.outcome == .activated }.count
    retainedCount = summaries.filter { $0.isRepeatedUseProof }.count
    churnedCount = summaries.filter { $0.outcome == .churned }.count
    repeatedUseProofCount = summaries.filter(\.isRepeatedUseProof).count
    renewalProofCount = summaries.filter { $0.outcome == .renewed }.count
    paymentProofCount = summaries.filter { $0.outcome == .paid || $0.outcome == .renewed }.count
    unresolvedChurnReasons = ProductTournamentModelText.cleanedList(
      summaries.compactMap(\.churnReason),
      limit: 300
    )
  }

  var missingActivationProof: Bool { activationCount == 0 }
  var missingSecondUseProof: Bool { repeatedUseProofCount == 0 }
  var missingBudgetMomentProof: Bool { paymentProofCount == 0 }
  var hasUnresolvedChurn: Bool { !unresolvedChurnReasons.isEmpty }

  var summary: String {
    var parts: [String] = []
    if missingActivationProof { parts.append("activation") }
    if missingSecondUseProof { parts.append("second_use") }
    if missingBudgetMomentProof { parts.append("budget_or_renewal") }
    if hasUnresolvedChurn { parts.append("churn_reason") }
    return parts.isEmpty ? "clear" : parts.joined(separator: ", ")
  }

  var nextMove: String {
    if hasUnresolvedChurn {
      return "Resolve churn reason: \(unresolvedChurnReasons[0])"
    }
    if missingSecondUseProof {
      return "Run second-use proof before selecting a winner."
    }
    if missingBudgetMomentProof {
      return "Run budget or renewal proof before selecting a winner."
    }
    if missingActivationProof {
      return "Run activation proof before lifecycle claims advance."
    }
    return "Lifecycle proof is strong enough for Round 3 retention gates."
  }
}

enum SyntheticCohortBuilderError: LocalizedError, Equatable {
  case missingContender(String)
  case missingMarket(String)
  case missingTimeline(String)

  var errorDescription: String? {
    switch self {
    case .missingContender(let id): return "No tournament contender exists for \(id)."
    case .missingMarket(let id): return "No synthetic market exists for \(id)."
    case .missingTimeline(let id): return "No adoption timeline exists for \(id)."
    }
  }
}

struct SyntheticCohortBuildResult: Equatable, Sendable {
  var cohort: SyntheticCohort
  var scenarios: [LifecycleScenario]
}

enum SyntheticCohortBuilder {
  static func build(
    contenderID: String,
    in config: ProductTournamentConfig
  ) throws -> SyntheticCohortBuildResult {
    guard let contender = config.tournamentContenders.first(where: { $0.id == contenderID }) else {
      throw SyntheticCohortBuilderError.missingContender(contenderID)
    }
    guard let market = market(for: contender, in: config) else {
      throw SyntheticCohortBuilderError.missingMarket(contenderID)
    }
    guard let timeline = market.adoptionTimelines.first else {
      throw SyntheticCohortBuilderError.missingTimeline(market.id)
    }
    let cohortID = ProductTournamentModelText.identifier(
      "\(contender.id)-lifecycle-cohort",
      fallback: "synthetic-cohort"
    )
    let actorIDs = actorIDs(for: contender, market: market)
    let scenarios = timeline.stages.map { stage in
      scenario(
        cohortID: cohortID,
        stage: stage,
        contender: contender,
        market: market
      )
    }
    return SyntheticCohortBuildResult(
      cohort: SyntheticCohort(
        id: cohortID,
        marketID: market.id,
        contenderID: contender.id,
        name: "\(contender.title) lifecycle cohort",
        actorIDs: actorIDs,
        adoptionTimelineID: timeline.id,
        sizeLabel: "Synthetic cohort of \(max(1, actorIDs.count)) market actor(s)",
        lifecycleScenarioIDs: scenarios.map(\.id),
        status: .draft
      ),
      scenarios: scenarios
    )
  }

  private static func market(
    for contender: ProductTournamentContender,
    in config: ProductTournamentConfig
  ) -> ProductMarket? {
    if let tournament = config.tournaments.first(where: { $0.id == contender.tournamentID }) {
      return config.markets.first(where: { $0.painID == tournament.painID }) ?? config.markets.first
    }
    return config.markets.first
  }

  private static func actorIDs(
    for contender: ProductTournamentContender,
    market: ProductMarket
  ) -> [String] {
    let matched = market.actors.filter { actor in
      actor.segmentID.map(contender.targetSegmentIDs.contains) == true
        || actor.role == .economicBuyer
        || actor.role == .managerSponsor
    }.map(\.id)
    return matched.isEmpty ? market.actors.map(\.id) : matched
  }

  private static func scenario(
    cohortID: String,
    stage: AdoptionStage,
    contender: ProductTournamentContender,
    market: ProductMarket
  ) -> LifecycleScenario {
    let lower = "\(stage.id) \(stage.nameish) \(stage.trigger) \(stage.userQuestion)".lowercased()
    let incumbent = market.incumbents.first?.name ?? "the current alternative"
    let buyerActorID = market.actors.first {
      $0.role == .economicBuyer || $0.role == .managerSponsor
    }?.id ?? "buyer-actor"
    let stageSlug = ProductTournamentModelText.slug(
      stage.trigger,
      fallback: stage.id
    )
    let currentAlternativeClause =
      lower.contains("second") || lower.contains("repeat") || lower.contains("renew")
      ? " Compare explicitly against \(incumbent) and decide whether the market comes back."
      : ""
    let budgetClause =
      lower.contains("budget") || lower.contains("renew")
      ? " Target buyer actor \(buyerActorID) and require payment, renewal, or churn rationale."
      : ""
    return LifecycleScenario(
      id: "lifecycle-\(stage.dayOffset)-\(contender.id)-\(stageSlug)",
      cohortID: cohortID,
      stageID: stage.id,
      title: "\(contender.title): \(stage.trigger)",
      dayOffset: stage.dayOffset,
      trigger: stage.trigger,
      task:
        "\(stage.userQuestion) Test \(contender.valueProposition).\(currentAlternativeClause)\(budgetClause)",
      passSignal: stage.passSignal,
      failSignal: stage.failSignal
    )
  }
}

private extension AdoptionStage {
  var nameish: String { "\(trigger) \(userQuestion) \(passSignal) \(failSignal)" }
}

enum LifecycleSimulationRunner {
  static func run(
    cohort: SyntheticCohort,
    scenario: LifecycleScenario,
    config: ProductTournamentConfig,
    actorID: String? = nil,
    productEvidence: String = "",
    now: Date = Date()
  ) -> LifecycleRunRecord {
    let market = config.markets.first { $0.id == cohort.marketID }
    let actor = actorID ?? cohort.actorIDs.first ?? market?.actors.first?.id ?? "actor"
    let text = "\(scenario.title) \(scenario.trigger) \(scenario.task) \(scenario.passSignal) \(productEvidence)"
      .lowercased()
    let isRepeat = containsAny(text, ["second", "repeat", "recur", "again", "come back", "renew"])
    let isBudget = containsAny(text, ["budget", "buyer", "payment", "paid", "sponsor", "renew"])
    let isTeam = containsAny(text, ["team", "share", "collaboration", "others"])
    let hasCurrentAlternative = containsAny(
      text,
      ["current alternative", "current workaround", "manual", "spreadsheet", "incumbent"]
    )
    let evidenceStrong = containsAny(
      productEvidence.lowercased(),
      ["retained", "repeated", "renewed", "paid", "habit", "came back"]
    )
    let evidenceChurn = containsAny(
      productEvidence.lowercased(),
      ["churn", "stalled", "did not return", "one-off", "novelty"]
    )
    let activation = score(3 + (text.contains("result") || text.contains("proof") ? 1 : 0))
    let repeatedUse = score((isRepeat ? 3 : 1) + (hasCurrentAlternative ? 1 : 0) + (evidenceStrong ? 1 : 0) - (evidenceChurn ? 2 : 0))
    let habitFit = score((isRepeat ? 2 : 1) + (evidenceStrong ? 2 : 0) - (evidenceChurn ? 1 : 0))
    let collaborationPull = score((isTeam ? 3 : 1) + (evidenceStrong ? 1 : 0))
    let paymentReadiness = score((isBudget ? 3 : 1) + (evidenceStrong ? 1 : 0) - (evidenceChurn ? 1 : 0))
    let renewalReadiness = score((text.contains("renew") ? 3 : 1) + (evidenceStrong ? 1 : 0) - (evidenceChurn ? 2 : 0))
    let churnRisk = score((evidenceChurn ? 4 : 2) - (repeatedUse >= 4 ? 1 : 0) - (paymentReadiness >= 4 ? 1 : 0))
    let scores = LifecycleScores(
      activation: activation,
      repeatedUse: repeatedUse,
      habitFit: habitFit,
      collaborationPull: collaborationPull,
      paymentReadiness: paymentReadiness,
      renewalReadiness: renewalReadiness,
      churnRisk: churnRisk
    )
    let outcome = outcome(for: scenario, scores: scores, isRepeat: isRepeat, isBudget: isBudget, isTeam: isTeam)
    let churnReason = outcome == .churned || outcome == .stalled
      ? "The product looked useful once but did not create repeat pull against the current alternative."
      : nil
    let retainedReason = outcome == .retained || outcome == .shared || outcome == .renewed
      ? "The market came back because the job recurred and the product beat the current alternative."
      : nil
    return LifecycleRunRecord(
      id: "lifecycle-\(scenario.id)-\(outcome.rawValue)-\(Int(now.timeIntervalSince1970))",
      cohortID: cohort.id,
      scenarioID: scenario.id,
      marketID: cohort.marketID,
      contenderID: cohort.contenderID,
      actorID: actor,
      stageID: scenario.stageID,
      outcome: outcome,
      scores: scores,
      churnReason: churnReason,
      retainedReason: retainedReason,
      objections: churnReason.map { [$0] } ?? [],
      createdAt: now.timeIntervalSince1970
    )
  }

  private static func outcome(
    for scenario: LifecycleScenario,
    scores: LifecycleScores,
    isRepeat: Bool,
    isBudget: Bool,
    isTeam: Bool
  ) -> LifecycleOutcome {
    let text = "\(scenario.title) \(scenario.task)".lowercased()
    if scores.churnRisk >= 4 && (isRepeat || isBudget || text.contains("renew")) {
      return .churned
    }
    if text.contains("renew") {
      return scores.renewalReadiness >= 3 ? .renewed : .churned
    }
    if isBudget {
      return scores.paymentReadiness >= 3 ? .paid : .stalled
    }
    if isTeam {
      return scores.collaborationPull >= 3 ? .shared : .stalled
    }
    if isRepeat {
      return scores.repeatedUse >= 3 ? .retained : .churned
    }
    return scores.activation >= 3 ? .activated : .stalled
  }

  private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
    needles.contains { text.contains($0) }
  }

  private static func score(_ value: Int) -> Int {
    min(5, max(0, value))
  }
}

enum RoundThreeRetentionGate {
  static func winnerBlocker(
    contenderID: String,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String? {
    guard let debt = evidenceIndex.aggregate.lifecycleProofDebtByContender.first(where: {
      $0.contenderID == contenderID
    }) else {
      return "Winner blocked: run lifecycle second-use proof before selecting a winner."
    }
    if debt.hasUnresolvedChurn {
      return "Winner blocked: \(debt.nextMove)"
    }
    if debt.missingSecondUseProof {
      return "Winner blocked: run second-use proof before selecting a winner."
    }
    if debt.missingBudgetMomentProof {
      return "Winner blocked: run budget or renewal proof before selecting a winner."
    }
    return nil
  }
}

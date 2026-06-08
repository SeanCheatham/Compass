import Foundation

enum MarketPressureKind: String, Codable, CaseIterable, Equatable, Sendable {
  case buyingCommittee = "buying_committee"
  case incumbentDefense = "incumbent_defense"
  case procurementReview = "procurement_review"
  case featureNotCompany = "feature_not_company"
  case urgencyChallenge = "urgency_challenge"
  case budgetChallenge = "budget_challenge"
  case channelChallenge = "channel_challenge"
  case churnChallenge = "churn_challenge"
}

enum MarketPressureVerdict: String, Codable, CaseIterable, Equatable, Sendable {
  case survives
  case narrowed
  case needsReframe = "needs_reframe"
  case blocked
  case rejected
}

struct MarketPressureScores: Codable, Equatable, Sendable {
  var attention: Int
  var urgency: Int
  var incumbentAdvantage: Int
  var buyerClarity: Int
  var budgetFit: Int
  var trustReadiness: Int
  var channelFit: Int
  var retentionRisk: Int

  init(
    attention: Int,
    urgency: Int,
    incumbentAdvantage: Int,
    buyerClarity: Int,
    budgetFit: Int,
    trustReadiness: Int,
    channelFit: Int,
    retentionRisk: Int
  ) {
    self.attention = Self.clamped(attention)
    self.urgency = Self.clamped(urgency)
    self.incumbentAdvantage = Self.clamped(incumbentAdvantage)
    self.buyerClarity = Self.clamped(buyerClarity)
    self.budgetFit = Self.clamped(budgetFit)
    self.trustReadiness = Self.clamped(trustReadiness)
    self.channelFit = Self.clamped(channelFit)
    self.retentionRisk = Self.clamped(retentionRisk)
  }

  private static func clamped(_ value: Int) -> Int {
    min(5, max(0, value))
  }
}

struct MarketProofDebtDelta: Codable, Equatable, Sendable {
  var attentionDelta: Int
  var urgencyDelta: Int
  var buyerClarityDelta: Int
  var budgetFitDelta: Int
  var incumbentDefeatDelta: Int
  var channelFitDelta: Int
  var retentionDelta: Int
  var committeeDelta: Int

  static let none = MarketProofDebtDelta()

  init(
    attentionDelta: Int = 0,
    urgencyDelta: Int = 0,
    buyerClarityDelta: Int = 0,
    budgetFitDelta: Int = 0,
    incumbentDefeatDelta: Int = 0,
    channelFitDelta: Int = 0,
    retentionDelta: Int = 0,
    committeeDelta: Int = 0
  ) {
    self.attentionDelta = attentionDelta
    self.urgencyDelta = urgencyDelta
    self.buyerClarityDelta = buyerClarityDelta
    self.budgetFitDelta = budgetFitDelta
    self.incumbentDefeatDelta = incumbentDefeatDelta
    self.channelFitDelta = channelFitDelta
    self.retentionDelta = retentionDelta
    self.committeeDelta = committeeDelta
  }

  var total: Int {
    attentionDelta + urgencyDelta + buyerClarityDelta + budgetFitDelta
      + incumbentDefeatDelta + channelFitDelta + retentionDelta + committeeDelta
  }

  var summary: String {
    let parts = [
      ("attention", attentionDelta),
      ("urgency", urgencyDelta),
      ("buyer", buyerClarityDelta),
      ("budget", budgetFitDelta),
      ("incumbent", incumbentDefeatDelta),
      ("channel", channelFitDelta),
      ("retention", retentionDelta),
      ("committee", committeeDelta),
    ]
    .filter { $0.1 != 0 }
    .map { "\($0.0) \($0.1 > 0 ? "+" : "")\($0.1)" }
    return parts.isEmpty ? "no debt movement" : parts.joined(separator: ", ")
  }
}

struct MarketPressureEvaluationRecord: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var tournamentID: String
  var roundID: String?
  var marketID: String
  var contenderID: String
  var pressureKind: MarketPressureKind
  var actorIDs: [String]
  var committeeID: String?
  var incumbentID: String?
  var channelID: String?
  var verdict: MarketPressureVerdict
  var scores: MarketPressureScores
  var objections: [String]
  var proofDebtDelta: MarketProofDebtDelta
  var requiredNextProof: [String]
  var transcriptSummary: String
  var createdAt: Double

  init(
    id: String,
    tournamentID: String,
    roundID: String? = nil,
    marketID: String,
    contenderID: String,
    pressureKind: MarketPressureKind,
    actorIDs: [String] = [],
    committeeID: String? = nil,
    incumbentID: String? = nil,
    channelID: String? = nil,
    verdict: MarketPressureVerdict,
    scores: MarketPressureScores,
    objections: [String] = [],
    proofDebtDelta: MarketProofDebtDelta = .none,
    requiredNextProof: [String] = [],
    transcriptSummary: String,
    createdAt: Double
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "market-pressure")
    self.tournamentID = ProductTournamentModelText.identifier(tournamentID, fallback: "tournament")
    self.roundID = ProductTournamentModelText.optionalIdentifier(roundID, fallback: "round")
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.contenderID = ProductTournamentModelText.identifier(contenderID, fallback: "contender")
    self.pressureKind = pressureKind
    self.actorIDs =
      ProductTournamentModelText.cleanedList(actorIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "market-actor") }
    self.committeeID = ProductTournamentModelText.optionalIdentifier(
      committeeID, fallback: "buying-committee")
    self.incumbentID = ProductTournamentModelText.optionalIdentifier(
      incumbentID, fallback: "incumbent")
    self.channelID = ProductTournamentModelText.optionalIdentifier(channelID, fallback: "channel")
    self.verdict = verdict
    self.scores = scores
    self.objections = ProductTournamentModelText.cleanedList(objections, limit: 260)
    self.proofDebtDelta = proofDebtDelta
    self.requiredNextProof = ProductTournamentModelText.cleanedList(requiredNextProof, limit: 260)
    self.transcriptSummary = ProductTournamentModelText.cleanedText(
      transcriptSummary,
      fallback: "Market pressure hearing completed.",
      limit: 1_200
    )
    self.createdAt = createdAt
  }

  var summaryRecord: MarketPressureEvaluationSummary {
    MarketPressureEvaluationSummary(record: self)
  }
}

struct MarketPressureEvaluationSummary: Codable, Equatable, Identifiable, Sendable {
  var id: String { evaluationID }
  var evaluationID: String
  var tournamentID: String
  var roundID: String?
  var marketID: String
  var contenderID: String
  var pressureKind: MarketPressureKind
  var verdict: MarketPressureVerdict
  var strongestObjection: String
  var proofDebtDelta: MarketProofDebtDelta
  var createdAt: Double

  init(record: MarketPressureEvaluationRecord) {
    evaluationID = record.id
    tournamentID = record.tournamentID
    roundID = record.roundID
    marketID = record.marketID
    contenderID = record.contenderID
    pressureKind = record.pressureKind
    verdict = record.verdict
    strongestObjection = record.objections.first ?? ""
    proofDebtDelta = record.proofDebtDelta
    createdAt = record.createdAt
  }
}

enum MarketPressureEvaluator {
  static func evaluate(
    kind: MarketPressureKind,
    market: ProductMarket,
    contender: ProductTournamentContender,
    tournamentID: String,
    roundID: String?,
    now: Date = Date()
  ) -> MarketPressureEvaluationRecord {
    let buyer = market.actors.first { $0.role == .economicBuyer || $0.role == .managerSponsor }
    let operatorActor = market.actors.first { $0.role == .operator }
    let committee = market.buyingCommittees.first
    let incumbent = market.incumbents.first
    let channel = market.channels.sorted {
      if $0.reachability == $1.reachability { return $0.costRisk < $1.costRisk }
      return $0.reachability > $1.reachability
    }.first
    let text = [
      contender.title,
      contender.productPlan,
      contender.valueProposition,
      contender.primaryRisk,
    ].joined(separator: " ").lowercased()
    let mentionsBudget = text.contains("budget") || text.contains("pay") || text.contains("roi")
    let mentionsRepeat = text.contains("repeat") || text.contains("recurr") || text.contains("habit")
    let mentionsIncumbent =
      incumbent.map { text.contains($0.name.lowercased()) } ?? false
        || text.contains("alternative")
        || text.contains("workaround")
    let attention = max(1, 5 - market.marketProofDebt.attentionDeficit)
    let urgency = max(1, market.marketForces.first { $0.kind == .urgency }?.strength ?? 2)
    let buyerClarity = buyer == nil ? 1 : max(2, 5 - market.marketProofDebt.buyerClarityDeficit)
    let budgetFit = mentionsBudget ? 4 : max(1, 4 - market.marketProofDebt.budgetFitDeficit)
    let incumbentAdvantage =
      mentionsIncumbent ? max(1, 3 - market.marketProofDebt.incumbentDefeatDeficit) : 5
    let channelFit = channel.map { max(1, $0.reachability - max(0, $0.costRisk - 2)) } ?? 1
    let retentionRisk = mentionsRepeat ? max(1, market.marketProofDebt.retentionDeficit) : 5
    let trustReadiness = market.actors.contains { $0.role == .securityReviewer } ? 2 : 3

    let scores = MarketPressureScores(
      attention: attention,
      urgency: urgency,
      incumbentAdvantage: incumbentAdvantage,
      buyerClarity: buyerClarity,
      budgetFit: budgetFit,
      trustReadiness: trustReadiness,
      channelFit: channelFit,
      retentionRisk: retentionRisk
    )
    let verdict = verdict(for: kind, scores: scores)
    let objections = objections(
      for: kind,
      buyer: buyer,
      incumbent: incumbent,
      channel: channel,
      scores: scores,
      mentionsRepeat: mentionsRepeat
    )
    let debtDelta = proofDebtDelta(for: kind, verdict: verdict, scores: scores)
    let nextProof = requiredNextProof(for: kind, verdict: verdict, objections: objections)
    let actorIDs = [operatorActor?.id, buyer?.id].compactMap { $0 }
    return MarketPressureEvaluationRecord(
      id:
        "\(contender.id)-\(kind.rawValue)-\(Int(now.timeIntervalSince1970))",
      tournamentID: tournamentID,
      roundID: roundID,
      marketID: market.id,
      contenderID: contender.id,
      pressureKind: kind,
      actorIDs: actorIDs,
      committeeID: kind == .buyingCommittee ? committee?.id : nil,
      incumbentID: kind == .incumbentDefense ? incumbent?.id : nil,
      channelID: kind == .channelChallenge ? channel?.id : nil,
      verdict: verdict,
      scores: scores,
      objections: objections,
      proofDebtDelta: debtDelta,
      requiredNextProof: nextProof,
      transcriptSummary:
        "\(kind.rawValue) judged \(contender.title): \(verdict.rawValue); \(objections.prefix(2).joined(separator: " "))",
      createdAt: now.timeIntervalSince1970
    )
  }

  private static func verdict(
    for kind: MarketPressureKind,
    scores: MarketPressureScores
  ) -> MarketPressureVerdict {
    let blockers = [
      scores.buyerClarity <= 1,
      scores.urgency <= 1,
      scores.channelFit <= 1 && kind == .channelChallenge,
      scores.retentionRisk >= 5 && kind == .churnChallenge,
    ].filter { $0 }.count
    if blockers > 0 { return .blocked }
    if scores.incumbentAdvantage >= 5 && kind == .incumbentDefense { return .rejected }
    let positive = scores.attention + scores.urgency + scores.buyerClarity + scores.budgetFit
      + scores.channelFit
    if positive >= 18 && scores.retentionRisk <= 3 { return .survives }
    if positive >= 14 { return .narrowed }
    return .needsReframe
  }

  private static func objections(
    for kind: MarketPressureKind,
    buyer: MarketActor?,
    incumbent: IncumbentPressure?,
    channel: AcquisitionChannel?,
    scores: MarketPressureScores,
    mentionsRepeat: Bool
  ) -> [String] {
    var objections: [String] = []
    if buyer == nil || scores.buyerClarity <= 2 {
      objections.append("No clear economic buyer owns the decision.")
    }
    if scores.budgetFit <= 2 {
      objections.append("Budget logic is not explicit enough for purchase.")
    }
    if kind == .incumbentDefense && scores.incumbentAdvantage >= 4 {
      objections.append(
        "\(incumbent?.name ?? "The incumbent") remains good enough and safer to keep.")
    }
    if kind == .channelChallenge && (channel == nil || scores.channelFit <= 2) {
      objections.append("The channel may not reach buyers with sufficient intent.")
    }
    if kind == .churnChallenge && !mentionsRepeat {
      objections.append("The contender does not name a repeat usage loop.")
    }
    if objections.isEmpty {
      objections.append("The market asks for narrower proof before broader investment.")
    }
    return objections
  }

  private static func proofDebtDelta(
    for kind: MarketPressureKind,
    verdict: MarketPressureVerdict,
    scores: MarketPressureScores
  ) -> MarketProofDebtDelta {
    let clear = verdict == .survives || verdict == .narrowed
    switch kind {
    case .buyingCommittee:
      return MarketProofDebtDelta(
        buyerClarityDelta: clear ? -1 : 1,
        committeeDelta: clear ? -1 : 1
      )
    case .incumbentDefense:
      return MarketProofDebtDelta(incumbentDefeatDelta: clear ? -1 : 1)
    case .procurementReview:
      return MarketProofDebtDelta(budgetFitDelta: scores.budgetFit >= 3 ? -1 : 1)
    case .featureNotCompany:
      return MarketProofDebtDelta(budgetFitDelta: clear ? 0 : 1, retentionDelta: clear ? -1 : 1)
    case .urgencyChallenge:
      return MarketProofDebtDelta(urgencyDelta: scores.urgency >= 3 ? -1 : 1)
    case .budgetChallenge:
      return MarketProofDebtDelta(budgetFitDelta: scores.budgetFit >= 3 ? -1 : 1)
    case .channelChallenge:
      return MarketProofDebtDelta(channelFitDelta: scores.channelFit >= 3 ? -1 : 1)
    case .churnChallenge:
      return MarketProofDebtDelta(retentionDelta: scores.retentionRisk <= 3 ? -1 : 1)
    }
  }

  private static func requiredNextProof(
    for kind: MarketPressureKind,
    verdict: MarketPressureVerdict,
    objections: [String]
  ) -> [String] {
    guard verdict != .survives else { return ["Record the pressure result in the decision trail."] }
    let prefix: String
    switch kind {
    case .buyingCommittee: prefix = "Run a narrower buying committee proof"
    case .incumbentDefense: prefix = "Show why the incumbent fails now"
    case .procurementReview: prefix = "Name procurement threshold and risk controls"
    case .featureNotCompany: prefix = "Prove a repeat workflow wedge"
    case .urgencyChallenge: prefix = "Quantify urgency and frequency"
    case .budgetChallenge: prefix = "Tie pain to buyer-owned budget"
    case .channelChallenge: prefix = "Rewrite or test a different channel"
    case .churnChallenge: prefix = "Simulate second use and churn reason"
    }
    return [prefix] + objections.prefix(2)
  }
}

enum MarketPressureTransitionGate {
  static func roundOneBlocker(
    contenderID: String,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String? {
    let rows = evidenceIndex.aggregate.marketPressureByContender[contenderID] ?? []
    let hasRequiredPressure = rows.contains {
      $0.pressureKind == .buyingCommittee || $0.pressureKind == .incumbentDefense
    }
    guard hasRequiredPressure else {
      return "Round 1 needs buying committee or incumbent pressure evidence."
    }
    if rows.contains(where: { $0.verdict == .rejected || $0.verdict == .blocked }) {
      return "Round 1 market pressure is blocked or rejected."
    }
    return nil
  }

  static func roundTwoBlocker(
    contenderID: String,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String? {
    let rows = evidenceIndex.aggregate.marketPressureByContender[contenderID] ?? []
    guard
      let incumbent = rows.first(where: { $0.pressureKind == .incumbentDefense })
    else {
      return "Round 2 needs incumbent defense pressure evidence."
    }
    if incumbent.verdict == .rejected || incumbent.verdict == .blocked {
      return "Round 2 is blocked by incumbent defense verdict \(incumbent.verdict.rawValue)."
    }
    return nil
  }

  static func winnerBlocker(
    contenderID: String,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String? {
    let rows = evidenceIndex.aggregate.marketPressureByContender[contenderID] ?? []
    guard
      let churn = rows.first(where: { $0.pressureKind == .churnChallenge })
    else {
      return "Winner selection needs churn pressure evidence."
    }
    if churn.verdict == .blocked || churn.proofDebtDelta.retentionDelta > 0 {
      return "Winner selection is blocked by unresolved churn or retention debt."
    }
    return nil
  }
}

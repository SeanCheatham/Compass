import Foundation

struct ProductTournamentPlanEvaluationOutcome {
  var tournamentID: String
  var roundID: String
  var records: [ProductTournamentPlanEvaluationRecord]
  var skippedContenderIDs: [String]

  var completedEvaluationCount: Int {
    records.filter { $0.status == .completed }.count
  }

  var latestRecordID: String? {
    records.last?.id
  }

  var isSuccess: Bool {
    !records.isEmpty && completedEvaluationCount == records.count
  }

  var userMessage: String {
    "Round 1 plan evaluation recorded \(completedEvaluationCount) simulated-user evaluation(s) for \(records.map(\.contenderID).uniquedCount) contender(s), \(skippedContenderIDs.count) skipped."
  }
}

enum ProductTournamentPlanEvaluationError: LocalizedError, Equatable {
  case unknownTournament(String)
  case unknownRound(String)
  case unknownContender(String)
  case unknownSolution(String)
  case unknownPain(String)
  case roundRequiresBuiltProduct(String)
  case noPlanRound(String)

  var errorDescription: String? {
    switch self {
    case .unknownTournament(let id):
      return "Product tournament \(id) was not found."
    case .unknownRound(let id):
      return "Product tournament round \(id) was not found."
    case .unknownContender(let id):
      return "Product tournament contender \(id) was not found."
    case .unknownSolution(let id):
      return "Product solution \(id) was not found."
    case .unknownPain(let id):
      return "Pain hypothesis \(id) was not found."
    case .roundRequiresBuiltProduct(let id):
      return "Tournament round \(id) requires a built product and cannot run plan-only evaluation."
    case .noPlanRound(let tournamentID):
      return "Product tournament \(tournamentID) has no plan-only round to evaluate."
    }
  }
}

enum ProductTournamentPlanEvaluator {
  static let promptVersionID = "product_tournament.plan_evaluator.model_free.v1"

  static func runPlanRound(
    tournamentID: String,
    roundID: String? = nil,
    in workspace: CompassWorkspace,
    projectID: UUID? = nil,
    now: Date = Date()
  ) throws -> ProductTournamentPlanEvaluationOutcome {
    var config = try workspace.readProductizationConfig()
    let evaluationStart = now.timeIntervalSince1970
    guard let tournament = config.tournaments.first(where: { $0.id == tournamentID }) else {
      throw ProductTournamentPlanEvaluationError.unknownTournament(tournamentID)
    }
    let round = try planRound(roundID: roundID, tournament: tournament, config: config)
    let contenderIDs = round.contenderIDs.isEmpty ? tournament.contenderIDs : round.contenderIDs
    var records: [ProductTournamentPlanEvaluationRecord] = []
    var skippedContenderIDs: [String] = []

    for contenderID in contenderIDs {
      guard let contender = config.tournamentContenders.first(where: { $0.id == contenderID })
      else {
        throw ProductTournamentPlanEvaluationError.unknownContender(contenderID)
      }
      guard contender.status == .competing || contender.status == .narrowed else {
        skippedContenderIDs.append(contender.id)
        continue
      }
      let solution = try solution(for: contender, config: config)
      let pain = try pain(for: solution, config: config)
      let segments = targetSegments(for: contender, painID: pain.id, config: config)
      for segment in segments {
        let workflow = currentWorkflow(for: segment, painID: pain.id, config: config)
        let alternative = currentAlternative(for: segment, painID: pain.id, config: config)
        let endedAt = Date().timeIntervalSince1970
        let record = evaluate(
          tournament: tournament,
          round: round,
          contender: contender,
          solution: solution,
          pain: pain,
          segment: segment,
          currentWorkflow: workflow,
          alternative: alternative,
          projectID: projectID,
          startedAt: evaluationStart,
          endedAt: endedAt
        )
        records.append(try workspace.writeProductTournamentPlanEvaluationRecord(record))
      }
    }

    if let roundIndex = config.tournamentRounds.firstIndex(where: { $0.id == round.id }) {
      config.tournamentRounds[roundIndex].updatedAt = Date().timeIntervalSince1970
      try workspace.writeProductizationConfig(config)
    }

    return ProductTournamentPlanEvaluationOutcome(
      tournamentID: tournament.id,
      roundID: round.id,
      records: records,
      skippedContenderIDs: skippedContenderIDs
    )
  }

  private static func evaluate(
    tournament: ProductTournament,
    round: ProductTournamentRound,
    contender: ProductTournamentContender,
    solution: SolutionHypothesis,
    pain: PainHypothesis,
    segment: UserSegment,
    currentWorkflow: CurrentWorkflow?,
    alternative: Alternative?,
    projectID: UUID?,
    startedAt: Double,
    endedAt: Double
  ) -> ProductTournamentPlanEvaluationRecord {
    let text = [
      contender.title,
      contender.productPlan,
      contender.valueProposition,
      contender.primaryRisk,
      solution.promise,
      solution.workflowBet,
      solution.differentiator,
      solution.whyThisCouldWin,
      solution.requiredProof.joined(separator: " "),
    ].joined(separator: " ")

    let painRecognition = score(
      text: text,
      anchors: [pain.rawPain, pain.targetSituation, pain.costOfInaction] + pain.successSignals,
      base: 3
    )
    let workflowImprovement = score(
      text: text,
      anchors: (currentWorkflow?.steps ?? []) + (currentWorkflow?.failureModes ?? [])
        + (currentWorkflow?.handoffs ?? []),
      base: 3
    )
    let alternativeAdvantage = score(
      text: text,
      anchors: [alternative?.title, alternative?.switchingCost].compactMap { $0 }
        + (alternative?.weaknesses ?? []) + (alternative?.strengths ?? []),
      base: text.containsWord(["alternative", "current", "workaround", "instead", "beats"]) ? 4 : 3
    )
    let switchingReadiness = switchingReadinessScore(
      contender: contender,
      segment: segment,
      alternative: alternative,
      text: text
    )
    let continuedUsePull = continuedUsePullScore(
      painRecognition: painRecognition,
      workflowImprovement: workflowImprovement,
      alternativeAdvantage: alternativeAdvantage,
      switchingReadiness: switchingReadiness
    )
    let willingnessToPay = willingnessToPayScore(
      pain: pain,
      segment: segment,
      scores: [
        painRecognition,
        workflowImprovement,
        alternativeAdvantage,
        switchingReadiness,
        continuedUsePull,
      ]
    )
    let scores = ProductizationEvidenceScores(
      painRecognition: painRecognition,
      workflowImprovement: workflowImprovement,
      alternativeAdvantage: alternativeAdvantage,
      switchingReadiness: switchingReadiness,
      continuedUsePull: continuedUsePull
    )
    let average =
      Double(
        painRecognition + workflowImprovement + alternativeAdvantage + switchingReadiness
          + continuedUsePull + willingnessToPay
      ) / 6
    let verdict = verdict(averageScore: average, willingnessToPayScore: willingnessToPay)
    let price = estimatedMonthlyPriceCents(
      pain: pain,
      segment: segment,
      willingnessToPayScore: willingnessToPay
    )
    let objections = objections(
      contender: contender,
      segment: segment,
      alternative: alternative,
      switchingReadiness: switchingReadiness,
      willingnessToPay: willingnessToPay
    )
    let missingCapabilities = missingCapabilities(
      solution: solution,
      workflowImprovement: workflowImprovement,
      alternativeAdvantage: alternativeAdvantage
    )
    let comparison = currentAlternativeComparison(
      contender: contender,
      alternative: alternative,
      alternativeAdvantage: alternativeAdvantage
    )
    let summary = summary(
      contender: contender,
      segment: segment,
      verdict: verdict,
      willingnessToPay: willingnessToPay,
      price: price
    )

    return ProductTournamentPlanEvaluationRecord(
      id: recordID(round: round, contender: contender, segment: segment, endedAt: endedAt),
      projectID: projectID?.uuidString,
      tournamentID: tournament.id,
      roundID: round.id,
      contenderID: contender.id,
      solutionID: solution.id,
      experimentID: contender.experimentID,
      painID: pain.id,
      personaID: segment.id,
      personaName: segment.name,
      currentWorkflowID: currentWorkflow?.id,
      alternativeID: alternative?.id,
      startedAt: startedAt,
      endedAt: endedAt,
      scores: scores,
      willingnessToPayScore: willingnessToPay,
      estimatedMonthlyPriceCents: price,
      objections: objections,
      missingCapabilities: missingCapabilities,
      currentAlternativeComparison: comparison,
      verdict: verdict,
      summary: summary,
      rationale: rationale(
        contender: contender,
        segment: segment,
        scores: scores,
        willingnessToPay: willingnessToPay,
        verdict: verdict
      ),
      planStrengths: planStrengths(contender: contender, solution: solution),
      planRisks: planRisks(contender: contender, solution: solution),
      promptVersions: [promptVersionID]
    )
  }

  private static func recordID(
    round: ProductTournamentRound,
    contender: ProductTournamentContender,
    segment: UserSegment,
    endedAt: Double
  ) -> String {
    [
      "plan",
      String(round.id.suffix(20)),
      String(contender.id.suffix(30)),
      String(segment.id.suffix(22)),
      "\(Int(endedAt))",
    ].joined(separator: "-")
  }

  private static func planRound(
    roundID: String?,
    tournament: ProductTournament,
    config: ProductizationConfig
  ) throws -> ProductTournamentRound {
    let round: ProductTournamentRound?
    if let roundID {
      round = config.tournamentRounds.first {
        $0.id == roundID && $0.tournamentID == tournament.id
      }
    } else if let currentRoundID = tournament.currentRoundID {
      round = config.tournamentRounds.first {
        $0.id == currentRoundID && $0.tournamentID == tournament.id
      }
    } else {
      round = nil
    }
    let selected =
      round
      ?? config.tournamentRounds
      .filter { $0.tournamentID == tournament.id && $0.kind == .productPlans }
      .sorted { $0.ordinal < $1.ordinal }
      .first
    guard let selected else {
      throw ProductTournamentPlanEvaluationError.noPlanRound(tournament.id)
    }
    guard selected.kind == .productPlans && !selected.requiresBuiltProduct else {
      throw ProductTournamentPlanEvaluationError.roundRequiresBuiltProduct(selected.id)
    }
    return selected
  }

  private static func solution(
    for contender: ProductTournamentContender,
    config: ProductizationConfig
  ) throws -> SolutionHypothesis {
    guard let solution = config.solutionHypotheses.first(where: { $0.id == contender.solutionID })
    else {
      throw ProductTournamentPlanEvaluationError.unknownSolution(contender.solutionID)
    }
    return solution
  }

  private static func pain(
    for solution: SolutionHypothesis,
    config: ProductizationConfig
  ) throws -> PainHypothesis {
    guard let pain = config.painHypotheses.first(where: { $0.id == solution.painID }) else {
      throw ProductTournamentPlanEvaluationError.unknownPain(solution.painID)
    }
    return pain
  }

  private static func targetSegments(
    for contender: ProductTournamentContender,
    painID: String,
    config: ProductizationConfig
  ) -> [UserSegment] {
    let targetIDs = Set(contender.targetSegmentIDs)
    let targeted = config.userSegments.filter {
      $0.painID == painID && (targetIDs.isEmpty || targetIDs.contains($0.id))
    }
    if !targeted.isEmpty { return targeted }
    return config.userSegments.filter { $0.painID == painID }
  }

  private static func currentWorkflow(
    for segment: UserSegment,
    painID: String,
    config: ProductizationConfig
  ) -> CurrentWorkflow? {
    config.currentWorkflows.first {
      $0.painID == painID && segment.currentWorkflowIDs.contains($0.id)
    } ?? config.currentWorkflows.first { $0.painID == painID }
  }

  private static func currentAlternative(
    for segment: UserSegment,
    painID: String,
    config: ProductizationConfig
  ) -> Alternative? {
    config.alternatives.first {
      $0.painID == painID && segment.alternativeIDs.contains($0.id)
    } ?? config.alternatives.first { $0.painID == painID }
  }

  private static func score(text: String, anchors: [String], base: Int) -> Int {
    let tokens = Set(text.significantTokens)
    let anchorTokens = Set(anchors.flatMap(\.significantTokens))
    guard !anchorTokens.isEmpty else { return base }
    let overlap = tokens.intersection(anchorTokens).count
    switch overlap {
    case 8...: return 5
    case 4...: return max(4, base)
    case 2...: return max(3, base)
    case 1: return max(2, base - 1)
    default: return max(1, base - 1)
    }
  }

  private static func switchingReadinessScore(
    contender: ProductTournamentContender,
    segment: UserSegment,
    alternative: Alternative?,
    text: String
  ) -> Int {
    var score = text.containsWord(["guided", "without", "less", "clear", "reduce"]) ? 4 : 3
    let risk = contender.primaryRisk.lowercased()
    let skepticism = segment.skepticism.lowercased()
    if risk.contains("slower") || risk.contains("setup") || skepticism.contains("setup") {
      score -= 1
    }
    if let alternative, alternative.switchingCost.lowercased().contains("low") {
      score += 1
    }
    return min(5, max(1, score))
  }

  private static func continuedUsePullScore(
    painRecognition: Int,
    workflowImprovement: Int,
    alternativeAdvantage: Int,
    switchingReadiness: Int
  ) -> Int {
    let average =
      Double(painRecognition + workflowImprovement + alternativeAdvantage + switchingReadiness) / 4
    switch average {
    case 4.5...: return 5
    case 3.7...: return 4
    case 2.8...: return 3
    case 2.0...: return 2
    default: return 1
    }
  }

  private static func willingnessToPayScore(
    pain: PainHypothesis,
    segment: UserSegment,
    scores: [Int]
  ) -> Int {
    let average = Double(scores.reduce(0, +)) / Double(max(1, scores.count))
    let buyerText = [
      segment.role, segment.context, segment.decisionCriteria.joined(separator: " "),
    ]
    .joined(separator: " ")
    .lowercased()
    let painText = [pain.painSeverity, pain.costOfInaction].joined(separator: " ").lowercased()
    var score = Int(average.rounded())
    if buyerText.contains("buyer") || buyerText.contains("budget") || buyerText.contains("sponsor")
    {
      score += 1
    }
    if painText.contains("high") || painText.contains("cost") || painText.contains("hour") {
      score += 1
    }
    return min(5, max(1, score))
  }

  private static func estimatedMonthlyPriceCents(
    pain: PainHypothesis,
    segment: UserSegment,
    willingnessToPayScore: Int
  ) -> Int? {
    guard willingnessToPayScore >= 3 else { return nil }
    let buyerText = [segment.role, segment.context].joined(separator: " ").lowercased()
    let multiplier = buyerText.contains("buyer") || buyerText.contains("sponsor") ? 2 : 1
    let severe = [pain.painSeverity, pain.costOfInaction].joined(separator: " ").lowercased()
      .contains("high")
    let base = severe ? 9900 : 4900
    return base * multiplier * max(1, willingnessToPayScore - 2)
  }

  private static func verdict(
    averageScore: Double,
    willingnessToPayScore: Int
  ) -> ProductizationEvidenceVerdict {
    if averageScore >= 4.4 && willingnessToPayScore >= 4 { return .strongPull }
    if averageScore >= 3.5 && willingnessToPayScore >= 3 { return .promising }
    if averageScore >= 2.7 { return .unclear }
    if averageScore >= 2.0 { return .weak }
    return .rejected
  }

  private static func objections(
    contender: ProductTournamentContender,
    segment: UserSegment,
    alternative: Alternative?,
    switchingReadiness: Int,
    willingnessToPay: Int
  ) -> [String] {
    var objections: [String] = []
    if switchingReadiness <= 3 {
      objections.append(contender.primaryRisk)
    }
    if willingnessToPay <= 2 {
      objections.append("\(segment.name) would need clearer ROI before paying.")
    }
    if let alternative, !alternative.strengths.isEmpty {
      objections.append("Current alternative strength: \(alternative.strengths[0])")
    }
    return objections
  }

  private static func missingCapabilities(
    solution: SolutionHypothesis,
    workflowImprovement: Int,
    alternativeAdvantage: Int
  ) -> [String] {
    var missing: [String] = []
    if workflowImprovement <= 2 {
      missing.append("workflow_proof")
    }
    if alternativeAdvantage <= 2 {
      missing.append("current_alternative_proof")
    }
    if solution.requiredProof.isEmpty {
      missing.append("required_proof")
    }
    return missing
  }

  private static func currentAlternativeComparison(
    contender: ProductTournamentContender,
    alternative: Alternative?,
    alternativeAdvantage: Int
  ) -> String {
    let alternativeName = alternative?.title ?? "the current alternative"
    if alternativeAdvantage >= 4 {
      return
        "\(contender.title) looks meaningfully better than \(alternativeName) on the plan because it offers \(contender.valueProposition)"
    }
    if alternativeAdvantage <= 2 {
      return
        "\(alternativeName) remains safer than \(contender.title) until the plan proves a sharper advantage."
    }
    return
      "\(contender.title) is plausible against \(alternativeName), but the plan needs a clearer switching proof."
  }

  private static func summary(
    contender: ProductTournamentContender,
    segment: UserSegment,
    verdict: ProductizationEvidenceVerdict,
    willingnessToPay: Int,
    price: Int?
  ) -> String {
    let priceText = price.map { " at about \(priceLabel(cents: $0))" } ?? ""
    return
      "\(segment.name) rated \(contender.title) as \(verdict.rawValue) from the plan alone, with willingness to pay \(willingnessToPay)/5\(priceText)."
  }

  private static func rationale(
    contender: ProductTournamentContender,
    segment: UserSegment,
    scores: ProductizationEvidenceScores,
    willingnessToPay: Int,
    verdict: ProductizationEvidenceVerdict
  ) -> [String] {
    [
      "\(segment.name) evaluated the plan without a built product.",
      "The plan promise was: \(contender.valueProposition)",
      "Scorecard pain \(scores.painRecognition ?? 0), workflow \(scores.workflowImprovement ?? 0), alternative \(scores.alternativeAdvantage ?? 0), switching \(scores.switchingReadiness ?? 0), pull \(scores.continuedUsePull ?? 0), pay \(willingnessToPay).",
      "Verdict \(verdict.rawValue) reflects plan evidence only.",
    ]
  }

  private static func planStrengths(
    contender: ProductTournamentContender,
    solution: SolutionHypothesis
  ) -> [String] {
    [contender.valueProposition, solution.differentiator, solution.whyThisCouldWin]
  }

  private static func planRisks(
    contender: ProductTournamentContender,
    solution: SolutionHypothesis
  ) -> [String] {
    [contender.primaryRisk, solution.whyThisMightFail]
  }

  private static func priceLabel(cents: Int) -> String {
    let dollars = Double(max(0, cents)) / 100
    return String(format: "$%.0f/month", dollars)
  }
}

@MainActor
extension CompassProject {
  func runProductTournamentPlanRoundModelFree(
    tournamentID: String,
    roundID: String? = nil
  ) async -> ProductTournamentPlanEvaluationOutcome? {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return nil
      }
      let outcome = try ProductTournamentPlanEvaluator.runPlanRound(
        tournamentID: tournamentID,
        roundID: roundID,
        in: workspace,
        projectID: id
      )
      productizationConfig = try workspace.readProductizationConfig()
      productizationEvidenceIndex = workspace.readProductizationEvidenceIndex()
      log(outcome.userMessage, level: outcome.isSuccess ? .success : .warning)
      return outcome
    } catch {
      fail(error)
      return nil
    }
  }
}

extension String {
  fileprivate var significantTokens: [String] {
    lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
      .split(separator: " ")
      .map(String.init)
      .filter { $0.count >= 4 && !Self.stopWords.contains($0) }
  }

  fileprivate func containsWord(_ words: [String]) -> Bool {
    let lowercased = lowercased()
    return words.contains { lowercased.contains($0) }
  }

  fileprivate static let stopWords: Set<String> = [
    "about", "after", "also", "because", "before", "current", "from", "have", "into",
    "more", "need", "needs", "that", "their", "them", "they", "this", "turn", "user",
    "with", "workflow", "would",
  ]
}

extension Array where Element == String {
  fileprivate var uniquedCount: Int {
    Set(self).count
  }
}

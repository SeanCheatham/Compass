import Foundation

struct DistributionExperiment: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var marketID: String
  var contenderID: String
  var channelID: String
  var title: String
  var artifactKind: DistributionArtifactKind
  var artifactText: String
  var targetActorID: String?
  var successThreshold: String
  var killCriteria: String
  var status: DistributionExperimentStatus
  var createdAt: Double
  var updatedAt: Double

  init(
    id: String,
    marketID: String,
    contenderID: String,
    channelID: String,
    title: String,
    artifactKind: DistributionArtifactKind,
    artifactText: String,
    targetActorID: String? = nil,
    successThreshold: String,
    killCriteria: String,
    status: DistributionExperimentStatus = .draft,
    createdAt: Double,
    updatedAt: Double? = nil
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "distribution-experiment")
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.contenderID = ProductTournamentModelText.identifier(contenderID, fallback: "contender")
    self.channelID = ProductTournamentModelText.identifier(channelID, fallback: "channel")
    self.title = ProductTournamentModelText.cleanedText(
      title,
      fallback: "Distribution experiment",
      limit: 180
    )
    self.artifactKind = artifactKind
    self.artifactText = ProductTournamentModelText.cleanedText(
      artifactText,
      fallback: "Distribution artifact to test buyer attention.",
      limit: 4_000
    )
    self.targetActorID = ProductTournamentModelText.optionalIdentifier(
      targetActorID,
      fallback: "actor"
    )
    self.successThreshold = ProductTournamentModelText.cleanedText(
      successThreshold,
      fallback: "Audience recognizes the painful workflow and takes the next step.",
      limit: 500
    )
    self.killCriteria = ProductTournamentModelText.cleanedText(
      killCriteria,
      fallback: "The channel ignores the message or cannot reach the buyer.",
      limit: 500
    )
    self.status = status
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
  }
}

enum DistributionArtifactKind: String, Codable, CaseIterable, Equatable, Sendable {
  case coldEmail = "cold_email"
  case landingPage = "landing_page"
  case seoPage = "seo_page"
  case marketplaceListing = "marketplace_listing"
  case communityPost = "community_post"
  case salesScript = "sales_script"
  case openSourceReadme = "open_source_readme"
  case integrationPitch = "integration_pitch"
  case templateLeadMagnet = "template_lead_magnet"
  case paidAd = "paid_ad"
}

enum DistributionExperimentStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case draft
  case simulated
  case passed
  case narrowed
  case failed
}

struct DistributionPressureRecord: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var experimentID: String
  var marketID: String
  var contenderID: String
  var channelID: String
  var simulatedAudience: String
  var verdict: DistributionVerdict
  var scores: DistributionScores
  var objections: [String]
  var rewriteRecommendations: [String]
  var createdAt: Double

  init(
    id: String,
    experimentID: String,
    marketID: String,
    contenderID: String,
    channelID: String,
    simulatedAudience: String,
    verdict: DistributionVerdict,
    scores: DistributionScores,
    objections: [String] = [],
    rewriteRecommendations: [String] = [],
    createdAt: Double
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "distribution-pressure")
    self.experimentID = ProductTournamentModelText.identifier(
      experimentID,
      fallback: "distribution-experiment"
    )
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.contenderID = ProductTournamentModelText.identifier(contenderID, fallback: "contender")
    self.channelID = ProductTournamentModelText.identifier(channelID, fallback: "channel")
    self.simulatedAudience = ProductTournamentModelText.cleanedText(
      simulatedAudience,
      fallback: "Audience with the target pain",
      limit: 500
    )
    self.verdict = verdict
    self.scores = scores
    self.objections = ProductTournamentModelText.cleanedList(objections, limit: 300)
    self.rewriteRecommendations = ProductTournamentModelText.cleanedList(
      rewriteRecommendations,
      limit: 300
    )
    self.createdAt = createdAt
  }

  var summaryRecord: DistributionPressureSummary {
    DistributionPressureSummary(record: self)
  }
}

enum DistributionVerdict: String, Codable, CaseIterable, Equatable, Sendable {
  case getsAttention = "gets_attention"
  case needsSharperWedge = "needs_sharper_wedge"
  case wrongChannel = "wrong_channel"
  case tooExpensive = "too_expensive"
  case ignored
}

struct DistributionScores: Codable, Equatable, Sendable {
  var attention: Int
  var intentMatch: Int
  var credibility: Int
  var differentiation: Int
  var buyerReachability: Int
  var channelEconomics: Int

  init(
    attention: Int,
    intentMatch: Int,
    credibility: Int,
    differentiation: Int,
    buyerReachability: Int,
    channelEconomics: Int
  ) {
    self.attention = Self.clamped(attention)
    self.intentMatch = Self.clamped(intentMatch)
    self.credibility = Self.clamped(credibility)
    self.differentiation = Self.clamped(differentiation)
    self.buyerReachability = Self.clamped(buyerReachability)
    self.channelEconomics = Self.clamped(channelEconomics)
  }

  var average: Double {
    let total =
      attention + intentMatch + credibility + differentiation + buyerReachability
      + channelEconomics
    return (Double(total) / 6 * 100).rounded() / 100
  }

  private static func clamped(_ value: Int) -> Int {
    min(5, max(0, value))
  }
}

struct DistributionPressureSummary: Codable, Equatable, Identifiable, Sendable {
  var id: String { pressureID }
  var pressureID: String
  var experimentID: String
  var marketID: String
  var contenderID: String
  var channelID: String
  var simulatedAudience: String
  var verdict: DistributionVerdict
  var scores: DistributionScores
  var strongestObjection: String
  var topRewriteRecommendation: String
  var createdAt: Double

  init(record: DistributionPressureRecord) {
    pressureID = record.id
    experimentID = record.experimentID
    marketID = record.marketID
    contenderID = record.contenderID
    channelID = record.channelID
    simulatedAudience = record.simulatedAudience
    verdict = record.verdict
    scores = record.scores
    strongestObjection = record.objections.first ?? ""
    topRewriteRecommendation = record.rewriteRecommendations.first ?? ""
    createdAt = record.createdAt
  }

  var passedChannelProof: Bool {
    verdict == .getsAttention && scores.attention >= 4 && scores.buyerReachability >= 3
  }

  var digestLine: String {
    let objection = strongestObjection.isEmpty ? "no objection" : strongestObjection
    let rewrite = topRewriteRecommendation.isEmpty ? "no rewrite" : topRewriteRecommendation
    return
      "distribution \(pressureID); contender \(contenderID); channel \(channelID); verdict \(verdict.rawValue); score \(scores.average)/5; objection \(objection); next \(rewrite)"
  }
}

struct DistributionChannelProof: Codable, Equatable, Sendable {
  var contenderID: String
  var bestChannelID: String?
  var bestPressureID: String?
  var bestScore: Double
  var latestVerdict: DistributionVerdict?
  var failedChannelCount: Int
  var proofDebt: MarketProofDebt
  var nextMove: String

  init(contenderID: String, summaries: [DistributionPressureSummary]) {
    self.contenderID = contenderID
    let sorted = summaries.sorted { lhs, rhs in
      if lhs.createdAt == rhs.createdAt { return lhs.pressureID < rhs.pressureID }
      return lhs.createdAt > rhs.createdAt
    }
    let best = sorted.max { lhs, rhs in
      if lhs.scores.average == rhs.scores.average { return lhs.createdAt < rhs.createdAt }
      return lhs.scores.average < rhs.scores.average
    }
    bestChannelID = best?.channelID
    bestPressureID = best?.pressureID
    bestScore = best?.scores.average ?? 0
    latestVerdict = sorted.first?.verdict
    failedChannelCount = Set(
      summaries
        .filter { $0.verdict == .wrongChannel || $0.verdict == .tooExpensive || $0.verdict == .ignored }
        .map(\.channelID)
    ).count
    proofDebt = Self.proofDebt(best: best, summaries: summaries)
    nextMove = Self.nextMove(best: best, failedChannelCount: failedChannelCount)
  }

  private static func proofDebt(
    best: DistributionPressureSummary?,
    summaries: [DistributionPressureSummary]
  ) -> MarketProofDebt {
    guard let best else {
      return MarketProofDebt(
        attentionDeficit: 2,
        channelFitDeficit: 2,
        buyerReachabilityDeficit: 2,
        messageClarityDeficit: 2
      )
    }
    return MarketProofDebt(
      attentionDeficit: best.scores.attention >= 4 ? 0 : 1,
      channelFitDeficit: best.scores.channelEconomics >= 3 ? 0 : 1,
      buyerReachabilityDeficit: best.scores.buyerReachability >= 3 ? 0 : 1,
      messageClarityDeficit: best.scores.intentMatch >= 4 && best.scores.differentiation >= 3
        ? 0 : 1
    )
  }

  private static func nextMove(
    best: DistributionPressureSummary?,
    failedChannelCount: Int
  ) -> String {
    guard let best else {
      return "Create and run distribution pressure before declaring a winner."
    }
    switch best.verdict {
    case .getsAttention:
      return "Use this channel proof in the next tournament decision."
    case .needsSharperWedge:
      return "Rewrite the wedge around the buyer's urgent workflow pain."
    case .wrongChannel:
      return "Try a different channel with stronger buyer intent."
    case .tooExpensive:
      return "Find a lower-cost path to the same buyer or narrow the niche."
    case .ignored:
      return failedChannelCount > 1
        ? "Narrow or kill unless a sharper audience can be named."
        : "Rewrite the message and rerun the channel pressure."
    }
  }
}

enum DistributionExperimentBuilderError: LocalizedError, Equatable {
  case missingContender(String)
  case missingMarket(String)
  case missingChannel(String)

  var errorDescription: String? {
    switch self {
    case .missingContender(let id):
      return "No tournament contender exists for \(id)."
    case .missingMarket(let id):
      return "No synthetic market exists for \(id)."
    case .missingChannel(let id):
      return "No acquisition channel exists for \(id)."
    }
  }
}

enum DistributionExperimentBuilder {
  static func build(
    contenderID: String,
    in config: ProductTournamentConfig,
    artifactKind requestedKind: DistributionArtifactKind? = nil,
    now: Date = Date()
  ) throws -> DistributionExperiment {
    guard let contender = config.tournamentContenders.first(where: { $0.id == contenderID }) else {
      throw DistributionExperimentBuilderError.missingContender(contenderID)
    }
    guard let market = market(for: contender, in: config) else {
      throw DistributionExperimentBuilderError.missingMarket(contenderID)
    }
    guard let channel = bestChannel(in: market) else {
      throw DistributionExperimentBuilderError.missingChannel(market.id)
    }
    let targetActor = targetActor(for: contender, market: market)
    let incumbent = market.incumbents.first
    let pain = config.painHypotheses.first(where: { $0.id == market.painID })
    let kind = requestedKind ?? artifactKind(for: channel.kind)
    let artifact = artifactText(
      kind: kind,
      contender: contender,
      market: market,
      pain: pain,
      channel: channel,
      targetActor: targetActor,
      incumbent: incumbent
    )
    let slug = ProductTournamentModelText.slug(
      "\(contender.id)-\(channel.id)-\(kind.rawValue)",
      fallback: "distribution-experiment"
    )
    return DistributionExperiment(
      id: "\(slug)-distribution",
      marketID: market.id,
      contenderID: contender.id,
      channelID: channel.id,
      title: "\(contender.title) \(kind.rawValue.replacingOccurrences(of: "_", with: " ")) test",
      artifactKind: kind,
      artifactText: artifact,
      targetActorID: targetActor?.id,
      successThreshold:
        "Target audience asks to see the workflow proof or can name why the pain is urgent.",
      killCriteria:
        "Audience ignores the message, rejects the channel, or cannot identify a buyer-owned pain.",
      status: .draft,
      createdAt: now.timeIntervalSince1970
    )
  }

  static func rewrite(
    _ experiment: DistributionExperiment,
    using pressure: DistributionPressureRecord,
    now: Date = Date()
  ) -> DistributionExperiment {
    let recommendations =
      pressure.rewriteRecommendations.isEmpty
      ? ["Name the buyer, pain, incumbent, and next proof more concretely."]
      : pressure.rewriteRecommendations
    var next = experiment
    next.id = "\(experiment.id)-rewrite-\(Int(now.timeIntervalSince1970))"
    next.artifactText =
      experiment.artifactText + "\n\nRewrite focus:\n- "
      + recommendations.prefix(4).joined(separator: "\n- ")
    next.status = .draft
    next.updatedAt = now.timeIntervalSince1970
    return next
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

  private static func bestChannel(in market: ProductMarket) -> AcquisitionChannel? {
    market.channels.max { lhs, rhs in
      let lhsScore = lhs.reachability - lhs.costRisk
      let rhsScore = rhs.reachability - rhs.costRisk
      if lhsScore == rhsScore { return lhs.id > rhs.id }
      return lhsScore < rhsScore
    }
  }

  private static func targetActor(
    for contender: ProductTournamentContender,
    market: ProductMarket
  ) -> MarketActor? {
    market.actors.first { actor in
      actor.role == .economicBuyer && actor.segmentID.map(contender.targetSegmentIDs.contains) == true
    } ?? market.actors.first { $0.role == .economicBuyer || $0.role == .managerSponsor }
      ?? market.actors.first { actor in
        actor.segmentID.map(contender.targetSegmentIDs.contains) == true
      }
  }

  private static func artifactKind(for channelKind: AcquisitionChannelKind)
    -> DistributionArtifactKind
  {
    switch channelKind {
    case .coldOutbound: return .coldEmail
    case .seo, .content: return .seoPage
    case .marketplace: return .marketplaceListing
    case .community: return .communityPost
    case .founderLedSales: return .salesScript
    case .openSource: return .openSourceReadme
    case .integrationPartner: return .integrationPitch
    case .templates: return .templateLeadMagnet
    case .paidAds: return .paidAd
    case .existingAudience: return .landingPage
    }
  }

  private static func artifactText(
    kind: DistributionArtifactKind,
    contender: ProductTournamentContender,
    market: ProductMarket,
    pain: PainHypothesis?,
    channel: AcquisitionChannel,
    targetActor: MarketActor?,
    incumbent: IncumbentPressure?
  ) -> String {
    let buyer = targetActor?.name ?? "the buyer"
    let incumbentName = incumbent?.name ?? "the current workaround"
    let proof = channel.proofRequired.first ?? "a short workflow proof"
    let painLine = pain?.rawPain ?? market.summary
    switch kind {
    case .coldEmail:
      return """
        Subject: \(market.category) without the \(incumbentName) drag

        \(buyer), teams keep paying a hidden tax when \(painLine)
        \(contender.title) focuses on one proof: \(contender.valueProposition)
        If this beats \(incumbentName), the next step is a 15 minute workflow review around \(proof).
        """
    case .seoPage:
      return """
        Title: Better \(market.category) than \(incumbentName)
        Meta: Compare \(contender.title) against \(incumbentName) for teams with urgent \(painLine) pain.
        Search intent: \(channel.userIntent)
        Proof: \(proof)
        """
    case .communityPost:
      return """
        Has anyone solved this specific workflow pain?

        We are testing \(contender.title) for \(painLine). The useful part is narrow:
        \(contender.valueProposition)
        The honest comparison is against \(incumbentName), not a blank slate. What would you need to see before trying it?
        """
    case .salesScript:
      return """
        Open with the pain: \(market.summary)
        Ask \(buyer): where does \(incumbentName) fail often enough to matter?
        Pitch \(contender.title): \(contender.valueProposition)
        Close: if \(proof) is credible, should this get a pilot conversation?
        """
    case .openSourceReadme:
      return """
        # \(contender.title)

        A narrow workflow proof for \(market.category), built to show whether it can beat \(incumbentName).
        Try it when \(channel.userIntent)
        Success means: \(proof)
        """
    case .integrationPitch:
      return """
        Partner pitch: \(contender.title) helps your ecosystem users with \(market.category).
        It fits when \(channel.userIntent)
        It wins only if it proves \(proof) and makes \(incumbentName) less attractive.
        """
    case .templateLeadMagnet:
      return """
        Free template: diagnose \(market.category) pain in 10 minutes.
        Step 1: name the recurring failure.
        Step 2: compare against \(incumbentName).
        Step 3: use \(contender.title) when \(proof) matters.
        """
    case .paidAd:
      return """
        Stop losing time to \(market.category).
        \(contender.title): \(contender.valueProposition)
        Compare it with \(incumbentName). See the proof before you switch.
        """
    case .landingPage, .marketplaceListing:
      return """
        \(contender.title)

        For \(buyer) dealing with \(market.category).
        Promise: \(contender.valueProposition)
        Why now: \(market.marketForces.first?.summary ?? market.summary)
        Proof required: \(proof)
        Alternative to beat: \(incumbentName)
        """
    }
  }
}

enum DistributionPressureEvaluator {
  static func evaluate(
    experiment: DistributionExperiment,
    config: ProductTournamentConfig,
    simulatedAudience: String? = nil,
    now: Date = Date()
  ) -> DistributionPressureRecord {
    let market = config.markets.first(where: { $0.id == experiment.marketID })
    let channel = market?.channels.first(where: { $0.id == experiment.channelID })
    let actor = market?.actors.first(where: { $0.id == experiment.targetActorID })
    let text = experiment.artifactText.lowercased()

    let mentionsPain = containsAny(text, words: [market?.category, market?.summary])
    let mentionsBuyer = actor.map { text.contains($0.name.lowercased()) } ?? false
    let mentionsIncumbent =
      (market?.incumbents.contains { text.contains($0.name.lowercased()) } ?? false)
      || containsAny(text, words: ["current workaround", "alternative", "spreadsheet", "manual"])
    let hasCTA = containsAny(
      text,
      words: ["try", "see", "review", "pilot", "conversation", "next step", "compare"]
    )
    let hypePenalty = containsAny(
      text,
      words: ["revolutionary", "game-changing", "world-class", "magic", "disrupt"]
    ) ? 1 : 0
    let textLength = text.split(separator: " ").count
    let vaguePenalty = textLength < 25 || !mentionsPain ? 2 : 0

    let attention = score(
      base: 2 + (mentionsPain ? 1 : 0) + (hasCTA ? 1 : 0) - vaguePenalty - hypePenalty
    )
    let intentMatch = score(
      base: 2 + (mentionsPain ? 1 : 0) + (channel.map { text.contains($0.userIntent.lowercased()) } ?? false ? 1 : 0)
        - vaguePenalty
    )
    let credibility = score(base: 2 + (mentionsIncumbent ? 1 : 0) + (hasCTA ? 1 : 0) - hypePenalty)
    let differentiation = score(base: 2 + (mentionsIncumbent ? 1 : 0) + (mentionsPain ? 1 : 0))
    let buyerReachability = score(
      base: (channel?.reachability ?? 1) + (mentionsBuyer ? 1 : 0) + (actor != nil ? 1 : 0)
        - (channel?.costRisk ?? 3) / 3
    )
    let channelEconomics = score(base: 3 + (channel?.reachability ?? 1) - (channel?.costRisk ?? 3))

    let scores = DistributionScores(
      attention: attention,
      intentMatch: intentMatch,
      credibility: credibility,
      differentiation: differentiation,
      buyerReachability: buyerReachability,
      channelEconomics: channelEconomics
    )
    let verdict = verdict(for: scores, channel: channel)
    return DistributionPressureRecord(
      id:
        "distribution-\(experiment.id)-\(verdict.rawValue)-\(Int(now.timeIntervalSince1970))",
      experimentID: experiment.id,
      marketID: experiment.marketID,
      contenderID: experiment.contenderID,
      channelID: experiment.channelID,
      simulatedAudience: simulatedAudience ?? channel?.audience ?? "Synthetic channel audience",
      verdict: verdict,
      scores: scores,
      objections: objections(verdict: verdict, scores: scores, channel: channel),
      rewriteRecommendations: rewrites(verdict: verdict, scores: scores),
      createdAt: now.timeIntervalSince1970
    )
  }

  private static func verdict(
    for scores: DistributionScores,
    channel: AcquisitionChannel?
  ) -> DistributionVerdict {
    if scores.channelEconomics <= 1 { return .tooExpensive }
    if channel == nil || scores.buyerReachability <= 1 { return .wrongChannel }
    if scores.attention <= 1 || scores.intentMatch <= 1 { return .ignored }
    if scores.attention >= 4 && scores.intentMatch >= 3 && scores.buyerReachability >= 3 {
      return .getsAttention
    }
    return .needsSharperWedge
  }

  private static func objections(
    verdict: DistributionVerdict,
    scores: DistributionScores,
    channel: AcquisitionChannel?
  ) -> [String] {
    var objections: [String] = []
    if scores.attention <= 2 {
      objections.append("The message does not earn attention quickly enough.")
    }
    if scores.intentMatch <= 2 {
      objections.append("The artifact does not match a specific audience intent.")
    }
    if scores.buyerReachability <= 2 {
      objections.append("The channel may not reach the economic buyer.")
    }
    if scores.channelEconomics <= 2 {
      objections.append("The channel may be too expensive for this stage.")
    }
    if verdict == .wrongChannel {
      objections.append("The selected channel is a poor fit for this audience.")
    }
    if objections.isEmpty {
      objections.append(channel?.proofRequired.first ?? "Channel proof is plausible but still synthetic.")
    }
    return objections
  }

  private static func rewrites(
    verdict: DistributionVerdict,
    scores: DistributionScores
  ) -> [String] {
    var rewrites: [String] = []
    if scores.attention < 4 {
      rewrites.append("Lead with the painful workflow moment in the first sentence.")
    }
    if scores.intentMatch < 4 {
      rewrites.append("Name the audience's current intent and what they are comparing against.")
    }
    if scores.buyerReachability < 3 {
      rewrites.append("Aim at a buyer or sponsor who owns the cost of inaction.")
    }
    switch verdict {
    case .getsAttention:
      rewrites.append("Turn this into the next channel proof artifact.")
    case .wrongChannel:
      rewrites.append("Try a channel with clearer buyer intent before building more product.")
    case .tooExpensive:
      rewrites.append("Reduce acquisition cost or narrow to a reachable niche.")
    case .ignored, .needsSharperWedge:
      rewrites.append("Sharpen the wedge before retesting the same channel.")
    }
    return rewrites
  }

  private static func containsAny(_ text: String, words: [String?]) -> Bool {
    words.compactMap { $0?.lowercased() }.contains { word in
      !word.isEmpty && text.contains(word)
    }
  }

  private static func score(base: Int) -> Int {
    min(5, max(0, base))
  }
}

enum DistributionTournamentGate {
  static func winnerBlocker(
    contenderID: String,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String? {
    let experiments = config.distributionExperiments.filter { $0.contenderID == contenderID }
    guard !experiments.isEmpty else {
      return "Winner blocked: create at least one distribution experiment for this contender."
    }
    let summaries = evidenceIndex.distributionPressureSummaries.filter {
      $0.contenderID == contenderID
    }
    guard !summaries.isEmpty else {
      return "Winner blocked: run distribution pressure before declaring a product winner."
    }
    if summaries.contains(where: \.passedChannelProof) {
      return nil
    }
    let proof = DistributionChannelProof(contenderID: contenderID, summaries: summaries)
    return "Winner blocked: channel proof is unresolved. \(proof.nextMove)"
  }

  static func nextMove(
    contenderID: String,
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String {
    if let blocker = winnerBlocker(
      contenderID: contenderID,
      config: config,
      evidenceIndex: evidenceIndex
    ) {
      return blocker
    }
    return "Distribution proof is strong enough to support the next tournament decision."
  }
}

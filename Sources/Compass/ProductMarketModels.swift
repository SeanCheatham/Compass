import Foundation

struct ProductMarket: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var painID: String
  var category: String
  var summary: String
  var marketForces: [MarketForce]
  var actors: [MarketActor]
  var buyingCommittees: [BuyingCommittee]
  var incumbents: [IncumbentPressure]
  var channels: [AcquisitionChannel]
  var budgetModels: [BudgetModel]
  var adoptionTimelines: [AdoptionTimeline]
  var marketProofDebt: MarketProofDebt

  init(
    id: String,
    painID: String,
    category: String,
    summary: String,
    marketForces: [MarketForce] = [],
    actors: [MarketActor] = [],
    buyingCommittees: [BuyingCommittee] = [],
    incumbents: [IncumbentPressure] = [],
    channels: [AcquisitionChannel] = [],
    budgetModels: [BudgetModel] = [],
    adoptionTimelines: [AdoptionTimeline] = [],
    marketProofDebt: MarketProofDebt = .unknown
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "market")
    self.painID = ProductTournamentModelText.identifier(painID, fallback: "pain")
    self.category = ProductTournamentModelText.cleanedText(
      category, fallback: "Synthetic market", limit: 180)
    self.summary = ProductTournamentModelText.cleanedText(
      summary, fallback: "Synthetic market hypothesis for the pain.", limit: 1_000)
    self.marketForces = marketForces
    self.actors = actors
    self.buyingCommittees = buyingCommittees
    self.incumbents = incumbents
    self.channels = channels
    self.budgetModels = budgetModels
    self.adoptionTimelines = adoptionTimelines
    self.marketProofDebt = marketProofDebt
  }
}

struct MarketActor: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var marketID: String
  var segmentID: String?
  var role: MarketActorRole
  var name: String
  var jobToBeDone: String
  var successCriteria: [String]
  var objections: [String]
  var informationSources: [String]
  var trustThreshold: String

  init(
    id: String,
    marketID: String,
    segmentID: String? = nil,
    role: MarketActorRole,
    name: String,
    jobToBeDone: String,
    successCriteria: [String] = [],
    objections: [String] = [],
    informationSources: [String] = [],
    trustThreshold: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "market-actor")
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.segmentID = ProductTournamentModelText.optionalIdentifier(segmentID, fallback: "segment")
    self.role = role
    self.name = ProductTournamentModelText.cleanedText(name, fallback: "Market actor", limit: 160)
    self.jobToBeDone = ProductTournamentModelText.cleanedText(
      jobToBeDone, fallback: "Decide whether the product relieves a real job.", limit: 500)
    self.successCriteria = ProductTournamentModelText.cleanedList(successCriteria, limit: 220)
    self.objections = ProductTournamentModelText.cleanedList(objections, limit: 240)
    self.informationSources = ProductTournamentModelText.cleanedList(
      informationSources, limit: 180)
    self.trustThreshold = ProductTournamentModelText.cleanedText(
      trustThreshold, fallback: "Needs credible proof before changing behavior.", limit: 360)
  }
}

enum MarketActorRole: String, Codable, CaseIterable, Equatable, Sendable {
  case `operator`
  case economicBuyer = "economic_buyer"
  case managerSponsor = "manager_sponsor"
  case technicalGatekeeper = "technical_gatekeeper"
  case procurementGatekeeper = "procurement_gatekeeper"
  case securityReviewer = "security_reviewer"
  case incumbentDefender = "incumbent_defender"
  case channelVisitor = "channel_visitor"
  case churnedUser = "churned_user"
}

struct BuyingCommittee: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var marketID: String
  var name: String
  var actorIDs: [String]
  var decisionProcess: String
  var approvalThreshold: String
  var vetoRisks: [String]

  init(
    id: String,
    marketID: String,
    name: String,
    actorIDs: [String] = [],
    decisionProcess: String,
    approvalThreshold: String,
    vetoRisks: [String] = []
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "buying-committee")
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.name = ProductTournamentModelText.cleanedText(
      name, fallback: "Buying committee", limit: 180)
    self.actorIDs =
      ProductTournamentModelText.cleanedList(actorIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "market-actor") }
    self.decisionProcess = ProductTournamentModelText.cleanedText(
      decisionProcess, fallback: "Committee reviews whether proof justifies a pilot.",
      limit: 600)
    self.approvalThreshold = ProductTournamentModelText.cleanedText(
      approvalThreshold, fallback: "Approval requires buyer, user, and gatekeeper confidence.",
      limit: 400)
    self.vetoRisks = ProductTournamentModelText.cleanedList(vetoRisks, limit: 240)
  }
}

struct IncumbentPressure: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var marketID: String
  var alternativeID: String?
  var name: String
  var category: String
  var whyItWinsToday: [String]
  var switchingMoat: [String]
  var copyRisk: String
  var failureOpening: String

  init(
    id: String,
    marketID: String,
    alternativeID: String? = nil,
    name: String,
    category: String,
    whyItWinsToday: [String] = [],
    switchingMoat: [String] = [],
    copyRisk: String,
    failureOpening: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "incumbent")
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.alternativeID = ProductTournamentModelText.optionalIdentifier(
      alternativeID, fallback: "alternative")
    self.name = ProductTournamentModelText.cleanedText(name, fallback: "Incumbent", limit: 180)
    self.category = ProductTournamentModelText.cleanedText(
      category, fallback: "Current alternative", limit: 180)
    self.whyItWinsToday = ProductTournamentModelText.cleanedList(whyItWinsToday, limit: 240)
    self.switchingMoat = ProductTournamentModelText.cleanedList(switchingMoat, limit: 240)
    self.copyRisk = ProductTournamentModelText.cleanedText(
      copyRisk, fallback: "The incumbent could copy the useful feature.", limit: 400)
    self.failureOpening = ProductTournamentModelText.cleanedText(
      failureOpening, fallback: "The incumbent fails when the pain becomes urgent.", limit: 500)
  }
}

struct AcquisitionChannel: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var marketID: String
  var kind: AcquisitionChannelKind
  var audience: String
  var userIntent: String
  var messageFit: String
  var reachability: Int
  var costRisk: Int
  var proofRequired: [String]

  init(
    id: String,
    marketID: String,
    kind: AcquisitionChannelKind,
    audience: String,
    userIntent: String,
    messageFit: String,
    reachability: Int,
    costRisk: Int,
    proofRequired: [String] = []
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "channel")
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.kind = kind
    self.audience = ProductTournamentModelText.cleanedText(
      audience, fallback: "Audience with the pain", limit: 260)
    self.userIntent = ProductTournamentModelText.cleanedText(
      userIntent, fallback: "Looking for a better way through the workflow.", limit: 360)
    self.messageFit = ProductTournamentModelText.cleanedText(
      messageFit, fallback: "Message must name the painful workflow clearly.", limit: 360)
    self.reachability = Self.score(reachability)
    self.costRisk = Self.score(costRisk)
    self.proofRequired = ProductTournamentModelText.cleanedList(proofRequired, limit: 220)
  }

  private static func score(_ value: Int) -> Int {
    min(5, max(0, value))
  }
}

enum AcquisitionChannelKind: String, Codable, CaseIterable, Equatable, Sendable {
  case founderLedSales = "founder_led_sales"
  case coldOutbound = "cold_outbound"
  case seo
  case marketplace
  case community
  case openSource = "open_source"
  case integrationPartner = "integration_partner"
  case paidAds = "paid_ads"
  case templates
  case content
  case existingAudience = "existing_audience"
}

struct BudgetModel: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var marketID: String
  var buyerActorID: String?
  var budgetSource: String
  var priceToleranceCentsMonthly: Int?
  var procurementThresholdCentsAnnual: Int?
  var roiLogic: String
  var objectionTriggers: [String]

  init(
    id: String,
    marketID: String,
    buyerActorID: String? = nil,
    budgetSource: String,
    priceToleranceCentsMonthly: Int? = nil,
    procurementThresholdCentsAnnual: Int? = nil,
    roiLogic: String,
    objectionTriggers: [String] = []
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "budget")
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.buyerActorID = ProductTournamentModelText.optionalIdentifier(
      buyerActorID, fallback: "market-actor")
    self.budgetSource = ProductTournamentModelText.cleanedText(
      budgetSource, fallback: "Unclear buyer-owned budget", limit: 300)
    self.priceToleranceCentsMonthly = priceToleranceCentsMonthly.map { max(0, $0) }
    self.procurementThresholdCentsAnnual = procurementThresholdCentsAnnual.map { max(0, $0) }
    self.roiLogic = ProductTournamentModelText.cleanedText(
      roiLogic, fallback: "Must reduce enough cost, delay, or risk to justify payment.",
      limit: 500)
    self.objectionTriggers = ProductTournamentModelText.cleanedList(
      objectionTriggers, limit: 220)
  }
}

struct AdoptionTimeline: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var marketID: String
  var name: String
  var stages: [AdoptionStage]

  init(
    id: String,
    marketID: String,
    name: String,
    stages: [AdoptionStage] = []
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "adoption-timeline")
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.name = ProductTournamentModelText.cleanedText(
      name, fallback: "Adoption timeline", limit: 180)
    self.stages = stages
  }
}

struct AdoptionStage: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var dayOffset: Int
  var trigger: String
  var userQuestion: String
  var passSignal: String
  var failSignal: String

  init(
    id: String,
    dayOffset: Int,
    trigger: String,
    userQuestion: String,
    passSignal: String,
    failSignal: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "adoption-stage")
    self.dayOffset = max(0, dayOffset)
    self.trigger = ProductTournamentModelText.cleanedText(
      trigger, fallback: "A market actor encounters the product.", limit: 300)
    self.userQuestion = ProductTournamentModelText.cleanedText(
      userQuestion, fallback: "Is this better than the current alternative?", limit: 300)
    self.passSignal = ProductTournamentModelText.cleanedText(
      passSignal, fallback: "The actor has a concrete reason to continue.", limit: 300)
    self.failSignal = ProductTournamentModelText.cleanedText(
      failSignal, fallback: "The actor stays with the current alternative.", limit: 300)
  }
}

struct MarketForce: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var marketID: String
  var kind: MarketForceKind
  var summary: String
  var strength: Int
  var evidenceBasis: String

  init(
    id: String,
    marketID: String,
    kind: MarketForceKind,
    summary: String,
    strength: Int,
    evidenceBasis: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "market-force")
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.kind = kind
    self.summary = ProductTournamentModelText.cleanedText(
      summary, fallback: "Synthetic market force.", limit: 360)
    self.strength = min(5, max(0, strength))
    self.evidenceBasis = ProductTournamentModelText.cleanedText(
      evidenceBasis, fallback: "Synthetic assumption from provided project context.",
      limit: 360)
  }
}

enum MarketForceKind: String, Codable, CaseIterable, Equatable, Sendable {
  case urgency
  case frequency
  case painCost = "pain_cost"
  case alternativeGravity = "alternative_gravity"
  case budgetClarity = "budget_clarity"
  case channelReachability = "channel_reachability"
  case trustRisk = "trust_risk"
  case switchingCost = "switching_cost"
  case competitiveMoat = "competitive_moat"
}

enum MarketCompilationStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case missing
  case compiled
  case needsReframe = "needs_reframe"
  case blockedByInsufficientPain = "blocked_by_insufficient_pain"
}

extension ProductTournamentConfig {
  var marketCompilationStatus: MarketCompilationStatus {
    if markets.contains(where: { !$0.actors.isEmpty && !$0.incumbents.isEmpty && !$0.channels.isEmpty }) {
      return .compiled
    }
    let hasPain =
      !rawPain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || painHypotheses.contains { $0.status == .active || $0.status == .draft }
    return hasPain ? .missing : .blockedByInsufficientPain
  }
}

struct MarketProofDebt: Codable, Equatable, Sendable {
  var attentionDeficit: Int
  var urgencyDeficit: Int
  var buyerClarityDeficit: Int
  var budgetFitDeficit: Int
  var incumbentDefeatDeficit: Int
  var channelFitDeficit: Int
  var retentionDeficit: Int
  var committeeDeficit: Int

  static let clear = MarketProofDebt()
  static let unknown = MarketProofDebt(
    attentionDeficit: 2,
    urgencyDeficit: 2,
    buyerClarityDeficit: 2,
    budgetFitDeficit: 2,
    incumbentDefeatDeficit: 2,
    channelFitDeficit: 2,
    retentionDeficit: 2,
    committeeDeficit: 2
  )

  init(
    attentionDeficit: Int = 0,
    urgencyDeficit: Int = 0,
    buyerClarityDeficit: Int = 0,
    budgetFitDeficit: Int = 0,
    incumbentDefeatDeficit: Int = 0,
    channelFitDeficit: Int = 0,
    retentionDeficit: Int = 0,
    committeeDeficit: Int = 0
  ) {
    self.attentionDeficit = max(0, attentionDeficit)
    self.urgencyDeficit = max(0, urgencyDeficit)
    self.buyerClarityDeficit = max(0, buyerClarityDeficit)
    self.budgetFitDeficit = max(0, budgetFitDeficit)
    self.incumbentDefeatDeficit = max(0, incumbentDefeatDeficit)
    self.channelFitDeficit = max(0, channelFitDeficit)
    self.retentionDeficit = max(0, retentionDeficit)
    self.committeeDeficit = max(0, committeeDeficit)
  }

  var total: Int {
    attentionDeficit + urgencyDeficit + buyerClarityDeficit + budgetFitDeficit
      + incumbentDefeatDeficit + channelFitDeficit + retentionDeficit + committeeDeficit
  }

  var summary: String {
    let parts = [
      ("attention", attentionDeficit),
      ("urgency", urgencyDeficit),
      ("buyer", buyerClarityDeficit),
      ("budget", budgetFitDeficit),
      ("incumbent", incumbentDefeatDeficit),
      ("channel", channelFitDeficit),
      ("retention", retentionDeficit),
      ("committee", committeeDeficit),
    ]
    .filter { $0.1 > 0 }
    .map { "\($0.0) \($0.1)" }
    return parts.isEmpty ? "clear" : parts.joined(separator: ", ")
  }
}

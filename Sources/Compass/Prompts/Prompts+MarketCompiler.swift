import Foundation

extension Prompts {
  static let marketCompilerPromptVersionID = "market_compiler.synthetic_market.v1"

  static func marketCompilerPrompt(context: DiscoveryPromptContext) throws -> String {
    let digestJSON = try marketCompilerPromptJSON(MarketCompilerPromptDigest(context: context))
    return """
      You are the synthetic Market Compiler for Compass.
      Prompt version: \(marketCompilerPromptVersionID).

      Compile the market before product planning. Do not propose implementation
      work, branches, UI screens, or a final app. Your job is to turn rough pain
      into a falsifiable synthetic market hypothesis.

      Compiler rules:
      - Start with the market, not the product.
      - Separate operator, economic buyer, manager sponsor, gatekeeper, and incumbent defender.
      - Make the current alternative persuasive, including at least one non-software alternative.
      - Name at least one plausible distribution path and why it might be unreachable.
      - Emit distributionExperimentEdits when a contender has a plausible channel artifact to test.
      - Mark every claim as synthetic unless it came from user-provided text.
      - Prefer needs_reframe or blocked_by_insufficient_pain over invented confidence.
      - Contender seeds must reference market actors, likely buyer, channel, and incumbent when known.
      - Required market proof should name attention, urgency, buyer, incumbent, channel, budget, or retention proof.

      Return only JSON matching this schema:
      \(marketCompilerSchema)

      Context:
      ```json
      \(digestJSON)
      ```
      """
  }

  static func decodeMarketCompilerResponse(
    _ json: String,
    currentConfig: ProductTournamentConfig = .empty
  ) throws -> MarketCompilerOutput {
    let data = Data(json.utf8)
    do {
      _ = try marketCompilerTopLevelObject(data)
      let output = try JSONDecoder().decode(MarketCompilerOutput.self, from: data)
      try output.validate(applyingTo: currentConfig)
      return output
    } catch let error as DiscoverPromptValidationError {
      throw error
    } catch let error as DecodingError {
      throw DiscoverPromptValidationError.invalidJSON(String(describing: error))
    } catch {
      throw DiscoverPromptValidationError.invalidJSON(error.localizedDescription)
    }
  }

  private static func marketCompilerPromptJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
  }

  private static func marketCompilerTopLevelObject(_ data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: Any] else {
      throw DiscoverPromptValidationError.invalidJSON("Market compiler response must be a JSON object.")
    }
    return dictionary
  }
}

private struct MarketCompilerPromptDigest: Encodable {
  var promptVersionID: String
  var rawPain: String
  var vision: String
  var drafts: String
  var lessons: String
  var assumptions: String
  var productTournamentDigest: String
  var repositoryShape: String

  init(context: DiscoveryPromptContext) {
    self.promptVersionID = Prompts.marketCompilerPromptVersionID
    rawPain = context.rawPain
    vision = context.vision
    drafts = context.drafts
    lessons = context.lessons
    assumptions = context.assumptions
    productTournamentDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: context.productTournamentConfig,
      evidenceIndex: context.evidenceIndex
    )
    repositoryShape = context.repositoryShape
  }
}

struct MarketCompilerOutput: Codable, Equatable {
  var summary: String
  var status: MarketCompilationStatus
  var marketEdits: [ProductMarket]
  var distributionExperimentEdits: [DistributionExperiment]
  var contenderSeeds: [MarketContenderSeed]
  var openMarketQuestions: [String]
  var fragileAssumptions: [MarketAssumption]

  init(
    summary: String,
    status: MarketCompilationStatus,
    marketEdits: [ProductMarket],
    distributionExperimentEdits: [DistributionExperiment] = [],
    contenderSeeds: [MarketContenderSeed] = [],
    openMarketQuestions: [String] = [],
    fragileAssumptions: [MarketAssumption] = []
  ) {
    self.summary = StringUtils.boundedText(summary, limit: 1_200)
    self.status = status
    self.marketEdits = marketEdits
    self.distributionExperimentEdits = distributionExperimentEdits
    self.contenderSeeds = contenderSeeds
    self.openMarketQuestions = ProductTournamentModelText.cleanedList(
      openMarketQuestions,
      limit: 240
    )
    self.fragileAssumptions = fragileAssumptions
  }

  func applying(to config: ProductTournamentConfig) throws -> ProductTournamentConfig {
    try validate(applyingTo: config)
    var next = config
    upsert(&next.markets, edits: marketEdits, id: \.id)
    upsert(&next.distributionExperiments, edits: distributionExperimentEdits, id: \.id)
    return next
  }

  func validate(applyingTo currentConfig: ProductTournamentConfig) throws {
    guard status != .compiled || !marketEdits.isEmpty else {
      throw DiscoverPromptValidationError.invalidJSON(
        "Compiled market output must include at least one market edit."
      )
    }
    let candidateConfig = try applyingMarketEditsOnly(to: currentConfig)
    try ProductMarketReferenceValidator.validateMarkets(in: candidateConfig)
    try validateContenderSeeds(in: candidateConfig)
  }

  private func applyingMarketEditsOnly(to config: ProductTournamentConfig) throws
    -> ProductTournamentConfig
  {
    var next = config
    upsert(&next.markets, edits: marketEdits, id: \.id)
    upsert(&next.distributionExperiments, edits: distributionExperimentEdits, id: \.id)
    return next
  }

  private func validateContenderSeeds(in config: ProductTournamentConfig) throws {
    let marketsByID = Dictionary(uniqueKeysWithValues: config.markets.map { ($0.id, $0) })
    for seed in contenderSeeds {
      guard let market = marketsByID[seed.marketID] else {
        throw DiscoverPromptValidationError.invalidJSON(
          "Contender seed \(seed.id) references missing market \(seed.marketID)."
        )
      }
      let actorIDs = Set(market.actors.map(\.id))
      for actorID in seed.targetActorIDs where !actorIDs.contains(actorID) {
        throw DiscoverPromptValidationError.invalidJSON(
          "Contender seed \(seed.id) references missing actor \(actorID)."
        )
      }
      if let buyerActorID = seed.likelyBuyerActorID {
        guard let actor = market.actors.first(where: { $0.id == buyerActorID }) else {
          throw DiscoverPromptValidationError.invalidJSON(
            "Contender seed \(seed.id) references missing buyer actor \(buyerActorID)."
          )
        }
        guard actor.role == .economicBuyer || actor.role == .managerSponsor else {
          throw DiscoverPromptValidationError.invalidJSON(
            "Contender seed \(seed.id) buyer actor \(buyerActorID) must be an economic buyer or sponsor."
          )
        }
      }
      if let channelID = seed.likelyChannelID,
        !market.channels.contains(where: { $0.id == channelID })
      {
        throw DiscoverPromptValidationError.invalidJSON(
          "Contender seed \(seed.id) references missing channel \(channelID)."
        )
      }
      if let incumbentID = seed.incumbentToBeatID,
        !market.incumbents.contains(where: { $0.id == incumbentID })
      {
        throw DiscoverPromptValidationError.invalidJSON(
          "Contender seed \(seed.id) references missing incumbent \(incumbentID)."
        )
      }
    }
  }

  private func upsert<T>(
    _ values: inout [T],
    edits: [T],
    id: KeyPath<T, String>
  ) {
    var indicesByID = Dictionary(uniqueKeysWithValues: values.enumerated().map {
      ($0.element[keyPath: id], $0.offset)
    })
    for edit in edits {
      if let index = indicesByID[edit[keyPath: id]] {
        values[index] = edit
      } else {
        indicesByID[edit[keyPath: id]] = values.count
        values.append(edit)
      }
    }
  }
}

struct MarketContenderSeed: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var marketID: String
  var targetActorIDs: [String]
  var promise: String
  var wedge: String
  var likelyBuyerActorID: String?
  var likelyChannelID: String?
  var incumbentToBeatID: String?
  var requiredMarketProof: [String]

  init(
    id: String,
    marketID: String,
    targetActorIDs: [String] = [],
    promise: String,
    wedge: String,
    likelyBuyerActorID: String? = nil,
    likelyChannelID: String? = nil,
    incumbentToBeatID: String? = nil,
    requiredMarketProof: [String] = []
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "contender-seed")
    self.marketID = ProductTournamentModelText.identifier(marketID, fallback: "market")
    self.targetActorIDs =
      ProductTournamentModelText.cleanedList(targetActorIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "market-actor") }
    self.promise = ProductTournamentModelText.cleanedText(
      promise, fallback: "Relieve a specific market pain.", limit: 500)
    self.wedge = ProductTournamentModelText.cleanedText(
      wedge, fallback: "A narrow workflow wedge into the market.", limit: 500)
    self.likelyBuyerActorID = ProductTournamentModelText.optionalIdentifier(
      likelyBuyerActorID, fallback: "market-actor")
    self.likelyChannelID = ProductTournamentModelText.optionalIdentifier(
      likelyChannelID, fallback: "channel")
    self.incumbentToBeatID = ProductTournamentModelText.optionalIdentifier(
      incumbentToBeatID, fallback: "incumbent")
    self.requiredMarketProof = ProductTournamentModelText.cleanedList(
      requiredMarketProof,
      limit: 240
    )
  }
}

struct MarketAssumption: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var marketID: String?
  var text: String
  var fragility: String
  var invalidationSignal: String
  var evidenceBasis: String

  init(
    id: String,
    marketID: String? = nil,
    text: String,
    fragility: String,
    invalidationSignal: String,
    evidenceBasis: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "market-assumption")
    self.marketID = ProductTournamentModelText.optionalIdentifier(marketID, fallback: "market")
    self.text = ProductTournamentModelText.cleanedText(
      text, fallback: "Synthetic market assumption.", limit: 500)
    self.fragility = ProductTournamentModelText.cleanedText(
      fragility, fallback: "Could break the market hypothesis.", limit: 360)
    self.invalidationSignal = ProductTournamentModelText.cleanedText(
      invalidationSignal, fallback: "Evidence that would weaken or kill the assumption.",
      limit: 360)
    self.evidenceBasis = ProductTournamentModelText.cleanedText(
      evidenceBasis, fallback: "Synthetic unless user-provided.", limit: 360)
  }
}

enum ProductMarketReferenceValidator {
  static func validateMarkets(in config: ProductTournamentConfig) throws {
    let painIDs = Set(config.painHypotheses.map(\.id))
    let segmentIDs = Set(config.userSegments.map(\.id))
    let alternativeIDs = Set(config.alternatives.map(\.id))
    let contenderIDs = Set(config.tournamentContenders.map(\.id))
    let marketsByID = Dictionary(uniqueKeysWithValues: config.markets.map { ($0.id, $0) })
    for market in config.markets {
      if !painIDs.isEmpty && !painIDs.contains(market.painID) {
        throw DiscoverPromptValidationError.invalidJSON(
          "Market \(market.id) references missing pain \(market.painID)."
        )
      }
      let actorIDs = Set(market.actors.map(\.id))
      for actor in market.actors {
        guard actor.marketID == market.id else {
          throw DiscoverPromptValidationError.invalidJSON(
            "Market actor \(actor.id) references market \(actor.marketID), expected \(market.id)."
          )
        }
        if let segmentID = actor.segmentID, !segmentIDs.contains(segmentID) {
          throw DiscoverPromptValidationError.invalidJSON(
            "Market actor \(actor.id) references missing segment \(segmentID)."
          )
        }
      }
      for committee in market.buyingCommittees {
        guard committee.marketID == market.id else {
          throw DiscoverPromptValidationError.invalidJSON(
            "Buying committee \(committee.id) references market \(committee.marketID), expected \(market.id)."
          )
        }
        for actorID in committee.actorIDs where !actorIDs.contains(actorID) {
          throw DiscoverPromptValidationError.invalidJSON(
            "Buying committee \(committee.id) references missing actor \(actorID)."
          )
        }
      }
      for incumbent in market.incumbents {
        guard incumbent.marketID == market.id else {
          throw DiscoverPromptValidationError.invalidJSON(
            "Incumbent \(incumbent.id) references market \(incumbent.marketID), expected \(market.id)."
          )
        }
        if let alternativeID = incumbent.alternativeID, !alternativeIDs.contains(alternativeID) {
          throw DiscoverPromptValidationError.invalidJSON(
            "Incumbent \(incumbent.id) references missing alternative \(alternativeID)."
          )
        }
      }
      for channel in market.channels where channel.marketID != market.id {
        throw DiscoverPromptValidationError.invalidJSON(
          "Channel \(channel.id) references market \(channel.marketID), expected \(market.id)."
        )
      }
      for budget in market.budgetModels {
        guard budget.marketID == market.id else {
          throw DiscoverPromptValidationError.invalidJSON(
            "Budget model \(budget.id) references market \(budget.marketID), expected \(market.id)."
          )
        }
        if let buyerActorID = budget.buyerActorID {
          guard let actor = market.actors.first(where: { $0.id == buyerActorID }) else {
            throw DiscoverPromptValidationError.invalidJSON(
              "Budget model \(budget.id) references missing buyer actor \(buyerActorID)."
            )
          }
          guard actor.role == .economicBuyer || actor.role == .managerSponsor else {
            throw DiscoverPromptValidationError.invalidJSON(
              "Budget model \(budget.id) buyer actor \(buyerActorID) must be an economic buyer or sponsor."
            )
          }
        }
      }
      for timeline in market.adoptionTimelines where timeline.marketID != market.id {
        throw DiscoverPromptValidationError.invalidJSON(
          "Adoption timeline \(timeline.id) references market \(timeline.marketID), expected \(market.id)."
        )
      }
      for force in market.marketForces where force.marketID != market.id {
        throw DiscoverPromptValidationError.invalidJSON(
          "Market force \(force.id) references market \(force.marketID), expected \(market.id)."
        )
      }
    }
    for experiment in config.distributionExperiments {
      guard let market = marketsByID[experiment.marketID] else {
        throw DiscoverPromptValidationError.invalidJSON(
          "Distribution experiment \(experiment.id) references missing market \(experiment.marketID)."
        )
      }
      guard contenderIDs.isEmpty || contenderIDs.contains(experiment.contenderID) else {
        throw DiscoverPromptValidationError.invalidJSON(
          "Distribution experiment \(experiment.id) references missing contender \(experiment.contenderID)."
        )
      }
      guard market.channels.contains(where: { $0.id == experiment.channelID }) else {
        throw DiscoverPromptValidationError.invalidJSON(
          "Distribution experiment \(experiment.id) references missing channel \(experiment.channelID)."
        )
      }
      if let targetActorID = experiment.targetActorID,
        !market.actors.contains(where: { $0.id == targetActorID })
      {
        throw DiscoverPromptValidationError.invalidJSON(
          "Distribution experiment \(experiment.id) references missing target actor \(targetActorID)."
        )
      }
    }
    let lifecycleScenarioIDs = Set(config.lifecycleScenarios.map(\.id))
    let lifecycleScenariosByCohortID = Dictionary(grouping: config.lifecycleScenarios) {
      $0.cohortID
    }
    for cohort in config.syntheticCohorts {
      guard let market = marketsByID[cohort.marketID] else {
        throw DiscoverPromptValidationError.invalidJSON(
          "Synthetic cohort \(cohort.id) references missing market \(cohort.marketID)."
        )
      }
      guard contenderIDs.isEmpty || contenderIDs.contains(cohort.contenderID) else {
        throw DiscoverPromptValidationError.invalidJSON(
          "Synthetic cohort \(cohort.id) references missing contender \(cohort.contenderID)."
        )
      }
      guard let timeline = market.adoptionTimelines.first(where: {
        $0.id == cohort.adoptionTimelineID
      }) else {
        throw DiscoverPromptValidationError.invalidJSON(
          "Synthetic cohort \(cohort.id) references missing adoption timeline \(cohort.adoptionTimelineID)."
        )
      }
      let actorIDs = Set(market.actors.map(\.id))
      for actorID in cohort.actorIDs where !actorIDs.contains(actorID) {
        throw DiscoverPromptValidationError.invalidJSON(
          "Synthetic cohort \(cohort.id) references missing actor \(actorID)."
        )
      }
      let stageIDs = Set(timeline.stages.map(\.id))
      for scenarioID in cohort.lifecycleScenarioIDs where !lifecycleScenarioIDs.contains(scenarioID) {
        throw DiscoverPromptValidationError.invalidJSON(
          "Synthetic cohort \(cohort.id) references missing lifecycle scenario \(scenarioID)."
        )
      }
      for scenario in lifecycleScenariosByCohortID[cohort.id] ?? []
      where !stageIDs.contains(scenario.stageID) {
        throw DiscoverPromptValidationError.invalidJSON(
          "Lifecycle scenario \(scenario.id) references missing adoption stage \(scenario.stageID)."
        )
      }
    }
  }
}

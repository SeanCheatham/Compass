import Foundation

extension Prompts {
  static let discoverPromptVersionID = "discover.product_tournament.v1"

  static func discoverPrompt(context: DiscoveryPromptContext) throws -> String {
    let digestJSON = try discoverPromptJSON(DiscoveryPromptDigest(context: context))
    return """
      You are the Discover agent for Compass's pain-driven product tournament loop.
      Prompt version: \(discoverPromptVersionID).

      Turn rough user pain into structured tournament state after the synthetic
      market is compiled and before any implementation work starts. Do not
      create branches, edit project files, or specify a final app as if the
      first idea is guaranteed correct.

      Discovery rules:
      - Start from pain, not a solution.
      - If no market exists, compile the synthetic market first: actors, buyer,
        incumbent/current alternative, channel, budget, adoption path, and
        market proof debt.
      - Name the user segment before naming the app.
      - Describe what users do today, including tools, handoffs, and coping
        mechanisms.
      - Include non-software alternatives such as manual work, spreadsheets,
        internal workarounds, outsourcing, or doing nothing.
      - Generate multiple competing product contenders when the pain is broad.
      - Create a tournament with explicit rounds: Round 0 compiles the
        synthetic market, Round 1 compares product plans with no built product,
        Round 2 proves the core technology, and Round 3 evaluates low-medium
        fidelity product implementations.
      - Make each candidate tournament experiment small enough to become the Round 2 or
        Round 3 Rust desktop track for one contender.
      - Include willingness-to-pay or willingness-to-sponsor signals in the
        tournament evaluation focus when buyer evidence matters.
      - Record unknowns that would materially change the product direction.
      - Use "assumption" for guesses. Do not invent evidence.

      Candidate tournament experiment rules:
      - `candidateTournamentExperiments` are implementation tracks for tournament
        contenders after the plan-only round; do not treat them as Round 1.
        Do not emit them until `stateEdits.markets` or current tournament state
        contains at least one valid synthetic market.
        When a candidate references a contender without a linked tournament
        experiment, Compass will materialize a durable Round 2/Round 3
        implementation track and starter scenario from it during apply when the
        target segment and current workflow can be resolved.
      - `contenderID` must reference a tournament contender in `stateEdits` or current
        tournament state.
      - `branchSlug` must be a single safe git-ref component such as
        `runbook-desk-triage-board`; do not include `refs/`, spaces, or shell
        punctuation.
      - `smallestWorkflowToProve` should name the smallest workflow slice, not
        a full product vision.
      - `expectedEvidenceSignal` should compare pain relief against the current
        alternative.
      - `killCriteria` should describe what would make the contender deserve stopping
        or reframing.

      Return only JSON matching this schema:
      \(discoverSchema)

      Context:
      ```json
      \(digestJSON)
      ```
      """
  }

  static func decodeDiscoverResponse(
    _ json: String,
    currentConfig: ProductTournamentConfig = .empty
  ) throws -> DiscoverPromptOutput {
    let data = Data(json.utf8)
    do {
      _ = try DiscoverPromptJSON.topLevelObject(data)
      let output = try JSONDecoder().decode(DiscoverPromptOutput.self, from: data)
      _ = try output.validatedProductTournamentConfig(applyingTo: currentConfig)
      return output
    } catch let error as DiscoverPromptValidationError {
      throw error
    } catch let error as DecodingError {
      throw DiscoverPromptValidationError.invalidJSON(String(describing: error))
    } catch {
      throw DiscoverPromptValidationError.invalidJSON(error.localizedDescription)
    }
  }

  private static func discoverPromptJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
  }
}

struct DiscoveryPromptContext: Equatable {
  var rawPain: String
  var vision: String
  var drafts: String
  var lessons: String
  var assumptions: String
  var productTournamentConfig: ProductTournamentConfig
  var evidenceIndex: ProductTournamentEvidenceIndex
  var repositoryShape: String

  init(
    rawPain: String,
    vision: String = "",
    drafts: String = "",
    lessons: String = "",
    assumptions: String = "",
    productTournamentConfig: ProductTournamentConfig = .empty,
    evidenceIndex: ProductTournamentEvidenceIndex = .empty,
    repositoryShape: String = ""
  ) {
    self.rawPain = StringUtils.boundedText(rawPain, limit: 4_000)
    self.vision = StringUtils.boundedText(vision, limit: 2_400)
    self.drafts = StringUtils.boundedText(drafts, limit: 2_400)
    self.lessons = StringUtils.boundedText(lessons, limit: 1_800)
    self.assumptions = StringUtils.boundedText(assumptions, limit: 1_800)
    self.productTournamentConfig = productTournamentConfig
    self.evidenceIndex = evidenceIndex
    self.repositoryShape = StringUtils.boundedText(repositoryShape, limit: 1_800)
  }
}

struct DiscoverPromptOutput: Codable, Equatable {
  static let stateEditByteLimit = 60_000

  var summary: String
  var stateEdits: DiscoveryStateEdits
  var candidateTournamentExperiments: [DiscoveryCandidateTournamentExperiment]
  var openQuestions: [String]
  var lessonEdits: [LessonEdit]
  var assumptions: [AssumptionDraft]

  enum CodingKeys: String, CodingKey {
    case summary
    case stateEdits
    case candidateTournamentExperiments
    case openQuestions
    case lessonEdits
    case assumptions
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case candidateExperiments
  }

  init(
    summary: String,
    stateEdits: DiscoveryStateEdits,
    candidateTournamentExperiments: [DiscoveryCandidateTournamentExperiment],
    openQuestions: [String] = [],
    lessonEdits: [LessonEdit] = [],
    assumptions: [AssumptionDraft] = []
  ) {
    self.summary = StringUtils.boundedText(summary, limit: 1_200)
    self.stateEdits = stateEdits
    self.candidateTournamentExperiments = candidateTournamentExperiments.map(\.cleaned)
    self.openQuestions =
      openQuestions
      .map { StringUtils.boundedText($0, limit: 240) }
      .filter { !$0.isEmpty }
    self.lessonEdits = lessonEdits
    self.assumptions = assumptions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
    if legacyContainer.contains(.candidateExperiments) {
      throw DiscoverPromptValidationError.invalidJSON(
        "Use candidateTournamentExperiments instead of candidateExperiments."
      )
    }
    self.init(
      summary: try container.decode(String.self, forKey: .summary),
      stateEdits: try container.decode(DiscoveryStateEdits.self, forKey: .stateEdits),
      candidateTournamentExperiments: try container.decodeIfPresent(
        [DiscoveryCandidateTournamentExperiment].self, forKey: .candidateTournamentExperiments)
        ?? [],
      openQuestions: try container.decodeIfPresent([String].self, forKey: .openQuestions) ?? [],
      lessonEdits: try container.decodeIfPresent([LessonEdit].self, forKey: .lessonEdits) ?? [],
      assumptions: try container.decodeIfPresent([AssumptionDraft].self, forKey: .assumptions)
        ?? []
    )
  }

  func validatedProductTournamentConfig(
    applyingTo currentConfig: ProductTournamentConfig
  ) throws -> ProductTournamentConfig {
    let editData = try JSONEncoder().encode(stateEdits)
    guard editData.count <= Self.stateEditByteLimit else {
      throw DiscoverPromptValidationError.stateUpdateTooLarge(editData.count)
    }

    var config = stateEdits.applying(to: currentConfig)
    let painIDs = Set(config.painHypotheses.map(\.id))
    let activePainIDs = Set(
      config.painHypotheses
        .filter { $0.status == .active }
        .map(\.id)
    )
    guard !activePainIDs.isEmpty else {
      throw DiscoverPromptValidationError.missingActivePainHypothesis
    }

    for workflow in config.currentWorkflows where !painIDs.contains(workflow.painID) {
      throw DiscoverPromptValidationError.workflowReferencesMissingPain(
        workflowID: workflow.id,
        painID: workflow.painID
      )
    }
    for alternative in config.alternatives where !painIDs.contains(alternative.painID) {
      throw DiscoverPromptValidationError.alternativeReferencesMissingPain(
        alternativeID: alternative.id,
        painID: alternative.painID
      )
    }
    for segment in config.userSegments where !painIDs.contains(segment.painID) {
      throw DiscoverPromptValidationError.segmentReferencesMissingPain(
        segmentID: segment.id,
        painID: segment.painID
      )
    }
    for market in config.markets {
      guard painIDs.contains(market.painID) else {
        throw DiscoverPromptValidationError.invalidJSON(
          "Market \(market.id) references missing pain \(market.painID)."
        )
      }
      let marketActorIDs = Set(market.actors.map(\.id))
      let segmentIDs = Set(config.userSegments.map(\.id))
      let alternativeIDs = Set(config.alternatives.map(\.id))
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
        for actorID in committee.actorIDs where !marketActorIDs.contains(actorID) {
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

    let contenderPlanIDs = Set(config.contenderPlans.map(\.id))
    for contenderPlan in config.contenderPlans where !painIDs.contains(contenderPlan.painID) {
      throw DiscoverPromptValidationError.contenderPlanReferencesMissingPain(
        contenderPlanID: contenderPlan.id,
        painID: contenderPlan.painID
      )
    }

    let candidateReferenceContenderIDs = Set(config.tournamentContenders.map(\.id))
    if !candidateTournamentExperiments.isEmpty && config.marketCompilationStatus != .compiled {
      throw DiscoverPromptValidationError.invalidJSON(
        "Candidate tournament experiments require a compiled synthetic market."
      )
    }
    for candidate in candidateTournamentExperiments {
      guard candidateReferenceContenderIDs.contains(candidate.contenderID) else {
        throw DiscoverPromptValidationError.candidateReferencesMissingContender(
          contenderID: candidate.contenderID
        )
      }
      guard DiscoverBranchName.isValidComponent(candidate.branchSlug) else {
        throw DiscoverPromptValidationError.invalidBranchSlug(candidate.branchSlug)
      }
    }

    config = materializingCandidateTournamentExperiments(in: config)

    for experiment in config.tournamentExperiments {
      guard contenderPlanIDs.contains(experiment.contenderPlanID) else {
        throw DiscoverPromptValidationError.experimentReferencesMissingContenderPlan(
          experimentID: experiment.id,
          contenderPlanID: experiment.contenderPlanID
        )
      }
      guard DiscoverBranchName.isValidRef(experiment.branchName) else {
        throw DiscoverPromptValidationError.invalidBranchSlug(experiment.branchName)
      }
    }

    let tournamentIDs = Set(config.tournaments.map(\.id))
    let contenderIDs = Set(config.tournamentContenders.map(\.id))
    let roundIDs = Set(config.tournamentRounds.map(\.id))
    let experimentIDs = Set(config.tournamentExperiments.map(\.id))
    let scenarioCohortIDs = Set(config.scenarioCohorts.map(\.id))
    let marketsByID = Dictionary(uniqueKeysWithValues: config.markets.map { ($0.id, $0) })
    for tournament in config.tournaments {
      guard painIDs.contains(tournament.painID) else {
        throw DiscoverPromptValidationError.tournamentReferencesMissingPain(
          tournamentID: tournament.id,
          painID: tournament.painID
        )
      }
      for contenderID in tournament.contenderIDs where !contenderIDs.contains(contenderID) {
        throw DiscoverPromptValidationError.tournamentReferencesMissingContender(
          tournamentID: tournament.id,
          contenderID: contenderID
        )
      }
      for roundID in tournament.roundIDs where !roundIDs.contains(roundID) {
        throw DiscoverPromptValidationError.tournamentReferencesMissingRound(
          tournamentID: tournament.id,
          roundID: roundID
        )
      }
    }
    for contender in config.tournamentContenders {
      guard tournamentIDs.contains(contender.tournamentID) else {
        throw DiscoverPromptValidationError.contenderReferencesMissingTournament(
          contenderID: contender.id,
          tournamentID: contender.tournamentID
        )
      }
      guard contenderPlanIDs.contains(contender.contenderPlanID) else {
        throw DiscoverPromptValidationError.contenderReferencesMissingContenderPlan(
          contenderID: contender.id,
          contenderPlanID: contender.contenderPlanID
        )
      }
      if let experimentID = contender.experimentID, !experimentIDs.contains(experimentID) {
        throw DiscoverPromptValidationError.contenderReferencesMissingExperiment(
          contenderID: contender.id,
          experimentID: experimentID
        )
      }
    }
    for round in config.tournamentRounds {
      guard tournamentIDs.contains(round.tournamentID) else {
        throw DiscoverPromptValidationError.roundReferencesMissingTournament(
          roundID: round.id,
          tournamentID: round.tournamentID
        )
      }
      for contenderID in round.contenderIDs where !contenderIDs.contains(contenderID) {
        throw DiscoverPromptValidationError.roundReferencesMissingContender(
          roundID: round.id,
          contenderID: contenderID
        )
      }
      for cohortID in round.scenarioCohortIDs where !scenarioCohortIDs.contains(cohortID) {
        throw DiscoverPromptValidationError.roundReferencesMissingCohort(
          roundID: round.id,
          cohortID: cohortID
        )
      }
    }
    for experiment in config.distributionExperiments {
      guard let market = marketsByID[experiment.marketID] else {
        throw DiscoverPromptValidationError.invalidJSON(
          "Distribution experiment \(experiment.id) references missing market \(experiment.marketID)."
        )
      }
      guard contenderIDs.contains(experiment.contenderID) else {
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

    if candidateTournamentExperiments.isEmpty && !openQuestions.isEmpty {
      throw DiscoverPromptValidationError.openQuestionsUsedInsteadOfActionableNextSteps(
        openQuestions[0]
      )
    }
    for question in openQuestions {
      guard DiscoveryOpenQuestion.isActuallyQuestion(question) else {
        throw DiscoverPromptValidationError.openQuestionsUsedInsteadOfActionableNextSteps(question)
      }
    }

    return config
  }

  private func materializingCandidateTournamentExperiments(
    in config: ProductTournamentConfig
  ) -> ProductTournamentConfig {
    guard !candidateTournamentExperiments.isEmpty else { return config }

    var next = config
    var experimentIDs = Set(next.tournamentExperiments.map(\.id))
    var branchNames = Set(next.tournamentExperiments.map(\.branchName))
    var worktreeIDs = Set(next.tournamentExperiments.map(\.worktreeID))
    var cohortIDs = Set(next.scenarioCohorts.map(\.id))
    var scenarioIDs = Set(next.scenarios.map(\.id))
    let timestamp = Self.materializationTimestamp(in: next)

    for candidate in candidateTournamentExperiments {
      guard
        let contenderIndex = next.tournamentContenders.firstIndex(where: {
          $0.id == candidate.contenderID
        })
      else { continue }

      let contender = next.tournamentContenders[contenderIndex]
      if let experimentID = contender.experimentID,
        next.tournamentExperiments.contains(where: { $0.id == experimentID })
      {
        continue
      }

      let branchSlug = ProductTournamentModelText.slug(
        candidate.branchSlug,
        fallback: candidate.implementationName
      )
      let experimentID = Self.reserveUniqueIdentifier(
        preferred: contender.experimentID ?? "experiment-\(branchSlug)",
        fallback: "experiment-\(branchSlug)",
        existing: &experimentIDs
      )
      let branchName = Self.reserveUniqueBranchName(
        component: branchSlug,
        existing: &branchNames
      )
      let worktreeID = Self.reserveUniqueIdentifier(
        preferred: "\(branchSlug)-worktree",
        fallback: "implementation-worktree",
        existing: &worktreeIDs
      )
      let cohortID = Self.reserveUniqueIdentifier(
        preferred: "\(experimentID)-starter-cohort",
        fallback: "\(branchSlug)-cohort",
        existing: &cohortIDs
      )
      let starterScenario = Self.starterScenario(
        for: candidate,
        contender: contender,
        experimentID: experimentID,
        cohortID: cohortID,
        config: next,
        timestamp: timestamp,
        existingScenarioIDs: &scenarioIDs
      )

      next.tournamentExperiments.append(
        ProductTournamentExperiment(
          id: experimentID,
          contenderPlanID: contender.contenderPlanID,
          title: candidate.implementationName,
          branchName: branchName,
          worktreeID: worktreeID,
          baseSha: nil,
          currentSha: nil,
          implementationScope: Self.implementationScope(for: candidate),
          scenarioCohortIDs: [cohortID],
          evidenceSummary:
            "Candidate implementation track from Discover; no evidence recorded yet.",
          decision: .notRun,
          createdAt: timestamp,
          updatedAt: timestamp
        )
      )

      next.scenarioCohorts.append(
        ProductScenarioCohort(
          id: cohortID,
          title: candidate.targetScenarioCohort,
          experimentID: experimentID,
          scenarioIDs: starterScenario.map { [$0.id] } ?? [],
          enabled: true,
          tags: ["discover", "candidate-implementation-track"]
        )
      )
      if let starterScenario {
        next.scenarios.append(starterScenario)
      }

      next.tournamentContenders[contenderIndex].experimentID = experimentID
      next.tournamentContenders[contenderIndex].updatedAt = timestamp

      for roundIndex in next.tournamentRounds.indices
      where next.tournamentRounds[roundIndex].tournamentID == contender.tournamentID
        && next.tournamentRounds[roundIndex].requiresBuiltProduct
        && next.tournamentRounds[roundIndex].contenderIDs.contains(contender.id)
      {
        if !next.tournamentRounds[roundIndex].scenarioCohortIDs.contains(cohortID) {
          next.tournamentRounds[roundIndex].scenarioCohortIDs.append(cohortID)
          next.tournamentRounds[roundIndex].updatedAt = timestamp
        }
      }
    }

    return next
  }

  private static func starterScenario(
    for candidate: DiscoveryCandidateTournamentExperiment,
    contender: ProductTournamentContender,
    experimentID: String,
    cohortID: String,
    config: ProductTournamentConfig,
    timestamp: Double,
    existingScenarioIDs: inout Set<String>
  ) -> ProductScenario? {
    guard
      let contenderPlan = config.contenderPlans.first(where: { $0.id == contender.contenderPlanID }
      ),
      let segment = scenarioSegment(
        for: contender,
        contenderPlan: contenderPlan,
        in: config
      ),
      let workflow = scenarioWorkflow(
        for: segment,
        painID: contenderPlan.painID,
        in: config
      )
    else { return nil }

    let alternative = scenarioAlternative(
      for: segment,
      painID: contenderPlan.painID,
      in: config
    )
    let scenarioID = reserveUniqueIdentifier(
      preferred: "\(experimentID)-starter-scenario",
      fallback: "\(cohortID)-scenario",
      existing: &existingScenarioIDs
    )
    let alternativeComparison =
      alternative.map {
        " Compare it with \($0.title)."
      } ?? " Compare it with the current workaround."
    return ProductScenario(
      id: scenarioID,
      experimentID: experimentID,
      segmentID: segment.id,
      currentWorkflowID: workflow.id,
      alternativeID: alternative?.id,
      title: "\(candidate.implementationName) starter scenario",
      task:
        "Use \(candidate.implementationName) to \(candidate.smallestWorkflowToProve) in the \(workflow.title) workflow.\(alternativeComparison) Decide whether it relieves \(segment.name)'s pain.",
      successSignal: candidate.expectedEvidenceSignal,
      targetCommitSha: nil,
      maxTurns: 8,
      appCommandTimeoutSeconds: 120,
      enabled: true,
      createdAt: timestamp,
      updatedAt: timestamp
    )
  }

  private static func scenarioSegment(
    for contender: ProductTournamentContender,
    contenderPlan: ProductTournamentContenderPlan,
    in config: ProductTournamentConfig
  ) -> UserSegment? {
    let preferredIDs = uniqueIDs(contender.targetSegmentIDs + contenderPlan.targetSegmentIDs)
    if let segment = preferredIDs.compactMap({ segmentID in
      config.userSegments.first { $0.id == segmentID }
    }).first {
      return segment
    }
    return config.userSegments.first { $0.painID == contenderPlan.painID }
      ?? config.userSegments.first
  }

  private static func scenarioWorkflow(
    for segment: UserSegment,
    painID: String,
    in config: ProductTournamentConfig
  ) -> CurrentWorkflow? {
    if let workflow = segment.currentWorkflowIDs.compactMap({ workflowID in
      config.currentWorkflows.first { $0.id == workflowID }
    }).first {
      return workflow
    }
    return config.currentWorkflows.first { $0.painID == painID }
      ?? config.currentWorkflows.first
  }

  private static func scenarioAlternative(
    for segment: UserSegment,
    painID: String,
    in config: ProductTournamentConfig
  ) -> Alternative? {
    if let alternative = segment.alternativeIDs.compactMap({ alternativeID in
      config.alternatives.first { $0.id == alternativeID }
    }).first {
      return alternative
    }
    return config.alternatives.first { $0.painID == painID }
  }

  private static func uniqueIDs(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in values {
      let identifier = ProductTournamentModelText.identifier(value, fallback: "id")
      guard !identifier.isEmpty, seen.insert(identifier).inserted else { continue }
      out.append(identifier)
    }
    return out
  }

  private static func reserveUniqueIdentifier(
    preferred: String,
    fallback: String,
    existing: inout Set<String>
  ) -> String {
    let base = ProductTournamentModelText.identifier(preferred, fallback: fallback)
    var candidate = base
    var suffix = 2
    while existing.contains(candidate) {
      let trimmed = String(base.prefix(90)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
      candidate = "\(trimmed)-\(suffix)"
      suffix += 1
    }
    existing.insert(candidate)
    return candidate
  }

  private static func reserveUniqueBranchName(
    component: String,
    existing: inout Set<String>
  ) -> String {
    let base = ProductTournamentModelText.slug(component, fallback: "implementation")
    var branchName = "codex/\(base)"
    var suffix = 2
    while existing.contains(branchName) {
      let trimmed = String(base.prefix(58)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
      branchName = "codex/\(trimmed)-\(suffix)"
      suffix += 1
    }
    existing.insert(branchName)
    return branchName
  }

  private static func implementationScope(
    for candidate: DiscoveryCandidateTournamentExperiment
  ) -> String {
    StringUtils.boundedText(
      [
        "Build \(candidate.implementationName) as the smallest workflow slice: \(candidate.smallestWorkflowToProve)",
        "Expected evidence: \(candidate.expectedEvidenceSignal)",
        "Kill or reframe if: \(candidate.killCriteria)",
      ].joined(separator: ". "),
      limit: 800
    )
  }

  private static func materializationTimestamp(in config: ProductTournamentConfig) -> Double {
    var timestamps: [Double] = []
    for pain in config.painHypotheses {
      timestamps.append(pain.createdAt)
      timestamps.append(pain.updatedAt)
    }
    for experiment in config.tournamentExperiments {
      timestamps.append(experiment.createdAt)
      timestamps.append(experiment.updatedAt)
    }
    for tournament in config.tournaments {
      timestamps.append(tournament.createdAt)
      timestamps.append(tournament.updatedAt)
    }
    for contender in config.tournamentContenders {
      timestamps.append(contender.createdAt)
      timestamps.append(contender.updatedAt)
    }
    for round in config.tournamentRounds {
      timestamps.append(round.createdAt)
      timestamps.append(round.updatedAt)
    }
    return timestamps.max() ?? 0
  }
}

struct DiscoveryStateEdits: Codable, Equatable {
  var rawPain: String?
  var painHypotheses: [PainHypothesis]
  var userSegments: [UserSegment]
  var currentWorkflows: [CurrentWorkflow]
  var alternatives: [Alternative]
  var markets: [ProductMarket]
  var contenderPlans: [ProductTournamentContenderPlan]
  var tournamentExperiments: [ProductTournamentExperiment]
  var tournaments: [ProductTournament]
  var tournamentContenders: [ProductTournamentContender]
  var tournamentRounds: [ProductTournamentRound]
  var distributionExperiments: [DistributionExperiment]
  var scenarioCohorts: [ProductScenarioCohort]
  var decisions: [ProductTournamentDecision]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case rawPain
    case painHypotheses
    case userSegments
    case currentWorkflows
    case alternatives
    case markets
    case contenderPlans
    case tournamentExperiments
    case tournaments
    case tournamentContenders
    case tournamentRounds
    case distributionExperiments
    case scenarioCohorts
    case decisions
  }

  init(
    rawPain: String? = nil,
    painHypotheses: [PainHypothesis] = [],
    userSegments: [UserSegment] = [],
    currentWorkflows: [CurrentWorkflow] = [],
    alternatives: [Alternative] = [],
    markets: [ProductMarket] = [],
    contenderPlans: [ProductTournamentContenderPlan] = [],
    tournamentExperiments: [ProductTournamentExperiment] = [],
    tournaments: [ProductTournament] = [],
    tournamentContenders: [ProductTournamentContender] = [],
    tournamentRounds: [ProductTournamentRound] = [],
    distributionExperiments: [DistributionExperiment] = [],
    scenarioCohorts: [ProductScenarioCohort] = [],
    decisions: [ProductTournamentDecision] = []
  ) {
    self.rawPain = ProductTournamentModelText.optionalCleanedText(rawPain, limit: 4_000)
    self.painHypotheses = painHypotheses
    self.userSegments = userSegments
    self.currentWorkflows = currentWorkflows
    self.alternatives = alternatives
    self.markets = markets
    self.contenderPlans = contenderPlans
    self.tournamentExperiments = tournamentExperiments
    self.tournaments = tournaments
    self.tournamentContenders = tournamentContenders
    self.tournamentRounds = tournamentRounds
    self.distributionExperiments = distributionExperiments
    self.scenarioCohorts = scenarioCohorts
    self.decisions = decisions
  }

  init(from decoder: Decoder) throws {
    let rawContainer = try decoder.container(keyedBy: ProductTournamentDynamicCodingKey.self)
    let supportedKeys = Set(CodingKeys.allCases.map(\.stringValue))
    if let unsupportedKey = rawContainer.allKeys.first(where: {
      !supportedKeys.contains($0.stringValue)
    }) {
      throw DiscoverPromptValidationError.invalidJSON(
        "Unsupported stateEdits key \(unsupportedKey.stringValue)."
      )
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      rawPain: try container.decodeIfPresent(String.self, forKey: .rawPain),
      painHypotheses: try container.decodeIfPresent([PainHypothesis].self, forKey: .painHypotheses)
        ?? [],
      userSegments: try container.decodeIfPresent([UserSegment].self, forKey: .userSegments) ?? [],
      currentWorkflows: try container.decodeIfPresent(
        [CurrentWorkflow].self, forKey: .currentWorkflows) ?? [],
      alternatives: try container.decodeIfPresent([Alternative].self, forKey: .alternatives) ?? [],
      markets: try container.decodeIfPresent([ProductMarket].self, forKey: .markets) ?? [],
      contenderPlans: try container.decodeIfPresent(
        [ProductTournamentContenderPlan].self, forKey: .contenderPlans) ?? [],
      tournamentExperiments: try container.decodeIfPresent(
        [ProductTournamentExperiment].self, forKey: .tournamentExperiments)
        ?? [],
      tournaments: try container.decodeIfPresent([ProductTournament].self, forKey: .tournaments)
        ?? [],
      tournamentContenders: try container.decodeIfPresent(
        [ProductTournamentContender].self,
        forKey: .tournamentContenders
      ) ?? [],
      tournamentRounds: try container.decodeIfPresent(
        [ProductTournamentRound].self,
        forKey: .tournamentRounds
      ) ?? [],
      distributionExperiments: try container.decodeIfPresent(
        [DistributionExperiment].self,
        forKey: .distributionExperiments
      ) ?? [],
      scenarioCohorts: try container.decodeIfPresent(
        [ProductScenarioCohort].self, forKey: .scenarioCohorts) ?? [],
      decisions: try container.decodeIfPresent(
        [ProductTournamentDecision].self,
        forKey: .decisions
      ) ?? []
    )
  }

  func applying(to config: ProductTournamentConfig) -> ProductTournamentConfig {
    var next = config
    if let rawPain, !rawPain.isEmpty {
      next.rawPain = rawPain
    }
    upsert(&next.painHypotheses, edits: painHypotheses, id: \.id)
    upsert(&next.userSegments, edits: userSegments, id: \.id)
    upsert(&next.currentWorkflows, edits: currentWorkflows, id: \.id)
    upsert(&next.alternatives, edits: alternatives, id: \.id)
    upsert(&next.markets, edits: markets, id: \.id)
    upsert(&next.contenderPlans, edits: contenderPlans, id: \.id)
    upsert(&next.tournamentExperiments, edits: tournamentExperiments, id: \.id)
    upsert(&next.tournaments, edits: tournaments, id: \.id)
    upsert(&next.tournamentContenders, edits: tournamentContenders, id: \.id)
    upsert(&next.tournamentRounds, edits: tournamentRounds, id: \.id)
    upsert(&next.distributionExperiments, edits: distributionExperiments, id: \.id)
    upsert(&next.scenarioCohorts, edits: scenarioCohorts, id: \.id)
    upsert(&next.decisions, edits: decisions, id: \.id)
    return next
  }

  private func upsert<T>(
    _ values: inout [T],
    edits: [T],
    id: KeyPath<T, String>
  ) {
    guard !edits.isEmpty else { return }
    var indicesByID: [String: Int] = [:]
    for (index, value) in values.enumerated() {
      indicesByID[value[keyPath: id]] = index
    }
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

struct DiscoveryCandidateTournamentExperiment: Codable, Equatable {
  var contenderID: String
  var implementationName: String
  var branchSlug: String
  var smallestWorkflowToProve: String
  var targetScenarioCohort: String
  var expectedEvidenceSignal: String
  var killCriteria: String

  enum CodingKeys: String, CodingKey {
    case contenderID
    case implementationName
    case branchSlug
    case smallestWorkflowToProve
    case targetScenarioCohort
    case expectedEvidenceSignal
    case killCriteria
  }

  private enum LegacyCodingKeys: String, CodingKey {
    case contenderPlanID
    case prototypeName
  }

  init(
    contenderID: String,
    implementationName: String,
    branchSlug: String,
    smallestWorkflowToProve: String,
    targetScenarioCohort: String,
    expectedEvidenceSignal: String,
    killCriteria: String
  ) {
    self.contenderID = ProductTournamentModelText.identifier(
      contenderID,
      fallback: "contender"
    )
    self.implementationName = StringUtils.boundedText(implementationName, limit: 160)
    self.branchSlug = StringUtils.boundedText(branchSlug, limit: 120)
    self.smallestWorkflowToProve = StringUtils.boundedText(smallestWorkflowToProve, limit: 500)
    self.targetScenarioCohort = StringUtils.boundedText(targetScenarioCohort, limit: 240)
    self.expectedEvidenceSignal = StringUtils.boundedText(expectedEvidenceSignal, limit: 500)
    self.killCriteria = StringUtils.boundedText(killCriteria, limit: 500)
  }

  init(from decoder: Decoder) throws {
    let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
    if legacyContainer.contains(.contenderPlanID) {
      throw DiscoverPromptValidationError.invalidJSON(
        "Use contenderID instead of contenderPlanID for candidateTournamentExperiments."
      )
    }
    if legacyContainer.contains(.prototypeName) {
      throw DiscoverPromptValidationError.invalidJSON(
        "Use implementationName instead of prototypeName for candidateTournamentExperiments."
      )
    }

    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      contenderID: try container.decode(String.self, forKey: .contenderID),
      implementationName: try container.decode(String.self, forKey: .implementationName),
      branchSlug: try container.decode(String.self, forKey: .branchSlug),
      smallestWorkflowToProve: try container.decode(
        String.self,
        forKey: .smallestWorkflowToProve
      ),
      targetScenarioCohort: try container.decode(String.self, forKey: .targetScenarioCohort),
      expectedEvidenceSignal: try container.decode(String.self, forKey: .expectedEvidenceSignal),
      killCriteria: try container.decode(String.self, forKey: .killCriteria)
    )
  }

  var cleaned: DiscoveryCandidateTournamentExperiment {
    DiscoveryCandidateTournamentExperiment(
      contenderID: contenderID,
      implementationName: implementationName,
      branchSlug: branchSlug,
      smallestWorkflowToProve: smallestWorkflowToProve,
      targetScenarioCohort: targetScenarioCohort,
      expectedEvidenceSignal: expectedEvidenceSignal,
      killCriteria: killCriteria
    )
  }
}

enum DiscoverPromptValidationError: LocalizedError, Equatable {
  case invalidJSON(String)
  case missingActivePainHypothesis
  case workflowReferencesMissingPain(workflowID: String, painID: String)
  case alternativeReferencesMissingPain(alternativeID: String, painID: String)
  case segmentReferencesMissingPain(segmentID: String, painID: String)
  case contenderPlanReferencesMissingPain(contenderPlanID: String, painID: String)
  case experimentReferencesMissingContenderPlan(
    experimentID: String, contenderPlanID: String)
  case tournamentReferencesMissingPain(tournamentID: String, painID: String)
  case tournamentReferencesMissingContender(tournamentID: String, contenderID: String)
  case tournamentReferencesMissingRound(tournamentID: String, roundID: String)
  case contenderReferencesMissingTournament(contenderID: String, tournamentID: String)
  case contenderReferencesMissingContenderPlan(contenderID: String, contenderPlanID: String)
  case contenderReferencesMissingExperiment(contenderID: String, experimentID: String)
  case roundReferencesMissingTournament(roundID: String, tournamentID: String)
  case roundReferencesMissingContender(roundID: String, contenderID: String)
  case roundReferencesMissingCohort(roundID: String, cohortID: String)
  case candidateReferencesMissingContender(contenderID: String)
  case invalidBranchSlug(String)
  case openQuestionsUsedInsteadOfActionableNextSteps(String)
  case stateUpdateTooLarge(Int)

  var errorDescription: String? {
    switch self {
    case .invalidJSON(let message):
      return "Invalid Discover response JSON: \(message)"
    case .missingActivePainHypothesis:
      return "Discover response must leave at least one active pain hypothesis."
    case .workflowReferencesMissingPain(let workflowID, let painID):
      return "Current workflow \(workflowID) references missing pain \(painID)."
    case .alternativeReferencesMissingPain(let alternativeID, let painID):
      return "Alternative \(alternativeID) references missing pain \(painID)."
    case .segmentReferencesMissingPain(let segmentID, let painID):
      return "User segment \(segmentID) references missing pain \(painID)."
    case .contenderPlanReferencesMissingPain(let contenderPlanID, let painID):
      return "Contender plan \(contenderPlanID) references missing pain \(painID)."
    case .experimentReferencesMissingContenderPlan(
      let experimentID, let contenderPlanID):
      return
        "Tournament experiment \(experimentID) references missing contender plan \(contenderPlanID)."
    case .tournamentReferencesMissingPain(let tournamentID, let painID):
      return "Product tournament \(tournamentID) references missing pain \(painID)."
    case .tournamentReferencesMissingContender(let tournamentID, let contenderID):
      return "Product tournament \(tournamentID) references missing contender \(contenderID)."
    case .tournamentReferencesMissingRound(let tournamentID, let roundID):
      return "Product tournament \(tournamentID) references missing round \(roundID)."
    case .contenderReferencesMissingTournament(let contenderID, let tournamentID):
      return "Product contender \(contenderID) references missing tournament \(tournamentID)."
    case .contenderReferencesMissingContenderPlan(let contenderID, let contenderPlanID):
      return
        "Product contender \(contenderID) references missing contender plan \(contenderPlanID)."
    case .contenderReferencesMissingExperiment(let contenderID, let experimentID):
      return "Product contender \(contenderID) references missing experiment \(experimentID)."
    case .roundReferencesMissingTournament(let roundID, let tournamentID):
      return "Product tournament round \(roundID) references missing tournament \(tournamentID)."
    case .roundReferencesMissingContender(let roundID, let contenderID):
      return "Product tournament round \(roundID) references missing contender \(contenderID)."
    case .roundReferencesMissingCohort(let roundID, let cohortID):
      return "Product tournament round \(roundID) references missing scenario cohort \(cohortID)."
    case .candidateReferencesMissingContender(let contenderID):
      return "Candidate tournament experiment references missing contender \(contenderID)."
    case .invalidBranchSlug(let slug):
      return "Invalid discovery branch slug or branch name: \(slug)."
    case .openQuestionsUsedInsteadOfActionableNextSteps(let text):
      return "Discover open question is being used instead of an actionable next step: \(text)."
    case .stateUpdateTooLarge(let byteCount):
      return "Discover state updates are too large (\(byteCount) bytes)."
    }
  }
}

private struct DiscoveryPromptDigest: Encodable {
  var promptVersionID: String
  var rawPain: String
  var vision: String
  var drafts: String
  var lessons: String
  var assumptions: String
  var productTournamentDigest: String
  var repositoryShape: String

  init(context: DiscoveryPromptContext) {
    promptVersionID = Prompts.discoverPromptVersionID
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

private enum DiscoverPromptJSON {
  static func topLevelObject(_ data: Data) throws -> [String: Any] {
    let parsed: Any
    do {
      parsed = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw DiscoverPromptValidationError.invalidJSON(error.localizedDescription)
    }
    guard let object = parsed as? [String: Any] else {
      throw DiscoverPromptValidationError.invalidJSON("Top-level response must be a JSON object.")
    }
    return object
  }
}

private enum DiscoverBranchName {
  static func isValidComponent(_ value: String) -> Bool {
    isValidRef(value) && !value.contains("/")
  }

  static func isValidRef(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed == value, !trimmed.isEmpty, trimmed.count <= 240 else { return false }
    guard !trimmed.hasPrefix("/") && !trimmed.hasSuffix("/") else { return false }
    guard !trimmed.contains("..") && !trimmed.contains("@{") else { return false }
    guard !trimmed.hasSuffix(".") && !trimmed.hasSuffix(".lock") else { return false }
    let forbidden = CharacterSet(charactersIn: #" ~^:?*[\\"#)
    guard trimmed.rangeOfCharacter(from: forbidden) == nil else { return false }
    return trimmed.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component in
      !component.isEmpty && !component.hasPrefix(".") && !component.hasSuffix(".lock")
    }
  }
}

private enum DiscoveryOpenQuestion {
  static func isActuallyQuestion(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasSuffix("?") else { return false }
    let lower = trimmed.lowercased()
    let actionPrefixes = [
      "add ",
      "build ",
      "create ",
      "implement ",
      "run ",
      "ship ",
      "test ",
    ]
    return !actionPrefixes.contains { lower.hasPrefix($0) }
  }
}

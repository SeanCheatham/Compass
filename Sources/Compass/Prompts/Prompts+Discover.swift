import Foundation

extension Prompts {
  static let discoverPromptVersionID = "discover.product_tournament.v1"

  static func discoverPrompt(context: DiscoveryPromptContext) throws -> String {
    let digestJSON = try discoverPromptJSON(DiscoveryPromptDigest(context: context))
    return """
      You are the Discover agent for Compass's pain-driven product tournament loop.
      Prompt version: \(discoverPromptVersionID).

      Turn rough user pain into structured tournament state before any
      implementation work starts. Do not create branches, edit project files,
      or specify a final app as if the first idea is guaranteed correct.

      Discovery rules:
      - Start from pain, not a solution.
      - Name the user segment before naming the app.
      - Describe what users do today, including tools, handoffs, and coping
        mechanisms.
      - Include non-software alternatives such as manual work, spreadsheets,
        internal workarounds, outsourcing, or doing nothing.
      - Generate multiple competing product contenders when the pain is broad.
      - Create a tournament with explicit rounds: Round 1 compares product
        plans with no built product, Round 2 proves the core technology, and
        Round 3 evaluates low-medium fidelity product versions.
      - Make each candidate experiment small enough to become the Round 2 or
        Round 3 Rust desktop track for one contender.
      - Include willingness-to-pay or willingness-to-sponsor signals in the
        tournament evaluation focus when buyer evidence matters.
      - Record unknowns that would materially change the product direction.
      - Use "assumption" for guesses. Do not invent evidence.

      Candidate experiment rules:
      - `candidateExperiments` are implementation tracks for tournament
        contenders after the plan-only round; do not treat them as Round 1.
      - `solutionHypothesisID` must reference a solution in `stateEdits` or
        current tournament state.
      - `branchSlug` must be a single safe git-ref component such as
        `runbook-desk-triage-board`; do not include `refs/`, spaces, or shell
        punctuation.
      - `smallestWorkflowToProve` should name the smallest workflow slice, not
        a full product vision.
      - `expectedEvidenceSignal` should compare pain relief against the current
        alternative.
      - `killCriteria` should describe what would make the bet deserve stopping
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
    currentConfig: ProductizationConfig = .empty
  ) throws -> DiscoverPromptOutput {
    let data = Data(json.utf8)
    do {
      _ = try DiscoverPromptJSON.topLevelObject(data)
      let output = try JSONDecoder().decode(DiscoverPromptOutput.self, from: data)
      _ = try output.validatedProductizationConfig(applyingTo: currentConfig)
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
  var productizationConfig: ProductizationConfig
  var evidenceIndex: ProductTournamentEvidenceIndex
  var repositoryShape: String

  init(
    rawPain: String,
    vision: String = "",
    drafts: String = "",
    lessons: String = "",
    assumptions: String = "",
    productizationConfig: ProductizationConfig = .empty,
    evidenceIndex: ProductTournamentEvidenceIndex = .empty,
    repositoryShape: String = ""
  ) {
    self.rawPain = StringUtils.boundedText(rawPain, limit: 4_000)
    self.vision = StringUtils.boundedText(vision, limit: 2_400)
    self.drafts = StringUtils.boundedText(drafts, limit: 2_400)
    self.lessons = StringUtils.boundedText(lessons, limit: 1_800)
    self.assumptions = StringUtils.boundedText(assumptions, limit: 1_800)
    self.productizationConfig = productizationConfig
    self.evidenceIndex = evidenceIndex
    self.repositoryShape = StringUtils.boundedText(repositoryShape, limit: 1_800)
  }
}

struct DiscoverPromptOutput: Codable, Equatable {
  static let stateEditByteLimit = 60_000

  var summary: String
  var stateEdits: DiscoveryStateEdits
  var candidateExperiments: [DiscoveryCandidateExperiment]
  var openQuestions: [String]
  var lessonEdits: [LessonEdit]
  var assumptions: [AssumptionDraft]

  enum CodingKeys: String, CodingKey {
    case summary
    case stateEdits
    case candidateExperiments
    case openQuestions
    case lessonEdits
    case assumptions
  }

  init(
    summary: String,
    stateEdits: DiscoveryStateEdits,
    candidateExperiments: [DiscoveryCandidateExperiment],
    openQuestions: [String] = [],
    lessonEdits: [LessonEdit] = [],
    assumptions: [AssumptionDraft] = []
  ) {
    self.summary = StringUtils.boundedText(summary, limit: 1_200)
    self.stateEdits = stateEdits
    self.candidateExperiments = candidateExperiments.map(\.cleaned)
    self.openQuestions =
      openQuestions
      .map { StringUtils.boundedText($0, limit: 240) }
      .filter { !$0.isEmpty }
    self.lessonEdits = lessonEdits
    self.assumptions = assumptions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      summary: try container.decode(String.self, forKey: .summary),
      stateEdits: try container.decode(DiscoveryStateEdits.self, forKey: .stateEdits),
      candidateExperiments: try container.decodeIfPresent(
        [DiscoveryCandidateExperiment].self, forKey: .candidateExperiments) ?? [],
      openQuestions: try container.decodeIfPresent([String].self, forKey: .openQuestions) ?? [],
      lessonEdits: try container.decodeIfPresent([LessonEdit].self, forKey: .lessonEdits) ?? [],
      assumptions: try container.decodeIfPresent([AssumptionDraft].self, forKey: .assumptions)
        ?? []
    )
  }

  func validatedProductizationConfig(
    applyingTo currentConfig: ProductizationConfig
  ) throws -> ProductizationConfig {
    let editData = try JSONEncoder().encode(stateEdits)
    guard editData.count <= Self.stateEditByteLimit else {
      throw DiscoverPromptValidationError.stateUpdateTooLarge(editData.count)
    }

    let config = stateEdits.applying(to: currentConfig)
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

    let solutionIDs = Set(config.solutionHypotheses.map(\.id))
    for solution in config.solutionHypotheses where !painIDs.contains(solution.painID) {
      throw DiscoverPromptValidationError.solutionReferencesMissingPain(
        solutionID: solution.id,
        painID: solution.painID
      )
    }
    for experiment in config.experiments {
      guard solutionIDs.contains(experiment.solutionID) else {
        throw DiscoverPromptValidationError.experimentReferencesMissingSolution(
          experimentID: experiment.id,
          solutionID: experiment.solutionID
        )
      }
      guard DiscoverBranchName.isValidRef(experiment.branchName) else {
        throw DiscoverPromptValidationError.invalidBranchSlug(experiment.branchName)
      }
    }

    let tournamentIDs = Set(config.tournaments.map(\.id))
    let contenderIDs = Set(config.tournamentContenders.map(\.id))
    let roundIDs = Set(config.tournamentRounds.map(\.id))
    let experimentIDs = Set(config.experiments.map(\.id))
    let scenarioCohortIDs = Set(config.scenarioCohorts.map(\.id))
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
      guard solutionIDs.contains(contender.solutionID) else {
        throw DiscoverPromptValidationError.contenderReferencesMissingSolution(
          contenderID: contender.id,
          solutionID: contender.solutionID
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
    for candidate in candidateExperiments {
      guard solutionIDs.contains(candidate.solutionHypothesisID) else {
        throw DiscoverPromptValidationError.candidateReferencesMissingSolution(
          solutionID: candidate.solutionHypothesisID
        )
      }
      guard DiscoverBranchName.isValidComponent(candidate.branchSlug) else {
        throw DiscoverPromptValidationError.invalidBranchSlug(candidate.branchSlug)
      }
    }

    if candidateExperiments.isEmpty && !openQuestions.isEmpty {
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
}

struct DiscoveryStateEdits: Codable, Equatable {
  var rawPain: String?
  var painHypotheses: [PainHypothesis]
  var userSegments: [UserSegment]
  var currentWorkflows: [CurrentWorkflow]
  var alternatives: [Alternative]
  var solutionHypotheses: [SolutionHypothesis]
  var experiments: [ProductExperiment]
  var tournaments: [ProductTournament]
  var tournamentContenders: [ProductTournamentContender]
  var tournamentRounds: [ProductTournamentRound]
  var scenarioCohorts: [ProductScenarioCohort]
  var decisions: [ProductDecision]

  enum CodingKeys: String, CodingKey {
    case rawPain
    case painHypotheses
    case userSegments
    case currentWorkflows
    case alternatives
    case solutionHypotheses
    case experiments
    case tournaments
    case tournamentContenders
    case tournamentRounds
    case scenarioCohorts
    case decisions
  }

  init(
    rawPain: String? = nil,
    painHypotheses: [PainHypothesis] = [],
    userSegments: [UserSegment] = [],
    currentWorkflows: [CurrentWorkflow] = [],
    alternatives: [Alternative] = [],
    solutionHypotheses: [SolutionHypothesis] = [],
    experiments: [ProductExperiment] = [],
    tournaments: [ProductTournament] = [],
    tournamentContenders: [ProductTournamentContender] = [],
    tournamentRounds: [ProductTournamentRound] = [],
    scenarioCohorts: [ProductScenarioCohort] = [],
    decisions: [ProductDecision] = []
  ) {
    self.rawPain = ProductTournamentModelText.optionalCleanedText(rawPain, limit: 4_000)
    self.painHypotheses = painHypotheses
    self.userSegments = userSegments
    self.currentWorkflows = currentWorkflows
    self.alternatives = alternatives
    self.solutionHypotheses = solutionHypotheses
    self.experiments = experiments
    self.tournaments = tournaments
    self.tournamentContenders = tournamentContenders
    self.tournamentRounds = tournamentRounds
    self.scenarioCohorts = scenarioCohorts
    self.decisions = decisions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      rawPain: try container.decodeIfPresent(String.self, forKey: .rawPain),
      painHypotheses: try container.decodeIfPresent([PainHypothesis].self, forKey: .painHypotheses)
        ?? [],
      userSegments: try container.decodeIfPresent([UserSegment].self, forKey: .userSegments) ?? [],
      currentWorkflows: try container.decodeIfPresent(
        [CurrentWorkflow].self, forKey: .currentWorkflows) ?? [],
      alternatives: try container.decodeIfPresent([Alternative].self, forKey: .alternatives) ?? [],
      solutionHypotheses: try container.decodeIfPresent(
        [SolutionHypothesis].self, forKey: .solutionHypotheses) ?? [],
      experiments: try container.decodeIfPresent([ProductExperiment].self, forKey: .experiments)
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
      scenarioCohorts: try container.decodeIfPresent(
        [ProductScenarioCohort].self, forKey: .scenarioCohorts) ?? [],
      decisions: try container.decodeIfPresent([ProductDecision].self, forKey: .decisions) ?? []
    )
  }

  func applying(to config: ProductizationConfig) -> ProductizationConfig {
    var next = config
    if let rawPain, !rawPain.isEmpty {
      next.rawPain = rawPain
    }
    upsert(&next.painHypotheses, edits: painHypotheses, id: \.id)
    upsert(&next.userSegments, edits: userSegments, id: \.id)
    upsert(&next.currentWorkflows, edits: currentWorkflows, id: \.id)
    upsert(&next.alternatives, edits: alternatives, id: \.id)
    upsert(&next.solutionHypotheses, edits: solutionHypotheses, id: \.id)
    upsert(&next.experiments, edits: experiments, id: \.id)
    upsert(&next.tournaments, edits: tournaments, id: \.id)
    upsert(&next.tournamentContenders, edits: tournamentContenders, id: \.id)
    upsert(&next.tournamentRounds, edits: tournamentRounds, id: \.id)
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

struct DiscoveryCandidateExperiment: Codable, Equatable {
  var solutionHypothesisID: String
  var prototypeName: String
  var branchSlug: String
  var smallestWorkflowToProve: String
  var targetScenarioCohort: String
  var expectedEvidenceSignal: String
  var killCriteria: String

  enum CodingKeys: String, CodingKey {
    case solutionHypothesisID
    case prototypeName
    case branchSlug
    case smallestWorkflowToProve
    case targetScenarioCohort
    case expectedEvidenceSignal
    case killCriteria
  }

  init(
    solutionHypothesisID: String,
    prototypeName: String,
    branchSlug: String,
    smallestWorkflowToProve: String,
    targetScenarioCohort: String,
    expectedEvidenceSignal: String,
    killCriteria: String
  ) {
    self.solutionHypothesisID = ProductTournamentModelText.identifier(
      solutionHypothesisID,
      fallback: "solution"
    )
    self.prototypeName = StringUtils.boundedText(prototypeName, limit: 160)
    self.branchSlug = StringUtils.boundedText(branchSlug, limit: 120)
    self.smallestWorkflowToProve = StringUtils.boundedText(smallestWorkflowToProve, limit: 500)
    self.targetScenarioCohort = StringUtils.boundedText(targetScenarioCohort, limit: 240)
    self.expectedEvidenceSignal = StringUtils.boundedText(expectedEvidenceSignal, limit: 500)
    self.killCriteria = StringUtils.boundedText(killCriteria, limit: 500)
  }

  var cleaned: DiscoveryCandidateExperiment {
    DiscoveryCandidateExperiment(
      solutionHypothesisID: solutionHypothesisID,
      prototypeName: prototypeName,
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
  case solutionReferencesMissingPain(solutionID: String, painID: String)
  case experimentReferencesMissingSolution(experimentID: String, solutionID: String)
  case tournamentReferencesMissingPain(tournamentID: String, painID: String)
  case tournamentReferencesMissingContender(tournamentID: String, contenderID: String)
  case tournamentReferencesMissingRound(tournamentID: String, roundID: String)
  case contenderReferencesMissingTournament(contenderID: String, tournamentID: String)
  case contenderReferencesMissingSolution(contenderID: String, solutionID: String)
  case contenderReferencesMissingExperiment(contenderID: String, experimentID: String)
  case roundReferencesMissingTournament(roundID: String, tournamentID: String)
  case roundReferencesMissingContender(roundID: String, contenderID: String)
  case roundReferencesMissingCohort(roundID: String, cohortID: String)
  case candidateReferencesMissingSolution(solutionID: String)
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
    case .solutionReferencesMissingPain(let solutionID, let painID):
      return "Solution hypothesis \(solutionID) references missing pain \(painID)."
    case .experimentReferencesMissingSolution(let experimentID, let solutionID):
      return "Product experiment \(experimentID) references missing solution \(solutionID)."
    case .tournamentReferencesMissingPain(let tournamentID, let painID):
      return "Product tournament \(tournamentID) references missing pain \(painID)."
    case .tournamentReferencesMissingContender(let tournamentID, let contenderID):
      return "Product tournament \(tournamentID) references missing contender \(contenderID)."
    case .tournamentReferencesMissingRound(let tournamentID, let roundID):
      return "Product tournament \(tournamentID) references missing round \(roundID)."
    case .contenderReferencesMissingTournament(let contenderID, let tournamentID):
      return "Product contender \(contenderID) references missing tournament \(tournamentID)."
    case .contenderReferencesMissingSolution(let contenderID, let solutionID):
      return "Product contender \(contenderID) references missing solution \(solutionID)."
    case .contenderReferencesMissingExperiment(let contenderID, let experimentID):
      return "Product contender \(contenderID) references missing experiment \(experimentID)."
    case .roundReferencesMissingTournament(let roundID, let tournamentID):
      return "Product tournament round \(roundID) references missing tournament \(tournamentID)."
    case .roundReferencesMissingContender(let roundID, let contenderID):
      return "Product tournament round \(roundID) references missing contender \(contenderID)."
    case .roundReferencesMissingCohort(let roundID, let cohortID):
      return "Product tournament round \(roundID) references missing scenario cohort \(cohortID)."
    case .candidateReferencesMissingSolution(let solutionID):
      return "Candidate experiment references missing solution \(solutionID)."
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
  var productizationDigest: String
  var repositoryShape: String

  init(context: DiscoveryPromptContext) {
    promptVersionID = Prompts.discoverPromptVersionID
    rawPain = context.rawPain
    vision = context.vision
    drafts = context.drafts
    lessons = context.lessons
    assumptions = context.assumptions
    productizationDigest = ProductizationPlanningDigestFormatter.promptText(
      config: context.productizationConfig,
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

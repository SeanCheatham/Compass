import Foundation

struct ProductTournamentConfig: Codable, Equatable, Sendable {
  static let supportedSchemaVersion = 3

  var schemaVersion: Int
  var rawPain: String
  var painHypotheses: [PainHypothesis]
  var userSegments: [UserSegment]
  var currentWorkflows: [CurrentWorkflow]
  var alternatives: [Alternative]
  var contenderPlans: [ProductTournamentContenderPlan]
  var tournamentExperiments: [ProductTournamentExperiment]
  var tournaments: [ProductTournament]
  var tournamentContenders: [ProductTournamentContender]
  var tournamentRounds: [ProductTournamentRound]
  var scenarios: [ProductScenario]
  var scenarioCohorts: [ProductScenarioCohort]
  var decisions: [ProductTournamentDecision]
  var tournamentAutomationCycleAudits: [TournamentAutomationCycleAudit]

  static let empty = ProductTournamentConfig(
    rawPain: "",
    painHypotheses: [],
    userSegments: [],
    currentWorkflows: [],
    alternatives: [],
    contenderPlans: [],
    tournamentExperiments: [],
    tournaments: [],
    tournamentContenders: [],
    tournamentRounds: [],
    scenarios: [],
    scenarioCohorts: [],
    decisions: [],
    tournamentAutomationCycleAudits: []
  )

  enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case rawPain
    case painHypotheses
    case userSegments
    case currentWorkflows
    case alternatives
    case contenderPlans
    case tournamentExperiments
    case tournaments
    case tournamentContenders
    case tournamentRounds
    case scenarios
    case scenarioCohorts
    case decisions
    case tournamentAutomationCycleAudits
  }

  init(
    schemaVersion: Int = Self.supportedSchemaVersion,
    rawPain: String,
    painHypotheses: [PainHypothesis],
    userSegments: [UserSegment],
    currentWorkflows: [CurrentWorkflow],
    alternatives: [Alternative],
    contenderPlans: [ProductTournamentContenderPlan],
    tournamentExperiments: [ProductTournamentExperiment],
    tournaments: [ProductTournament] = [],
    tournamentContenders: [ProductTournamentContender] = [],
    tournamentRounds: [ProductTournamentRound] = [],
    scenarios: [ProductScenario] = [],
    scenarioCohorts: [ProductScenarioCohort] = [],
    decisions: [ProductTournamentDecision] = [],
    tournamentAutomationCycleAudits: [TournamentAutomationCycleAudit] = []
  ) {
    self.schemaVersion = schemaVersion
    self.rawPain = ProductTournamentModelText.cleanedText(rawPain, limit: 4_000)
    self.painHypotheses = painHypotheses
    self.userSegments = userSegments
    self.currentWorkflows = currentWorkflows
    self.alternatives = alternatives
    self.contenderPlans = contenderPlans
    self.tournamentExperiments = tournamentExperiments
    self.tournaments = tournaments
    self.tournamentContenders = tournamentContenders
    self.tournamentRounds = tournamentRounds
    self.scenarios = scenarios
    self.scenarioCohorts = scenarioCohorts
    self.decisions = decisions
    self.tournamentAutomationCycleAudits = tournamentAutomationCycleAudits
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion =
      try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
      ?? Self.supportedSchemaVersion
    guard schemaVersion == Self.supportedSchemaVersion else {
      throw ProductTournamentConfigError.unsupportedSchemaVersion(schemaVersion)
    }
    let rawContainer = try decoder.container(keyedBy: ProductTournamentDynamicCodingKey.self)
    let supportedKeys = Set(CodingKeys.allCases.map(\.stringValue))
    if let unsupportedKey = rawContainer.allKeys.first(where: {
      !supportedKeys.contains($0.stringValue)
    }) {
      throw ProductTournamentConfigError.unsupportedKey(unsupportedKey.stringValue)
    }

    self.init(
      schemaVersion: schemaVersion,
      rawPain: try container.decodeIfPresent(String.self, forKey: .rawPain) ?? "",
      painHypotheses: try container.decodeIfPresent(
        [PainHypothesis].self, forKey: .painHypotheses) ?? [],
      userSegments: try container.decodeIfPresent([UserSegment].self, forKey: .userSegments) ?? [],
      currentWorkflows: try container.decodeIfPresent(
        [CurrentWorkflow].self, forKey: .currentWorkflows) ?? [],
      alternatives: try container.decodeIfPresent([Alternative].self, forKey: .alternatives) ?? [],
      contenderPlans: try container.decodeIfPresent(
        [ProductTournamentContenderPlan].self, forKey: .contenderPlans) ?? [],
      tournamentExperiments: try container.decodeIfPresent([ProductTournamentExperiment].self, forKey: .tournamentExperiments)
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
      scenarios: try container.decodeIfPresent([ProductScenario].self, forKey: .scenarios) ?? [],
      scenarioCohorts: try container.decodeIfPresent(
        [ProductScenarioCohort].self, forKey: .scenarioCohorts) ?? [],
      decisions: try container.decodeIfPresent([ProductTournamentDecision].self, forKey: .decisions)
        ?? [],
      tournamentAutomationCycleAudits: try container.decodeIfPresent(
        [TournamentAutomationCycleAudit].self,
        forKey: .tournamentAutomationCycleAudits
      ) ?? []
    )
  }

  var isEmpty: Bool {
    rawPain.isEmpty
      && painHypotheses.isEmpty
      && userSegments.isEmpty
      && currentWorkflows.isEmpty
      && alternatives.isEmpty
      && contenderPlans.isEmpty
      && tournamentExperiments.isEmpty
      && tournaments.isEmpty
      && tournamentContenders.isEmpty
      && tournamentRounds.isEmpty
      && scenarios.isEmpty
      && scenarioCohorts.isEmpty
      && decisions.isEmpty
      && tournamentAutomationCycleAudits.isEmpty
  }

  func recordingTournamentAutomationCycleAudit(
    _ audit: TournamentAutomationCycleAudit,
    limit: Int = 20
  ) -> ProductTournamentConfig {
    var next = self
    let cappedLimit = max(1, limit)
    next.tournamentAutomationCycleAudits = (next.tournamentAutomationCycleAudits + [audit])
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt > rhs.endedAt
      }
      .prefix(cappedLimit)
      .sorted { lhs, rhs in
        if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
        return lhs.endedAt < rhs.endedAt
      }
    return next
  }

  static func seedDefaults(
    projectTitle: String,
    rawPain: String,
    now: Date = Date()
  ) -> ProductTournamentConfig {
    let timestamp = now.timeIntervalSince1970
    let title = ProductTournamentModelText.cleanedText(projectTitle, fallback: "Project", limit: 120)
    let painText =
      ProductTournamentModelText.firstMeaningfulLine(in: rawPain)
      ?? "\(title) has an unresolved workflow pain that needs product discovery."
    let slug = ProductTournamentModelText.slug(painText, fallback: title)
    let painID = "\(slug)-pain"
    let workflowID = "\(slug)-current-workflow"
    let manualAlternativeID = "\(slug)-manual-alternative"
    let doNothingAlternativeID = "\(slug)-do-nothing"
    let operatorSegmentID = "\(slug)-operator"
    let buyerSegmentID = "\(slug)-buyer"
    let workflowHypothesisID = "\(slug)-workflow-clarifier"
    let proofHypothesisID = "\(slug)-proof-assistant"
    let tournamentID = "\(slug)-tournament"
    let workflowContenderID = "\(slug)-workflow-contender"
    let proofContenderID = "\(slug)-proof-contender"
    let planRoundID = "\(slug)-round-1-plans"
    let feasibilityRoundID = "\(slug)-round-2-feasibility"
    let prototypeRoundID = "\(slug)-round-3-prototype"
    let workflowExperimentID = "\(slug)-workflow-prototype"
    let proofExperimentID = "\(slug)-proof-prototype"
    let workflowOperatorScenarioID = "\(workflowExperimentID)-operator-starter-scenario"
    let workflowBuyerScenarioID = "\(workflowExperimentID)-buyer-starter-scenario"
    let proofOperatorScenarioID = "\(proofExperimentID)-operator-starter-scenario"
    let proofBuyerScenarioID = "\(proofExperimentID)-buyer-starter-scenario"

    let pain = PainHypothesis(
      id: painID,
      title: "\(title) pain hypothesis",
      rawPain: painText,
      targetSituation: "The user is in the workflow described by the project intake.",
      painFrequency: "Unknown frequency; discovery should estimate when and how often it happens.",
      painSeverity: "Unknown severity; assume it is material enough to justify exploration.",
      costOfInaction:
        "The user keeps relying on the current workaround and absorbs the coordination, delay, or rework cost.",
      successSignals: [
        "A target user can name the pain in their own current workflow.",
        "A prototype reduces a concrete step, delay, uncertainty, or handoff cost.",
        "Evidence compares the product contender against the user's actual alternative.",
      ],
      unknowns: [
        "Which user segment feels this pain most acutely?",
        "What current alternative wins today, and why?",
        "Which smallest workflow proof would change the next tournament decision?",
      ],
      status: .active,
      createdAt: timestamp
    )

    let workflow = CurrentWorkflow(
      id: workflowID,
      painID: painID,
      title: "\(title) current workflow",
      steps: [
        "Notice the pain during normal work.",
        "Use the current tool, document, chat thread, or manual process.",
        "Follow up, reconcile missing context, or accept a lower-confidence result.",
      ],
      tools: [
        "Current tool stack from intake",
        "Manual notes, chat, documents, spreadsheets, or memory",
      ],
      handoffs: [
        "Context moves between people or tools without a durable product surface."
      ],
      failureModes: [
        "Important context is missing when the user needs to act.",
        "The workaround consumes time without producing reusable evidence.",
      ],
      workarounds: [
        "Manual checklist",
        "Spreadsheet or shared document",
        "Do nothing until the pain becomes urgent",
      ],
      estimatedCost: "Unquantified; use discovery and evidence runs to estimate."
    )

    let alternatives = [
      Alternative(
        id: manualAlternativeID,
        painID: painID,
        title: "Manual workaround",
        kind: .manual,
        strengths: [
          "Already understood by the user.",
          "No migration or setup required.",
        ],
        weaknesses: [
          "Depends on memory and follow-up.",
          "Hard to evaluate or improve systematically.",
        ],
        switchingCost: "Low short-term cost to keep using it; higher hidden cost over time."
      ),
      Alternative(
        id: doNothingAlternativeID,
        painID: painID,
        title: "Do nothing",
        kind: .doNothing,
        strengths: [
          "No new process to adopt."
        ],
        weaknesses: [
          "Leaves the pain and its recurring cost intact."
        ],
        switchingCost: "Zero immediate switching cost, but the cost of inaction remains."
      ),
    ]

    let userSegments = [
      UserSegment(
        id: operatorSegmentID,
        painID: painID,
        name: "Hands-on operator",
        role: "Primary user responsible for getting through the painful workflow",
        context:
          "Evaluates whether a product contender helps in the moment of work, not just in a pitch.",
        goals: [
          "Reduce the painful step or handoff.",
          "Know what to do next with less rework.",
        ],
        constraints: [
          "Limited time to evaluate new tooling.",
          "Needs proof against the current workaround.",
        ],
        currentWorkflowIDs: [workflowID],
        alternativeIDs: [manualAlternativeID, doNothingAlternativeID],
        decisionCriteria: [
          "Less effort than the current workaround",
          "Clear next action",
          "Trustworthy workflow detail",
        ],
        skepticism: "Will reject a generic app that does not fit the actual pain."
      ),
      UserSegment(
        id: buyerSegmentID,
        painID: painID,
        name: "Budget owner",
        role: "Economic buyer or sponsor",
        context: "Looks for evidence that the pain is worth product investment.",
        goals: [
          "Understand the cost of the pain.",
          "See a credible path from prototype to adoption.",
        ],
        constraints: [
          "Needs ROI or risk reduction before promoting the contender."
        ],
        currentWorkflowIDs: [workflowID],
        alternativeIDs: [manualAlternativeID, doNothingAlternativeID],
        decisionCriteria: [
          "Pain severity",
          "Adoption risk",
          "Evidence quality",
        ],
        skepticism:
          "Treats subjective enthusiasm as weak until paired with concrete workflow proof."
      ),
    ]

    let contenderPlans = [
      ProductTournamentContenderPlan(
        id: workflowHypothesisID,
        painID: painID,
        title: "\(title) workflow clarifier",
        promise: "Make the painful workflow visible, guided, and easier to complete.",
        contenderPlan:
          "A small desktop prototype can reduce confusion by turning the current workaround into explicit steps.",
        targetSegmentIDs: [operatorSegmentID],
        differentiator:
          "Starts from the user's current workflow instead of asking them to adopt a generic planning surface.",
        whyThisCouldWin:
          "The operator may switch if the prototype makes the next action clearer than the manual workaround.",
        whyThisMightFail:
          "The pain may be too context-specific for a lightweight prototype to prove relief.",
        requiredProof: [
          "Persona evidence shows clearer next actions than the current workaround.",
          "The prototype supports at least one real workflow moment end-to-end.",
        ],
        status: .active
      ),
      ProductTournamentContenderPlan(
        id: proofHypothesisID,
        painID: painID,
        title: "\(title) proof assistant",
        promise: "Help the user compare options and produce evidence for a tournament decision.",
        contenderPlan:
          "A prototype that captures assumptions, alternatives, and proof can make product investment decisions sharper.",
        targetSegmentIDs: [operatorSegmentID, buyerSegmentID],
        differentiator:
          "Frames the output as pain-relief evidence rather than a polished app concept.",
        whyThisCouldWin:
          "The buyer may sponsor the direction if evidence is easier to inspect and reuse.",
        whyThisMightFail:
          "The user may need workflow relief more than decision support.",
        requiredProof: [
          "Evidence runs surface specific objections and decision criteria.",
          "The buyer segment can make a clearer continue, pivot, kill, or promote decision.",
        ],
        status: .candidate
      ),
    ]

    let experiments = [
      ProductTournamentExperiment(
        id: workflowExperimentID,
        contenderPlanID: workflowHypothesisID,
        title: "\(title) workflow prototype",
        branchName: "codex/\(slug)-workflow-prototype",
        worktreeID: "\(slug)-workflow-worktree",
        baseSha: nil,
        currentSha: nil,
        prototypeScope:
          "Build the smallest Rust desktop workflow that proves one pain-relief moment.",
        scenarioCohortIDs: ["\(workflowExperimentID)-starter-cohort"],
        evidenceSummary: "No evidence recorded yet.",
        decision: .notRun,
        createdAt: timestamp
      ),
      ProductTournamentExperiment(
        id: proofExperimentID,
        contenderPlanID: proofHypothesisID,
        title: "\(title) proof prototype",
        branchName: "codex/\(slug)-proof-prototype",
        worktreeID: "\(slug)-proof-worktree",
        baseSha: nil,
        currentSha: nil,
        prototypeScope:
          "Build the smallest Rust desktop workflow that captures alternatives, assumptions, and a decision trail.",
        scenarioCohortIDs: ["\(proofExperimentID)-starter-cohort"],
        evidenceSummary: "No evidence recorded yet.",
        decision: .notRun,
        createdAt: timestamp
      ),
    ]

    let scenarios = [
      ProductScenario(
        id: workflowOperatorScenarioID,
        experimentID: workflowExperimentID,
        segmentID: operatorSegmentID,
        currentWorkflowID: workflowID,
        alternativeID: manualAlternativeID,
        title: "\(title) workflow proof",
        task:
          "Try the prototype against the current manual workflow and decide whether it makes the next action clearer.",
        successSignal:
          "The operator can complete one workflow moment with less ambiguity than the manual workaround.",
        targetCommitSha: nil,
        maxTurns: 8,
        appCommandTimeoutSeconds: 120,
        enabled: true,
        createdAt: timestamp
      ),
      ProductScenario(
        id: workflowBuyerScenarioID,
        experimentID: workflowExperimentID,
        segmentID: buyerSegmentID,
        currentWorkflowID: workflowID,
        alternativeID: doNothingAlternativeID,
        title: "\(title) workflow sponsor proof",
        task:
          "Review the workflow prototype as the sponsor and decide whether the evidence justifies more product investment.",
        successSignal:
          "The buyer can explain whether the workflow relief is valuable enough to sponsor.",
        targetCommitSha: nil,
        maxTurns: 8,
        appCommandTimeoutSeconds: 120,
        enabled: true,
        createdAt: timestamp
      ),
      ProductScenario(
        id: proofOperatorScenarioID,
        experimentID: proofExperimentID,
        segmentID: operatorSegmentID,
        currentWorkflowID: workflowID,
        alternativeID: manualAlternativeID,
        title: "\(title) evidence operator proof",
        task:
          "Use the proof assistant during the current workflow and decide whether it makes tournament evidence easier to capture.",
        successSignal:
          "The operator can capture reusable evidence with less rework than the manual workaround.",
        targetCommitSha: nil,
        maxTurns: 8,
        appCommandTimeoutSeconds: 120,
        enabled: true,
        createdAt: timestamp
      ),
      ProductScenario(
        id: proofBuyerScenarioID,
        experimentID: proofExperimentID,
        segmentID: buyerSegmentID,
        currentWorkflowID: workflowID,
        alternativeID: doNothingAlternativeID,
        title: "\(title) decision proof",
        task:
          "Use the prototype to compare the product contender against doing nothing and decide whether evidence is strong enough to continue.",
        successSignal:
          "The buyer can explain the decision criteria and the next tournament decision with reusable evidence.",
        targetCommitSha: nil,
        maxTurns: 8,
        appCommandTimeoutSeconds: 120,
        enabled: true,
        createdAt: timestamp
      ),
    ]

    let cohorts = experiments.map { experiment in
      ProductScenarioCohort(
        id: "\(experiment.id)-starter-cohort",
        title: "\(experiment.title) starter cohort",
        experimentID: experiment.id,
        scenarioIDs:
          scenarios
          .filter { $0.experimentID == experiment.id }
          .map(\.id),
        enabled: true,
        tags: ["seeded", "starter"]
      )
    }

    let contenders = [
      ProductTournamentContender(
        id: workflowContenderID,
        tournamentID: tournamentID,
        contenderPlanID: workflowHypothesisID,
        experimentID: workflowExperimentID,
        title: "\(title) workflow product",
        productPlan:
          "Turn the current workaround into a guided workflow that helps the operator complete one painful moment with less ambiguity.",
        valueProposition:
          "The user gets a clearer next action without adopting a broad product surface.",
        primaryRisk:
          "The workflow may be too context-specific for a reusable product to win against the manual workaround.",
        targetSegmentIDs: [operatorSegmentID],
        status: .competing,
        createdAt: timestamp
      ),
      ProductTournamentContender(
        id: proofContenderID,
        tournamentID: tournamentID,
        contenderPlanID: proofHypothesisID,
        experimentID: proofExperimentID,
        title: "\(title) proof product",
        productPlan:
          "Capture alternatives, assumptions, and proof while the user evaluates what product investment should happen next.",
        valueProposition:
          "The buyer and operator can reuse evidence instead of relying on subjective enthusiasm.",
        primaryRisk:
          "Decision support may feel one step removed from the pain if the user needs direct workflow relief first.",
        targetSegmentIDs: [operatorSegmentID, buyerSegmentID],
        status: .competing,
        createdAt: timestamp
      ),
    ]

    let contenderIDs = contenders.map(\.id)
    let cohortIDs = cohorts.map(\.id)
    let rounds = [
      ProductTournamentRound(
        id: planRoundID,
        tournamentID: tournamentID,
        ordinal: 1,
        kind: .productPlans,
        title: "Round 1: product plans",
        goal:
          "Compare product plans before any implementation exists and ask simulated users which plan best recognizes the pain.",
        evaluationFocus: [
          "Pain recognition",
          "Current alternative comparison",
          "Willingness to pay or sponsor",
        ],
        contenderIDs: contenderIDs,
        scenarioCohortIDs: [],
        status: .active,
        createdAt: timestamp
      ),
      ProductTournamentRound(
        id: feasibilityRoundID,
        tournamentID: tournamentID,
        ordinal: 2,
        kind: .coreTechnology,
        title: "Round 2: core technology",
        goal:
          "Build the smallest feasibility proof for each surviving contender so users can react to whether the hard part works.",
        evaluationFocus: [
          "Technical feasibility",
          "Trust in the core workflow",
          "Evidence that the product can beat the workaround",
        ],
        contenderIDs: contenderIDs,
        scenarioCohortIDs: cohortIDs,
        status: .planned,
        createdAt: timestamp
      ),
      ProductTournamentRound(
        id: prototypeRoundID,
        tournamentID: tournamentID,
        ordinal: 3,
        kind: .prototype,
        title: "Round 3: low-medium fidelity product",
        goal:
          "Let agentic users exercise low-medium fidelity prototype versions and judge adoption, switching, and willingness to pay.",
        evaluationFocus: [
          "Workflow improvement",
          "Switching readiness",
          "Continued-use pull",
        ],
        contenderIDs: contenderIDs,
        scenarioCohortIDs: cohortIDs,
        status: .planned,
        createdAt: timestamp
      ),
    ]

    let tournament = ProductTournament(
      id: tournamentID,
      painID: painID,
      title: "\(title) product tournament",
      premise: painText,
      contenderIDs: contenderIDs,
      roundIDs: rounds.map(\.id),
      currentRoundID: planRoundID,
      status: .active,
      createdAt: timestamp
    )

    return ProductTournamentConfig(
      rawPain: painText,
      painHypotheses: [pain],
      userSegments: userSegments,
      currentWorkflows: [workflow],
      alternatives: alternatives,
      contenderPlans: contenderPlans,
      tournamentExperiments: experiments,
      tournaments: [tournament],
      tournamentContenders: contenders,
      tournamentRounds: rounds,
      scenarios: scenarios,
      scenarioCohorts: cohorts,
      decisions: []
    )
  }
}

struct PainHypothesis: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var title: String
  var rawPain: String
  var targetSituation: String
  var painFrequency: String
  var painSeverity: String
  var costOfInaction: String
  var successSignals: [String]
  var unknowns: [String]
  var status: PainHypothesisStatus
  var createdAt: Double
  var updatedAt: Double

  init(
    id: String,
    title: String,
    rawPain: String,
    targetSituation: String,
    painFrequency: String,
    painSeverity: String,
    costOfInaction: String,
    successSignals: [String] = [],
    unknowns: [String] = [],
    status: PainHypothesisStatus,
    createdAt: Double,
    updatedAt: Double? = nil
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "pain")
    self.title = ProductTournamentModelText.cleanedText(title, fallback: "Pain hypothesis", limit: 180)
    self.rawPain = ProductTournamentModelText.cleanedText(
      rawPain, fallback: "Current workflow pain to explore", limit: 4_000)
    self.targetSituation = ProductTournamentModelText.cleanedText(
      targetSituation, fallback: "The situation where the pain appears", limit: 800)
    self.painFrequency = ProductTournamentModelText.cleanedText(
      painFrequency, fallback: "Unknown frequency", limit: 300)
    self.painSeverity = ProductTournamentModelText.cleanedText(
      painSeverity, fallback: "Unknown severity", limit: 300)
    self.costOfInaction = ProductTournamentModelText.cleanedText(
      costOfInaction, fallback: "The current workaround continues", limit: 800)
    self.successSignals = ProductTournamentModelText.cleanedList(successSignals, limit: 240)
    self.unknowns = ProductTournamentModelText.cleanedList(unknowns, limit: 240)
    self.status = status
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
  }
}

enum PainHypothesisStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case draft
  case active
  case reframed
  case resolved
  case parked
}

struct UserSegment: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var painID: String
  var name: String
  var role: String
  var context: String
  var goals: [String]
  var constraints: [String]
  var currentWorkflowIDs: [String]
  var alternativeIDs: [String]
  var decisionCriteria: [String]
  var skepticism: String

  init(
    id: String,
    painID: String,
    name: String,
    role: String,
    context: String,
    goals: [String] = [],
    constraints: [String] = [],
    currentWorkflowIDs: [String] = [],
    alternativeIDs: [String] = [],
    decisionCriteria: [String] = [],
    skepticism: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "segment")
    self.painID = ProductTournamentModelText.identifier(painID, fallback: "pain")
    self.name = ProductTournamentModelText.cleanedText(name, fallback: "User segment", limit: 160)
    self.role = ProductTournamentModelText.cleanedText(role, fallback: "Target user", limit: 220)
    self.context = ProductTournamentModelText.cleanedText(
      context, fallback: "Experiences the pain in a real workflow", limit: 800)
    self.goals = ProductTournamentModelText.cleanedList(goals, limit: 220)
    self.constraints = ProductTournamentModelText.cleanedList(constraints, limit: 220)
    self.currentWorkflowIDs =
      ProductTournamentModelText.cleanedList(currentWorkflowIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "workflow") }
    self.alternativeIDs =
      ProductTournamentModelText.cleanedList(alternativeIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "alternative") }
    self.decisionCriteria = ProductTournamentModelText.cleanedList(decisionCriteria, limit: 220)
    self.skepticism = ProductTournamentModelText.cleanedText(
      skepticism, fallback: "Needs proof before switching", limit: 500)
  }
}

struct CurrentWorkflow: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var painID: String
  var title: String
  var steps: [String]
  var tools: [String]
  var handoffs: [String]
  var failureModes: [String]
  var workarounds: [String]
  var estimatedCost: String

  init(
    id: String,
    painID: String,
    title: String,
    steps: [String] = [],
    tools: [String] = [],
    handoffs: [String] = [],
    failureModes: [String] = [],
    workarounds: [String] = [],
    estimatedCost: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "workflow")
    self.painID = ProductTournamentModelText.identifier(painID, fallback: "pain")
    self.title = ProductTournamentModelText.cleanedText(
      title, fallback: "Current workflow", limit: 180)
    self.steps = ProductTournamentModelText.cleanedList(steps, limit: 260)
    self.tools = ProductTournamentModelText.cleanedList(tools, limit: 180)
    self.handoffs = ProductTournamentModelText.cleanedList(handoffs, limit: 240)
    self.failureModes = ProductTournamentModelText.cleanedList(failureModes, limit: 260)
    self.workarounds = ProductTournamentModelText.cleanedList(workarounds, limit: 220)
    self.estimatedCost = ProductTournamentModelText.cleanedText(
      estimatedCost, fallback: "Unknown cost", limit: 400)
  }
}

struct Alternative: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var painID: String
  var title: String
  var kind: AlternativeKind
  var strengths: [String]
  var weaknesses: [String]
  var switchingCost: String

  init(
    id: String,
    painID: String,
    title: String,
    kind: AlternativeKind,
    strengths: [String] = [],
    weaknesses: [String] = [],
    switchingCost: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "alternative")
    self.painID = ProductTournamentModelText.identifier(painID, fallback: "pain")
    self.title = ProductTournamentModelText.cleanedText(title, fallback: "Alternative", limit: 180)
    self.kind = kind
    self.strengths = ProductTournamentModelText.cleanedList(strengths, limit: 220)
    self.weaknesses = ProductTournamentModelText.cleanedList(weaknesses, limit: 220)
    self.switchingCost = ProductTournamentModelText.cleanedText(
      switchingCost, fallback: "Unknown switching cost", limit: 400)
  }
}

enum AlternativeKind: String, Codable, CaseIterable, Equatable, Sendable {
  case manual
  case spreadsheet
  case existingTool = "existing_tool"
  case internalWorkaround = "internal_workaround"
  case outsourced
  case doNothing = "do_nothing"
}

struct ProductTournamentContenderPlan: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var painID: String
  var title: String
  var promise: String
  var contenderPlan: String
  var targetSegmentIDs: [String]
  var differentiator: String
  var whyThisCouldWin: String
  var whyThisMightFail: String
  var requiredProof: [String]
  var status: ProductTournamentContenderPlanStatus

  init(
    id: String,
    painID: String,
    title: String,
    promise: String,
    contenderPlan: String,
    targetSegmentIDs: [String] = [],
    differentiator: String,
    whyThisCouldWin: String,
    whyThisMightFail: String,
    requiredProof: [String] = [],
    status: ProductTournamentContenderPlanStatus
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "contender-plan")
    self.painID = ProductTournamentModelText.identifier(painID, fallback: "pain")
    self.title = ProductTournamentModelText.cleanedText(
      title, fallback: "Contender plan", limit: 180)
    self.promise = ProductTournamentModelText.cleanedText(
      promise, fallback: "Relieve the target pain", limit: 500)
    self.contenderPlan = ProductTournamentModelText.cleanedText(
      contenderPlan, fallback: "A prototype can prove pain relief", limit: 700)
    self.targetSegmentIDs =
      ProductTournamentModelText.cleanedList(targetSegmentIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "segment") }
    self.differentiator = ProductTournamentModelText.cleanedText(
      differentiator, fallback: "Different from the current alternative", limit: 500)
    self.whyThisCouldWin = ProductTournamentModelText.cleanedText(
      whyThisCouldWin, fallback: "The target segment may prefer it", limit: 700)
    self.whyThisMightFail = ProductTournamentModelText.cleanedText(
      whyThisMightFail, fallback: "The product contender may not relieve enough pain", limit: 700)
    self.requiredProof = ProductTournamentModelText.cleanedList(requiredProof, limit: 260)
    self.status = status
  }
}

enum ProductTournamentContenderPlanStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case candidate
  case active
  case promoted
  case rejected
  case parked
}

struct ProductTournamentExperiment: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var contenderPlanID: String
  var title: String
  var branchName: String
  var worktreeID: String
  var baseSha: String?
  var currentSha: String?
  var prototypeScope: String
  var scenarioCohortIDs: [String]
  var evidenceSummary: String
  var decision: ProductTournamentExperimentDecision
  var createdAt: Double
  var updatedAt: Double

  init(
    id: String,
    contenderPlanID: String,
    title: String,
    branchName: String,
    worktreeID: String,
    baseSha: String?,
    currentSha: String?,
    prototypeScope: String,
    scenarioCohortIDs: [String] = [],
    evidenceSummary: String,
    decision: ProductTournamentExperimentDecision,
    createdAt: Double,
    updatedAt: Double? = nil
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "experiment")
    self.contenderPlanID = ProductTournamentModelText.identifier(contenderPlanID, fallback: "contender-plan")
    self.title = ProductTournamentModelText.cleanedText(
      title, fallback: "Tournament experiment", limit: 180)
    self.branchName = ProductTournamentModelText.cleanedText(
      branchName, fallback: "codex/product-experiment", limit: 240)
    self.worktreeID = ProductTournamentModelText.identifier(worktreeID, fallback: "worktree")
    self.baseSha = ProductTournamentModelText.optionalCleanedText(baseSha, limit: 80)
    self.currentSha = ProductTournamentModelText.optionalCleanedText(currentSha, limit: 80)
    self.prototypeScope = ProductTournamentModelText.cleanedText(
      prototypeScope, fallback: "Smallest prototype needed for evidence", limit: 800)
    self.scenarioCohortIDs =
      ProductTournamentModelText.cleanedList(scenarioCohortIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "cohort") }
    self.evidenceSummary = ProductTournamentModelText.cleanedText(
      evidenceSummary, fallback: "No evidence recorded yet.", limit: 1_000)
    self.decision = decision
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
  }
}

enum ProductTournamentExperimentDecision: String, Codable, CaseIterable, Equatable, Sendable {
  case notRun = "not_run"
  case keepGoing = "continue"
  case narrow
  case pivot
  case kill
  case promote
  case archived
  case promoted
}

struct ProductTournament: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var painID: String
  var title: String
  var premise: String
  var contenderIDs: [String]
  var roundIDs: [String]
  var currentRoundID: String?
  var status: ProductTournamentStatus
  var createdAt: Double
  var updatedAt: Double

  init(
    id: String,
    painID: String,
    title: String,
    premise: String,
    contenderIDs: [String] = [],
    roundIDs: [String] = [],
    currentRoundID: String? = nil,
    status: ProductTournamentStatus,
    createdAt: Double,
    updatedAt: Double? = nil
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "tournament")
    self.painID = ProductTournamentModelText.identifier(painID, fallback: "pain")
    self.title = ProductTournamentModelText.cleanedText(
      title,
      fallback: "Product tournament",
      limit: 180
    )
    self.premise = ProductTournamentModelText.cleanedText(
      premise,
      fallback: "A user pain worth exploring with competing product plans.",
      limit: 1_000
    )
    self.contenderIDs =
      ProductTournamentModelText.cleanedList(contenderIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "contender") }
    self.roundIDs =
      ProductTournamentModelText.cleanedList(roundIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "round") }
    self.currentRoundID = ProductTournamentModelText.optionalIdentifier(
      currentRoundID,
      fallback: "round"
    )
    self.status = status
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
  }
}

enum ProductTournamentStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case drafting
  case active
  case completed
  case archived
}

struct ProductTournamentContender: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var tournamentID: String
  var contenderPlanID: String
  var experimentID: String?
  var title: String
  var productPlan: String
  var valueProposition: String
  var primaryRisk: String
  var targetSegmentIDs: [String]
  var status: ProductTournamentContenderStatus
  var createdAt: Double
  var updatedAt: Double

  init(
    id: String,
    tournamentID: String,
    contenderPlanID: String,
    experimentID: String? = nil,
    title: String,
    productPlan: String,
    valueProposition: String,
    primaryRisk: String,
    targetSegmentIDs: [String] = [],
    status: ProductTournamentContenderStatus,
    createdAt: Double,
    updatedAt: Double? = nil
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "contender")
    self.tournamentID = ProductTournamentModelText.identifier(tournamentID, fallback: "tournament")
    self.contenderPlanID = ProductTournamentModelText.identifier(contenderPlanID, fallback: "contender-plan")
    self.experimentID = ProductTournamentModelText.optionalIdentifier(
      experimentID,
      fallback: "experiment"
    )
    self.title = ProductTournamentModelText.cleanedText(
      title,
      fallback: "Product contender",
      limit: 180
    )
    self.productPlan = ProductTournamentModelText.cleanedText(
      productPlan,
      fallback: "Plan how this contender will relieve the pain.",
      limit: 1_000
    )
    self.valueProposition = ProductTournamentModelText.cleanedText(
      valueProposition,
      fallback: "Why the user may switch or pay.",
      limit: 700
    )
    self.primaryRisk = ProductTournamentModelText.cleanedText(
      primaryRisk,
      fallback: "Why this contender may lose.",
      limit: 700
    )
    self.targetSegmentIDs =
      ProductTournamentModelText.cleanedList(targetSegmentIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "segment") }
    self.status = status
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
  }
}

enum ProductTournamentContenderStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case competing
  case narrowed
  case needsRevision = "needs_revision"
  case eliminated
  case winner
  case archived
}

struct ProductTournamentRound: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var tournamentID: String
  var ordinal: Int
  var kind: ProductTournamentRoundKind
  var title: String
  var goal: String
  var evaluationFocus: [String]
  var contenderIDs: [String]
  var scenarioCohortIDs: [String]
  var status: ProductTournamentRoundStatus
  var createdAt: Double
  var updatedAt: Double

  var requiresBuiltProduct: Bool {
    kind.requiresBuiltProduct
  }

  init(
    id: String,
    tournamentID: String,
    ordinal: Int,
    kind: ProductTournamentRoundKind,
    title: String,
    goal: String,
    evaluationFocus: [String] = [],
    contenderIDs: [String] = [],
    scenarioCohortIDs: [String] = [],
    status: ProductTournamentRoundStatus,
    createdAt: Double,
    updatedAt: Double? = nil
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "round")
    self.tournamentID = ProductTournamentModelText.identifier(tournamentID, fallback: "tournament")
    self.ordinal = max(1, ordinal)
    self.kind = kind
    self.title = ProductTournamentModelText.cleanedText(
      title,
      fallback: "Tournament round",
      limit: 180
    )
    self.goal = ProductTournamentModelText.cleanedText(
      goal,
      fallback: "Evaluate product contenders against the pain.",
      limit: 1_000
    )
    self.evaluationFocus = ProductTournamentModelText.cleanedList(evaluationFocus, limit: 220)
    self.contenderIDs =
      ProductTournamentModelText.cleanedList(contenderIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "contender") }
    self.scenarioCohortIDs =
      ProductTournamentModelText.cleanedList(scenarioCohortIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "cohort") }
    self.status = status
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
  }
}

enum ProductTournamentRoundKind: String, Codable, CaseIterable, Equatable, Sendable {
  case productPlans = "product_plans"
  case coreTechnology = "core_technology"
  case prototype

  var title: String {
    switch self {
    case .productPlans: return "Product plans"
    case .coreTechnology: return "Core technology"
    case .prototype: return "Prototype"
    }
  }

  var requiresBuiltProduct: Bool {
    switch self {
    case .productPlans:
      return false
    case .coreTechnology, .prototype:
      return true
    }
  }
}

enum ProductTournamentRoundStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case planned
  case active
  case completed
  case skipped
}

struct ProductScenario: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var experimentID: String
  var segmentID: String
  var currentWorkflowID: String
  var alternativeID: String?
  var title: String
  var task: String
  var successSignal: String
  var targetCommitSha: String?
  var maxTurns: Int
  var appCommandTimeoutSeconds: Double
  var enabled: Bool
  var createdAt: Double
  var updatedAt: Double

  init(
    id: String,
    experimentID: String,
    segmentID: String,
    currentWorkflowID: String,
    alternativeID: String? = nil,
    title: String,
    task: String,
    successSignal: String,
    targetCommitSha: String? = nil,
    maxTurns: Int = 8,
    appCommandTimeoutSeconds: Double = 120,
    enabled: Bool = true,
    createdAt: Double,
    updatedAt: Double? = nil
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "scenario")
    self.experimentID = ProductTournamentModelText.identifier(experimentID, fallback: "experiment")
    self.segmentID = ProductTournamentModelText.identifier(segmentID, fallback: "segment")
    self.currentWorkflowID = ProductTournamentModelText.identifier(
      currentWorkflowID,
      fallback: "workflow"
    )
    self.alternativeID = ProductTournamentModelText.optionalIdentifier(
      alternativeID,
      fallback: "alternative"
    )
    self.title = ProductTournamentModelText.cleanedText(
      title,
      fallback: "Product Tournament scenario",
      limit: 180
    )
    self.task = ProductTournamentModelText.cleanedText(
      task,
      fallback: "Try the tournament experiment against the current workflow.",
      limit: 800
    )
    self.successSignal = ProductTournamentModelText.cleanedText(
      successSignal,
      fallback: "The scenario produces evidence for the next tournament decision.",
      limit: 500
    )
    self.targetCommitSha = ProductTournamentModelText.optionalCleanedText(
      targetCommitSha,
      limit: 80
    )
    self.maxTurns = min(20, max(1, maxTurns))
    self.appCommandTimeoutSeconds = min(20 * 60, max(5, appCommandTimeoutSeconds))
    self.enabled = enabled
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
  }
}

struct ProductScenarioCohort: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var title: String
  var experimentID: String
  var scenarioIDs: [String]
  var enabled: Bool
  var tags: [String]

  init(
    id: String,
    title: String,
    experimentID: String,
    scenarioIDs: [String],
    enabled: Bool = true,
    tags: [String] = []
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "cohort")
    self.title = ProductTournamentModelText.cleanedText(
      title, fallback: "Product scenario cohort", limit: 180)
    self.experimentID = ProductTournamentModelText.identifier(experimentID, fallback: "experiment")
    self.scenarioIDs =
      ProductTournamentModelText.cleanedList(scenarioIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "scenario") }
    self.enabled = enabled
    self.tags = ProductTournamentModelText.cleanedList(tags, limit: 80)
  }
}

struct ProductTournamentDecision: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var experimentID: String
  var decision: ProductTournamentExperimentDecision
  var summary: String
  var evidenceRunIDs: [String]
  var branchName: String?
  var beforeSha: String?
  var afterSha: String?
  var decidedAt: Double
  var decidedBy: String

  init(
    id: String,
    experimentID: String,
    decision: ProductTournamentExperimentDecision,
    summary: String,
    evidenceRunIDs: [String] = [],
    branchName: String? = nil,
    beforeSha: String? = nil,
    afterSha: String? = nil,
    decidedAt: Double,
    decidedBy: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "decision")
    self.experimentID = ProductTournamentModelText.identifier(experimentID, fallback: "experiment")
    self.decision = decision
    self.summary = ProductTournamentModelText.cleanedText(
      summary, fallback: "Tournament decision recorded.", limit: 1_000)
    self.evidenceRunIDs =
      ProductTournamentModelText.cleanedList(evidenceRunIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "evidence-run") }
    self.branchName = ProductTournamentModelText.optionalCleanedText(branchName, limit: 240)
    self.beforeSha = ProductTournamentModelText.optionalCleanedText(beforeSha, limit: 80)
    self.afterSha = ProductTournamentModelText.optionalCleanedText(afterSha, limit: 80)
    self.decidedAt = decidedAt
    self.decidedBy = ProductTournamentModelText.cleanedText(
      decidedBy, fallback: "Compass", limit: 120)
  }
}

enum TournamentAutomationCycleAuditStopReason: String, Codable, CaseIterable, Equatable, Sendable {
  case reachedStepLimit = "reached_step_limit"
  case noExecutableStep = "no_executable_step"
  case repeatedStep = "repeated_step"
  case executionFailed = "execution_failed"
}

struct TournamentAutomationCycleAudit: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var startedAt: Double
  var endedAt: Double
  var executedStepIDs: [String]
  var experimentIDs: [String]
  var messages: [String]
  var maxSteps: Int
  var appliedDecisionCount: Int
  var appliedRoundTransitionCount: Int
  var promotedDecisionCount: Int
  var killedDecisionCount: Int
  var targetedPromoteProofCount: Int
  var targetedKillProofCount: Int
  var evidenceRunStepCount: Int
  var evidenceRunIDs: [String]
  var completedEvidenceRunCount: Int
  var failedEvidenceRunCount: Int
  var skippedScenarioCount: Int
  var startingProofDebtCount: Int?
  var endingProofDebtCount: Int?
  var startingProofDebtSummary: String?
  var endingProofDebtSummary: String?
  var startingPersonaModelPlanEvaluationCount: Int?
  var endingPersonaModelPlanEvaluationCount: Int?
  var startingModelFreePlanEvaluationCount: Int?
  var endingModelFreePlanEvaluationCount: Int?
  var decisionCandidateSummaries: [String]
  var evidenceTensionSummaries: [String]
  var proofTargetSummaries: [String]
  var targetedProofOutcomeSummaries: [String]
  var personaRationaleSignalSummaries: [String]
  var revisionBriefSummaries: [String]
  var stopReason: TournamentAutomationCycleAuditStopReason
  var stopStepID: String?
  var stopStepTitle: String?
  var stopDetail: String
  var userMessage: String

  var executedStepCount: Int {
    executedStepIDs.count
  }

  var proofDebtDelta: Int? {
    guard let startingProofDebtCount, let endingProofDebtCount else { return nil }
    return endingProofDebtCount - startingProofDebtCount
  }

  var summary: String {
    let stopTarget = stopStepTitle.map { "; stopped at \($0)" } ?? ""
    let runIDs =
      evidenceRunIDs.isEmpty
      ? ""
      : "; runs \(evidenceRunIDs.prefix(5).joined(separator: ", "))"
    let proofDebt =
      proofDebtSummary.map { "; \($0)" } ?? ""
    let planModes =
      planEvaluationModeSummary.map { "; \($0)" } ?? ""
    let targetedProof =
      targetedPromoteProofCount + targetedKillProofCount > 0
      ? "; targeted proof \(targetedPromoteProofCount) promote, \(targetedKillProofCount) kill"
      : ""
    let roundTransitions =
      appliedRoundTransitionCount > 0
      ? "; round transitions \(appliedRoundTransitionCount)"
      : ""
    let decisionCandidates =
      decisionCandidateSummaries.isEmpty
      ? ""
      : "; candidates \(decisionCandidateSummaries.prefix(3).joined(separator: " | "))"
    let evidenceTensions =
      evidenceTensionSummaries.isEmpty
      ? ""
      : "; tensions \(evidenceTensionSummaries.prefix(3).joined(separator: " | "))"
    let proofTargets =
      proofTargetSummaries.isEmpty
      ? ""
      : "; targets \(proofTargetSummaries.prefix(3).joined(separator: " | "))"
    let targetedOutcomes =
      targetedProofOutcomeSummaries.isEmpty
      ? ""
      : "; targeted outcomes \(targetedProofOutcomeSummaries.prefix(3).joined(separator: " | "))"
    let rationaleSignals =
      personaRationaleSignalSummaries.isEmpty
      ? ""
      : "; rationale signals \(personaRationaleSignalSummaries.prefix(3).joined(separator: " | "))"
    let revisionBriefs =
      revisionBriefSummaries.isEmpty
      ? ""
      : "; revisions \(revisionBriefSummaries.prefix(3).joined(separator: " | "))"
    return
      "\(executedStepCount) step(s); decisions \(appliedDecisionCount) (\(promotedDecisionCount) promote, \(killedDecisionCount) kill)\(roundTransitions)\(targetedProof); evidence \(evidenceRunStepCount) step(s), \(completedEvidenceRunCount) completed run(s), \(failedEvidenceRunCount) needing review, \(skippedScenarioCount) skipped\(runIDs)\(proofDebt)\(planModes)\(decisionCandidates)\(evidenceTensions)\(proofTargets)\(targetedOutcomes)\(rationaleSignals)\(revisionBriefs); \(stopReason.rawValue)\(stopTarget); \(stopDetail)"
  }

  var planEvaluationModeContext: String? {
    guard hasPlanEvaluationModeCounts else { return nil }
    return
      "plan_modes start_persona_model \(startingPersonaModelPlanEvaluationCount ?? 0) start_model_free \(startingModelFreePlanEvaluationCount ?? 0) end_persona_model \(endingPersonaModelPlanEvaluationCount ?? 0) end_model_free \(endingModelFreePlanEvaluationCount ?? 0)"
  }

  private var proofDebtSummary: String? {
    guard let startingProofDebtCount, let endingProofDebtCount, let proofDebtDelta else {
      return nil
    }
    let sign = proofDebtDelta > 0 ? "+" : ""
    return
      "proof debt \(startingProofDebtCount) -> \(endingProofDebtCount) (\(sign)\(proofDebtDelta))"
  }

  private var planEvaluationModeSummary: String? {
    guard hasPlanEvaluationModeCounts else { return nil }
    return
      "plan modes persona-model \(startingPersonaModelPlanEvaluationCount ?? 0) -> \(endingPersonaModelPlanEvaluationCount ?? 0), model-free \(startingModelFreePlanEvaluationCount ?? 0) -> \(endingModelFreePlanEvaluationCount ?? 0)"
  }

  private var hasPlanEvaluationModeCounts: Bool {
    startingPersonaModelPlanEvaluationCount != nil
      || endingPersonaModelPlanEvaluationCount != nil
      || startingModelFreePlanEvaluationCount != nil
      || endingModelFreePlanEvaluationCount != nil
  }

  init(
    id: String,
    startedAt: Double,
    endedAt: Double,
    executedStepIDs: [String],
    experimentIDs: [String],
    messages: [String],
    maxSteps: Int,
    appliedDecisionCount: Int = 0,
    appliedRoundTransitionCount: Int = 0,
    promotedDecisionCount: Int = 0,
    killedDecisionCount: Int = 0,
    targetedPromoteProofCount: Int = 0,
    targetedKillProofCount: Int = 0,
    evidenceRunStepCount: Int = 0,
    evidenceRunIDs: [String] = [],
    completedEvidenceRunCount: Int = 0,
    failedEvidenceRunCount: Int = 0,
    skippedScenarioCount: Int = 0,
    startingProofDebtCount: Int? = nil,
    endingProofDebtCount: Int? = nil,
    startingProofDebtSummary: String? = nil,
    endingProofDebtSummary: String? = nil,
    startingPersonaModelPlanEvaluationCount: Int? = nil,
    endingPersonaModelPlanEvaluationCount: Int? = nil,
    startingModelFreePlanEvaluationCount: Int? = nil,
    endingModelFreePlanEvaluationCount: Int? = nil,
    decisionCandidateSummaries: [String] = [],
    evidenceTensionSummaries: [String] = [],
    proofTargetSummaries: [String] = [],
    targetedProofOutcomeSummaries: [String] = [],
    personaRationaleSignalSummaries: [String] = [],
    revisionBriefSummaries: [String] = [],
    stopReason: TournamentAutomationCycleAuditStopReason,
    stopStepID: String? = nil,
    stopStepTitle: String? = nil,
    stopDetail: String,
    userMessage: String
  ) {
    self.id = ProductTournamentModelText.identifier(id, fallback: "tournament-cycle-audit")
    self.startedAt = startedAt
    self.endedAt = max(startedAt, endedAt)
    self.executedStepIDs = ProductTournamentModelText.cleanedList(executedStepIDs, limit: 260)
    self.experimentIDs =
      ProductTournamentModelText.cleanedList(experimentIDs, limit: 120)
      .map { ProductTournamentModelText.identifier($0, fallback: "experiment") }
    self.messages = ProductTournamentModelText.cleanedList(messages, limit: 500)
    self.maxSteps = max(1, maxSteps)
    self.appliedDecisionCount = max(0, appliedDecisionCount)
    self.appliedRoundTransitionCount = max(0, appliedRoundTransitionCount)
    self.promotedDecisionCount = max(0, promotedDecisionCount)
    self.killedDecisionCount = max(0, killedDecisionCount)
    self.targetedPromoteProofCount = max(0, targetedPromoteProofCount)
    self.targetedKillProofCount = max(0, targetedKillProofCount)
    self.evidenceRunStepCount = max(0, evidenceRunStepCount)
    self.evidenceRunIDs = ProductTournamentModelText.cleanedList(evidenceRunIDs, limit: 120)
    self.completedEvidenceRunCount = max(0, completedEvidenceRunCount)
    self.failedEvidenceRunCount = max(0, failedEvidenceRunCount)
    self.skippedScenarioCount = max(0, skippedScenarioCount)
    self.startingProofDebtCount = startingProofDebtCount.map { max(0, $0) }
    self.endingProofDebtCount = endingProofDebtCount.map { max(0, $0) }
    self.startingProofDebtSummary = ProductTournamentModelText.optionalCleanedText(
      startingProofDebtSummary,
      limit: 500
    )
    self.endingProofDebtSummary = ProductTournamentModelText.optionalCleanedText(
      endingProofDebtSummary,
      limit: 500
    )
    self.startingPersonaModelPlanEvaluationCount =
      startingPersonaModelPlanEvaluationCount.map { max(0, $0) }
    self.endingPersonaModelPlanEvaluationCount =
      endingPersonaModelPlanEvaluationCount.map { max(0, $0) }
    self.startingModelFreePlanEvaluationCount =
      startingModelFreePlanEvaluationCount.map { max(0, $0) }
    self.endingModelFreePlanEvaluationCount =
      endingModelFreePlanEvaluationCount.map { max(0, $0) }
    self.decisionCandidateSummaries = ProductTournamentModelText.cleanedList(
      decisionCandidateSummaries,
      limit: 300
    )
    self.evidenceTensionSummaries = ProductTournamentModelText.cleanedList(
      evidenceTensionSummaries,
      limit: 360
    )
    self.proofTargetSummaries = ProductTournamentModelText.cleanedList(
      proofTargetSummaries,
      limit: 360
    )
    self.targetedProofOutcomeSummaries = ProductTournamentModelText.cleanedList(
      targetedProofOutcomeSummaries,
      limit: 360
    )
    self.personaRationaleSignalSummaries = ProductTournamentModelText.cleanedList(
      personaRationaleSignalSummaries,
      limit: 360
    )
    self.revisionBriefSummaries = ProductTournamentModelText.cleanedList(
      revisionBriefSummaries,
      limit: 300
    )
    self.stopReason = stopReason
    self.stopStepID = ProductTournamentModelText.optionalCleanedText(stopStepID, limit: 200)
    self.stopStepTitle = ProductTournamentModelText.optionalCleanedText(stopStepTitle, limit: 180)
    let cleanedStopDetail = ProductTournamentModelText.cleanedText(
      stopDetail,
      fallback: "Tournament automation cycle stopped.",
      limit: 500
    )
    self.stopDetail = cleanedStopDetail
    self.userMessage = ProductTournamentModelText.cleanedText(
      userMessage,
      fallback: cleanedStopDetail,
      limit: 2_000
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case startedAt
    case endedAt
    case executedStepIDs
    case experimentIDs
    case messages
    case maxSteps
    case appliedDecisionCount
    case appliedRoundTransitionCount
    case promotedDecisionCount
    case killedDecisionCount
    case targetedPromoteProofCount
    case targetedKillProofCount
    case evidenceRunStepCount
    case evidenceRunIDs
    case completedEvidenceRunCount
    case failedEvidenceRunCount
    case skippedScenarioCount
    case startingProofDebtCount
    case endingProofDebtCount
    case startingProofDebtSummary
    case endingProofDebtSummary
    case startingPersonaModelPlanEvaluationCount
    case endingPersonaModelPlanEvaluationCount
    case startingModelFreePlanEvaluationCount
    case endingModelFreePlanEvaluationCount
    case decisionCandidateSummaries
    case evidenceTensionSummaries
    case proofTargetSummaries
    case targetedProofOutcomeSummaries
    case personaRationaleSignalSummaries
    case revisionBriefSummaries
    case stopReason
    case stopStepID
    case stopStepTitle
    case stopDetail
    case userMessage
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(String.self, forKey: .id),
      startedAt: try container.decode(Double.self, forKey: .startedAt),
      endedAt: try container.decode(Double.self, forKey: .endedAt),
      executedStepIDs: try container.decode([String].self, forKey: .executedStepIDs),
      experimentIDs: try container.decode([String].self, forKey: .experimentIDs),
      messages: try container.decode([String].self, forKey: .messages),
      maxSteps: try container.decode(Int.self, forKey: .maxSteps),
      appliedDecisionCount: try container.decodeIfPresent(
        Int.self,
        forKey: .appliedDecisionCount
      ) ?? 0,
      appliedRoundTransitionCount: try container.decodeIfPresent(
        Int.self,
        forKey: .appliedRoundTransitionCount
      ) ?? 0,
      promotedDecisionCount: try container.decodeIfPresent(
        Int.self,
        forKey: .promotedDecisionCount
      ) ?? 0,
      killedDecisionCount: try container.decodeIfPresent(
        Int.self,
        forKey: .killedDecisionCount
      ) ?? 0,
      targetedPromoteProofCount: try container.decodeIfPresent(
        Int.self,
        forKey: .targetedPromoteProofCount
      ) ?? 0,
      targetedKillProofCount: try container.decodeIfPresent(
        Int.self,
        forKey: .targetedKillProofCount
      ) ?? 0,
      evidenceRunStepCount: try container.decodeIfPresent(
        Int.self,
        forKey: .evidenceRunStepCount
      ) ?? 0,
      evidenceRunIDs: try container.decodeIfPresent([String].self, forKey: .evidenceRunIDs)
        ?? [],
      completedEvidenceRunCount: try container.decodeIfPresent(
        Int.self,
        forKey: .completedEvidenceRunCount
      ) ?? 0,
      failedEvidenceRunCount: try container.decodeIfPresent(
        Int.self,
        forKey: .failedEvidenceRunCount
      ) ?? 0,
      skippedScenarioCount: try container.decodeIfPresent(
        Int.self,
        forKey: .skippedScenarioCount
      ) ?? 0,
      startingProofDebtCount: try container.decodeIfPresent(
        Int.self,
        forKey: .startingProofDebtCount
      ),
      endingProofDebtCount: try container.decodeIfPresent(
        Int.self,
        forKey: .endingProofDebtCount
      ),
      startingProofDebtSummary: try container.decodeIfPresent(
        String.self,
        forKey: .startingProofDebtSummary
      ),
      endingProofDebtSummary: try container.decodeIfPresent(
        String.self,
        forKey: .endingProofDebtSummary
      ),
      startingPersonaModelPlanEvaluationCount: try container.decodeIfPresent(
        Int.self,
        forKey: .startingPersonaModelPlanEvaluationCount
      ),
      endingPersonaModelPlanEvaluationCount: try container.decodeIfPresent(
        Int.self,
        forKey: .endingPersonaModelPlanEvaluationCount
      ),
      startingModelFreePlanEvaluationCount: try container.decodeIfPresent(
        Int.self,
        forKey: .startingModelFreePlanEvaluationCount
      ),
      endingModelFreePlanEvaluationCount: try container.decodeIfPresent(
        Int.self,
        forKey: .endingModelFreePlanEvaluationCount
      ),
      decisionCandidateSummaries: try container.decodeIfPresent(
        [String].self,
        forKey: .decisionCandidateSummaries
      ) ?? [],
      evidenceTensionSummaries: try container.decodeIfPresent(
        [String].self,
        forKey: .evidenceTensionSummaries
      ) ?? [],
      proofTargetSummaries: try container.decodeIfPresent(
        [String].self,
        forKey: .proofTargetSummaries
      ) ?? [],
      targetedProofOutcomeSummaries: try container.decodeIfPresent(
        [String].self,
        forKey: .targetedProofOutcomeSummaries
      ) ?? [],
      personaRationaleSignalSummaries: try container.decodeIfPresent(
        [String].self,
        forKey: .personaRationaleSignalSummaries
      ) ?? [],
      revisionBriefSummaries: try container.decodeIfPresent(
        [String].self,
        forKey: .revisionBriefSummaries
      ) ?? [],
      stopReason: try container.decode(
        TournamentAutomationCycleAuditStopReason.self, forKey: .stopReason),
      stopStepID: try container.decodeIfPresent(String.self, forKey: .stopStepID),
      stopStepTitle: try container.decodeIfPresent(String.self, forKey: .stopStepTitle),
      stopDetail: try container.decode(String.self, forKey: .stopDetail),
      userMessage: try container.decode(String.self, forKey: .userMessage)
    )
  }
}

struct ProductTournamentDynamicCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}

enum ProductTournamentConfigError: LocalizedError, Equatable {
  case unsupportedSchemaVersion(Int)
  case unsupportedKey(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version):
      return "Unsupported product tournament config schema version \(version)."
    case .unsupportedKey(let key):
      return "Unsupported product tournament config key \(key)."
    }
  }
}

enum ProductTournamentModelText {
  static func firstMeaningfulLine(in text: String) -> String? {
    text
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
  }

  static func slug(_ value: String, fallback: String) -> String {
    let fallbackValue = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized =
      value
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let fallbackSlug =
      fallbackValue
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return String((normalized.isEmpty ? fallbackSlug : normalized).prefix(64))
  }

  static func identifier(_ value: String, fallback: String) -> String {
    let fallbackValue = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized =
      value
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let fallbackSlug =
      fallbackValue
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return String((normalized.isEmpty ? fallbackSlug : normalized).prefix(96))
  }

  static func optionalIdentifier(_ value: String?, fallback: String) -> String? {
    let cleaned = StringUtils.boundedText(value ?? "", limit: 120)
    guard !cleaned.isEmpty else { return nil }
    return identifier(cleaned, fallback: fallback)
  }

  static func cleanedText(_ value: String, fallback: String = "", limit: Int) -> String {
    let cleaned = StringUtils.boundedText(value, limit: limit)
    return cleaned.isEmpty ? fallback : cleaned
  }

  static func optionalCleanedText(_ value: String?, limit: Int) -> String? {
    let cleaned = StringUtils.boundedText(value ?? "", limit: limit)
    return cleaned.isEmpty ? nil : cleaned
  }

  static func cleanedList(_ values: [String], limit: Int) -> [String] {
    let cleaned =
      values
      .map { StringUtils.boundedText($0, limit: limit) }
      .filter { !$0.isEmpty }
    var seen = Set<String>()
    var cleanedValues: [String] = []
    for value in cleaned {
      guard seen.insert(value).inserted else { continue }
      cleanedValues.append(value)
    }
    return cleanedValues
  }
}

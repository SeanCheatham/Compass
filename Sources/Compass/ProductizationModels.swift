import Foundation

struct ProductizationConfig: Codable, Equatable, Sendable {
  static let supportedSchemaVersion = 1

  var schemaVersion: Int
  var rawPain: String
  var painHypotheses: [PainHypothesis]
  var userSegments: [UserSegment]
  var currentWorkflows: [CurrentWorkflow]
  var alternatives: [Alternative]
  var solutionHypotheses: [SolutionHypothesis]
  var experiments: [ProductExperiment]
  var scenarios: [ProductScenario]
  var scenarioCohorts: [ProductScenarioCohort]
  var decisions: [ProductDecision]
  var factoryCycleAudits: [ProductFactoryCycleAudit]

  static let empty = ProductizationConfig(
    rawPain: "",
    painHypotheses: [],
    userSegments: [],
    currentWorkflows: [],
    alternatives: [],
    solutionHypotheses: [],
    experiments: [],
    scenarios: [],
    scenarioCohorts: [],
    decisions: [],
    factoryCycleAudits: []
  )

  enum CodingKeys: String, CodingKey {
    case schemaVersion
    case rawPain
    case painHypotheses
    case userSegments
    case currentWorkflows
    case alternatives
    case solutionHypotheses
    case experiments
    case scenarios
    case scenarioCohorts
    case decisions
    case factoryCycleAudits
  }

  init(
    schemaVersion: Int = Self.supportedSchemaVersion,
    rawPain: String,
    painHypotheses: [PainHypothesis],
    userSegments: [UserSegment],
    currentWorkflows: [CurrentWorkflow],
    alternatives: [Alternative],
    solutionHypotheses: [SolutionHypothesis],
    experiments: [ProductExperiment],
    scenarios: [ProductScenario] = [],
    scenarioCohorts: [ProductScenarioCohort] = [],
    decisions: [ProductDecision] = [],
    factoryCycleAudits: [ProductFactoryCycleAudit] = []
  ) {
    self.schemaVersion = schemaVersion
    self.rawPain = ProductizationModelText.cleanedText(rawPain, limit: 4_000)
    self.painHypotheses = painHypotheses
    self.userSegments = userSegments
    self.currentWorkflows = currentWorkflows
    self.alternatives = alternatives
    self.solutionHypotheses = solutionHypotheses
    self.experiments = experiments
    self.scenarios = scenarios
    self.scenarioCohorts = scenarioCohorts
    self.decisions = decisions
    self.factoryCycleAudits = factoryCycleAudits
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion =
      try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
      ?? Self.supportedSchemaVersion
    guard schemaVersion == Self.supportedSchemaVersion else {
      throw ProductizationConfigError.unsupportedSchemaVersion(schemaVersion)
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
      solutionHypotheses: try container.decodeIfPresent(
        [SolutionHypothesis].self, forKey: .solutionHypotheses) ?? [],
      experiments: try container.decodeIfPresent([ProductExperiment].self, forKey: .experiments)
        ?? [],
      scenarios: try container.decodeIfPresent([ProductScenario].self, forKey: .scenarios) ?? [],
      scenarioCohorts: try container.decodeIfPresent(
        [ProductScenarioCohort].self, forKey: .scenarioCohorts) ?? [],
      decisions: try container.decodeIfPresent([ProductDecision].self, forKey: .decisions) ?? [],
      factoryCycleAudits: try container.decodeIfPresent(
        [ProductFactoryCycleAudit].self,
        forKey: .factoryCycleAudits
      ) ?? []
    )
  }

  var isEmpty: Bool {
    rawPain.isEmpty
      && painHypotheses.isEmpty
      && userSegments.isEmpty
      && currentWorkflows.isEmpty
      && alternatives.isEmpty
      && solutionHypotheses.isEmpty
      && experiments.isEmpty
      && scenarios.isEmpty
      && scenarioCohorts.isEmpty
      && decisions.isEmpty
      && factoryCycleAudits.isEmpty
  }

  func recordingFactoryCycleAudit(
    _ audit: ProductFactoryCycleAudit,
    limit: Int = 20
  ) -> ProductizationConfig {
    var next = self
    let cappedLimit = max(1, limit)
    next.factoryCycleAudits = (next.factoryCycleAudits + [audit])
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
  ) -> ProductizationConfig {
    let timestamp = now.timeIntervalSince1970
    let title = ProductizationModelText.cleanedText(projectTitle, fallback: "Project", limit: 120)
    let painText =
      ProductizationModelText.firstMeaningfulLine(in: rawPain)
      ?? "\(title) has an unresolved workflow pain that needs product discovery."
    let slug = ProductizationModelText.slug(painText, fallback: title)
    let painID = "\(slug)-pain"
    let workflowID = "\(slug)-current-workflow"
    let manualAlternativeID = "\(slug)-manual-alternative"
    let doNothingAlternativeID = "\(slug)-do-nothing"
    let operatorSegmentID = "\(slug)-operator"
    let buyerSegmentID = "\(slug)-buyer"
    let workflowSolutionID = "\(slug)-workflow-clarifier"
    let proofSolutionID = "\(slug)-proof-assistant"
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
        "Evidence compares the product bet against the user's actual alternative.",
      ],
      unknowns: [
        "Which user segment feels this pain most acutely?",
        "What current alternative wins today, and why?",
        "Which smallest workflow proof would change the next product decision?",
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
        context: "Evaluates whether a product bet helps in the moment of work, not just in a pitch.",
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
          "Needs ROI or risk reduction before promoting the bet."
        ],
        currentWorkflowIDs: [workflowID],
        alternativeIDs: [manualAlternativeID, doNothingAlternativeID],
        decisionCriteria: [
          "Pain severity",
          "Adoption risk",
          "Evidence quality",
        ],
        skepticism: "Treats subjective enthusiasm as weak until paired with concrete workflow proof."
      ),
    ]

    let solutions = [
      SolutionHypothesis(
        id: workflowSolutionID,
        painID: painID,
        title: "\(title) workflow clarifier",
        promise: "Make the painful workflow visible, guided, and easier to complete.",
        workflowBet:
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
      SolutionHypothesis(
        id: proofSolutionID,
        painID: painID,
        title: "\(title) proof assistant",
        promise: "Help the user compare options and produce evidence for a product decision.",
        workflowBet:
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
      ProductExperiment(
        id: workflowExperimentID,
        solutionID: workflowSolutionID,
        title: "\(title) workflow prototype",
        branchName: "codex/\(slug)-workflow-prototype",
        worktreeID: "\(slug)-workflow-worktree",
        baseSha: nil,
        currentSha: nil,
        prototypeScope: "Build the smallest Rust desktop workflow that proves one pain-relief moment.",
        scenarioCohortIDs: ["\(workflowExperimentID)-starter-cohort"],
        evidenceSummary: "No evidence recorded yet.",
        decision: .notRun,
        createdAt: timestamp
      ),
      ProductExperiment(
        id: proofExperimentID,
        solutionID: proofSolutionID,
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
        task: "Try the prototype against the current manual workflow and decide whether it makes the next action clearer.",
        successSignal: "The operator can complete one workflow moment with less ambiguity than the manual workaround.",
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
        task: "Review the workflow prototype as the sponsor and decide whether the evidence justifies more product investment.",
        successSignal: "The buyer can explain whether the workflow relief is valuable enough to sponsor.",
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
        task: "Use the proof assistant during the current workflow and decide whether it makes product evidence easier to capture.",
        successSignal: "The operator can capture reusable evidence with less rework than the manual workaround.",
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
        task: "Use the prototype to compare the product bet against doing nothing and decide whether evidence is strong enough to continue.",
        successSignal: "The buyer can explain the decision criteria and the next product decision with reusable evidence.",
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
        scenarioIDs: scenarios
          .filter { $0.experimentID == experiment.id }
          .map(\.id),
        enabled: true,
        tags: ["seeded", "starter"]
      )
    }

    return ProductizationConfig(
      rawPain: painText,
      painHypotheses: [pain],
      userSegments: userSegments,
      currentWorkflows: [workflow],
      alternatives: alternatives,
      solutionHypotheses: solutions,
      experiments: experiments,
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
    self.id = ProductizationModelText.identifier(id, fallback: "pain")
    self.title = ProductizationModelText.cleanedText(title, fallback: "Pain hypothesis", limit: 180)
    self.rawPain = ProductizationModelText.cleanedText(
      rawPain, fallback: "Current workflow pain to explore", limit: 4_000)
    self.targetSituation = ProductizationModelText.cleanedText(
      targetSituation, fallback: "The situation where the pain appears", limit: 800)
    self.painFrequency = ProductizationModelText.cleanedText(
      painFrequency, fallback: "Unknown frequency", limit: 300)
    self.painSeverity = ProductizationModelText.cleanedText(
      painSeverity, fallback: "Unknown severity", limit: 300)
    self.costOfInaction = ProductizationModelText.cleanedText(
      costOfInaction, fallback: "The current workaround continues", limit: 800)
    self.successSignals = ProductizationModelText.cleanedList(successSignals, limit: 240)
    self.unknowns = ProductizationModelText.cleanedList(unknowns, limit: 240)
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
    self.id = ProductizationModelText.identifier(id, fallback: "segment")
    self.painID = ProductizationModelText.identifier(painID, fallback: "pain")
    self.name = ProductizationModelText.cleanedText(name, fallback: "User segment", limit: 160)
    self.role = ProductizationModelText.cleanedText(role, fallback: "Target user", limit: 220)
    self.context = ProductizationModelText.cleanedText(
      context, fallback: "Experiences the pain in a real workflow", limit: 800)
    self.goals = ProductizationModelText.cleanedList(goals, limit: 220)
    self.constraints = ProductizationModelText.cleanedList(constraints, limit: 220)
    self.currentWorkflowIDs =
      ProductizationModelText.cleanedList(currentWorkflowIDs, limit: 120)
      .map { ProductizationModelText.identifier($0, fallback: "workflow") }
    self.alternativeIDs =
      ProductizationModelText.cleanedList(alternativeIDs, limit: 120)
      .map { ProductizationModelText.identifier($0, fallback: "alternative") }
    self.decisionCriteria = ProductizationModelText.cleanedList(decisionCriteria, limit: 220)
    self.skepticism = ProductizationModelText.cleanedText(
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
    self.id = ProductizationModelText.identifier(id, fallback: "workflow")
    self.painID = ProductizationModelText.identifier(painID, fallback: "pain")
    self.title = ProductizationModelText.cleanedText(
      title, fallback: "Current workflow", limit: 180)
    self.steps = ProductizationModelText.cleanedList(steps, limit: 260)
    self.tools = ProductizationModelText.cleanedList(tools, limit: 180)
    self.handoffs = ProductizationModelText.cleanedList(handoffs, limit: 240)
    self.failureModes = ProductizationModelText.cleanedList(failureModes, limit: 260)
    self.workarounds = ProductizationModelText.cleanedList(workarounds, limit: 220)
    self.estimatedCost = ProductizationModelText.cleanedText(
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
    self.id = ProductizationModelText.identifier(id, fallback: "alternative")
    self.painID = ProductizationModelText.identifier(painID, fallback: "pain")
    self.title = ProductizationModelText.cleanedText(title, fallback: "Alternative", limit: 180)
    self.kind = kind
    self.strengths = ProductizationModelText.cleanedList(strengths, limit: 220)
    self.weaknesses = ProductizationModelText.cleanedList(weaknesses, limit: 220)
    self.switchingCost = ProductizationModelText.cleanedText(
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

struct SolutionHypothesis: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var painID: String
  var title: String
  var promise: String
  var workflowBet: String
  var targetSegmentIDs: [String]
  var differentiator: String
  var whyThisCouldWin: String
  var whyThisMightFail: String
  var requiredProof: [String]
  var status: SolutionHypothesisStatus

  init(
    id: String,
    painID: String,
    title: String,
    promise: String,
    workflowBet: String,
    targetSegmentIDs: [String] = [],
    differentiator: String,
    whyThisCouldWin: String,
    whyThisMightFail: String,
    requiredProof: [String] = [],
    status: SolutionHypothesisStatus
  ) {
    self.id = ProductizationModelText.identifier(id, fallback: "solution")
    self.painID = ProductizationModelText.identifier(painID, fallback: "pain")
    self.title = ProductizationModelText.cleanedText(
      title, fallback: "Solution hypothesis", limit: 180)
    self.promise = ProductizationModelText.cleanedText(
      promise, fallback: "Relieve the target pain", limit: 500)
    self.workflowBet = ProductizationModelText.cleanedText(
      workflowBet, fallback: "A prototype can prove pain relief", limit: 700)
    self.targetSegmentIDs =
      ProductizationModelText.cleanedList(targetSegmentIDs, limit: 120)
      .map { ProductizationModelText.identifier($0, fallback: "segment") }
    self.differentiator = ProductizationModelText.cleanedText(
      differentiator, fallback: "Different from the current alternative", limit: 500)
    self.whyThisCouldWin = ProductizationModelText.cleanedText(
      whyThisCouldWin, fallback: "The target segment may prefer it", limit: 700)
    self.whyThisMightFail = ProductizationModelText.cleanedText(
      whyThisMightFail, fallback: "The product bet may not relieve enough pain", limit: 700)
    self.requiredProof = ProductizationModelText.cleanedList(requiredProof, limit: 260)
    self.status = status
  }
}

enum SolutionHypothesisStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case candidate
  case active
  case promoted
  case rejected
  case parked
}

struct ProductExperiment: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var solutionID: String
  var title: String
  var branchName: String
  var worktreeID: String
  var baseSha: String?
  var currentSha: String?
  var prototypeScope: String
  var scenarioCohortIDs: [String]
  var evidenceSummary: String
  var decision: ProductExperimentDecision
  var createdAt: Double
  var updatedAt: Double

  init(
    id: String,
    solutionID: String,
    title: String,
    branchName: String,
    worktreeID: String,
    baseSha: String?,
    currentSha: String?,
    prototypeScope: String,
    scenarioCohortIDs: [String] = [],
    evidenceSummary: String,
    decision: ProductExperimentDecision,
    createdAt: Double,
    updatedAt: Double? = nil
  ) {
    self.id = ProductizationModelText.identifier(id, fallback: "experiment")
    self.solutionID = ProductizationModelText.identifier(solutionID, fallback: "solution")
    self.title = ProductizationModelText.cleanedText(
      title, fallback: "Product experiment", limit: 180)
    self.branchName = ProductizationModelText.cleanedText(
      branchName, fallback: "codex/product-experiment", limit: 240)
    self.worktreeID = ProductizationModelText.identifier(worktreeID, fallback: "worktree")
    self.baseSha = ProductizationModelText.optionalCleanedText(baseSha, limit: 80)
    self.currentSha = ProductizationModelText.optionalCleanedText(currentSha, limit: 80)
    self.prototypeScope = ProductizationModelText.cleanedText(
      prototypeScope, fallback: "Smallest prototype needed for evidence", limit: 800)
    self.scenarioCohortIDs =
      ProductizationModelText.cleanedList(scenarioCohortIDs, limit: 120)
      .map { ProductizationModelText.identifier($0, fallback: "cohort") }
    self.evidenceSummary = ProductizationModelText.cleanedText(
      evidenceSummary, fallback: "No evidence recorded yet.", limit: 1_000)
    self.decision = decision
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
  }
}

enum ProductExperimentDecision: String, Codable, CaseIterable, Equatable, Sendable {
  case notRun = "not_run"
  case keepGoing = "continue"
  case narrow
  case pivot
  case kill
  case promote
  case archived
  case promoted
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
    self.id = ProductizationModelText.identifier(id, fallback: "scenario")
    self.experimentID = ProductizationModelText.identifier(experimentID, fallback: "experiment")
    self.segmentID = ProductizationModelText.identifier(segmentID, fallback: "segment")
    self.currentWorkflowID = ProductizationModelText.identifier(
      currentWorkflowID,
      fallback: "workflow"
    )
    self.alternativeID = ProductizationModelText.optionalIdentifier(
      alternativeID,
      fallback: "alternative"
    )
    self.title = ProductizationModelText.cleanedText(
      title,
      fallback: "Productization scenario",
      limit: 180
    )
    self.task = ProductizationModelText.cleanedText(
      task,
      fallback: "Try the product experiment against the current workflow.",
      limit: 800
    )
    self.successSignal = ProductizationModelText.cleanedText(
      successSignal,
      fallback: "The scenario produces evidence for the next product decision.",
      limit: 500
    )
    self.targetCommitSha = ProductizationModelText.optionalCleanedText(
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
    self.id = ProductizationModelText.identifier(id, fallback: "cohort")
    self.title = ProductizationModelText.cleanedText(
      title, fallback: "Product scenario cohort", limit: 180)
    self.experimentID = ProductizationModelText.identifier(experimentID, fallback: "experiment")
    self.scenarioIDs =
      ProductizationModelText.cleanedList(scenarioIDs, limit: 120)
      .map { ProductizationModelText.identifier($0, fallback: "scenario") }
    self.enabled = enabled
    self.tags = ProductizationModelText.cleanedList(tags, limit: 80)
  }
}

struct ProductDecision: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var experimentID: String
  var decision: ProductExperimentDecision
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
    decision: ProductExperimentDecision,
    summary: String,
    evidenceRunIDs: [String] = [],
    branchName: String? = nil,
    beforeSha: String? = nil,
    afterSha: String? = nil,
    decidedAt: Double,
    decidedBy: String
  ) {
    self.id = ProductizationModelText.identifier(id, fallback: "decision")
    self.experimentID = ProductizationModelText.identifier(experimentID, fallback: "experiment")
    self.decision = decision
    self.summary = ProductizationModelText.cleanedText(
      summary, fallback: "Product decision recorded.", limit: 1_000)
    self.evidenceRunIDs =
      ProductizationModelText.cleanedList(evidenceRunIDs, limit: 120)
      .map { ProductizationModelText.identifier($0, fallback: "evidence-run") }
    self.branchName = ProductizationModelText.optionalCleanedText(branchName, limit: 240)
    self.beforeSha = ProductizationModelText.optionalCleanedText(beforeSha, limit: 80)
    self.afterSha = ProductizationModelText.optionalCleanedText(afterSha, limit: 80)
    self.decidedAt = decidedAt
    self.decidedBy = ProductizationModelText.cleanedText(
      decidedBy, fallback: "Compass", limit: 120)
  }
}

enum ProductFactoryCycleAuditStopReason: String, Codable, CaseIterable, Equatable, Sendable {
  case reachedStepLimit = "reached_step_limit"
  case noExecutableStep = "no_executable_step"
  case repeatedStep = "repeated_step"
  case executionFailed = "execution_failed"
}

struct ProductFactoryCycleAudit: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var startedAt: Double
  var endedAt: Double
  var executedStepIDs: [String]
  var experimentIDs: [String]
  var messages: [String]
  var maxSteps: Int
  var appliedDecisionCount: Int
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
  var decisionCandidateSummaries: [String]
  var evidenceTensionSummaries: [String]
  var proofTargetSummaries: [String]
  var targetedProofOutcomeSummaries: [String]
  var personaRationaleSignalSummaries: [String]
  var revisionBriefSummaries: [String]
  var stopReason: ProductFactoryCycleAuditStopReason
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
    let targetedProof =
      targetedPromoteProofCount + targetedKillProofCount > 0
      ? "; targeted proof \(targetedPromoteProofCount) promote, \(targetedKillProofCount) kill"
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
      "\(executedStepCount) step(s); decisions \(appliedDecisionCount) (\(promotedDecisionCount) promote, \(killedDecisionCount) kill)\(targetedProof); evidence \(evidenceRunStepCount) step(s), \(completedEvidenceRunCount) completed run(s), \(failedEvidenceRunCount) needing review, \(skippedScenarioCount) skipped\(runIDs)\(proofDebt)\(decisionCandidates)\(evidenceTensions)\(proofTargets)\(targetedOutcomes)\(rationaleSignals)\(revisionBriefs); \(stopReason.rawValue)\(stopTarget); \(stopDetail)"
  }

  private var proofDebtSummary: String? {
    guard let startingProofDebtCount, let endingProofDebtCount, let proofDebtDelta else {
      return nil
    }
    let sign = proofDebtDelta > 0 ? "+" : ""
    return "proof debt \(startingProofDebtCount) -> \(endingProofDebtCount) (\(sign)\(proofDebtDelta))"
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
    decisionCandidateSummaries: [String] = [],
    evidenceTensionSummaries: [String] = [],
    proofTargetSummaries: [String] = [],
    targetedProofOutcomeSummaries: [String] = [],
    personaRationaleSignalSummaries: [String] = [],
    revisionBriefSummaries: [String] = [],
    stopReason: ProductFactoryCycleAuditStopReason,
    stopStepID: String? = nil,
    stopStepTitle: String? = nil,
    stopDetail: String,
    userMessage: String
  ) {
    self.id = ProductizationModelText.identifier(id, fallback: "factory-cycle-audit")
    self.startedAt = startedAt
    self.endedAt = max(startedAt, endedAt)
    self.executedStepIDs = ProductizationModelText.cleanedList(executedStepIDs, limit: 260)
    self.experimentIDs =
      ProductizationModelText.cleanedList(experimentIDs, limit: 120)
      .map { ProductizationModelText.identifier($0, fallback: "experiment") }
    self.messages = ProductizationModelText.cleanedList(messages, limit: 500)
    self.maxSteps = max(1, maxSteps)
    self.appliedDecisionCount = max(0, appliedDecisionCount)
    self.promotedDecisionCount = max(0, promotedDecisionCount)
    self.killedDecisionCount = max(0, killedDecisionCount)
    self.targetedPromoteProofCount = max(0, targetedPromoteProofCount)
    self.targetedKillProofCount = max(0, targetedKillProofCount)
    self.evidenceRunStepCount = max(0, evidenceRunStepCount)
    self.evidenceRunIDs = ProductizationModelText.cleanedList(evidenceRunIDs, limit: 120)
    self.completedEvidenceRunCount = max(0, completedEvidenceRunCount)
    self.failedEvidenceRunCount = max(0, failedEvidenceRunCount)
    self.skippedScenarioCount = max(0, skippedScenarioCount)
    self.startingProofDebtCount = startingProofDebtCount.map { max(0, $0) }
    self.endingProofDebtCount = endingProofDebtCount.map { max(0, $0) }
    self.startingProofDebtSummary = ProductizationModelText.optionalCleanedText(
      startingProofDebtSummary,
      limit: 500
    )
    self.endingProofDebtSummary = ProductizationModelText.optionalCleanedText(
      endingProofDebtSummary,
      limit: 500
    )
    self.decisionCandidateSummaries = ProductizationModelText.cleanedList(
      decisionCandidateSummaries,
      limit: 300
    )
    self.evidenceTensionSummaries = ProductizationModelText.cleanedList(
      evidenceTensionSummaries,
      limit: 360
    )
    self.proofTargetSummaries = ProductizationModelText.cleanedList(
      proofTargetSummaries,
      limit: 360
    )
    self.targetedProofOutcomeSummaries = ProductizationModelText.cleanedList(
      targetedProofOutcomeSummaries,
      limit: 360
    )
    self.personaRationaleSignalSummaries = ProductizationModelText.cleanedList(
      personaRationaleSignalSummaries,
      limit: 360
    )
    self.revisionBriefSummaries = ProductizationModelText.cleanedList(
      revisionBriefSummaries,
      limit: 300
    )
    self.stopReason = stopReason
    self.stopStepID = ProductizationModelText.optionalCleanedText(stopStepID, limit: 200)
    self.stopStepTitle = ProductizationModelText.optionalCleanedText(stopStepTitle, limit: 180)
    let cleanedStopDetail = ProductizationModelText.cleanedText(
      stopDetail,
      fallback: "Factory cycle stopped.",
      limit: 500
    )
    self.stopDetail = cleanedStopDetail
    self.userMessage = ProductizationModelText.cleanedText(
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
        ProductFactoryCycleAuditStopReason.self, forKey: .stopReason),
      stopStepID: try container.decodeIfPresent(String.self, forKey: .stopStepID),
      stopStepTitle: try container.decodeIfPresent(String.self, forKey: .stopStepTitle),
      stopDetail: try container.decode(String.self, forKey: .stopDetail),
      userMessage: try container.decode(String.self, forKey: .userMessage)
    )
  }
}

enum ProductizationConfigError: LocalizedError, Equatable {
  case unsupportedSchemaVersion(Int)

  var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version):
      return "Unsupported productization config schema version \(version)."
    }
  }
}

enum ProductizationModelText {
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
    let cleaned = values
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

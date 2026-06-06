import Foundation
import Testing

@testable import Compass

struct DiscoverPromptContractTests {
  @Test func discoverPromptFramesPainBeforeSolutions() throws {
    let context = DiscoveryPromptContext(
      rawPain: "Support leads lose escalation decisions across chat and tickets.",
      vision: "Help support teams preserve customer promise context.",
      drafts: "Explore the current workflow before building.",
      lessons: "Keep generated prototypes Rust-only.",
      assumptions: "Assumption: buyers care about escalation latency.",
      productTournamentConfig: ProductTournamentConfig.seedDefaults(
        projectTitle: "Escalation Desk",
        rawPain: "Support leads lose escalation decisions across chat and tickets.",
        now: Date(timeIntervalSince1970: 1_700_000_000)
      ),
      repositoryShape: "Rust-capable Compass workspace"
    )

    let prompt = try Prompts.discoverPrompt(context: context)

    try #require(prompt.contains(Prompts.discoverPromptVersionID))
    try #require(prompt.contains("Start from pain, not a solution"))
    try #require(prompt.contains("Name the user segment before naming the app"))
    try #require(prompt.contains("Round 1 compares product"))
    try #require(prompt.contains("candidateExperiments"))
    try #require(prompt.contains("contenderPlan"))
    try #require(!prompt.contains("workflowBet"))
    try #require(prompt.contains("current tournament state"))
    try #require(prompt.contains("Support leads lose escalation decisions"))
    try #require(prompt.contains("Rust desktop"))
  }

  @Test func validDiscoverResponseAppliesStructuredProductTournamentEdits() throws {
    let output = makeDiscoverOutput()
    let decoded = try Prompts.decodeDiscoverResponse(try encodeDiscoverJSON(output))
    let config = try decoded.validatedProductTournamentConfig(applyingTo: .empty)

    try #require(config.rawPain.contains("customer-facing decisions"))
    try #require(config.painHypotheses.count == 1)
    try #require(config.solutionHypotheses.count == 2)
    try #require(config.solutionHypotheses[0].contenderPlan.contains("focused board"))
    try #require(config.experiments.count == 1)
    try #require(config.tournaments.count == 1)
    try #require(config.tournamentContenders.count == 2)
    try #require(
      config.tournamentRounds.map(\.kind) == [.productPlans, .coreTechnology, .prototype])
    try #require(config.tournamentRounds[0].requiresBuiltProduct == false)
    try #require(decoded.candidateExperiments[0].branchSlug == "incident-command-board")
    try #require(decoded.assumptions[0].text.contains("Incident leads"))
  }

  @Test func discoverValidationRejectsMissingActivePain() throws {
    var output = makeDiscoverOutput()
    output.stateEdits = DiscoveryStateEdits()

    #expect(throws: DiscoverPromptValidationError.missingActivePainHypothesis) {
      _ = try Prompts.decodeDiscoverResponse(try encodeDiscoverJSON(output))
    }
  }

  @Test func discoverValidationRejectsSolutionWithoutPain() throws {
    var output = makeDiscoverOutput()
    output.stateEdits.solutionHypotheses[0] = SolutionHypothesis(
      id: "solution-bad",
      painID: "missing-pain",
      title: "Bad solution",
      promise: "Help somehow",
      contenderPlan: "Prototype something",
      targetSegmentIDs: [],
      differentiator: "Unknown",
      whyThisCouldWin: "Unknown",
      whyThisMightFail: "Unknown",
      requiredProof: ["Proof"],
      status: .active
    )

    #expect(
      throws: DiscoverPromptValidationError.solutionReferencesMissingPain(
        solutionID: "solution-bad",
        painID: "missing-pain"
      )
    ) {
      _ = try Prompts.decodeDiscoverResponse(try encodeDiscoverJSON(output))
    }
  }

  @Test func discoverValidationRejectsInvalidCandidateBranchSlug() throws {
    var output = makeDiscoverOutput()
    output.candidateExperiments[0] = DiscoveryCandidateExperiment(
      solutionHypothesisID: "solution-command-board",
      prototypeName: "Incident Command Board",
      branchSlug: "bad slug",
      smallestWorkflowToProve: "Draft a customer update",
      targetScenarioCohort: "Incident lead cohort",
      expectedEvidenceSignal: "Lead gets a clearer update than chat.",
      killCriteria: "Persona still prefers chat."
    )

    #expect(throws: DiscoverPromptValidationError.invalidBranchSlug("bad slug")) {
      _ = try Prompts.decodeDiscoverResponse(try encodeDiscoverJSON(output))
    }
  }

  @Test func discoverValidationRejectsOpenQuestionsAsNextSteps() throws {
    var output = makeDiscoverOutput()
    output.candidateExperiments = []
    output.openQuestions = ["Build the prototype next"]

    #expect(
      throws: DiscoverPromptValidationError.openQuestionsUsedInsteadOfActionableNextSteps(
        "Build the prototype next"
      )
    ) {
      _ = try Prompts.decodeDiscoverResponse(try encodeDiscoverJSON(output))
    }
  }

  @Test func workspaceAppliesDiscoverOutputOnlyAfterValidation() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    var invalid = makeDiscoverOutput()
    invalid.stateEdits = DiscoveryStateEdits()

    #expect(throws: DiscoverPromptValidationError.missingActivePainHypothesis) {
      try workspace.applyDiscoverOutput(invalid)
    }
    try #require(!FileManager.default.fileExists(atPath: workspace.productTournamentConfigURL.path))

    let written = try workspace.applyDiscoverOutput(makeDiscoverOutput())

    try #require(FileManager.default.fileExists(atPath: workspace.productTournamentConfigURL.path))
    try #require(try workspace.readProductTournamentConfig() == written)
  }
}

private func makeDiscoverOutput() -> DiscoverPromptOutput {
  let timestamp = 1_700_000_000.0
  let pain = PainHypothesis(
    id: "pain-incident-decisions",
    title: "Incident decisions disappear",
    rawPain: "Incident leads lose customer-facing decisions across chat threads.",
    targetSituation: "A live incident is moving from triage to customer update.",
    painFrequency: "Weekly",
    painSeverity: "High",
    costOfInaction: "Teams repeat decisions and send inconsistent updates.",
    successSignals: ["Lead produces a clearer customer update"],
    unknowns: ["Which handoff hurts most?"],
    status: .active,
    createdAt: timestamp,
    updatedAt: timestamp
  )
  let workflow = CurrentWorkflow(
    id: "workflow-chat-triage",
    painID: pain.id,
    title: "Chat triage",
    steps: ["Read chat", "Find owner", "Draft customer update"],
    tools: ["Slack", "Ticketing"],
    handoffs: ["Support to engineering"],
    failureModes: ["Decision gets buried"],
    workarounds: ["Manual checklist"],
    estimatedCost: "One hour per incident"
  )
  let alternative = Alternative(
    id: "alternative-chat",
    painID: pain.id,
    title: "Slack thread",
    kind: .manual,
    strengths: ["Already used"],
    weaknesses: ["Hard to audit"],
    switchingCost: "Low"
  )
  let segment = UserSegment(
    id: "segment-incident-lead",
    painID: pain.id,
    name: "Incident lead",
    role: "Owns incident communication",
    context: "Needs a reliable customer update under time pressure.",
    goals: ["Send clear update"],
    constraints: ["Cannot add setup during incident"],
    currentWorkflowIDs: [workflow.id],
    alternativeIDs: [alternative.id],
    decisionCriteria: ["Clarity", "Speed"],
    skepticism: "Will stay in chat if the product is slower."
  )
  let commandBoard = SolutionHypothesis(
    id: "solution-command-board",
    painID: pain.id,
    title: "Incident Command Board",
    promise: "Preserve decisions, owners, and customer update status.",
    contenderPlan: "A focused board beats searching chat.",
    targetSegmentIDs: [segment.id],
    differentiator: "Decision timeline plus update composer.",
    whyThisCouldWin: "Lead can draft a clearer update quickly.",
    whyThisMightFail: "Chat may still be faster.",
    requiredProof: ["Persona drafts clearer update than chat"],
    status: .active
  )
  let timeline = SolutionHypothesis(
    id: "solution-timeline",
    painID: pain.id,
    title: "Incident Timeline",
    promise: "Turn noisy chat into an auditable timeline.",
    contenderPlan: "Timeline proof may reduce repeated context gathering.",
    targetSegmentIDs: [segment.id],
    differentiator: "Audit-first workflow.",
    whyThisCouldWin: "Teams need after-action clarity.",
    whyThisMightFail: "Does not help during the incident.",
    requiredProof: ["Lead can find why a decision changed"],
    status: .candidate
  )
  let experiment = ProductExperiment(
    id: "experiment-command-board",
    solutionID: commandBoard.id,
    title: "Incident command board prototype",
    branchName: "codex/incident-command-board",
    worktreeID: "incident-command-board-worktree",
    baseSha: nil,
    currentSha: nil,
    prototypeScope: "Board with owner queue and update composer.",
    scenarioCohortIDs: ["cohort-incident-lead"],
    evidenceSummary: "No evidence yet.",
    decision: .notRun,
    createdAt: timestamp,
    updatedAt: timestamp
  )
  let cohort = ProductScenarioCohort(
    id: "cohort-incident-lead",
    title: "Incident lead cohort",
    experimentID: experiment.id,
    scenarioIDs: [],
    tags: ["discover"]
  )
  let tournament = ProductTournament(
    id: "tournament-incident-decisions",
    painID: pain.id,
    title: "Incident decisions tournament",
    premise: pain.rawPain,
    contenderIDs: ["contender-command-board", "contender-timeline"],
    roundIDs: [
      "round-incident-plans",
      "round-incident-core-technology",
      "round-incident-prototype",
    ],
    currentRoundID: "round-incident-plans",
    status: .active,
    createdAt: timestamp,
    updatedAt: timestamp
  )
  let commandBoardContender = ProductTournamentContender(
    id: "contender-command-board",
    tournamentID: tournament.id,
    solutionID: commandBoard.id,
    experimentID: experiment.id,
    title: "Incident command board",
    productPlan: "Use owner and decision context to draft a customer update during triage.",
    valueProposition: "Incident leads produce clearer updates than they can from chat alone.",
    primaryRisk: "The board may be slower than Slack during a live incident.",
    targetSegmentIDs: [segment.id],
    status: .competing,
    createdAt: timestamp,
    updatedAt: timestamp
  )
  let timelineContender = ProductTournamentContender(
    id: "contender-timeline",
    tournamentID: tournament.id,
    solutionID: timeline.id,
    experimentID: nil,
    title: "Incident timeline",
    productPlan: "Turn chat and ticket context into an auditable incident timeline.",
    valueProposition: "Teams can explain why decisions changed without repeated context gathering.",
    primaryRisk: "After-action clarity may not relieve the live communication pain.",
    targetSegmentIDs: [segment.id],
    status: .competing,
    createdAt: timestamp,
    updatedAt: timestamp
  )
  let rounds = [
    ProductTournamentRound(
      id: "round-incident-plans",
      tournamentID: tournament.id,
      ordinal: 1,
      kind: .productPlans,
      title: "Round 1: product plans",
      goal: "Compare the command board and timeline as plans before implementation.",
      evaluationFocus: ["Pain recognition", "Willingness to pay", "Current alternative"],
      contenderIDs: tournament.contenderIDs,
      scenarioCohortIDs: [],
      status: .active,
      createdAt: timestamp,
      updatedAt: timestamp
    ),
    ProductTournamentRound(
      id: "round-incident-core-technology",
      tournamentID: tournament.id,
      ordinal: 2,
      kind: .coreTechnology,
      title: "Round 2: core technology",
      goal: "Prove that owner and decision context can be assembled reliably.",
      evaluationFocus: ["Feasibility", "Trust", "Switching objection"],
      contenderIDs: ["contender-command-board"],
      scenarioCohortIDs: [cohort.id],
      status: .planned,
      createdAt: timestamp,
      updatedAt: timestamp
    ),
    ProductTournamentRound(
      id: "round-incident-prototype",
      tournamentID: tournament.id,
      ordinal: 3,
      kind: .prototype,
      title: "Round 3: prototype",
      goal: "Evaluate a low-medium fidelity command board with simulated users.",
      evaluationFocus: ["Workflow improvement", "Continued-use pull"],
      contenderIDs: ["contender-command-board"],
      scenarioCohortIDs: [cohort.id],
      status: .planned,
      createdAt: timestamp,
      updatedAt: timestamp
    ),
  ]
  return DiscoverPromptOutput(
    summary: "Modeled incident decision loss and two possible product contenders.",
    stateEdits: DiscoveryStateEdits(
      rawPain: pain.rawPain,
      painHypotheses: [pain],
      userSegments: [segment],
      currentWorkflows: [workflow],
      alternatives: [alternative],
      solutionHypotheses: [commandBoard, timeline],
      experiments: [experiment],
      tournaments: [tournament],
      tournamentContenders: [commandBoardContender, timelineContender],
      tournamentRounds: rounds,
      scenarioCohorts: [cohort],
      decisions: []
    ),
    candidateExperiments: [
      DiscoveryCandidateExperiment(
        solutionHypothesisID: commandBoard.id,
        prototypeName: "Incident Command Board",
        branchSlug: "incident-command-board",
        smallestWorkflowToProve: "Draft a customer update from owner and decision context.",
        targetScenarioCohort: "Incident lead cohort",
        expectedEvidenceSignal: "Persona creates a clearer update than the Slack thread.",
        killCriteria: "Persona still prefers Slack plus a checklist."
      )
    ],
    openQuestions: ["Which current handoff causes the most repeated decisions?"],
    lessonEdits: [],
    assumptions: [
      AssumptionDraft(
        text: "Incident leads value customer update clarity over a generic timeline.",
        rationale: "The raw pain centers on customer-facing decisions.",
        evidence: ["User pain statement"],
        impact: "Prioritizes update composer prototype scope.",
        invalidation: "If leads mainly need after-action audit, timeline may be stronger.",
        scope: .project
      )
    ]
  )
}

private func encodeDiscoverJSON(_ output: DiscoverPromptOutput) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(output)
  return String(decoding: data, as: UTF8.self)
}

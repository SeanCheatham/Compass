import Foundation
import Testing

@testable import Compass

struct DiscoverPromptContractTests {
  @Test func discoverPromptFramesPainBeforeSolutions() throws {
    let context = DiscoveryPromptContext(
      rawPain: "Support leads lose escalation decisions across chat and tickets.",
      vision: "Help support teams preserve customer promise context.",
      drafts: "Explore the current workflow before building.",
      lessons: "Keep generated implementations Rust-only.",
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
    try #require(prompt.contains("candidateTournamentExperiments"))
    try #require(prompt.contains("implementationName"))
    try #require(!prompt.contains("candidateExperiments"))
    try #require(!prompt.contains("prototypeName"))
    try #require(prompt.contains("tournamentExperiments"))
    try #require(prompt.contains("contenderPlans"))
    try #require(prompt.contains("contenderPlanID"))
    try #require(prompt.contains("contenderID"))
    try #require(prompt.contains("`contenderID` must reference a tournament contender"))
    try #require(!prompt.contains("`contenderPlanID` must reference"))
    try #require(prompt.contains("contenderPlan"))
    try #require(prompt.contains("product contenders"))
    try #require(!prompt.contains("reference a solution"))
    try #require(!prompt.contains("solutionHypotheses"))
    try #require(!prompt.contains("solutionHypothesisID"))
    try #require(!prompt.contains("workflowBet"))
    try #require(prompt.contains("current"))
    try #require(prompt.contains("tournament state"))
    try #require(prompt.contains("Support leads lose escalation decisions"))
    try #require(prompt.contains("Rust desktop"))
  }

  @Test func validDiscoverResponseAppliesStructuredProductTournamentEdits() throws {
    let output = makeDiscoverOutput()
    let decoded = try Prompts.decodeDiscoverResponse(try encodeDiscoverJSON(output))
    let config = try decoded.validatedProductTournamentConfig(applyingTo: .empty)

    try #require(config.rawPain.contains("customer-facing decisions"))
    try #require(config.painHypotheses.count == 1)
    try #require(config.contenderPlans.count == 2)
    try #require(config.contenderPlans[0].contenderPlan.contains("focused board"))
    try #require(config.tournamentExperiments.count == 1)
    try #require(config.tournaments.count == 1)
    try #require(config.tournamentContenders.count == 2)
    try #require(
      config.tournamentRounds.map(\.kind) == [.productPlans, .coreTechnology, .productImplementation])
    try #require(config.tournamentRounds[0].requiresBuiltProduct == false)
    try #require(decoded.candidateTournamentExperiments[0].branchSlug == "incident-command-board")
    try #require(decoded.candidateTournamentExperiments[0].contenderID == "contender-command-board")
    try #require(decoded.assumptions[0].text.contains("Incident leads"))
  }

  @Test func discoverResponseRejectsRetiredCandidateExperimentsKey() throws {
    var output = makeDiscoverOutput()
    output.openQuestions = []
    let legacyJSON = try encodeDiscoverJSON(output).replacingOccurrences(
      of: "\"candidateTournamentExperiments\"",
      with: "\"candidateExperiments\""
    )

    #expect(
      throws: DiscoverPromptValidationError.invalidJSON(
        "Use candidateTournamentExperiments instead of candidateExperiments."
      )
    ) {
      _ = try Prompts.decodeDiscoverResponse(legacyJSON)
    }
  }

  @Test func discoverResponseRejectsCandidateContenderPlanReference() throws {
    let invalidJSON = try discoverJSONWithCandidateContenderPlanReference(makeDiscoverOutput())

    #expect(
      throws: DiscoverPromptValidationError.invalidJSON(
        "Use contenderID instead of contenderPlanID for candidateTournamentExperiments."
      )
    ) {
      _ = try Prompts.decodeDiscoverResponse(invalidJSON)
    }
  }

  @Test func discoverResponseRejectsCandidatePrototypeNameKey() throws {
    let invalidJSON = try discoverJSONWithCandidatePrototypeName(makeDiscoverOutput())

    #expect(
      throws: DiscoverPromptValidationError.invalidJSON(
        "Use implementationName instead of prototypeName for candidateTournamentExperiments."
      )
    ) {
      _ = try Prompts.decodeDiscoverResponse(invalidJSON)
    }
  }

  @Test func discoverResponseRejectsUnsupportedStateEditKey() throws {
    let invalidJSON = try discoverJSONWithUnsupportedStateEditKey(makeDiscoverOutput())

    #expect(
      throws: DiscoverPromptValidationError.invalidJSON(
        "Unsupported stateEdits key retiredPlanIdeas."
      )
    ) {
      _ = try Prompts.decodeDiscoverResponse(invalidJSON)
    }
  }

  @Test func discoverValidationRejectsMissingActivePain() throws {
    var output = makeDiscoverOutput()
    output.stateEdits = DiscoveryStateEdits()

    #expect(throws: DiscoverPromptValidationError.missingActivePainHypothesis) {
      _ = try Prompts.decodeDiscoverResponse(try encodeDiscoverJSON(output))
    }
  }

  @Test func discoverValidationRejectsProductTournamentContenderPlanWithoutPain() throws {
    var output = makeDiscoverOutput()
    output.stateEdits.contenderPlans[0] = ProductTournamentContenderPlan(
      id: "plan-bad",
      painID: "missing-pain",
      title: "Bad contender plan",
      promise: "Help somehow",
      contenderPlan: "Implement something",
      targetSegmentIDs: [],
      differentiator: "Unknown",
      whyThisCouldWin: "Unknown",
      whyThisMightFail: "Unknown",
      requiredProof: ["Proof"],
      status: .active
    )

    #expect(
      throws: DiscoverPromptValidationError.contenderPlanReferencesMissingPain(
        contenderPlanID: "plan-bad",
        painID: "missing-pain"
      )
    ) {
      _ = try Prompts.decodeDiscoverResponse(try encodeDiscoverJSON(output))
    }
  }

  @Test func discoverValidationRejectsInvalidCandidateBranchSlug() throws {
    var output = makeDiscoverOutput()
    output.candidateTournamentExperiments[0] = DiscoveryCandidateTournamentExperiment(
      contenderID: "contender-command-board",
      implementationName: "Incident Command Board",
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

  @Test func discoverValidationRejectsCandidateWithoutContender() throws {
    var output = makeDiscoverOutput()
    output.candidateTournamentExperiments[0] = DiscoveryCandidateTournamentExperiment(
      contenderID: "missing-contender",
      implementationName: "Incident Command Board",
      branchSlug: "incident-command-board",
      smallestWorkflowToProve: "Draft a customer update",
      targetScenarioCohort: "Incident lead cohort",
      expectedEvidenceSignal: "Lead gets a clearer update than chat.",
      killCriteria: "Persona still prefers chat."
    )

    #expect(
      throws: DiscoverPromptValidationError.candidateReferencesMissingContender(
        contenderID: "missing-contender"
      )
    ) {
      _ = try Prompts.decodeDiscoverResponse(try encodeDiscoverJSON(output))
    }
  }

  @Test func discoverValidationRejectsOpenQuestionsAsNextSteps() throws {
    var output = makeDiscoverOutput()
    output.candidateTournamentExperiments = []
    output.openQuestions = ["Build the implementation next"]

    #expect(
      throws: DiscoverPromptValidationError.openQuestionsUsedInsteadOfActionableNextSteps(
        "Build the implementation next"
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
    try #require(written.tournamentExperiments.count == 1)
    try #require(written.scenarioCohorts.count == 1)
  }

  @Test func workspaceMaterializesCandidateTournamentExperimentsAsImplementationTracks() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    var output = makeDiscoverOutput()
    output.stateEdits.tournamentExperiments = []
    output.stateEdits.scenarioCohorts = []
    for contenderIndex in output.stateEdits.tournamentContenders.indices
    where output.stateEdits.tournamentContenders[contenderIndex].id == "contender-command-board"
    {
      output.stateEdits.tournamentContenders[contenderIndex].experimentID = nil
    }
    for roundIndex in output.stateEdits.tournamentRounds.indices {
      output.stateEdits.tournamentRounds[roundIndex].scenarioCohortIDs = []
    }

    let written = try workspace.applyDiscoverOutput(output)
    let experiment = try #require(
      written.tournamentExperiments.first { $0.id == "experiment-incident-command-board" }
    )
    try #require(experiment.title == "Incident Command Board")
    try #require(experiment.contenderPlanID == "plan-command-board")
    try #require(experiment.branchName == "codex/incident-command-board")
    try #require(experiment.worktreeID == "incident-command-board-worktree")
    try #require(
      experiment.scenarioCohortIDs == ["experiment-incident-command-board-starter-cohort"]
    )
    try #require(
      experiment.implementationScope.contains(
        "Draft a customer update from owner and decision context."
      )
    )
    try #require(
      experiment.implementationScope.contains(
        "Persona creates a clearer update than the Slack thread."
      )
    )
    try #require(experiment.implementationScope.contains("Persona still prefers Slack"))

    let linkedContender = try #require(
      written.tournamentContenders.first { $0.id == "contender-command-board" }
    )
    try #require(linkedContender.experimentID == experiment.id)

    let cohort = try #require(
      written.scenarioCohorts.first {
        $0.id == "experiment-incident-command-board-starter-cohort"
      }
    )
    try #require(cohort.title == "Incident lead cohort")
    try #require(cohort.experimentID == experiment.id)
    try #require(cohort.scenarioIDs == ["experiment-incident-command-board-starter-scenario"])
    try #require(cohort.tags == ["discover", "candidate-implementation-track"])
    let scenario = try #require(
      written.scenarios.first { $0.id == "experiment-incident-command-board-starter-scenario" }
    )
    try #require(scenario.experimentID == experiment.id)
    try #require(scenario.segmentID == "segment-incident-lead")
    try #require(scenario.currentWorkflowID == "workflow-chat-triage")
    try #require(scenario.alternativeID == "alternative-chat")
    try #require(scenario.title == "Incident Command Board starter scenario")
    try #require(
      scenario.task.contains("Draft a customer update from owner and decision context.")
    )
    try #require(scenario.task.contains("Compare it with Slack thread."))
    try #require(scenario.successSignal == "Persona creates a clearer update than the Slack thread.")
    try #require(scenario.targetCommitSha == nil)
    try #require(scenario.enabled)

    let planRound = try #require(written.tournamentRounds.first { $0.kind == .productPlans })
    try #require(!planRound.scenarioCohortIDs.contains(cohort.id))
    let builtProductRounds = written.tournamentRounds.filter {
      $0.requiresBuiltProduct && $0.contenderIDs.contains(linkedContender.id)
    }
    try #require(builtProductRounds.count == 2)
    for round in builtProductRounds {
      try #require(round.scenarioCohortIDs.contains(cohort.id))
    }
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
  let commandBoard = ProductTournamentContenderPlan(
    id: "plan-command-board",
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
  let timeline = ProductTournamentContenderPlan(
    id: "plan-timeline",
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
  let experiment = ProductTournamentExperiment(
    id: "experiment-command-board",
    contenderPlanID: commandBoard.id,
    title: "Incident command board implementation",
    branchName: "codex/incident-command-board",
    worktreeID: "incident-command-board-worktree",
    baseSha: nil,
    currentSha: nil,
    implementationScope: "Board with owner queue and update composer.",
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
      "round-incident-product-implementation",
    ],
    currentRoundID: "round-incident-plans",
    status: .active,
    createdAt: timestamp,
    updatedAt: timestamp
  )
  let commandBoardContender = ProductTournamentContender(
    id: "contender-command-board",
    tournamentID: tournament.id,
    contenderPlanID: commandBoard.id,
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
    contenderPlanID: timeline.id,
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
      id: "round-incident-product-implementation",
      tournamentID: tournament.id,
      ordinal: 3,
      kind: .productImplementation,
      title: "Round 3: product implementation",
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
      contenderPlans: [commandBoard, timeline],
      tournamentExperiments: [experiment],
      tournaments: [tournament],
      tournamentContenders: [commandBoardContender, timelineContender],
      tournamentRounds: rounds,
      scenarioCohorts: [cohort],
      decisions: []
    ),
    candidateTournamentExperiments: [
      DiscoveryCandidateTournamentExperiment(
        contenderID: commandBoardContender.id,
        implementationName: "Incident Command Board",
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
        impact: "Prioritizes update composer implementation scope.",
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

private func discoverJSONWithCandidateContenderPlanReference(_ output: DiscoverPromptOutput) throws
  -> String
{
  let data = Data(try encodeDiscoverJSON(output).utf8)
  var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  var candidates = try #require(object["candidateTournamentExperiments"] as? [[String: Any]])
  var firstCandidate = try #require(candidates.first)
  firstCandidate["contenderPlanID"] = firstCandidate.removeValue(forKey: "contenderID")
  candidates[0] = firstCandidate
  object["candidateTournamentExperiments"] = candidates
  let invalidData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  return String(decoding: invalidData, as: UTF8.self)
}

private func discoverJSONWithCandidatePrototypeName(_ output: DiscoverPromptOutput) throws -> String {
  let data = Data(try encodeDiscoverJSON(output).utf8)
  var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  var candidates = try #require(object["candidateTournamentExperiments"] as? [[String: Any]])
  var firstCandidate = try #require(candidates.first)
  firstCandidate["prototypeName"] = firstCandidate.removeValue(forKey: "implementationName")
  candidates[0] = firstCandidate
  object["candidateTournamentExperiments"] = candidates
  let invalidData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  return String(decoding: invalidData, as: UTF8.self)
}

private func discoverJSONWithUnsupportedStateEditKey(_ output: DiscoverPromptOutput) throws
  -> String
{
  let data = Data(try encodeDiscoverJSON(output).utf8)
  var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  var stateEdits = try #require(object["stateEdits"] as? [String: Any])
  stateEdits["retiredPlanIdeas"] = []
  object["stateEdits"] = stateEdits
  let invalidData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  return String(decoding: invalidData, as: UTF8.self)
}

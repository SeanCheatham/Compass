import Foundation
import Testing

@testable import Compass

struct PMFContextPackTests {
  @Test func planPacksStayUnderBudgetAndRetainProofCore() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "ProofBoard",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 10)
    )
    let ledger = PMFProofLedger.build(config: config, evidenceIndex: .empty)
    let packs = PMFContextPackPlanner.plan(
      ledger: ledger,
      evidenceIndex: .empty,
      phase: .plan,
      tokenBudget: 900
    )

    try #require(packs.totalEstimatedTokens <= 900)
    try #require(packs.packNames == ["proof_core", "evidence_slice", "tool_budget"])
    try #require(packs.promptText.contains("PMF Proof Ledger"))
    try #require(packs.promptText.contains("Hypothesis:"))
    try #require(packs.promptText.contains(ledger.riskiestUnknown?.title ?? ""))
    try #require(packs.promptText.contains(ledger.nextAction?.kind.rawValue ?? ""))
  }

  @Test func evidenceSliceKeepsActiveEvidenceAndOmitsSiblingDetails() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "ProofBoard",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 10)
    )
    let emptyLedger = PMFProofLedger.build(config: config, evidenceIndex: .empty)
    let activeExperimentID = try #require(
      emptyLedger.nextAction?.legacyReferences.first { $0.kind == .experimentID }?.value
    )
    let activeExperiment = try #require(
      config.tournamentExperiments.first { $0.id == activeExperimentID }
    )
    let siblingExperiment = try #require(
      config.tournamentExperiments.first { $0.id != activeExperimentID }
    )
    let activeRecord = makeEvidenceRecord(
      id: "active-run",
      experiment: activeExperiment,
      config: config,
      missingCapabilities: ["csv_import"],
      comparison: "Active contender still needs import proof before switching.",
      personaActionRationales: [
        "turn 2 choose valid action reduce_switching_objection: Needed import proof."
      ]
    )
    let siblingRecord = makeEvidenceRecord(
      id: "sibling-run",
      experiment: siblingExperiment,
      config: config,
      missingCapabilities: ["sibling_only_detail"],
      comparison: "Sibling contender detail should not be in the active slice."
    )
    let index = ProductTournamentEvidenceIndex.build(records: [activeRecord, siblingRecord])
    let ledger = PMFProofLedger.build(config: config, evidenceIndex: index)
    let packs = PMFContextPackPlanner.plan(
      ledger: ledger,
      evidenceIndex: index,
      phase: .plan,
      tokenBudget: 1_200
    )
    let text = packs.promptText

    try #require(text.contains("active-run"))
    try #require(text.contains("csv_import"))
    try #require(text.contains("persona_rationale"))
    try #require(!text.contains("sibling-run"))
    try #require(!text.contains("sibling_only_detail"))
  }

  @Test func planPromptUsesContextPacksAndOmitsBroadTournamentDigest() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "ProofBoard",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 10)
    )
    let ledger = PMFProofLedger.build(config: config, evidenceIndex: .empty)
    let packs = PMFContextPackPlanner.plan(
      ledger: ledger,
      evidenceIndex: .empty,
      phase: .plan,
      tokenBudget: 2_500
    )
    let fullDigest = ProductTournamentPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: .empty
    )
    let fullDigestTokens = AgentRunTokenUsage.estimateTokens(
      characters: fullDigest.count,
      charsPerToken: AgentExecutor.estimatedCharsPerToken
    )
    let prompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature,
      productTournamentConfig: config,
      productTournamentEvidenceIndex: .empty
    )

    try #require(packs.totalEstimatedTokens < fullDigestTokens)
    try #require(prompt.contains("PMF Context Packs"))
    try #require(prompt.contains("proof_core"))
    try #require(prompt.contains("Product Tournament Context is minimized"))
    try #require(!prompt.contains("Next tournament automation actions"))
    try #require(!prompt.contains("Tournament automation proof targets"))
  }

  private func makeEvidenceRecord(
    id: String,
    experiment: ProductTournamentExperiment,
    config: ProductTournamentConfig,
    missingCapabilities: [String] = [],
    comparison: String = "Compared with the current alternative.",
    personaActionRationales: [String] = []
  ) -> ProductTournamentEvidenceRecord {
    let contender = config.tournamentContenders.first {
      $0.experimentID == experiment.id
    }
    let tournament = config.tournaments.first
    let round = config.tournamentRounds.first
    return ProductTournamentEvidenceRecord(
      id: id,
      experimentID: experiment.id,
      contenderPlanID: experiment.contenderPlanID,
      painID: config.painHypotheses.first?.id ?? "pain-one",
      tournamentID: tournament?.id,
      roundID: round?.id,
      contenderID: contender?.id,
      branchName: experiment.branchName,
      commitSha: "abc123",
      scenarioID: config.scenarioCohorts.first?.scenarioIDs.first ?? "scenario-one",
      personaID: config.userSegments.first?.id ?? "segment-one",
      mode: .modelFree,
      status: .completed,
      startedAt: 10,
      endedAt: id == "active-run" ? 30 : 20,
      traceHash: "trace-\(id)",
      completedUseProof: true,
      promptVersions: ["test.context-pack"],
      model: "model-free",
      scores: ProductTournamentEvidenceScores(
        painRecognition: 4,
        workflowImprovement: 3,
        alternativeAdvantage: 3,
        switchingReadiness: 2,
        continuedUsePull: 3
      ),
      objections: ["The spreadsheet is already trusted"],
      missingCapabilities: missingCapabilities,
      currentAlternativeComparison: comparison,
      personaActionRationales: personaActionRationales,
      verdict: .promising,
      summary: "Evidence summary for \(id)."
    )
  }
}

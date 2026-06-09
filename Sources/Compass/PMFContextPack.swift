import Foundation

struct PMFContextPack: Equatable, Sendable, Identifiable {
  enum Name: String, Codable, Equatable, Sendable, CaseIterable {
    case proofCore = "proof_core"
    case repoSlice = "repo_slice"
    case historySlice = "history_slice"
    case evidenceSlice = "evidence_slice"
    case toolBudget = "tool_budget"
  }

  var id: String { name.rawValue }
  var name: Name
  var purpose: String
  var text: String
  var estimatedTokens: Int
  var sourceReferences: [PMFProofSourceReference]

  init(
    name: Name,
    purpose: String,
    text: String,
    sourceReferences: [PMFProofSourceReference] = [],
    charsPerToken: Int = AgentExecutor.estimatedCharsPerToken
  ) {
    self.name = name
    self.purpose = bounded(purpose, limit: 180)
    self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    estimatedTokens = AgentRunTokenUsage.estimateTokens(
      characters: self.text.count,
      charsPerToken: charsPerToken
    )
    self.sourceReferences = Self.uniqued(sourceReferences)
  }

  var promptText: String {
    """
    [\(name.rawValue)] \(purpose) (~\(estimatedTokens) tokens)
    \(text)
    """
  }

  private static func uniqued(_ refs: [PMFProofSourceReference]) -> [PMFProofSourceReference] {
    var seen = Set<PMFProofSourceReference>()
    var result: [PMFProofSourceReference] = []
    for ref in refs where !ref.value.isEmpty {
      if seen.insert(ref).inserted {
        result.append(ref)
      }
    }
    return result
  }
}

struct PMFContextPackPlan: Equatable, Sendable {
  var phase: AgentPhase
  var tokenBudget: Int
  var packs: [PMFContextPack]

  var totalEstimatedTokens: Int {
    packs.reduce(0) { $0 + $1.estimatedTokens }
  }

  var packNames: [String] {
    packs.map { $0.name.rawValue }
  }

  var diagnosticsText: String {
    let names = packs
      .map { "\($0.name.rawValue)=~\($0.estimatedTokens)" }
      .joined(separator: ", ")
    return "Context packs: \(names). Total ~\(totalEstimatedTokens)/\(tokenBudget) estimated tokens."
  }

  var promptText: String {
    var lines = [
      "PMF Context Packs",
      diagnosticsText,
    ]
    lines += packs.map(\.promptText)
    return lines.joined(separator: "\n\n")
  }

  var legacyCompatibilityText: String {
    let refs = packs
      .flatMap(\.sourceReferences)
      .prefix(10)
      .map { "\($0.kind.rawValue)=\($0.value)" }
      .joined(separator: ", ")
    return [
      "Product Tournament Context is minimized for this PMF proof action.",
      "Use the PMF context packs above as the source of truth; legacy tournament IDs are kept only for compatibility.",
      refs.isEmpty ? nil : "Legacy refs: \(refs)",
      diagnosticsText,
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
  }
}

enum PMFContextPackPlanner {
  static func plan(
    ledger: PMFProofLedger,
    productTournamentConfig: ProductTournamentConfig = .empty,
    evidenceIndex: ProductTournamentEvidenceIndex,
    phase: AgentPhase,
    proofActionKind: PMFProofActionKind? = nil,
    tokenBudget: Int
  ) -> PMFContextPackPlan {
    let budget = max(600, tokenBudget)
    let proofLimit = max(350, Int(Double(budget) * 0.45))
    let evidenceLimit = max(200, Int(Double(budget) * 0.35))
    let toolLimit = max(120, budget - proofLimit - evidenceLimit)
    let actionKind = proofActionKind ?? ledger.nextAction?.kind
    let proofCoreText = [
      ledger.promptDigest,
      actionSupplementText(
        actionKind: actionKind,
        ledger: ledger,
        productTournamentConfig: productTournamentConfig,
        evidenceIndex: evidenceIndex
      ),
    ]
    .filter { !$0.isEmpty }
    .joined(separator: "\n")

    var packs: [PMFContextPack] = [
      pack(
        name: .proofCore,
        purpose: "Current PMF hypothesis, riskiest unknowns, and next proof action.",
        text: proofCoreText,
        tokenLimit: proofLimit,
        sourceReferences: ledger.nextAction?.legacyReferences ?? ledger.hypothesis.sourceReferences
      ),
      pack(
        name: .evidenceSlice,
        purpose: "Latest evidence for the active proof target without sibling contender detail.",
        text: evidenceSliceText(ledger: ledger, evidenceIndex: evidenceIndex),
        tokenLimit: evidenceLimit,
        sourceReferences: evidenceSourceReferences(ledger: ledger, evidenceIndex: evidenceIndex)
      ),
      pack(
        name: .toolBudget,
        purpose: "Tool budget and stop condition for this phase.",
        text: toolBudgetText(phase: phase, actionKind: actionKind),
        tokenLimit: toolLimit,
        sourceReferences: ledger.nextAction?.legacyReferences ?? []
      ),
    ]

    packs = trimPacks(packs, toBudget: budget)
    return PMFContextPackPlan(phase: phase, tokenBudget: budget, packs: packs)
  }

  private static func actionSupplementText(
    actionKind: PMFProofActionKind?,
    ledger: PMFProofLedger,
    productTournamentConfig: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String {
    guard actionKind == .buildFeasibilitySlice, !productTournamentConfig.isEmpty else {
      return ""
    }
    guard let handoff = selectedFeasibilityHandoff(
      ledger: ledger,
      productTournamentConfig: productTournamentConfig,
      evidenceIndex: evidenceIndex
    ) else {
      return ""
    }

    var lines = ["Round 2 implementation target:"]
    lines.append(bounded(handoff.implementationTargetLine, limit: 760))
    if handoff.implementationBrief.isCandidateDerived {
      let expectedEvidence =
        handoff.implementationBrief.expectedEvidenceSignal ?? "no expected evidence signal"
      let killCriteria = handoff.implementationBrief.killCriteria ?? "no kill criteria"
      lines.append(
        bounded(
          "- round_2_candidate_track_signal selected_experiment \(handoff.experimentID) [tournament \(handoff.tournamentID), round \(handoff.roundID), only_contender \(handoff.contenderID)]: expected_evidence \(expectedEvidence); kill_criteria \(killCriteria); implementation_scope \(handoff.implementationBrief.scopeSummary).",
          limit: 760
        )
      )
    }
    let target = ProductTournamentRoundImplementationTarget(
      tournamentID: handoff.tournamentID,
      roundID: handoff.roundID,
      contenderID: handoff.contenderID,
      experimentID: handoff.experimentID
    )
    let pausedSiblingExperimentIDs =
      ProductTournamentRoundImplementationTargetResolver.blockedSiblingExperimentIDs(
        for: target,
        in: productTournamentConfig
      )
    if !pausedSiblingExperimentIDs.isEmpty {
      lines.append(
        bounded(
          "- round_2_evidence_lock selected_experiment \(handoff.experimentID) [tournament \(handoff.tournamentID), round \(handoff.roundID), only_contender \(handoff.contenderID), paused_sibling_experiments \(pausedSiblingExperimentIDs.joined(separator: ", "))]: sibling tournament automation evidence is paused; run only the selected core_technology_proof \(handoff.coreTechnologyProof).",
          limit: 760
        )
      )
    }
    return lines.joined(separator: "\n")
  }

  private static func selectedFeasibilityHandoff(
    ledger: PMFProofLedger,
    productTournamentConfig: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> ProductTournamentFeasibilityHandoff? {
    let handoffs = ProductTournamentFeasibilityAdvisor.handoffs(
      config: productTournamentConfig,
      evidenceIndex: evidenceIndex
    )
    guard !handoffs.isEmpty else { return nil }

    let refs = Set(
      (ledger.nextAction?.legacyReferences ?? ledger.hypothesis.sourceReferences)
        .map(\.value)
    )
    guard !refs.isEmpty else { return handoffs.first }
    return handoffs.first { handoff in
      [
        handoff.tournamentID,
        handoff.roundID,
        handoff.contenderID,
        handoff.contenderPlanID,
        handoff.experimentID,
      ].contains { refs.contains($0) }
    } ?? handoffs.first
  }

  private static func pack(
    name: PMFContextPack.Name,
    purpose: String,
    text: String,
    tokenLimit: Int,
    sourceReferences: [PMFProofSourceReference]
  ) -> PMFContextPack {
    PMFContextPack(
      name: name,
      purpose: purpose,
      text: bounded(text, limit: tokenLimit * AgentExecutor.estimatedCharsPerToken),
      sourceReferences: sourceReferences
    )
  }

  private static func trimPacks(
    _ packs: [PMFContextPack],
    toBudget budget: Int
  ) -> [PMFContextPack] {
    guard packs.reduce(0, { $0 + $1.estimatedTokens }) > budget else { return packs }
    let perPackBudget = max(120, budget / max(1, packs.count))
    return packs.map { pack in
      PMFContextPack(
        name: pack.name,
        purpose: pack.purpose,
        text: bounded(pack.text, limit: perPackBudget * AgentExecutor.estimatedCharsPerToken),
        sourceReferences: pack.sourceReferences
      )
    }
  }

  private static func evidenceSliceText(
    ledger: PMFProofLedger,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String {
    let matching = filteredEvidenceSummaries(ledger: ledger, evidenceIndex: evidenceIndex)
    guard !matching.isEmpty else {
      return "Latest evidence: none for the active proof target."
    }

    var lines = ["Latest active-hypothesis evidence:"]
    for summary in matching.prefix(3) {
      lines.append(
        "- run \(summary.runID); branch \(summary.branchName); mode \(summary.mode.rawValue); verdict \(summary.verdict.rawValue); completed_use_proof \(summary.completedUseProof ? "yes" : "no"); \(bounded(summary.summary, limit: 220))"
      )
      if !summary.currentAlternativeComparison.isEmpty {
        lines.append("- comparison: \(bounded(summary.currentAlternativeComparison, limit: 220))")
      }
      if !summary.objections.isEmpty {
        lines.append(
          "- objections: \(bounded(summary.objections.prefix(3).joined(separator: "; "), limit: 220))"
        )
      }
      if !summary.missingCapabilities.isEmpty {
        lines.append(
          "- missing: \(bounded(summary.missingCapabilities.prefix(3).joined(separator: "; "), limit: 180))"
        )
      }
      if !summary.personaActionRationales.isEmpty {
        lines.append(
          "- persona_rationale: \(bounded(summary.personaActionRationales.prefix(2).joined(separator: "; "), limit: 260))"
        )
      }
    }
    if matching.count > 3 {
      lines.append("- \(matching.count - 3) additional evidence item(s) omitted.")
    }
    return lines.joined(separator: "\n")
  }

  private static func filteredEvidenceSummaries(
    ledger: PMFProofLedger,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [ProductTournamentEvidenceSummary] {
    let refs = ledger.nextAction?.legacyReferences ?? ledger.hypothesis.sourceReferences
    let strongRefs = Set(
      refs
        .filter {
          $0.kind == .experimentID || $0.kind == .contenderID || $0.kind == .contenderPlanID
        }
        .map(\.value)
    )
    if !strongRefs.isEmpty {
      let filtered = evidenceIndex.summaries.filter { summary in
        [
          summary.experimentID,
          summary.contenderPlanID,
          summary.contenderID,
        ]
        .compactMap { $0 }
        .contains { strongRefs.contains($0) }
      }
      if !filtered.isEmpty { return filtered }
    }

    let activeRefs = Set(refs.map(\.value))
    guard !activeRefs.isEmpty else {
      return evidenceIndex.summaries
    }
    let filtered = evidenceIndex.summaries.filter { summary in
      [
        summary.experimentID,
        summary.contenderPlanID,
        summary.painID,
        summary.tournamentID,
        summary.roundID,
        summary.contenderID,
        summary.runID,
      ]
      .compactMap { $0 }
      .contains { activeRefs.contains($0) }
    }
    return filtered.isEmpty ? Array(evidenceIndex.summaries.prefix(3)) : filtered
  }

  private static func evidenceSourceReferences(
    ledger: PMFProofLedger,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> [PMFProofSourceReference] {
    filteredEvidenceSummaries(ledger: ledger, evidenceIndex: evidenceIndex)
      .prefix(3)
      .flatMap { summary in
        [
          PMFProofSourceReference(kind: .evidenceRunID, value: summary.runID),
          PMFProofSourceReference(kind: .experimentID, value: summary.experimentID),
          summary.contenderID.map { PMFProofSourceReference(kind: .contenderID, value: $0) },
          summary.tournamentID.map { PMFProofSourceReference(kind: .tournamentID, value: $0) },
        ]
        .compactMap { $0 }
      }
  }

  private static func toolBudgetText(
    phase: AgentPhase,
    actionKind: PMFProofActionKind?
  ) -> String {
    let action = actionKind?.rawValue ?? "unknown"
    switch phase {
    case .plan:
      return """
        Allowed tools: read-only repository probes and targeted shell checks.
        Expected tool calls: inspect only files or tests needed to choose the next \(action) slice.
        Stop condition: submit one Immediate handoff plus pmfProofAction metadata when the smallest proof is clear.
        """
    case .develop:
      return """
        Allowed tools: edit files, run the verify command, and inspect narrow repo slices.
        Expected tool calls: implement only the \(action) proof handoff.
        Stop condition: verify passes or feedback names the smallest Plan recovery.
        """
    case .reflect:
      return """
        Allowed tools: read-only probes over recent evidence and sessions.
        Expected tool calls: inspect only evidence needed to judge \(action).
        Stop condition: summarize proof debt movement and token worthiness.
        """
    case .critic:
      return """
        Allowed tools: read-only review probes and focused test reruns.
        Expected tool calls: audit whether the diff delivered \(action).
        Stop condition: approve or request one concrete Develop recovery.
        """
    }
  }
}

private func bounded(_ value: String, limit: Int) -> String {
  StringUtils.boundedText(value, limit: limit)
}

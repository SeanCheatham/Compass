import AppKit
import CompassCore
import Foundation

@MainActor
extension CompassProject {
  /// Record ship traces for targeted requirements after Critic approve + commit.
  func recordRequirementShipTraces(
    workspace: CompassWorkspace,
    shipped: PlanNext,
    sessionNumber: Int,
    commit: String?,
    changedPaths: [String] = []
  ) {
    let brief = workspace.readBrief()
    var ledger = workspace.readRequirementLedger(reconciledWith: brief)
    let targeted = shipped.targetedRequirementIDs ?? []
    if !targeted.isEmpty {
      ledger = ledger.recordingShip(
        requirementIDs: targeted,
        session: sessionNumber,
        commit: commit,
        verify: shipped.verify,
        planSummary: firstLine(shipped.plan)
      )
    }
    if !changedPaths.isEmpty {
      ledger = ledger.markingStale(
        changedPaths: changedPaths,
        excludingRequirementIDs: Set(targeted)
      )
    }
    try? workspace.writeRequirementLedger(ledger, reconciledWith: brief)
    requirementLedger = ledger
  }

  /// Run criteria + requirements audit agent for the given requirement ids
  /// (nil/empty = all brief requirements). Persists the updated ledger.
  @discardableResult
  func runRequirementsAuditPass(
    workspace: CompassWorkspace,
    requirementIDs: [String]?,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    sessionIndex: Int,
    commit: String?
  ) async -> RequirementLedger {
    let brief = workspace.readBrief()
    var ledger = workspace.readRequirementLedger(reconciledWith: brief)
    let scopedIDs: [String]
    if let requirementIDs, !requirementIDs.isEmpty {
      scopedIDs = requirementIDs.filter { id in
        brief.nonEmptyRequirements.contains(where: { $0.id == id })
      }
    } else {
      scopedIDs = brief.nonEmptyRequirements.map(\.id)
    }

    guard !scopedIDs.isEmpty else {
      requirementLedger = ledger
      return ledger
    }

    phase = .auditing
    log(
      "Requirements audit: \(scopedIDs.count) requirement(s).",
      level: .info
    )

    let launchPlan = agentLaunchPlan(for: workspace.repoURL)
    let criterionResults = await RequirementCriteriaRunner.collect(
      ledger: ledger,
      requirementIDs: scopedIDs,
      brief: brief
    ) { command in
      let result = try await self.runVerifyCommand(
        command: command,
        hostWorkingDirectory: workspace.repoURL,
        timeoutSeconds: 600,
        launchPlan: launchPlan,
        mirrorToStudio: false
      )
      return (
        exitCode: Int(result.exitCode),
        output: result.stdout + "\n" + result.stderr
      )
    }

    let failedCount = criterionResults.filter { !$0.passed }.count
    if !criterionResults.isEmpty {
      log(
        "Ran \(criterionResults.count) requirement criterion command(s); \(failedCount) failed.",
        level: failedCount == 0 ? .success : .warning
      )
    }

    guard sessions.indices.contains(sessionIndex) else { return ledger }
    let sessionNumber = sessions[sessionIndex].session

    let prompt = Prompts.requirementsAuditPrompt(
      brief: brief,
      ledger: ledger,
      requirementIDs: scopedIDs,
      criterionResults: criterionResults,
      commit: commit,
      promptMode: ModelRuntimeFactory.promptMode(settings: agentSettings)
    )
    do {
      let promptURL = try workspace.writeSessionArtifact(
        session: sessionNumber,
        name: "requirements-audit-prompt.md",
        contents: prompt
      )
      log("Saved Requirements Audit prompt: \(promptURL.path)", level: .info)

      let agentResult = try await runAgent(
        phase: .requirementsAudit,
        agentSettings: agentSettings,
        modelOverride: modelOverride,
        workingDirectory: workspace.repoURL,
        userPrompt: prompt,
        submitResultSchema: Prompts.requirementsAuditSchema,
        codemapStoreDirectory: CodemapStore.defaultDirectory(forWorkspace: workspace),
        sessionNumber: sessionNumber,
        decode: RequirementsAuditResult.self
      )

      ledger = RequirementAuditEvaluator.apply(
        agentResult: agentResult,
        criterionResults: criterionResults,
        into: ledger,
        brief: brief,
        commit: commit
      )
      ledger = ledger.reconciled(with: brief)
      try workspace.writeRequirementLedger(ledger, reconciledWith: brief)
      requirementLedger = ledger

      let satisfied = scopedIDs.filter { ledger.entry(for: $0)?.status == .satisfied }.count
      log(
        "Requirements audit complete: \(satisfied)/\(scopedIDs.count) satisfied. \(agentResult.summary)",
        level: satisfied == scopedIDs.count ? .success : .warning
      )
      appendSessionNote(
        "Requirements audit: \(satisfied)/\(scopedIDs.count) satisfied. \(agentResult.summary)",
        to: sessionIndex
      )
    } catch {
      if !criterionResults.isEmpty {
        let synthetic = RequirementsAuditResult(
          results: scopedIDs.map { id in
            RequirementAuditItemResult(
              requirementID: id,
              verdict: criterionResults.contains { $0.requirementID == id && !$0.passed }
                ? .unsatisfied : .unverified,
              evidence: ["Audit agent failed: \(error.localizedDescription)"]
            )
          },
          summary: "Audit agent failed; criterion overrides applied where available."
        )
        ledger = RequirementAuditEvaluator.apply(
          agentResult: synthetic,
          criterionResults: criterionResults,
          into: ledger,
          brief: brief,
          commit: commit
        )
        try? workspace.writeRequirementLedger(ledger, reconciledWith: brief)
        requirementLedger = ledger
      }
      log(
        "Requirements audit agent failed: \(error.localizedDescription)",
        level: .warning
      )
      appendSessionNote(
        "Requirements audit failed: \(error.localizedDescription)",
        to: sessionIndex
      )
    }

    return ledger
  }
}

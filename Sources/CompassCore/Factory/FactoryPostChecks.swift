import Foundation

/// Shared post-Develop check evaluation used by UI and headless factory loops.
public enum FactoryPostChecks {
  /// Develop-status and verify-bypass decisions before running the verify command.
  public struct PreVerifyDecision: Equatable, Sendable {
    public var earlyIssues: [String]
    public var requiresPlanRepair: Bool
    public var skipVerify: Bool
    public var verifyCommand: String
    public var autoRepairNote: String?

    public init(
      earlyIssues: [String] = [],
      requiresPlanRepair: Bool = false,
      skipVerify: Bool = false,
      verifyCommand: String,
      autoRepairNote: String? = nil
    ) {
      self.earlyIssues = earlyIssues
      self.requiresPlanRepair = requiresPlanRepair
      self.skipVerify = skipVerify
      self.verifyCommand = verifyCommand
      self.autoRepairNote = autoRepairNote
    }
  }

  public static func preVerifyDecision(
    next: PlanNext,
    summary: DevelopSummary
  ) -> PreVerifyDecision {
    var earlyIssues: [String] = []
    switch summary.status {
    case .succeeded:
      break
    case .blocked:
      if summary.bypassVerify != true {
        earlyIssues.append(
          "[verify] Develop reported it was blocked but did not request verify bypass.")
      }
    case .failed:
      earlyIssues.append("[verify] Develop reported failure: \(summary.feedback)")
    }

    let autoRepair = VerifyBypassAutoRepair.repair(
      plannedCommand: next.verify,
      developSummary: summary
    )

    if summary.bypassVerify == true, autoRepair == nil {
      let issue = """
        [verify] Verify was skipped because Develop reported the planned command is wrong or out of scope.
        Planned verify command: `\(next.verify)`
        Develop handoff: \(summary.feedback)
        Plan should replace the verify command or rescope Immediate Work before Develop continues.
        """
      earlyIssues.append(issue)
      return PreVerifyDecision(
        earlyIssues: earlyIssues,
        requiresPlanRepair: true,
        skipVerify: true,
        verifyCommand: next.verify,
        autoRepairNote: nil
      )
    }

    let command = autoRepair?.command ?? next.verify
    let note: String? = {
      guard let autoRepair else { return nil }
      return """
        [verify] Auto-repaired Develop verify bypass (\(autoRepair.reason.rawValue)).
        Planned verify command: `\(next.verify)`
        Repaired verify command: `\(autoRepair.command)`
        \(autoRepair.note)
        """
    }()
    return PreVerifyDecision(
      earlyIssues: earlyIssues,
      requiresPlanRepair: false,
      skipVerify: false,
      verifyCommand: command,
      autoRepairNote: note
    )
  }

  /// Semantic gates that run after a green verify exit.
  public static func issuesAfterGreenVerify(
    next: PlanNext,
    state: PlanState,
    workspace: CompassWorkspace,
    verifyCommand: String,
    verifyOutput: String,
    changedPaths: [String]?,
    repoURL: URL
  ) -> [String] {
    var issues: [String] = []
    if let finding = SuccessfulVerifyGates.firstFinding(
      immediate: next,
      brief: state.brief,
      command: verifyCommand,
      verifyOutput: verifyOutput,
      changedPaths: changedPaths,
      repoURL: repoURL
    ) {
      issues.append(finding.issue)
    }
    let gateIssues = AcceptanceGateEvaluator.issues(state: state, workspace: workspace)
    issues.append(contentsOf: gateIssues)
    return issues
  }

  public static func failedVerifyIssue(
    command: String,
    exitCode: Int32,
    output: String,
    plannedCommand: String,
    developFeedback: String,
    wasAutoRepaired: Bool
  ) -> (issue: String, verifyOutput: VerifyOutput, requiresPlanRepair: Bool) {
    let verifyTail = String(output.suffix(4000))
    let outputRecord = VerifyOutput(
      command: command,
      exitCode: Int(exitCode),
      tail: verifyTail
    )
    var issue = """
      [verify] Verify command `\(command)` exited with code \(exitCode). Output (tail):
      ```
      \(verifyTail)
      ```
      """
    var requiresPlanRepair = false
    if wasAutoRepaired {
      requiresPlanRepair = true
      issue += """


        [verify] Auto-repaired verify command failed after Develop requested bypassVerify=true.
        Planned verify command: `\(plannedCommand)`
        Repaired verify command: `\(command)`
        Develop handoff: \(developFeedback)
        Plan should now replace the verify command or rescope Immediate Work.
        """
    }
    return (issue, outputRecord, requiresPlanRepair)
  }

  public static func workingTreeIssues(
    porcelain: String,
    changedPaths: [String],
    develop: DevelopSummary
  ) -> (issues: [String], dirtyPendingHarnessCommit: Bool) {
    let assessment = DevelopPostCheckIssues.hostWorkingTreeIssues(
      porcelain: porcelain,
      changedPaths: changedPaths,
      develop: develop
    )
    var issues = assessment.issues
    if let message = GeneratedArtifactHygiene.formattedIssue(
      from: GeneratedArtifactHygiene.issues(forChangedPaths: changedPaths)
    ) {
      issues.append(message)
    }
    return (issues, assessment.dirtyPendingHarnessCommit)
  }
}

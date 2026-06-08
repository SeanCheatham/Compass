import Foundation

struct ProductTestDraftInput: Equatable, Sendable {
  var id: String?
  var experimentID: String
  var cohortID: String?
  var cohortTitle: String
  var cohortEnabled: Bool
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
}

struct ProductTestDraft: Equatable, Sendable {
  var productQuestion: String
  var targetUser: String
  var currentWorkflow: String
  var currentAlternative: String
  var productActionPath: String
  var successSignal: String
  var evidenceGap: String
  var expectedDecision: String
  var runSettingSummary: String
  var previewLines: [String]
  var validationItems: [ProductTestValidationItem]
  var auditReferences: [AuditReference]

  var canRun: Bool {
    validationItems.allSatisfy { $0.state == .ready }
  }

  static func build(
    input: ProductTestDraftInput,
    config: ProductTournamentConfig,
    nextMove: NextMoveSummary?,
    contractAvailable: Bool?,
    blockedReason: String?
  ) -> ProductTestDraft {
    let experiment = config.tournamentExperiments.first { $0.id == input.experimentID }
    let segment = config.userSegments.first { $0.id == input.segmentID }
    let workflow = config.currentWorkflows.first { $0.id == input.currentWorkflowID }
    let alternative = input.alternativeID.flatMap { id in
      config.alternatives.first { $0.id == id }
    }
    let title = clean(input.title)
    let task = clean(input.task)
    let success = clean(input.successSignal)
    let targetUser = segment.map { "\($0.name) - \($0.role)" } ?? "Target user not selected"
    let workflowTitle = workflow?.title ?? "Current workflow not selected"
    let alternativeTitle = alternative?.title ?? "No current alternative selected"
    let evidenceGap = nextMove?.why ?? "Evidence target not selected"
    let expectedDecision = nextMove?.expectedDecision ?? "Decide the next tournament move"
    let question =
      title.isEmpty
      ? questionFrom(nextMove: nextMove, segment: segment, experiment: experiment)
      : title
    let runSettingSummary =
      "\(input.enabled ? "enabled" : "disabled"), \(input.cohortEnabled ? "cohort enabled" : "cohort disabled"), \(max(1, input.maxTurns)) turns"
    let validations = validationItems(
      input: input,
      segment: segment,
      workflow: workflow,
      task: task,
      successSignal: success,
      nextMove: nextMove,
      contractAvailable: contractAvailable,
      blockedReason: blockedReason,
      experiment: experiment
    )
    var auditReferences: [AuditReference] = [
      AuditReference(kind: .experiment, label: "Experiment ID", value: input.experimentID)
    ]
    if let id = input.id, !id.isEmpty {
      auditReferences.append(AuditReference(kind: .scenario, label: "Scenario ID", value: id))
    }
    if let cohortID = input.cohortID, !cohortID.isEmpty {
      auditReferences.append(AuditReference(kind: .cohort, label: "Cohort ID", value: cohortID))
    }
    if let commit = input.targetCommitSha, !commit.isEmpty {
      auditReferences.append(AuditReference(kind: .commit, label: "Target commit", value: commit))
    }

    return ProductTestDraft(
      productQuestion: question,
      targetUser: targetUser,
      currentWorkflow: workflowTitle,
      currentAlternative: alternativeTitle,
      productActionPath: task.isEmpty ? "Product action path not written yet" : task,
      successSignal: success.isEmpty ? "Success signal not written yet" : success,
      evidenceGap: evidenceGap,
      expectedDecision: expectedDecision,
      runSettingSummary: runSettingSummary,
      previewLines: [
        "This test asks whether \(targetUser) gets enough relief from \(experiment?.title ?? "the product contender").",
        "It compares against \(alternativeTitle) in \(workflowTitle).",
        "It counts as success when \(success.isEmpty ? "an observable signal is captured" : success).",
        "It helps decide: \(expectedDecision).",
      ],
      validationItems: validations,
      auditReferences: uniqueAuditReferences(auditReferences)
    )
  }

  private static func validationItems(
    input: ProductTestDraftInput,
    segment: UserSegment?,
    workflow: CurrentWorkflow?,
    task: String,
    successSignal: String,
    nextMove: NextMoveSummary?,
    contractAvailable: Bool?,
    blockedReason: String?,
    experiment: ProductTournamentExperiment?
  ) -> [ProductTestValidationItem] {
    [
      ProductTestValidationItem(
        title: "Target user",
        detail: segment?.name ?? "Select a target user",
        state: segment == nil ? .missing : .ready
      ),
      ProductTestValidationItem(
        title: "Baseline workflow",
        detail: workflow?.title ?? "Select the current workflow",
        state: workflow == nil ? .missing : .ready
      ),
      ProductTestValidationItem(
        title: "Product action",
        detail: task.isEmpty ? "Write a specific product task" : task,
        state: task.count >= 12 ? .ready : .missing
      ),
      ProductTestValidationItem(
        title: "Success signal",
        detail: successSignal.isEmpty ? "Write an observable success signal" : successSignal,
        state: successSignal.count >= 8 ? .ready : .missing
      ),
      ProductTestValidationItem(
        title: "Evidence target",
        detail: nextMove?.actionTitle ?? "Choose the proof this scenario supports",
        state: nextMove == nil ? .missing : .ready
      ),
      ProductTestValidationItem(
        title: "Commit and contract",
        detail: commitContractDetail(
          input: input,
          experiment: experiment,
          contractAvailable: contractAvailable,
          blockedReason: blockedReason
        ),
        state: commitContractState(
          input: input,
          experiment: experiment,
          contractAvailable: contractAvailable,
          blockedReason: blockedReason
        )
      ),
    ]
  }

  private static func commitContractState(
    input: ProductTestDraftInput,
    experiment: ProductTournamentExperiment?,
    contractAvailable: Bool?,
    blockedReason: String?
  ) -> ProductTestValidationState {
    if blockedReason != nil { return .blocked }
    let commit = input.targetCommitSha ?? experiment?.currentSha ?? experiment?.baseSha
    guard commit?.isEmpty == false else { return .missing }
    guard contractAvailable == true else { return .blocked }
    return .ready
  }

  private static func commitContractDetail(
    input: ProductTestDraftInput,
    experiment: ProductTournamentExperiment?,
    contractAvailable: Bool?,
    blockedReason: String?
  ) -> String {
    if let blockedReason { return blockedReason }
    let commit = input.targetCommitSha ?? experiment?.currentSha ?? experiment?.baseSha
    if commit?.isEmpty != false {
      return "Target commit missing"
    }
    if contractAvailable != true {
      return "Tournament experience contract missing"
    }
    return "Target commit and contract ready"
  }

  private static func questionFrom(
    nextMove: NextMoveSummary?,
    segment: UserSegment?,
    experiment: ProductTournamentExperiment?
  ) -> String {
    if let nextMove {
      let target = nextMove.targetContender ?? experiment?.title ?? "this contender"
      return "\(nextMove.actionTitle) for \(target)"
    }
    if let segment, let experiment {
      return "Will \(segment.name) get enough value from \(experiment.title)?"
    }
    return "Product test question not selected"
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func uniqueAuditReferences(_ references: [AuditReference]) -> [AuditReference] {
    var seen: Set<AuditReference> = []
    var result: [AuditReference] = []
    for reference in references where !reference.value.isEmpty {
      if seen.insert(reference).inserted {
        result.append(reference)
      }
    }
    return result
  }
}

struct ProductTestValidationItem: Equatable, Sendable, Identifiable {
  var id: String { title }
  var title: String
  var detail: String
  var state: ProductTestValidationState
}

enum ProductTestValidationState: String, Equatable, Sendable {
  case ready
  case missing
  case blocked

  var tone: ProductSignalTone {
    switch self {
    case .ready: return .strong
    case .missing: return .missing
    case .blocked: return .blocked
    }
  }
}

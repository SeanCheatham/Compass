import Foundation

struct ProductTournamentLaneDevelopRequest: Codable, Equatable, Sendable {
  var experimentID: String
  var contenderID: String
  var worktreeURL: URL
  var branchName: String
  var baseCommit: String
  var currentCommit: String?
  var targetBrief: String
  var verifyCommand: String
  var auditArtifactPath: String
  var sessionLabel: String

  init(
    experimentID: String,
    contenderID: String,
    worktreeURL: URL,
    branchName: String,
    baseCommit: String,
    currentCommit: String?,
    targetBrief: String,
    verifyCommand: String,
    auditArtifactPath: String,
    sessionLabel: String
  ) {
    self.experimentID = ProductTournamentModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.contenderID = ProductTournamentModelText.identifier(contenderID, fallback: "contender")
    self.worktreeURL = worktreeURL.standardizedFileURL
    self.branchName = ProductTournamentModelText.cleanedText(
      branchName,
      fallback: "codex/product-experiment",
      limit: 240
    )
    self.baseCommit = ProductTournamentModelText.cleanedText(
      baseCommit,
      fallback: "unknown-base",
      limit: 80
    )
    self.currentCommit = ProductTournamentModelText.optionalCleanedText(currentCommit, limit: 80)
    self.targetBrief = ProductTournamentModelText.cleanedText(
      targetBrief,
      fallback: "Implement the lane-scoped product proof.",
      limit: 1_200
    )
    self.verifyCommand = ProductTournamentModelText.cleanedText(
      verifyCommand,
      fallback: "swift test",
      limit: 400
    )
    self.auditArtifactPath = ProductTournamentModelText.cleanedText(
      auditArtifactPath,
      fallback: ".compass/product-tournament/lane-develop-audit.json",
      limit: 400
    )
    self.sessionLabel = ProductTournamentModelText.cleanedText(
      sessionLabel,
      fallback: "Lane Develop",
      limit: 180
    )
  }

  var developPrompt: String {
    """
    Develop the product tournament lane `\(contenderID)` for experiment `\(experimentID)`.

    Work only in this lane worktree:
    \(worktreeURL.path)

    Branch: \(branchName)
    Base commit: \(baseCommit)
    Current lane commit: \(currentCommit ?? "not recorded yet")

    Target proof or revision:
    \(targetBrief)

    Do not edit another tournament lane, another experiment worktree, or the user's main checkout. Keep all product changes on branch `\(branchName)`, run `\(verifyCommand)`, and leave a local commit for this lane before reporting success.
    """
  }

  func launchPlan(
    vmReadiness: SharedCompassVMReadiness? = nil,
    sharedVMRouteFactory: (URL) -> SharedVMRoute? = { _ in nil }
  ) -> AgentExecutionLaunchPlan {
    AgentExecutionLaunchPlan.plan(
      repoURL: worktreeURL,
      vmReadiness: vmReadiness,
      sharedVMRouteFactory: sharedVMRouteFactory
    )
  }

  func verifyInvocation() -> AgentExecutionInvocation {
    AgentExecutionInvocation(
      executable: "/bin/zsh",
      arguments: ["-lc", verifyCommand],
      workingDirectory: worktreeURL
    )
  }
}

enum ProductTournamentLaneDevelopRequestBuilder {
  static func request(
    lane: ProductTournamentLaneState,
    worktreeURL: URL,
    targetBrief: String,
    verifyCommand: String
  ) -> ProductTournamentLaneDevelopRequest? {
    guard let contenderID = lane.contenderID else { return nil }
    return ProductTournamentLaneDevelopRequest(
      experimentID: lane.experimentID,
      contenderID: contenderID,
      worktreeURL: worktreeURL,
      branchName: lane.branchName,
      baseCommit: lane.baseCommit ?? lane.currentCommit ?? "unknown-base",
      currentCommit: lane.currentCommit,
      targetBrief: targetBrief,
      verifyCommand: verifyCommand,
      auditArtifactPath:
        ".compass/product-tournament/lanes/\(lane.experimentID)/develop-audit.json",
      sessionLabel: "Develop \(lane.experimentTitle)"
    )
  }
}

struct ProductTournamentLaneDevelopPostCheck: Equatable, Sendable {
  var request: ProductTournamentLaneDevelopRequest
  var observedBranchName: String
  var producedCommit: String?
  var mainCheckoutDirtyStatus: String
  var changedFiles: [String]

  init(
    request: ProductTournamentLaneDevelopRequest,
    observedBranchName: String,
    producedCommit: String?,
    mainCheckoutDirtyStatus: String = "",
    changedFiles: [String] = []
  ) {
    self.request = request
    self.observedBranchName = ProductTournamentModelText.cleanedText(
      observedBranchName,
      fallback: "unknown-branch",
      limit: 240
    )
    self.producedCommit = ProductTournamentModelText.optionalCleanedText(producedCommit, limit: 80)
    self.mainCheckoutDirtyStatus = ProductTournamentModelText.cleanedText(
      mainCheckoutDirtyStatus,
      limit: 1_000
    )
    self.changedFiles = ProductTournamentModelText.cleanedList(changedFiles, limit: 260)
  }
}

enum ProductTournamentLaneDevelopPostCheckIssue: Equatable, Sendable {
  case wrongBranch(expected: String, actual: String)
  case missingLaneCommit
  case mainCheckoutDirty(String)
  case noChangedFiles

  var summary: String {
    switch self {
    case .wrongBranch(let expected, let actual):
      return "Lane worktree is on \(actual), expected \(expected)."
    case .missingLaneCommit:
      return "Lane Develop did not produce a new local commit."
    case .mainCheckoutDirty(let status):
      return "Main checkout is dirty after lane Develop: \(status)"
    case .noChangedFiles:
      return "Lane Develop produced a commit but no changed-file summary."
    }
  }
}

enum ProductTournamentLaneDevelopPostChecker {
  static func issues(
    for check: ProductTournamentLaneDevelopPostCheck
  ) -> [ProductTournamentLaneDevelopPostCheckIssue] {
    var issues: [ProductTournamentLaneDevelopPostCheckIssue] = []
    if check.observedBranchName != check.request.branchName {
      issues.append(
        .wrongBranch(expected: check.request.branchName, actual: check.observedBranchName)
      )
    }
    let produced = check.producedCommit?.trimmingCharacters(in: .whitespacesAndNewlines)
    if produced == nil || produced == check.request.currentCommit || produced == check.request.baseCommit {
      issues.append(.missingLaneCommit)
    }
    if !check.mainCheckoutDirtyStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.mainCheckoutDirty(check.mainCheckoutDirtyStatus))
    }
    if check.changedFiles.isEmpty, produced != nil {
      issues.append(.noChangedFiles)
    }
    return issues
  }
}

struct ProductTournamentLaneFileConflict: Equatable, Identifiable, Sendable {
  var id: String { path }

  var path: String
  var laneIDs: [String]

  init(path: String, laneIDs: [String]) {
    self.path = ProductTournamentModelText.cleanedText(path, fallback: "unknown-file", limit: 320)
    self.laneIDs = ProductTournamentModelText.cleanedList(laneIDs, limit: 160)
  }

  var summary: String {
    "\(path) changed by lanes \(laneIDs.joined(separator: ", "))"
  }
}

enum ProductTournamentLaneConflictDetector {
  static func conflicts(changedFilesByLaneID: [String: [String]])
    -> [ProductTournamentLaneFileConflict]
  {
    var laneIDsByPath: [String: [String]] = [:]
    for (laneID, paths) in changedFilesByLaneID {
      for path in Set(paths.map(normalizedPath)).sorted() where !path.isEmpty {
        laneIDsByPath[path, default: []].append(laneID)
      }
    }
    return laneIDsByPath
      .compactMap { path, laneIDs in
        let unique = uniqued(laneIDs.sorted())
        return unique.count > 1 ? ProductTournamentLaneFileConflict(path: path, laneIDs: unique) : nil
      }
      .sorted { lhs, rhs in lhs.path < rhs.path }
  }

  private static func normalizedPath(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"^\./"#, with: "", options: .regularExpression)
  }

  private static func uniqued(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for value in values where !seen.contains(value) {
      output.append(value)
      seen.insert(value)
    }
    return output
  }
}

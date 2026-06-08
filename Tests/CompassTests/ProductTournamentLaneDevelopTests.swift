import Foundation
import Testing

@testable import Compass

struct ProductTournamentLaneDevelopTests {
  @Test func buildsLaneDevelopRequestWithScopedPromptAndVerifyInvocation() throws {
    let (lane, worktreeURL) = try makeLaneDevelopFixture()
    let request = try #require(
      ProductTournamentLaneDevelopRequestBuilder.request(
        lane: lane,
        worktreeURL: worktreeURL,
        targetBrief: "Revise the onboarding proof for the buyer persona.",
        verifyCommand: "swift test --filter BuyerOnboardingTests"
      ))

    try #require(request.experimentID == lane.experimentID)
    try #require(request.contenderID == lane.contenderID)
    try #require(request.worktreeURL == worktreeURL.standardizedFileURL)
    try #require(request.developPrompt.contains("Do not edit another tournament lane"))
    try #require(request.developPrompt.contains(lane.branchName))
    let verify = request.verifyInvocation()
    try #require(verify.workingDirectory == worktreeURL.standardizedFileURL)
    try #require(verify.arguments == ["-lc", "swift test --filter BuyerOnboardingTests"])
  }

  @Test func launchPlanTargetsLaneWorktreeRoute() throws {
    let (lane, worktreeURL) = try makeLaneDevelopFixture()
    let request = try #require(
      ProductTournamentLaneDevelopRequestBuilder.request(
        lane: lane,
        worktreeURL: worktreeURL,
        targetBrief: "Build lane proof.",
        verifyCommand: "swift test"
      ))
    let route = SharedVMRoute(
      sshDestination: "compass@192.0.2.42",
      hostWorktreeURL: worktreeURL,
      guestWorkspacePath: "/Users/compass/lanes/\(lane.experimentID)"
    )

    let launchPlan = request.launchPlan(
      vmReadiness: .ready(sshDestination: route.sshDestination),
      sharedVMRouteFactory: { url in
        url == worktreeURL.standardizedFileURL ? route : nil
      }
    )

    try #require(launchPlan.isVMRoute)
    try #require(route.guestWorkspacePath.hasPrefix(launchPlan.workspaceLabel))
    try #require(launchPlan.effectiveRouteIdentifier == "shared-vm")
  }

  @Test func postCheckRequiresExpectedBranchNewCommitAndCleanMainCheckout() throws {
    let (lane, worktreeURL) = try makeLaneDevelopFixture()
    let request = try #require(
      ProductTournamentLaneDevelopRequestBuilder.request(
        lane: lane,
        worktreeURL: worktreeURL,
        targetBrief: "Build lane proof.",
        verifyCommand: "swift test"
      ))
    let cleanCheck = ProductTournamentLaneDevelopPostCheck(
      request: request,
      observedBranchName: request.branchName,
      producedCommit: "new-head",
      changedFiles: ["Sources/App.swift"]
    )
    let dirtyCheck = ProductTournamentLaneDevelopPostCheck(
      request: request,
      observedBranchName: "main",
      producedCommit: request.currentCommit,
      mainCheckoutDirtyStatus: " M Sources/App.swift",
      changedFiles: []
    )

    try #require(ProductTournamentLaneDevelopPostChecker.issues(for: cleanCheck).isEmpty)
    let issues = ProductTournamentLaneDevelopPostChecker.issues(for: dirtyCheck)
    try #require(issues.contains(.wrongBranch(expected: request.branchName, actual: "main")))
    try #require(issues.contains(.missingLaneCommit))
    try #require(issues.contains(.mainCheckoutDirty("M Sources/App.swift")))
  }

  @Test func detectsFilesChangedByMultipleActiveLanes() throws {
    let conflicts = ProductTournamentLaneConflictDetector.conflicts(
      changedFilesByLaneID: [
        "lane-a": ["Sources/App.swift", "./Sources/Shared.swift"],
        "lane-b": ["Sources/Shared.swift", "Sources/Other.swift"],
        "lane-c": ["Sources/App.swift"],
      ])

    try #require(conflicts.map(\.path) == ["Sources/App.swift", "Sources/Shared.swift"])
    try #require(conflicts[0].laneIDs == ["lane-a", "lane-c"])
    try #require(conflicts[1].summary.contains("lane-a, lane-b"))
  }
}

private func makeLaneDevelopFixture() throws -> (ProductTournamentLaneState, URL) {
  var config = ProductTournamentConfig.seedDefaults(
    projectTitle: "LedgerLift",
    rawPain: "Finance operators lose weekly reporting context between Slack and spreadsheets.",
    now: Date(timeIntervalSince1970: 10)
  )
  config.tournamentExperiments[0].baseSha = "base-sha"
  config.tournamentExperiments[0].currentSha = "current-sha"
  let lane = try #require(
    ProductTournamentLaneStateBuilder.lanes(
      config: config,
      evidenceIndex: .empty,
      isPersonaModelAvailable: false
    ).first)
  let worktreeURL = FileManager.default.temporaryDirectory
    .appending(path: "lane-\(UUID().uuidString)", directoryHint: .isDirectory)
  return (lane, worktreeURL)
}

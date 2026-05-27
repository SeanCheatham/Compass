import Foundation
import Testing

@testable import Compass

struct CompassWorkspaceStorageDisplayStatusTests : ~Copyable {
  private var temporaryDirectories: [URL] = []

  init() throws {}

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  @Test func testApplicationSupportActiveWithNoRepoLocalReportsSupportRoot() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let resolver = CompassProjectStorageResolver(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )
    try resolver.workspace.initialize()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let display = CompassWorkspaceStorageDisplayStatus(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots,
      activeStorageRootURL: resolver.storageRootURL,
      assessment: assessment,
      preflight: preflight
    )

    #require(assessment.kind == .missingWorkspace)
    #require(preflight.repoLocalReadiness == .missingWorkspace)
    #require(display.kind == .applicationSupportActive)
    #require(display.severity == .healthy)
    #require(display.activeRootHealth == .healthy)
    #require(display.activeStorageRootURL == resolver.storageRootURL.standardizedFileURL)
    #require(display.activeStorageDisplayName == "Application Support")
    #require(preflight.currentApplicationSupportCandidateIsOccupied)
    #require(display.detail.contains("Active Compass state root"))
    #require(display.detail.contains("Repo-local .compass/ is absent"))
    #require(display.recommendation.contains("No repo-local storage action"))
    #require(!display.detail.localizedCaseInsensitiveContains("conflict"))
    #require(!display.recommendation.localizedCaseInsensitiveContains("repair"))
    let compatibility = #require(display.applicationSupportCompatibility)
    #require(compatibility.repoLocalContext.kind == .missing)
    #require(compatibility.inspectOnlyApplicationSupportDrift.isEmpty)
    #require(display.supportRepairAction == nil)
    #require(
      !FileManager.default.fileExists(atPath: resolver.workspace.repoLocalCompassURL.path))
  }

  @Test func testApplicationSupportActiveWithRetainedRepoLocalReportsStaleCompatibility() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let resolver = CompassProjectStorageResolver(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )
    try resolver.workspace.initialize()
    try CompassWorkspace(repoURL: repoURL).initialize()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let display = CompassWorkspaceStorageDisplayStatus(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots,
      activeStorageRootURL: resolver.storageRootURL,
      assessment: assessment,
      preflight: preflight
    )

    #require(preflight.repoLocalReadiness == .ready)
    #require(preflight.kind == .applicationSupportConflict)
    #require(preflight.currentApplicationSupportCandidateIsOccupied)
    #require(display.kind == .applicationSupportActive)
    #require(display.severity == .healthy)
    #require(display.activeRootHealth == .healthy)
    let compatibility = #require(display.applicationSupportCompatibility)
    #require(compatibility.repoLocalContext.kind == .retainedStale)
    #require(compatibility.inspectOnlyApplicationSupportDrift.isEmpty)
    #require(display.detail.contains("retained stale compatibility context"))
    #require(display.recommendation.contains("Leave repo-local state unchanged"))
    #require(!display.detail.localizedCaseInsensitiveContains("conflict"))
    #require(!display.detail.contains("Current:"))
    #require(!display.recommendation.localizedCaseInsensitiveContains("repair"))
    #require(display.supportRepairAction == nil)
  }

  @Test func testApplicationSupportActiveWithIncompleteRepoLocalReportsCompatibilityOnly() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let resolver = CompassProjectStorageResolver(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )
    try resolver.workspace.initialize()
    let repoLocalWorkspace = CompassWorkspace(repoURL: repoURL)
    try createDirectory(repoLocalWorkspace.compassURL)
    try write("[]\n", to: repoLocalWorkspace.sessionsRecordURL)

    let display = CompassWorkspaceStorageDisplayStatus(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )

    #require(display.kind == .applicationSupportActive)
    #require(display.severity == .healthy)
    #require(display.repoLocalReadiness == .incompleteWorkspace)
    let compatibility = #require(display.applicationSupportCompatibility)
    #require(compatibility.repoLocalContext.kind == .incomplete)
    #require(compatibility.repoLocalContext.missingItems.contains("state.json"))
    #require(compatibility.repoLocalContext.missingItems.contains("drafts.md"))
    #require(compatibility.repoLocalContext.missingItems.contains("lessons.md"))
    #require(compatibility.repoLocalContext.missingItems.contains("COMPASS.md"))
    #require(compatibility.repoLocalContext.missingItems.contains("sessions/"))
    #require(!compatibility.repoLocalContext.missingItems.contains("sessions.json"))
    #require(display.detail.contains("incomplete stale compatibility context"))
    #require(display.recommendation.contains("Leave incomplete repo-local state unchanged"))
    #require(!display.recommendation.localizedCaseInsensitiveContains("repair"))
    #require(display.supportRepairAction == nil)
  }

  @Test func testApplicationSupportActiveReportsMissingSupportStorage() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let resolver = CompassProjectStorageResolver(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )

    let display = CompassWorkspaceStorageDisplayStatus(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )

    #require(display.kind == .applicationSupportActiveMissing)
    #require(display.severity == .warning)
    #require(display.activeRootHealth == .missing)
    #require(display.activeStorageRootURL == resolver.storageRootURL.standardizedFileURL)
    #require(
      display.activeRootFacts.missingCoreFiles == CompassWorkspaceStorageAssessment.CoreFile.allCases)
    #require(!display.activeRootFacts.sessionsDirectoryExists)
    #require(display.detail.contains("Active Application Support state root is missing"))
    let repairAction = #require(display.supportRepairAction)
    #require(repairAction.kind == .initializeApplicationSupportWorkspace)
    #require(repairAction.issueKind == .applicationSupportActiveMissing)
    #require(repairAction.label == "Repair support storage")
    #require(repairAction.label.count <= CompassWorkspaceStorageDisplayStatus.repairActionLabelLimit)
    #require(repairAction.helpText.count <= CompassWorkspaceStorageDisplayStatus.repairActionHelpLimit)
    #require(repairAction.helpText.contains("Application Support"))
    #require(repairAction.helpText.contains("repo-local"))
    #require(!FileManager.default.fileExists(atPath: resolver.storageRootURL.path))
    #require(
      !FileManager.default.fileExists(atPath: resolver.workspace.repoLocalCompassURL.path))
  }

  @Test func testApplicationSupportActiveReportsIncompleteSupportStorage() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let resolver = CompassProjectStorageResolver(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )
    let supportWorkspace = resolver.workspace
    try createDirectory(supportWorkspace.compassURL)
    try write("[]\n", to: supportWorkspace.sessionsRecordURL)

    let display = CompassWorkspaceStorageDisplayStatus(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )

    #require(display.kind == .applicationSupportActiveIncomplete)
    #require(display.severity == .failure)
    #require(display.activeRootHealth == .incomplete)
    #require(display.activeRootFacts.presentCoreFiles.contains(.sessionsRecord))
    #require(!display.activeRootFacts.missingItems.contains("sessions.json"))
    #require(display.activeRootFacts.missingItems.contains("state.json"))
    #require(display.activeRootFacts.missingItems.contains("drafts.md"))
    #require(display.activeRootFacts.missingItems.contains("lessons.md"))
    #require(display.activeRootFacts.missingItems.contains("COMPASS.md"))
    #require(display.activeRootFacts.missingItems.contains("sessions/"))
    #require(display.detail.contains("Active Application Support state root is missing"))
    let repairAction = #require(display.supportRepairAction)
    #require(repairAction.kind == .initializeApplicationSupportWorkspace)
    #require(repairAction.issueKind == .applicationSupportActiveIncomplete)
    #require(repairAction.label == "Repair support storage")
    #require(repairAction.label.count <= CompassWorkspaceStorageDisplayStatus.repairActionLabelLimit)
    #require(repairAction.helpText.count <= CompassWorkspaceStorageDisplayStatus.repairActionHelpLimit)
    #require(repairAction.helpText.contains("Application Support"))
    #require(repairAction.helpText.contains("repo-local"))
    #require(
      !FileManager.default.fileExists(atPath: supportWorkspace.repoLocalCompassURL.path))
  }

  @Test func testRepoLocalDisplayStatusMatchesExistingBoundary() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)
    let display = CompassWorkspaceStorageDisplayStatus(
      repoURL: repoURL,
      activeStorage: .repoLocal,
      applicationSupportRoots: roots,
      activeStorageRootURL: CompassWorkspace.repoLocalStorageRootURL(
        for: repoURL.standardizedFileURL),
      assessment: assessment,
      preflight: preflight
    )

    #require(display.kind == .repoLocalRecommended)
    #require(display.severity == boundary.severity)
    #require(display.label == boundary.label)
    #require(display.detail == boundary.detail)
    #require(display.recommendation == boundary.recommendation)
    #require(display.systemImage == boundary.systemImage)
    #require(display.activeRootHealth == .healthy)
    #require(display.repoLocalReadiness == .ready)
    #require(display.supportRepairAction == nil)
  }

  @Test func testRepoLocalDisplayStatusStillReportsSupportConflicts() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    try CompassWorkspace(repoURL: repoURL).initialize()
    let seedAssessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    try write(
      "current\n",
      to: seedAssessment.currentApplicationSupportCandidateURL.appending(path: "state.json"))

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let display = CompassWorkspaceStorageDisplayStatus(
      repoURL: repoURL,
      activeStorage: .repoLocal,
      applicationSupportRoots: roots,
      activeStorageRootURL: CompassWorkspace.repoLocalStorageRootURL(
        for: repoURL.standardizedFileURL),
      assessment: assessment,
      preflight: preflight
    )

    #require(display.kind == .applicationSupportInspectOnlyConflict)
    #require(display.severity == .warning)
    #require(display.detail.contains("Active state remains in repo-local .compass/"))
    #require(display.detail.contains("inspect-only conflict"))
    #require(display.recommendation.contains("No migration or mirroring by default"))
    #require(display.applicationSupportCompatibility == nil)
  }

  @Test func testDisplayStatusTextAndIdentifiersStayBounded() throws {
    let longRepoPath = "/tmp/" + String(repeating: "Long Repository Name With Spaces/", count: 14)
    let longSupportPath = "/tmp/" + String(repeating: "Current Support Root/", count: 14)
    let roots = KnownProjectStore.ApplicationSupportRoots(
      current: URL(fileURLWithPath: longSupportPath)
    )
    let repoURL = URL(fileURLWithPath: longRepoPath)
    let facts = CompassWorkspaceStorageAssessment.Facts(
      compassDirectoryExists: false,
      presentCoreFiles: [],
      sessionsDirectoryExists: false,
      gitignoreContents: nil,
      currentApplicationSupportCandidateExists: true
    )
    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL,
      applicationSupportRoots: roots,
      facts: facts
    )
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let display = CompassWorkspaceStorageDisplayStatus(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots,
      activeStorageRootURL: assessment.currentApplicationSupportCandidateURL,
      assessment: assessment,
      preflight: preflight,
      activeRootFacts: CompassWorkspaceStorageDisplayStatus.ActiveRootFacts(
        directoryExists: true,
        presentCoreFiles: [.state],
        sessionsDirectoryExists: false
      )
    )

    #require(
      display.projectStorageIdentifier.count <=
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    #require(display.label.count <= CompassWorkspaceStorageDisplayStatus.labelLimit)
    #require(display.detail.count <= CompassWorkspaceStorageDisplayStatus.detailLimit)
    #require(
      display.recommendation.count <=
      CompassWorkspaceStorageDisplayStatus.recommendationLimit
    )
    #require(!display.label.isEmpty)
    #require(!display.detail.isEmpty)
    #require(!display.recommendation.isEmpty)
    let compatibility = #require(display.applicationSupportCompatibility)
    #require(
      compatibility.detail.count <=
      CompassWorkspaceStorageDisplayStatus.compatibilityDetailLimit
    )
    #require(
      compatibility.recommendation.count <=
      CompassWorkspaceStorageDisplayStatus.compatibilityRecommendationLimit
    )
    #require(
      compatibility.helpText.count <=
      CompassWorkspaceStorageDisplayStatus.compatibilityHelpLimit
    )
    #require(!compatibility.detail.isEmpty)
    #require(!compatibility.recommendation.isEmpty)
    #require(!compatibility.helpText.isEmpty)
  }

  @Test func testHeaderActionVisibilityDistinguishesActiveStorageAndFeedback() {
    let repoLocalActions = CompassWorkspaceStorageHeaderActions(
      activeStorage: .repoLocal,
      candidatePreparationIsAvailable: true,
      candidatePreparationShouldShowFeedback: false,
      activationIsAvailable: true,
      activationShouldShowFeedback: false,
      activationIsIdle: true,
      repoLocalRepairActionIsAvailable: true
    )

    #require(repoLocalActions.showsCandidatePreparation)
    #require(repoLocalActions.showsActivation)
    #require(repoLocalActions.showsRepoLocalRepair)
    #require(!repoLocalActions.showsApplicationSupportRepair)

    let busyRepoLocalActions = CompassWorkspaceStorageHeaderActions(
      activeStorage: .repoLocal,
      candidatePreparationIsAvailable: true,
      candidatePreparationShouldShowFeedback: false,
      activationIsAvailable: true,
      activationShouldShowFeedback: false,
      activationIsIdle: false,
      repoLocalRepairActionIsAvailable: false
    )

    #require(busyRepoLocalActions.showsCandidatePreparation)
    #require(!busyRepoLocalActions.showsActivation)
    #require(!busyRepoLocalActions.showsRepoLocalRepair)
    #require(!busyRepoLocalActions.showsApplicationSupportRepair)

    let supportActiveActions = CompassWorkspaceStorageHeaderActions(
      activeStorage: .applicationSupport,
      candidatePreparationIsAvailable: true,
      candidatePreparationShouldShowFeedback: false,
      activationIsAvailable: true,
      activationShouldShowFeedback: false,
      activationIsIdle: true,
      repoLocalRepairActionIsAvailable: true
    )

    #require(!supportActiveActions.showsCandidatePreparation)
    #require(!supportActiveActions.showsActivation)
    #require(!supportActiveActions.showsRepoLocalRepair)
    #require(!supportActiveActions.showsApplicationSupportRepair)

    let supportFeedbackActions = CompassWorkspaceStorageHeaderActions(
      activeStorage: .applicationSupport,
      candidatePreparationIsAvailable: false,
      candidatePreparationShouldShowFeedback: true,
      activationIsAvailable: false,
      activationShouldShowFeedback: true,
      activationIsIdle: false,
      repoLocalRepairActionIsAvailable: true
    )

    #require(supportFeedbackActions.showsCandidatePreparation)
    #require(supportFeedbackActions.showsActivation)
    #require(!supportFeedbackActions.showsRepoLocalRepair)
    #require(!supportFeedbackActions.showsApplicationSupportRepair)

    let supportRepairActions = CompassWorkspaceStorageHeaderActions(
      activeStorage: .applicationSupport,
      candidatePreparationIsAvailable: true,
      candidatePreparationShouldShowFeedback: false,
      activationIsAvailable: true,
      activationShouldShowFeedback: false,
      activationIsIdle: true,
      repoLocalRepairActionIsAvailable: true,
      applicationSupportRepairActionIsAvailable: true
    )

    #require(!supportRepairActions.showsCandidatePreparation)
    #require(!supportRepairActions.showsActivation)
    #require(!supportRepairActions.showsRepoLocalRepair)
    #require(supportRepairActions.showsApplicationSupportRepair)

    let repoLocalRepairActions = CompassWorkspaceStorageHeaderActions(
      activeStorage: .repoLocal,
      candidatePreparationIsAvailable: false,
      candidatePreparationShouldShowFeedback: false,
      activationIsAvailable: false,
      activationShouldShowFeedback: false,
      activationIsIdle: true,
      repoLocalRepairActionIsAvailable: true,
      applicationSupportRepairActionIsAvailable: true
    )

    #require(repoLocalRepairActions.showsRepoLocalRepair)
    #require(!repoLocalRepairActions.showsApplicationSupportRepair)
  }

  private func makeTemporaryGitRepository() throws -> URL {
    let directory = try makeTemporaryDirectory()
    try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
    return directory
  }

  private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
    let base = try makeTemporaryDirectory(prefix: "CompassWorkspaceStorageDisplayStatusSupport")
    return KnownProjectStore.ApplicationSupportRoots(
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory)
    )
  }

  private func makeTemporaryDirectory(prefix: String = "CompassWorkspaceStorageDisplayStatusTests")
    throws -> URL
  {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    temporaryDirectories.append(url)
    try createDirectory(url)
    return url
  }

  private func createDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func write(_ contents: String, to url: URL) throws {
    try createDirectory(url.deletingLastPathComponent())
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }
}

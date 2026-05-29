import Foundation
import Testing

@testable import Compass

final class CompassWorkspaceStorageDisplayStatusTests {
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

    try #require(assessment.kind == .missingWorkspace)
    try #require(preflight.repoLocalReadiness == .missingWorkspace)
    try #require(display.kind == .applicationSupportActive)
    try #require(display.severity == .healthy)
    try #require(display.activeRootHealth == .healthy)
    try #require(display.activeStorageRootURL == resolver.storageRootURL.standardizedFileURL)
    try #require(display.activeStorageDisplayName == "Application Support")
    try #require(preflight.currentApplicationSupportCandidateIsOccupied)
    try #require(display.detail.contains("Active Compass state root"))
    try #require(display.detail.contains("Repo-local .compass/ is absent"))
    try #require(display.recommendation.contains("No repo-local storage action"))
    try #require(!display.detail.localizedCaseInsensitiveContains("conflict"))
    try #require(!display.recommendation.localizedCaseInsensitiveContains("repair"))
    let compatibility = try #require(display.applicationSupportCompatibility)
    try #require(compatibility.repoLocalContext.kind == .missing)
    try #require(compatibility.inspectOnlyApplicationSupportDrift.isEmpty)
    try #require(display.supportRepairAction == nil)
    try #require(
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

    try #require(preflight.repoLocalReadiness == .ready)
    try #require(preflight.kind == .applicationSupportConflict)
    try #require(preflight.currentApplicationSupportCandidateIsOccupied)
    try #require(display.kind == .applicationSupportActive)
    try #require(display.severity == .healthy)
    try #require(display.activeRootHealth == .healthy)
    let compatibility = try #require(display.applicationSupportCompatibility)
    try #require(compatibility.repoLocalContext.kind == .retainedStale)
    try #require(compatibility.inspectOnlyApplicationSupportDrift.isEmpty)
    try #require(display.detail.contains("retained stale compatibility context"))
    try #require(display.recommendation.contains("Leave repo-local state unchanged"))
    try #require(!display.detail.localizedCaseInsensitiveContains("conflict"))
    try #require(!display.detail.contains("Current:"))
    try #require(!display.recommendation.localizedCaseInsensitiveContains("repair"))
    try #require(display.supportRepairAction == nil)
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

    try #require(display.kind == .applicationSupportActive)
    try #require(display.severity == .healthy)
    try #require(display.repoLocalReadiness == .incompleteWorkspace)
    let compatibility = try #require(display.applicationSupportCompatibility)
    try #require(compatibility.repoLocalContext.kind == .incomplete)
    try #require(compatibility.repoLocalContext.missingItems.contains("state.json"))
    try #require(compatibility.repoLocalContext.missingItems.contains("drafts.md"))
    try #require(compatibility.repoLocalContext.missingItems.contains("lessons.md"))
    try #require(compatibility.repoLocalContext.missingItems.contains("COMPASS.md"))
    try #require(compatibility.repoLocalContext.missingItems.contains("sessions/"))
    try #require(!compatibility.repoLocalContext.missingItems.contains("sessions.json"))
    try #require(display.detail.contains("incomplete stale compatibility context"))
    try #require(display.recommendation.contains("Leave incomplete repo-local state unchanged"))
    try #require(!display.recommendation.localizedCaseInsensitiveContains("repair"))
    try #require(display.supportRepairAction == nil)
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

    try #require(display.kind == .applicationSupportActiveMissing)
    try #require(display.severity == .warning)
    try #require(display.activeRootHealth == .missing)
    try #require(display.activeStorageRootURL == resolver.storageRootURL.standardizedFileURL)
    try #require(
      display.activeRootFacts.missingCoreFiles == CompassWorkspaceStorageAssessment.CoreFile.allCases)
    try #require(!display.activeRootFacts.sessionsDirectoryExists)
    try #require(display.detail.contains("Active Application Support state root is missing"))
    let repairAction = try #require(display.supportRepairAction)
    try #require(repairAction.kind == .initializeApplicationSupportWorkspace)
    try #require(repairAction.issueKind == .applicationSupportActiveMissing)
    try #require(repairAction.label == "Repair support storage")
    try #require(repairAction.label.count <= CompassWorkspaceStorageDisplayStatus.repairActionLabelLimit)
    try #require(repairAction.helpText.count <= CompassWorkspaceStorageDisplayStatus.repairActionHelpLimit)
    try #require(repairAction.helpText.contains("Application Support"))
    try #require(repairAction.helpText.contains("repo-local"))
    try #require(!FileManager.default.fileExists(atPath: resolver.storageRootURL.path))
    try #require(
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

    try #require(display.kind == .applicationSupportActiveIncomplete)
    try #require(display.severity == .failure)
    try #require(display.activeRootHealth == .incomplete)
    try #require(display.activeRootFacts.presentCoreFiles.contains(.sessionsRecord))
    try #require(!display.activeRootFacts.missingItems.contains("sessions.json"))
    try #require(display.activeRootFacts.missingItems.contains("state.json"))
    try #require(display.activeRootFacts.missingItems.contains("drafts.md"))
    try #require(display.activeRootFacts.missingItems.contains("lessons.md"))
    try #require(display.activeRootFacts.missingItems.contains("COMPASS.md"))
    try #require(display.activeRootFacts.missingItems.contains("sessions/"))
    try #require(display.detail.contains("Active Application Support state root is missing"))
    let repairAction = try #require(display.supportRepairAction)
    try #require(repairAction.kind == .initializeApplicationSupportWorkspace)
    try #require(repairAction.issueKind == .applicationSupportActiveIncomplete)
    try #require(repairAction.label == "Repair support storage")
    try #require(repairAction.label.count <= CompassWorkspaceStorageDisplayStatus.repairActionLabelLimit)
    try #require(repairAction.helpText.count <= CompassWorkspaceStorageDisplayStatus.repairActionHelpLimit)
    try #require(repairAction.helpText.contains("Application Support"))
    try #require(repairAction.helpText.contains("repo-local"))
    try #require(
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

    try #require(display.kind == .repoLocalRecommended)
    try #require(display.severity == boundary.severity)
    try #require(display.label == boundary.label)
    try #require(display.detail == boundary.detail)
    try #require(display.recommendation == boundary.recommendation)
    try #require(display.systemImage == boundary.systemImage)
    try #require(display.activeRootHealth == .healthy)
    try #require(display.repoLocalReadiness == .ready)
    try #require(display.supportRepairAction == nil)
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

    try #require(display.kind == .applicationSupportInspectOnlyConflict)
    try #require(display.severity == .warning)
    try #require(display.detail.contains("Active state remains in repo-local .compass/"))
    try #require(display.detail.contains("inspect-only conflict"))
    try #require(display.recommendation.contains("No migration or mirroring by default"))
    try #require(display.applicationSupportCompatibility == nil)
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

    try #require(
      display.projectStorageIdentifier.count <=
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    try #require(display.label.count <= CompassWorkspaceStorageDisplayStatus.labelLimit)
    try #require(display.detail.count <= CompassWorkspaceStorageDisplayStatus.detailLimit)
    try #require(
      display.recommendation.count <=
      CompassWorkspaceStorageDisplayStatus.recommendationLimit
    )
    try #require(!display.label.isEmpty)
    try #require(!display.detail.isEmpty)
    try #require(!display.recommendation.isEmpty)
    let compatibility = try #require(display.applicationSupportCompatibility)
    try #require(
      compatibility.detail.count <=
      CompassWorkspaceStorageDisplayStatus.compatibilityDetailLimit
    )
    try #require(
      compatibility.recommendation.count <=
      CompassWorkspaceStorageDisplayStatus.compatibilityRecommendationLimit
    )
    try #require(
      compatibility.helpText.count <=
      CompassWorkspaceStorageDisplayStatus.compatibilityHelpLimit
    )
    try #require(!compatibility.detail.isEmpty)
    try #require(!compatibility.recommendation.isEmpty)
    try #require(!compatibility.helpText.isEmpty)
  }

  @Test func testHeaderActionVisibilityDistinguishesActiveStorageAndFeedback() throws {
    let repoLocalActions = CompassWorkspaceStorageHeaderActions(
      activeStorage: .repoLocal,
      candidatePreparationIsAvailable: true,
      candidatePreparationShouldShowFeedback: false,
      activationIsAvailable: true,
      activationShouldShowFeedback: false,
      activationIsIdle: true,
      repoLocalRepairActionIsAvailable: true
    )

    try #require(repoLocalActions.showsCandidatePreparation)
    try #require(repoLocalActions.showsActivation)
    try #require(repoLocalActions.showsRepoLocalRepair)
    try #require(!repoLocalActions.showsApplicationSupportRepair)

    let busyRepoLocalActions = CompassWorkspaceStorageHeaderActions(
      activeStorage: .repoLocal,
      candidatePreparationIsAvailable: true,
      candidatePreparationShouldShowFeedback: false,
      activationIsAvailable: true,
      activationShouldShowFeedback: false,
      activationIsIdle: false,
      repoLocalRepairActionIsAvailable: false
    )

    try #require(busyRepoLocalActions.showsCandidatePreparation)
    try #require(!busyRepoLocalActions.showsActivation)
    try #require(!busyRepoLocalActions.showsRepoLocalRepair)
    try #require(!busyRepoLocalActions.showsApplicationSupportRepair)

    let supportActiveActions = CompassWorkspaceStorageHeaderActions(
      activeStorage: .applicationSupport,
      candidatePreparationIsAvailable: true,
      candidatePreparationShouldShowFeedback: false,
      activationIsAvailable: true,
      activationShouldShowFeedback: false,
      activationIsIdle: true,
      repoLocalRepairActionIsAvailable: true
    )

    try #require(!supportActiveActions.showsCandidatePreparation)
    try #require(!supportActiveActions.showsActivation)
    try #require(!supportActiveActions.showsRepoLocalRepair)
    try #require(!supportActiveActions.showsApplicationSupportRepair)

    let supportFeedbackActions = CompassWorkspaceStorageHeaderActions(
      activeStorage: .applicationSupport,
      candidatePreparationIsAvailable: false,
      candidatePreparationShouldShowFeedback: true,
      activationIsAvailable: false,
      activationShouldShowFeedback: true,
      activationIsIdle: false,
      repoLocalRepairActionIsAvailable: true
    )

    try #require(supportFeedbackActions.showsCandidatePreparation)
    try #require(supportFeedbackActions.showsActivation)
    try #require(!supportFeedbackActions.showsRepoLocalRepair)
    try #require(!supportFeedbackActions.showsApplicationSupportRepair)

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

    try #require(!supportRepairActions.showsCandidatePreparation)
    try #require(!supportRepairActions.showsActivation)
    try #require(!supportRepairActions.showsRepoLocalRepair)
    try #require(supportRepairActions.showsApplicationSupportRepair)

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

    try #require(repoLocalRepairActions.showsRepoLocalRepair)
    try #require(!repoLocalRepairActions.showsApplicationSupportRepair)
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

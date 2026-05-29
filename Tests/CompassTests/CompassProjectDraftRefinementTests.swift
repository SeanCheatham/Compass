import Foundation
import Testing

@testable import Compass

@MainActor
final class CompassProjectDraftRefinementTests {
  private var temporaryDirectories: [URL] = []

  init() throws {}

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  @Test func testAcceptQueuesRefinedTextThroughActiveStorageWithoutSubmittingRun() async throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
    let state = PlanState(
      completed: ["Keep existing plan state"],
      immediate: PlanNext(plan: "Maintain draft preview semantics", verify: "swift test"),
      midTerm: "Continue Compass polish",
      longTerm: "Autonomous software factory"
    )
    let project = CompassProject(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      storageApplicationSupportRoots: roots
    )
    let refinement = DraftRefinement(
      originalDraft: "add parser tests",
      refinedText: "Add parser tests.",
      source: .generated
    )

    try workspace.initialize()
    try workspace.writeState(state)
    await project.refresh()
    project.draftEntry = "add parser tests"

    await project.acceptDraftRefinement(refinement)

    try #require(workspace.readDrafts() == "- Add parser tests.\n")
    try #require(project.drafts == "- Add parser tests.\n")
    try #require(project.draftEntry == "")
    try #require(project.state == state)
    try #require(project.sessions == [])
    try #require(project.activeStorage == .applicationSupport)
    try #require(project.phase == .idle)
    try #require(!project.isRunning)
    try #require(!FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
  }

  @Test func testModifyReplacesDraftEntryWithoutQueueing() throws {
    let repoURL = try makeTemporaryGitRepository()
    let workspace = CompassWorkspace(repoURL: repoURL)
    let project = CompassProject(repoURL: repoURL)
    let refinement = DraftRefinement(
      originalDraft: "add parser tests",
      refinedText: "Add parser tests.",
      source: .generated
    )
    let stateBefore = project.state
    let activeStorageBefore = project.activeStorage

    project.draftEntry = "add parser tests"

    project.modifyDraft(with: refinement)

    try #require(project.draftEntry == "Add parser tests.")
    try #require(project.drafts == "")
    try #require(project.state == stateBefore)
    try #require(project.sessions == [])
    try #require(project.liveLog == [])
    try #require(project.activeStorage == activeStorageBefore)
    try #require(!FileManager.default.fileExists(atPath: workspace.compassURL.path))
    try #require(!project.isRunning)
  }

  private func makeTemporaryGitRepository() throws -> URL {
    let directory = try makeTemporaryDirectory()
    try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
    return directory
  }

  private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
    let base = try makeTemporaryDirectory(prefix: "CompassProjectDraftRefinementSupport")
    return KnownProjectStore.ApplicationSupportRoots(
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory)
    )
  }

  private func makeTemporaryDirectory(prefix: String = "CompassProjectDraftRefinementTests") throws
    -> URL
  {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    temporaryDirectories.append(directory)
    try createDirectory(directory)
    return directory
  }

  private func createDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func applicationSupportWorkspace(
    repoURL: URL,
    roots: KnownProjectStore.ApplicationSupportRoots
  ) -> CompassWorkspace {
    CompassProjectStorageResolver(
      repoURL: repoURL,
      activeStorage: .applicationSupport,
      applicationSupportRoots: roots
    )
    .workspace
  }
}

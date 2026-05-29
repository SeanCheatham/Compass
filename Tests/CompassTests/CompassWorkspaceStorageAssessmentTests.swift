import Foundation
import Testing

@testable import Compass

final class CompassWorkspaceStorageAssessmentTests {
  private var temporaryDirectories: [URL] = []

  init() throws {}

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  @Test func testHealthyRepoLocalStorageReportsNoActionNeeded() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    try #require(assessment.isHealthy)
    try #require(assessment.issues.isEmpty)
    try #require(assessment.kind == .repoLocalHealthy)
    try #require(assessment.severity == .healthy)
    try #require(assessment.label == "Repo-local healthy")
    try #require(assessment.detail.contains("core files"))
    try #require(assessment.recommendation.contains("No storage action"))
    try #require(assessment.repairAction == nil)
  }

  @Test func testMissingWorkspaceReportsUninitializedRepoLocalStorage() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    try #require(!assessment.isHealthy)
    try #require(assessment.kind == .missingWorkspace)
    try #require(assessment.severity == .warning)
    try #require(assessment.detail.contains(".compass/ has not been initialized"))
    try #require(assessment.recommendation.contains("Initialize"))
    try #require(assessment.repairAction?.kind == .initializeRepoLocalWorkspace)
    try #require(assessment.repairAction?.issueKind == .missingWorkspace)
  }

  @Test func testIncompleteCoreFilesReportMissingCoreAndSessionStorage() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try createDirectory(workspace.compassURL)
    try write(".compass/\n", to: repoURL.appending(path: ".gitignore"))
    try write("[]\n", to: workspace.sessionsRecordURL)

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    try #require(assessment.kind == .incompleteCoreFiles)
    try #require(assessment.severity == .failure)
    try #require(assessment.detail.contains("state.json"))
    try #require(assessment.detail.contains("drafts.md"))
    try #require(assessment.detail.contains("lessons.md"))
    try #require(assessment.detail.contains("COMPASS.md"))
    try #require(assessment.detail.contains("sessions/"))
    try #require(!assessment.detail.contains("sessions.json"))
    try #require(assessment.repairAction?.kind == .initializeRepoLocalWorkspace)
    try #require(assessment.repairAction?.issueKind == .incompleteCoreFiles)
  }

  @Test func testGitignoreVariantsRecognizeCompassCoverageAndFlagMissingCoverage() throws {
    let coveredVariants = [
      ".compass\n",
      ".compass/\n",
      "  /.compass  \n",
      "# build output\nbuild\n  /.compass/  \n",
    ]

    for gitignoreText in coveredVariants {
      let repoURL = try makeTemporaryGitRepository()
      let roots = try makeApplicationSupportRoots()
      let workspace = CompassWorkspace(repoURL: repoURL)
      try workspace.initialize()
      try write(gitignoreText, to: repoURL.appending(path: ".gitignore"))

      let assessment = CompassWorkspaceStorageAssessment(
        repoURL: repoURL,
        applicationSupportRoots: roots
      )

      try #require(assessment.kind == .repoLocalHealthy)
    }

    let unignoredRepoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = CompassWorkspace(repoURL: unignoredRepoURL)
    try workspace.initialize()
    try write("# .compass/\nbuild\n", to: unignoredRepoURL.appending(path: ".gitignore"))

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: unignoredRepoURL,
      applicationSupportRoots: roots
    )

    try #require(assessment.kind == .unignoredCompass)
    try #require(assessment.severity == .warning)
    try #require(assessment.recommendation.contains(".gitignore"))
    try #require(assessment.repairAction?.kind == .initializeRepoLocalWorkspace)
    try #require(assessment.repairAction?.issueKind == .unignoredCompass)
  }

  @Test func testRepairActionsAreDerivedForRepoLocalConditionsAndStayBounded() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let completeCoreFiles = Set(CompassWorkspaceStorageAssessment.CoreFile.allCases)
    let cases: [(CompassWorkspaceStorageAssessment.Kind, CompassWorkspaceStorageAssessment.Facts)] =
      [
        (
          .missingWorkspace,
          CompassWorkspaceStorageAssessment.Facts(
            compassDirectoryExists: false,
            presentCoreFiles: [],
            sessionsDirectoryExists: false,
            gitignoreContents: nil,
            currentApplicationSupportCandidateExists: false
          )
        ),
        (
          .incompleteCoreFiles,
          CompassWorkspaceStorageAssessment.Facts(
            compassDirectoryExists: true,
            presentCoreFiles: [.state],
            sessionsDirectoryExists: false,
            gitignoreContents: nil,
            currentApplicationSupportCandidateExists: false
          )
        ),
        (
          .unignoredCompass,
          CompassWorkspaceStorageAssessment.Facts(
            compassDirectoryExists: true,
            presentCoreFiles: completeCoreFiles,
            sessionsDirectoryExists: true,
            gitignoreContents: "build\n",
            currentApplicationSupportCandidateExists: false
          )
        ),
      ]

    for (issueKind, facts) in cases {
      let assessment = CompassWorkspaceStorageAssessment(
        repoURL: repoURL,
        applicationSupportRoots: roots,
        facts: facts
      )
      let action = try #require(assessment.repairAction)

      try #require(action.kind == .initializeRepoLocalWorkspace)
      try #require(action.issueKind == issueKind)
      try #require(action.label == "Repair storage")
      try #require(action.systemImage == "wrench.fill")
      try #require(action.label.count <= CompassWorkspaceStorageAssessment.repairActionLabelLimit)
      try #require(action.helpText.count <= CompassWorkspaceStorageAssessment.repairActionHelpLimit)
      try #require(!action.helpText.isEmpty)
    }
  }

  @Test func testCandidateApplicationSupportPathIsStableSanitizedAndBounded() throws {
    let longName = "My Project: Needs/Storage? Audit! " + String(repeating: "Segment ", count: 16)
    let repoURL = try makeTemporaryGitRepository(
      name: longName.replacingOccurrences(of: "/", with: "-"))
    let roots = try makeApplicationSupportRoots()

    let first = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)
    let second = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)

    try #require(first.projectStorageIdentifier == second.projectStorageIdentifier)
    try #require(
      first.currentApplicationSupportCandidateURL == second.currentApplicationSupportCandidateURL)
    try #require(
      first.projectStorageIdentifier.count <=
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    try #require(isSafeIdentifier(first.projectStorageIdentifier))
    try #require(
      first.currentApplicationSupportCandidateURL.lastPathComponent == first.projectStorageIdentifier)
  }

  @Test func testCurrentApplicationSupportCandidateIsReported() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()

    let seedAssessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    try createDirectory(seedAssessment.currentApplicationSupportCandidateURL)

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL, applicationSupportRoots: roots)
    let issueKinds = assessment.issues.map(\.kind)

    try #require(assessment.kind == .currentApplicationSupportCandidateExists)
    try #require(issueKinds.contains(.currentApplicationSupportCandidateExists))
    try #require(assessment.detail.contains("Future storage candidate"))
    try #require(assessment.severity == .warning)
    try #require(assessment.repairAction == nil)
  }

  @Test func testAssessmentDisplayTextAndIdentifiersStayBounded() throws {
    let longPath = "/tmp/" + String(repeating: "Long Repository Name With Spaces/", count: 12)
    let roots = KnownProjectStore.ApplicationSupportRoots(
      current: URL(
        fileURLWithPath: "/tmp/" + String(repeating: "Current Support Root/", count: 10))
    )
    let facts = CompassWorkspaceStorageAssessment.Facts(
      compassDirectoryExists: true,
      presentCoreFiles: Set(CompassWorkspaceStorageAssessment.CoreFile.allCases),
      sessionsDirectoryExists: true,
      gitignoreContents: ".compass/\n",
      currentApplicationSupportCandidateExists: true
    )

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: URL(fileURLWithPath: longPath),
      applicationSupportRoots: roots,
      facts: facts
    )

    try #require(
      assessment.projectStorageIdentifier.count <=
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    for issue in [assessment.primaryIssue] + assessment.issues {
      try #require(issue.label.count <= CompassWorkspaceStorageAssessment.labelLimit)
      try #require(issue.detail.count <= CompassWorkspaceStorageAssessment.detailLimit)
      try #require(
        issue.recommendation.count <= CompassWorkspaceStorageAssessment.recommendationLimit)
    }
  }

  @Test func testAssessingDoesNotCreateRepoOrApplicationSupportFiles() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let repoEntriesBefore = try entries(in: repoURL)

    _ = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)

    try #require(try entries(in: repoURL) == repoEntriesBefore)
    try #require(
      !FileManager.default.fileExists(atPath: CompassWorkspace(repoURL: repoURL).compassURL.path))
    try #require(
      !FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
    try #require(!FileManager.default.fileExists(atPath: roots.current.path))
  }

  private func makeTemporaryGitRepository(name: String? = nil) throws -> URL {
    let base = try makeTemporaryDirectory()
    let repoURL: URL
    if let name {
      repoURL = base.appending(path: name, directoryHint: .isDirectory)
      try createDirectory(repoURL)
    } else {
      repoURL = base
    }
    try createDirectory(repoURL.appending(path: ".git", directoryHint: .isDirectory))
    return repoURL
  }

  private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
    let base = try makeTemporaryDirectory(prefix: "CompassWorkspaceStorageAssessmentSupport")
    return KnownProjectStore.ApplicationSupportRoots(
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory)
    )
  }

  private func makeTemporaryDirectory(prefix: String = "CompassWorkspaceStorageAssessmentTests")
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

  private func entries(in url: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
  }

  private func isSafeIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, !value.hasPrefix("-"), !value.hasSuffix("-") else {
      return false
    }
    return value.unicodeScalars.allSatisfy { scalar in
      (scalar.value >= 48 && scalar.value <= 57)
        || (scalar.value >= 97 && scalar.value <= 122)
        || scalar.value == 45
    }
  }
}

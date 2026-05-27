import Foundation
import Testing

@testable import Compass

struct CompassWorkspaceStorageAssessmentTests : ~Copyable {
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

    #require(assessment.isHealthy)
    #require(assessment.issues.isEmpty)
    #require(assessment.kind == .repoLocalHealthy)
    #require(assessment.severity == .healthy)
    #require(assessment.label == "Repo-local healthy")
    #require(assessment.detail.contains("core files"))
    #require(assessment.recommendation.contains("No storage action"))
    #require(assessment.repairAction == nil)
  }

  @Test func testMissingWorkspaceReportsUninitializedRepoLocalStorage() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()

    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: repoURL,
      applicationSupportRoots: roots
    )

    #require(!assessment.isHealthy)
    #require(assessment.kind == .missingWorkspace)
    #require(assessment.severity == .warning)
    #require(assessment.detail.contains(".compass/ has not been initialized"))
    #require(assessment.recommendation.contains("Initialize"))
    #require(assessment.repairAction?.kind == .initializeRepoLocalWorkspace)
    #require(assessment.repairAction?.issueKind == .missingWorkspace)
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

    #require(assessment.kind == .incompleteCoreFiles)
    #require(assessment.severity == .failure)
    #require(assessment.detail.contains("state.json"))
    #require(assessment.detail.contains("drafts.md"))
    #require(assessment.detail.contains("lessons.md"))
    #require(assessment.detail.contains("COMPASS.md"))
    #require(assessment.detail.contains("sessions/"))
    #require(!assessment.detail.contains("sessions.json"))
    #require(assessment.repairAction?.kind == .initializeRepoLocalWorkspace)
    #require(assessment.repairAction?.issueKind == .incompleteCoreFiles)
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

      #require(assessment.kind == .repoLocalHealthy)
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

    #require(assessment.kind == .unignoredCompass)
    #require(assessment.severity == .warning)
    #require(assessment.recommendation.contains(".gitignore"))
    #require(assessment.repairAction?.kind == .initializeRepoLocalWorkspace)
    #require(assessment.repairAction?.issueKind == .unignoredCompass)
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
      let action = #require(assessment.repairAction)

      #require(action.kind == .initializeRepoLocalWorkspace)
      #require(action.issueKind == issueKind)
      #require(action.label == "Repair storage")
      #require(action.systemImage == "wrench.fill")
      #require(action.label.count <= CompassWorkspaceStorageAssessment.repairActionLabelLimit)
      #require(action.helpText.count <= CompassWorkspaceStorageAssessment.repairActionHelpLimit)
      #require(!action.helpText.isEmpty)
    }
  }

  @Test func testCandidateApplicationSupportPathIsStableSanitizedAndBounded() throws {
    let longName = "My Project: Needs/Storage? Audit! " + String(repeating: "Segment ", count: 16)
    let repoURL = try makeTemporaryGitRepository(
      name: longName.replacingOccurrences(of: "/", with: "-"))
    let roots = try makeApplicationSupportRoots()

    let first = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)
    let second = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)

    #require(first.projectStorageIdentifier == second.projectStorageIdentifier)
    #require(
      first.currentApplicationSupportCandidateURL == second.currentApplicationSupportCandidateURL)
    #require(
      first.projectStorageIdentifier.count <=
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    #require(isSafeIdentifier(first.projectStorageIdentifier))
    #require(
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

    #require(assessment.kind == .currentApplicationSupportCandidateExists)
    #require(issueKinds.contains(.currentApplicationSupportCandidateExists))
    #require(assessment.detail.contains("Future storage candidate"))
    #require(assessment.severity == .warning)
    #require(assessment.repairAction == nil)
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

    #require(
      assessment.projectStorageIdentifier.count <=
      CompassWorkspaceStorageAssessment.maxProjectIdentifierLength
    )
    for issue in [assessment.primaryIssue] + assessment.issues {
      #require(issue.label.count <= CompassWorkspaceStorageAssessment.labelLimit)
      #require(issue.detail.count <= CompassWorkspaceStorageAssessment.detailLimit)
      #require(
        issue.recommendation.count <= CompassWorkspaceStorageAssessment.recommendationLimit)
    }
  }

  @Test func testAssessingDoesNotCreateRepoOrApplicationSupportFiles() throws {
    let repoURL = try makeTemporaryGitRepository()
    let roots = try makeApplicationSupportRoots()
    let repoEntriesBefore = try entries(in: repoURL)

    _ = CompassWorkspaceStorageAssessment(repoURL: repoURL, applicationSupportRoots: roots)

    #require(try entries(in: repoURL) == repoEntriesBefore)
    #require(
      !FileManager.default.fileExists(atPath: CompassWorkspace(repoURL: repoURL).compassURL.path))
    #require(
      !FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
    #require(!FileManager.default.fileExists(atPath: roots.current.path))
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

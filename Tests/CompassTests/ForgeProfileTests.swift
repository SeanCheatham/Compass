import Foundation
import Testing

@testable import Compass

struct ForgeProfileTests {
  @Test func detectSwiftPackage() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try write("let package = Package(name: \"X\")\n", to: repoURL.appending(path: "Package.swift"))
    try #require(ForgeProfileService.detect(in: repoURL) == .swiftSPM)
  }

  @Test func detectGoModule() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try write("module example.com/x\n\ngo 1.22\n", to: repoURL.appending(path: "go.mod"))
    try #require(ForgeProfileService.detect(in: repoURL) == .goModule)
  }

  @Test func detectAndPersistWritesForgeProfileJSON() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try write("module example.com/x\n\ngo 1.22\n", to: repoURL.appending(path: "go.mod"))
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()

    let profile = try ForgeProfileService.detectAndPersist(repoURL: repoURL, workspace: workspace)
    try #require(profile == .goModule)
    let record = try #require(ForgeProfileService.readRecord(from: workspace))
    try #require(record.profile == .goModule)
    try #require(record.version == ForgeProfileRecord.currentVersion)
  }

  @Test func coverageViolationRequiresGoCoverprofile() throws {
    let message = ForgeVerifyValidator.coverageViolation(
      verify: "go test ./...",
      profile: .goModule
    )
    try #require(message != nil)
    try #require(message?.contains("coverprofile") == true)
  }

  @Test func xcodebuildTestVerifySatisfiesSwiftCoverageRule() throws {
    try #require(
      ForgeVerifyValidator.coverageViolation(
        verify:
          "xcodebuild -workspace .swiftpm/xcode/package.xcworkspace -scheme Compass-Package test",
        profile: .swiftSPM
      ) == nil)
  }

  @Test func compileOnlyVerifySkipsCoverageRequirement() throws {
    try #require(
      ForgeVerifyValidator.coverageViolation(
        verify: "swift build --target CompassTests",
        profile: .swiftSPM
      ) == nil)
    try #require(
      ForgeVerifyValidator.coverageViolation(
        verify: "go build ./...",
        profile: .goModule
      ) == nil)
  }

  @Test func parseGoCoverFuncOutput() throws {
    let output = """
      example.com/app/main.go:10:    main    100.0%
      example.com/app/util.go:4:     Helper  50.0%
      total:                         (statements)    75.0%
      """
    let snapshot = CoverageSnapshotParser.parseGoCoverFunc(output, profile: .goModule)
    try #require(snapshot.overallLineCoveragePercent == 75.0)
    try #require(snapshot.files.count == 2)
  }

  @Test func parseVitestSummaryJSON() throws {
    let json = """
      {"total":{"lines":{"total":100,"covered":80,"skipped":0,"pct":80}},"src/foo.ts":{"lines":{"pct":50}}}
      """
    let snapshot = CoverageSnapshotParser.parseVitestSummaryJSON(json, profile: .typeScriptVitest)
    try #require(snapshot.overallLineCoveragePercent == 80)
    try #require(snapshot.files.contains { $0.path == "src/foo.ts" && $0.lineCoveragePercent == 50 })
  }

  @Test func planPromptIncludesForgeProfileAndCoverage() throws {
    let prompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .test,
      forgeProfile: .swiftSPM,
      coverageSnapshot: CoverageSnapshot(
        profile: .swiftSPM,
        collectedAt: Date(),
        sessionNumber: 1,
        overallLineCoveragePercent: 42.5,
        files: [CoverageFileEntry(path: "Sources/Foo.swift", lineCoveragePercent: 10)],
        rawSummary: nil
      )
    )
    try #require(prompt.contains("Forge profile"))
    try #require(prompt.contains("swift-spm"))
    try #require(prompt.contains("--enable-code-coverage"))
    try #require(prompt.contains("Overall line coverage: 42.5%"))
    try #require(prompt.contains("Sources/Foo.swift"))
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "ForgeProfileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func write(_ contents: String, to url: URL) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }
}

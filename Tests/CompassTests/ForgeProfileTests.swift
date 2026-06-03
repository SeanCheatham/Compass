import Foundation
import Testing

@testable import Compass

struct ForgeProfileTests {
  @Test func rustCargoIsOnlyGeneratedProjectTarget() throws {
    try #require(ForgeProfile.generatedProjectDefault == .rustCargo)
    try #require(ForgeProfile.generatedProjectTargets == [.rustCargo])
    try #require(ForgeProfile.rustCargo.isGeneratedProjectTarget)
    try #require(!ForgeProfile.swiftSPM.isGeneratedProjectTarget)
    try #require(!ForgeProfile.typeScriptVitest.isGeneratedProjectTarget)
    try #require(ForgeProfile.swiftSPM.generationStatusDescription.contains("legacy"))
    try #require(ForgeProfile.typeScriptVitest.generationStatusDescription.contains("legacy"))
  }

  @Test func detectSwiftPackage() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try write("let package = Package(name: \"X\")\n", to: repoURL.appending(path: "Package.swift"))
    try #require(ForgeProfileService.detect(in: repoURL) == .swiftSPM)
  }

  @Test func doesNotDetectGoModule() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try write("module example.com/x\n\ngo 1.22\n", to: repoURL.appending(path: "go.mod"))
    try #require(ForgeProfileService.detect(in: repoURL) == nil)
  }

  @Test func detectAndPersistWritesForgeProfileJSON() throws {
    let repoURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: repoURL) }
    try write(
      "[package]\nname = \"x\"\nversion = \"0.1.0\"\n", to: repoURL.appending(path: "Cargo.toml"))
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.initialize()

    let profile = try ForgeProfileService.detectAndPersist(repoURL: repoURL, workspace: workspace)
    try #require(profile == .rustCargo)
    let record = try #require(ForgeProfileService.readRecord(from: workspace))
    try #require(record.profile == .rustCargo)
    try #require(record.version == ForgeProfileRecord.currentVersion)
  }

  @Test func coverageViolationRequiresRustLLVMCov() throws {
    let message = ForgeVerifyValidator.coverageViolation(
      verify: "cargo test",
      profile: .rustCargo
    )
    try #require(message != nil)
    try #require(message?.contains("cargo llvm-cov") == true)
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
        verify: "cargo check",
        profile: .rustCargo
      ) == nil)
  }

  @Test func parseRustLLVMCovSummaryOutput() throws {
    let output = """
      src/main.rs 50.0%
      TOTAL 75.0%
      """
    let snapshot = CoverageSnapshotParser.parseRustLLVMCovSummary(output, profile: .rustCargo)
    try #require(snapshot.overallLineCoveragePercent == 75.0)
    try #require(snapshot.files.count == 1)
  }

  @Test func parseVitestSummaryJSON() throws {
    let json = """
      {"total":{"lines":{"total":100,"covered":80,"skipped":0,"pct":80}},"src/foo.ts":{"lines":{"pct":50}}}
      """
    let snapshot = CoverageSnapshotParser.parseVitestSummaryJSON(json, profile: .typeScriptVitest)
    try #require(snapshot.overallLineCoveragePercent == 80)
    try #require(
      snapshot.files.contains { $0.path == "src/foo.ts" && $0.lineCoveragePercent == 50 })
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

  @Test func rustForgeProfileMentionsAllFeatureMatrixForFeatureGates() throws {
    try #require(ForgeProfile.rustCargo.planningGuidance.contains("feature-gated"))
    try #require(ForgeProfile.rustCargo.planningGuidance.contains("cargo test --all-features"))
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

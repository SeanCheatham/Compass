import Testing

@testable import Compass

struct RustReviewProbePlannerTests {
  @Test func nonRustProfilesDoNotSuggestRustProbes() throws {
    let diff = "diff --git a/Cargo.toml b/Cargo.toml\n+edition = \"2021\"\n"

    let probes = RustReviewProbePlanner.suggestions(
      forgeProfile: .swiftSPM,
      gitDiff: diff,
      verifyCommand: "swift test"
    )

    #expect(probes.isEmpty)
    #expect(RustReviewProbePlanner.formattedSection(for: probes).isEmpty)
  }

  @Test func cargoManifestChangesSuggestWorkspaceCompilerAndLintProbes() throws {
    let probes = RustReviewProbePlanner.suggestions(changedPaths: ["Cargo.toml"])
    let names = probes.map(\.toolName)

    #expect(names.contains(AgentWorkspaceOutlineTool.toolName))
    #expect(names.contains(AgentCargoCheckTool.toolName))
    #expect(names.contains(AgentClippyLintTool.toolName))
  }

  @Test func schemaChangesSuggestSchemaContractsAndScaffoldCheck() throws {
    let probes = RustReviewProbePlanner.suggestions(
      changedPaths: ["schemas/demo-state.schema.json"])
    let names = probes.map(\.toolName)

    #expect(names.contains(AgentSchemaContractsTool.toolName))
    #expect(names.contains(AgentScaffoldCheckTool.toolName))
  }

  @Test func scaffoldContractPathsSuggestScaffoldCheck() throws {
    for path in [
      "compass-scaffold.toml",
      "xtask/src/main.rs",
      "crates/app-core/src/lib.rs",
      "crates/app-cli/src/main.rs",
      "crates/app-desktop/src/main.rs",
      "rust-toolchain.toml",
    ] {
      let names = RustReviewProbePlanner.suggestions(changedPaths: [path]).map(\.toolName)
      #expect(names.contains(AgentScaffoldCheckTool.toolName), "missing scaffold_check for \(path)")
    }
  }

  @Test func rustSourceChangesSuggestCompilerAndLintProbes() throws {
    let probes = RustReviewProbePlanner.suggestions(
      changedPaths: ["crates/app-core/src/state.rs"])
    let names = probes.map(\.toolName)

    #expect(names.contains(AgentCargoCheckTool.toolName))
    #expect(names.contains(AgentClippyLintTool.toolName))
    #expect(names.contains(AgentSchemaContractsTool.toolName))
  }

  @Test func coverageGapsRequiresCoverageEvidence() throws {
    let sourceOnlyNames = RustReviewProbePlanner.suggestions(
      changedPaths: ["crates/app-core/src/lib.rs"],
      verifyCommand: "cargo test"
    ).map(\.toolName)
    let coverageNames = RustReviewProbePlanner.suggestions(
      changedPaths: ["crates/app-core/src/lib.rs"],
      verifyCommand: "cargo llvm-cov test --summary-only"
    ).map(\.toolName)

    #expect(!sourceOnlyNames.contains(AgentCoverageGapsTool.toolName))
    #expect(coverageNames.contains(AgentCoverageGapsTool.toolName))
  }

  @Test func changedPathsAreExtractedFromGitDiffHeaders() throws {
    let diff = """
      diff --git a/schemas/demo-state.schema.json b/schemas/demo-state.schema.json
      index 1111111..2222222 100644
      --- a/schemas/demo-state.schema.json
      +++ b/schemas/demo-state.schema.json
      diff --git a/crates/app-core/src/lib.rs b/crates/app-core/src/lib.rs
      index 3333333..4444444 100644
      --- a/crates/app-core/src/lib.rs
      +++ b/crates/app-core/src/lib.rs
      """

    let paths = RustReviewProbePlanner.changedPaths(fromGitDiff: diff)

    #expect(paths.contains("schemas/demo-state.schema.json"))
    #expect(paths.contains("crates/app-core/src/lib.rs"))
  }
}

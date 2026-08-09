import Foundation
import Testing

@testable import CompassCore

@Suite("AgentImportersOfTool")
struct AgentImportersOfToolTests {
  @Test
  func candidatesIncludePathStemAndBasename() {
    let values = AgentImportersOfTool.candidates(for: "crates/core/src/helpers.rs")
    #expect(values.contains("crates/core/src/helpers.rs"))
    #expect(values.contains("crates/core/src/helpers"))
    #expect(values.contains("helpers"))
    #expect(values.contains("crates.core.src.helpers"))
  }

  @Test
  func modRsAddsParentModuleKeys() {
    let values = AgentImportersOfTool.candidates(for: "crates/cli/src/utils/mod.rs")
    #expect(values.contains("crates/cli/src/utils"))
    #expect(values.contains("utils"))
    #expect(values.contains("mod"))
  }

  @Test
  func normalizeImportSourceStripsRelativePrefixesAndExtensions() {
    #expect(AgentCodemapPath.normalizeImportSource("./foo/bar.rs") == "foo/bar")
    #expect(AgentCodemapPath.normalizeImportSource("../pkg/mod.py") == "pkg/mod")
    #expect(AgentCodemapPath.normalizeImportSource("\"helpers\"") == "helpers")
  }

  @Test
  func normalizeStripsWorkingDirectoryPrefix() {
    let working = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
    #expect(
      AgentCodemapPath.normalize("/tmp/project/src/a.swift", workingDirectory: working)
        == "src/a.swift"
    )
    #expect(AgentCodemapPath.normalize("./src/a.swift", workingDirectory: working) == "src/a.swift")
  }
}

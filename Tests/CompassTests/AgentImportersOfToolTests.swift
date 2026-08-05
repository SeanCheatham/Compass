import Foundation
import Testing

@testable import CompassCore

@Suite("AgentImportersOfTool")
struct AgentImportersOfToolTests {
  @Test
  func candidatesIncludePathStemAndBasename() {
    let values = AgentImportersOfTool.candidates(for: "src/util/helpers.ts")
    #expect(values.contains("src/util/helpers.ts"))
    #expect(values.contains("src/util/helpers"))
    #expect(values.contains("helpers"))
    #expect(values.contains("src.util.helpers"))
  }

  @Test
  func indexModuleAddsParentPackageKeys() {
    let values = AgentImportersOfTool.candidates(for: "packages/cli/index.ts")
    #expect(values.contains("packages/cli"))
    #expect(values.contains("cli"))
    #expect(values.contains("index"))
  }

  @Test
  func normalizeImportSourceStripsRelativePrefixesAndExtensions() {
    #expect(AgentCodemapPath.normalizeImportSource("./foo/bar.ts") == "foo/bar")
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

import Foundation
import Testing

@testable import CompassCore

@Suite("GeneratedArtifactHygiene")
struct GeneratedArtifactHygieneTests {
  @Test
  func flagsRootAndNestedGeneratedPaths() {
    let issues = GeneratedArtifactHygiene.issues(forChangedPaths: [
      "target/debug/lib.rlib",
      "packages/web/dist/bundle.js",
      "src/util/__pycache__/mod.cpython-312.pyc",
      "App.xcodeproj/xcuserdata/sean.xcuserdatad/xcschemes/xcschememanagement.plist",
      "vendor/pkg.egg-info/PKG-INFO",
      "Sources/App/Main.swift",
    ])

    let paths = Set(issues.map(\.path))
    #expect(paths.contains("target/debug/lib.rlib"))
    #expect(paths.contains("packages/web/dist/bundle.js"))
    #expect(paths.contains("src/util/__pycache__/mod.cpython-312.pyc"))
    #expect(
      paths.contains(
        "App.xcodeproj/xcuserdata/sean.xcuserdatad/xcschemes/xcschememanagement.plist"
      )
    )
    #expect(paths.contains("vendor/pkg.egg-info/PKG-INFO"))
    #expect(!paths.contains("Sources/App/Main.swift"))
  }

  @Test
  func parsesGitNameStatusSkipsDeletesAndUsesRenameDestination() {
    let output = """
      A\t.target/debug/foo
      M\tpackages/app/dist/index.js
      D\tnode_modules/left-pad/index.js
      R100\told/build/out.o\tcrates/cli/src/main.rs
      R100\tsrc/lib.rs\ttarget/release/libcompass.rlib
      """

    let issues = GeneratedArtifactHygiene.issues(fromGitNameStatus: output)
    let paths = Set(issues.map(\.path))

    #expect(!paths.contains(".target/debug/foo"))
    #expect(paths.contains("packages/app/dist/index.js"))
    #expect(!paths.contains("node_modules/left-pad/index.js"))
    #expect(!paths.contains("crates/cli/src/main.rs"))
    #expect(paths.contains("target/release/libcompass.rlib"))
  }

  @Test
  func formattedIssueIncludesHiddenCount() throws {
    let issues = (0..<15).map {
      GeneratedArtifactHygieneIssue(
        path: "dist/\($0).js", reason: "inside generated directory component `dist/`")
    }
    let message = try #require(GeneratedArtifactHygiene.formattedIssue(from: issues, limit: 3))
    #expect(message.contains("[artifact-hygiene]"))
    #expect(message.contains("dist/0.js"))
    #expect(message.contains("...and 12 more generated artifact(s)"))
  }

  @Test
  func doesNotFlagSourceBuildFolderMidTree() {
    let issues = GeneratedArtifactHygiene.issues(forChangedPaths: [
      "tools/build/generate.swift"
    ])
    #expect(issues.isEmpty)
  }
}

@Suite("StringUtils")
struct StringUtilsTests {
  @Test
  func boundedTextPrefersWordBoundary() {
    let text = "Compass captured command output for this batch of work"
    let bounded = StringUtils.boundedText(text, limit: 40)
    #expect(bounded.count <= 40)
    #expect(!bounded.hasSuffix(" "))
    #expect(bounded == "Compass captured command output for this")

    let midWord = StringUtils.boundedText(text, limit: 38)
    #expect(midWord == "Compass captured command output for")
  }

  @Test
  func boundedTextHardCutsWhenNoSpace() {
    let text = String(repeating: "a", count: 20)
    #expect(StringUtils.boundedText(text, limit: 8) == "aaaaaaaa")
    #expect(StringUtils.boundedText(text, limit: 0).isEmpty)
  }

  @Test
  func boundedTextCollapsesWhitespace() {
    #expect(StringUtils.boundedText("  hello\n\nworld  ", limit: 100) == "hello world")
  }
}

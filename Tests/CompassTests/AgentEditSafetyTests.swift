import Foundation
import Testing

@testable import CompassCore

@Suite("AgentEditSafety")
struct AgentEditSafetyTests {
  @Test
  func recognizesCommonSourceExtensions() {
    #expect(AgentEditSafety.isSourceFile(URL(fileURLWithPath: "src/main.rs")))
    #expect(AgentEditSafety.isSourceFile(URL(fileURLWithPath: "App.swift")))
    #expect(AgentEditSafety.isSourceFile(URL(fileURLWithPath: "index.tsx")))
    #expect(!AgentEditSafety.isSourceFile(URL(fileURLWithPath: "README.md")))
    #expect(!AgentEditSafety.isSourceFile(URL(fileURLWithPath: "Cargo.toml")))
  }

  @Test
  func recognizesTestPaths() {
    #expect(AgentEditSafety.isTestFile(URL(fileURLWithPath: "crates/core/tests/cli.rs")))
    #expect(AgentEditSafety.isTestFile(URL(fileURLWithPath: "src/foo_test.rs")))
    #expect(AgentEditSafety.isTestFile(URL(fileURLWithPath: "src/foo.test.ts")))
    #expect(AgentEditSafety.isTestFile(URL(fileURLWithPath: "src/__tests__/foo.js")))
    #expect(!AgentEditSafety.isTestFile(URL(fileURLWithPath: "crates/core/src/lib.rs")))
  }

  @Test
  func rejectsClearingNonEmptySource() {
    let url = URL(fileURLWithPath: "/tmp/demo/src/lib.rs")
    let message = AgentEditSafety.validatePostEdit(
      relativePath: "src/lib.rs",
      sourceURL: url,
      originalText: "fn main() {}\n",
      editedText: "\n"
    )
    #expect(message?.contains("empty") == true)
  }

  @Test
  func allowsClearingNonSourceFiles() {
    let url = URL(fileURLWithPath: "/tmp/demo/notes.md")
    let message = AgentEditSafety.validatePostEdit(
      relativePath: "notes.md",
      sourceURL: url,
      originalText: "hello",
      editedText: ""
    )
    #expect(message == nil)
  }

  @Test
  func rejectsNewPlaceholderMarkers() {
    let url = URL(fileURLWithPath: "/tmp/demo/src/lib.rs")
    let message = AgentEditSafety.validatePostEdit(
      relativePath: "src/lib.rs",
      sourceURL: url,
      originalText: "fn ready() -> bool { true }\n",
      editedText: "fn ready() -> bool { todo!(\"implement logic\") }\n"
    )
    #expect(message?.contains("placeholder") == true)
  }

  @Test
  func allowsPreexistingPlaceholderMarkers() {
    let original = "// TODO: implement later\nfn ready() -> bool { true }\n"
    let marker = AgentEditSafety.newPlaceholderImplementationMarker(
      originalText: original,
      editedText: original + "fn extra() {}\n"
    )
    #expect(marker == nil)
  }

  @Test
  func detectsPlaceholderOnFreshWrite() {
    let marker = AgentEditSafety.newPlaceholderImplementationMarker(
      originalText: "",
      editedText: "fn work() { unimplemented!() }\n"
    )
    #expect(marker?.lineNumber == 1)
    #expect(marker?.preview.contains("unimplemented") == true)
  }
}

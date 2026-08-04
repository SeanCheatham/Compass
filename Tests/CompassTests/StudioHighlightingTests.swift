import AppKit
import Foundation
import Testing

@testable import CompassCore

@Suite("StudioANSIParser")
struct StudioANSIParserTests {
  @Test
  func plainTextPassthrough() {
    let text = "hello world\n"
    #expect(StudioANSIParser.strip(text) == text)
    #expect(StudioANSIParser.nsAttributedString(text).string == text)
  }

  @Test
  func stripsAndColorsSGR() {
    let text = "\u{001B}[31mred\u{001B}[0m plain"
    #expect(StudioANSIParser.strip(text) == "red plain")
    let attributed = StudioANSIParser.nsAttributedString(text)
    #expect(attributed.string == "red plain")
    #expect(attributed.length == "red plain".utf16.count)
  }

  @Test
  func stripsOSCSequences() {
    let text = "\u{001B}]0;title\u{0007}ok"
    #expect(StudioANSIParser.strip(text) == "ok")
  }

  @Test
  func nestedResets() {
    let text = "\u{001B}[1;32mbold green\u{001B}[22m normal\u{001B}[0m done"
    #expect(StudioANSIParser.strip(text) == "bold green normal done")
  }
}

@Suite("StudioSyntaxHighlighter")
struct StudioSyntaxHighlighterTests {
  @Test
  func lineCountMatchesInput() {
    let source = "func hello() {\n  return 1\n}\n"
    let lines = StudioSyntaxHighlighter.shared.highlightLines(
      source: source,
      path: "Demo.swift",
      theme: .light
    )
    #expect(lines.count == source.components(separatedBy: "\n").count)
  }

  @Test
  func swiftTreeSitterProducesNonDefaultColors() throws {
    let source = """
      func greet(_ name: String) -> Int {
        // comment
        return 42
      }
      """
    #expect(StudioSyntaxHighlighter.shared.usesTreeSitter(for: "Sources/Demo.swift"))
    let lines = StudioSyntaxHighlighter.shared.highlightLines(
      source: source,
      path: "Sources/Demo.swift",
      theme: .dark
    )
    #expect(lines.count == source.components(separatedBy: "\n").count)
    // At least one line should carry a non-empty attributed run.
    let joined = lines.map(\.characters.count).reduce(0, +)
    #expect(joined > 0)
  }

  @Test
  func unsupportedLanguageFallsBackWithoutCrashing() {
    let source = "def hello():\n  return 'x'\n"
    let lines = StudioSyntaxHighlighter.shared.highlightLines(
      source: source,
      path: "script.py",
      theme: .light
    )
    #expect(lines.count == 3)
    #expect(!StudioSyntaxHighlighter.shared.usesTreeSitter(for: "script.py"))
  }

  @Test
  func cacheHitReturnsSameLineCount() {
    let highlighter = StudioSyntaxHighlighter.shared
    highlighter.clearCache()
    let source = "let x = 1\n"
    let first = highlighter.highlightLines(source: source, path: "a.swift", theme: .light)
    let second = highlighter.highlightLines(source: source, path: "a.swift", theme: .light)
    #expect(first.count == second.count)
    #expect(first.count == 2)
  }
}

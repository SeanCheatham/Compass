import Foundation
import Testing

@testable import Compass

/// Tests for `SymbolDetailPopover` (lines 731–850 in ContentViewExploreTab.swift).
///
/// These tests use `String(reflecting: popover.body)` to inspect the rendered
/// SwiftUI view hierarchy without needing a live AppKit/SwiftUI environment.
/// This pattern is consistent with other Explore popover tests in this suite.
struct ExploreSymbolDetailPopoverTests {

  // MARK: - init_preservesEntryAndFileURL

  /// Verifies the popover stores the injected entry and fileURL.
  @Test
  func init_preservesEntryAndFileURL() {
    let entry = CodemapEntry(
      relativePath: "/tmp/test.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 100,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    let fileURL = URL(fileURLWithPath: "/tmp/test.swift")
    let popover = SymbolDetailPopover(entry: entry, fileURL: fileURL)

    #expect(popover.entry.relativePath == "/tmp/test.swift")
    #expect(popover.fileURL != nil)
  }

  // MARK: - init_fileURLNil_hidesOpenInXcodeButton

  /// Verifies the "Open in Xcode" button is absent when fileURL is nil.
  @Test
  func init_fileURLNil_hidesOpenInXcodeButton() {
    let entry = CodemapEntry(
      relativePath: "/tmp/test.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 100,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    let popover = SymbolDetailPopover(entry: entry, fileURL: nil)
    let body = String(reflecting: popover.body)

    // The button label "Open in Xcode" must not appear in the view hierarchy.
    #expect(!body.contains("Open in Xcode"))
  }

  // MARK: - init_withFileURL_showsOpenInXcodeButton

  /// Verifies the "Open in Xcode" button is present when a real fileURL is provided.
  @Test
  func init_withFileURL_showsOpenInXcodeButton() {
    let entry = CodemapEntry(
      relativePath: "/tmp/test.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 100,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    let fileURL = URL(fileURLWithPath: "/tmp/test.swift")
    let popover = SymbolDetailPopover(entry: entry, fileURL: fileURL)
    let body = String(reflecting: popover.body)

    #expect(body.contains("Open in Xcode"))
  }

  // MARK: - symbolsSection_visibleWithSymbols

  /// Verifies the symbols section renders when the entry has at least one symbol.
  @Test
  func symbolsSection_visibleWithSymbols() {
    let symbol = CodemapSymbol(kind: .function, name: "foo", line: 10, endLine: 10)
    let entry = CodemapEntry(
      relativePath: "/tmp/test.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 100,
      symbols: [symbol],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    let popover = SymbolDetailPopover(entry: entry, fileURL: nil)
    let body = String(reflecting: popover.body)

    #expect(body.contains("foo"))
    #expect(body.contains("Symbols"))
  }

  // MARK: - importsSection_visibleWithImports

  /// Verifies the imports section renders when the entry has at least one import.
  @Test
  func importsSection_visibleWithImports() {
    let `import` = CodemapImport(raw: "Foundation", line: 3)
    let entry = CodemapEntry(
      relativePath: "/tmp/test.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 100,
      symbols: [],
      imports: [`import`],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    let popover = SymbolDetailPopover(entry: entry, fileURL: nil)
    let body = String(reflecting: popover.body)

    #expect(body.contains("Foundation"))
    #expect(body.contains("Imports"))
  }

  // MARK: - emptyState_showsNoSymbolsOrImportsMessage

  /// Verifies the empty-state message is shown when both symbols and imports are absent.
  @Test
  func emptyState_showsNoSymbolsOrImportsMessage() {
    let entry = CodemapEntry(
      relativePath: "/tmp/test.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 100,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    let popover = SymbolDetailPopover(entry: entry, fileURL: nil)
    let body = String(reflecting: popover.body)

    #expect(body.contains("No symbols or imports found."))
  }

  // MARK: - frameWidth440

  /// Verifies the popover body declares the expected fixed width of 440.
  @Test
  func frameWidth440() {
    let entry = CodemapEntry(
      relativePath: "/tmp/test.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 100,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    let popover = SymbolDetailPopover(entry: entry, fileURL: nil)
    let body = String(reflecting: popover.body)

    #expect(body.contains("440"))
  }
}
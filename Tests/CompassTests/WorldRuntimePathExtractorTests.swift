import Foundation
import Testing

@testable import Compass

struct WorldRuntimePathExtractorTests {
  private let extractor = RuntimePathExtractor()

  @Test
  func detectEntrypoints_acrossSupportedLanguages() throws {
    let swiftEntries = RuntimePathExtractor.detectEntrypoints(
      source: """
        import SwiftUI
        @main
        struct DemoApp {}
        """,
      language: .swift,
      relativePath: "Sources/Demo/App.swift",
      symbols: [
        CodemapSymbol(kind: .struct, name: "DemoApp", line: 3, endLine: 3)
      ]
    )
    #expect(swiftEntries.first?.name == "DemoApp")
    #expect(swiftEntries.first?.confidence == .high)

    let goEntries = RuntimePathExtractor.detectEntrypoints(
      source: """
        package main
        func main() {}
        """,
      language: .go,
      relativePath: "cmd/demo/main.go",
      symbols: [
        CodemapSymbol(kind: .function, name: "main", line: 2, endLine: 2)
      ]
    )
    #expect(goEntries.first?.reason.contains("Go") == true)

    let rustEntries = RuntimePathExtractor.detectEntrypoints(
      source: "fn main() {}",
      language: .rust,
      relativePath: "src/main.rs",
      symbols: [
        CodemapSymbol(kind: .function, name: "main", line: 1, endLine: 1)
      ]
    )
    #expect(rustEntries.first?.reason.contains("Rust") == true)

    for language in [CodemapLanguage.javascript, .typescript, .tsx] {
      let entries = RuntimePathExtractor.detectEntrypoints(
        source: "export function main() { run(); }",
        language: language,
        relativePath: "src/index.\(language == .javascript ? "js" : "ts")",
        symbols: [
          CodemapSymbol(kind: .function, name: "main", line: 1, endLine: 1)
        ]
      )
      #expect(entries.contains { $0.name == "main" })
    }
  }

  @Test
  func extractsControlFlowAndCalls_acrossSupportedLanguages() throws {
    let fixtures: [(CodemapLanguage, String, String, Set<RuntimePathConstructKind>)] = [
      (
        .swift,
        "Sources/App.swift",
        """
        @main
        struct App {
          static func main() {
            if Bool.random() { helper() }
            for item in [1] { helper() }
            switch 1 { case 1: helper(); default: break }
            do { try risky() } catch { helper() }
          }
          static func helper() {}
          static func risky() throws {}
        }
        """,
        [.branch, .loop, .switchCase, .errorPath]
      ),
      (
        .typescript,
        "src/index.ts",
        """
        export function main(): void {
          if (ready()) { run(); }
          for (let i = 0; i < 1; i++) { run(); }
          switch (1) { case 1: run(); break; }
          try { run(); } catch (error) { recover(); }
        }
        function ready(): boolean { return true; }
        function run(): void {}
        function recover(): void {}
        """,
        [.branch, .loop, .switchCase, .errorPath]
      ),
      (
        .javascript,
        "src/index.js",
        """
        export function main() {
          if (ready()) { run(); }
          for (let i = 0; i < 1; i++) { run(); }
          switch (1) { case 1: run(); break; }
          try { run(); } catch (error) { recover(); }
        }
        function ready() { return true; }
        function run() {}
        function recover() {}
        """,
        [.branch, .loop, .switchCase, .errorPath]
      ),
      (
        .go,
        "cmd/demo/main.go",
        """
        package main
        func main() {
          if true { helper() }
          for i := 0; i < 1; i++ { helper() }
          switch i := 1; i { case 1: helper() }
        }
        func helper() {}
        """,
        [.branch, .loop, .switchCase]
      ),
      (
        .rust,
        "src/main.rs",
        """
        fn main() -> Result<(), ()> {
          if true { helper(); }
          for _item in 0..1 { helper(); }
          loop { break; }
          match 1 { 1 => helper(), _ => helper() };
          maybe()?;
          Ok(())
        }
        fn helper() {}
        fn maybe() -> Result<(), ()> { Ok(()) }
        """,
        [.branch, .loop, .switchCase, .errorPath]
      ),
    ]

    for (language, path, source, expectedKinds) in fixtures {
      let extraction = try extractor.extract(
        source: source,
        language: language,
        relativePath: path,
        symbols: []
      )
      let kinds = Set(extraction.constructs.map(\.kind))
      for kind in expectedKinds {
        #expect(kinds.contains(kind), "Missing \(kind) for \(language.displayName)")
      }
      #expect(!extraction.calls.isEmpty, "Missing calls for \(language.displayName)")
    }
  }
}

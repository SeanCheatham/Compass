import Foundation
import Testing

@testable import Compass

struct SymbolExtractorTests {
  private let extractor = SymbolExtractor()

  @Test
  func testSwiftFixtureExtractsExpectedSymbols() throws {
    let source = """
      import Foundation
      import Compass

      class Animal {
        func bark() {}
        var name: String = ""
      }

      struct Point2D {
        let x: Int
      }

      protocol Greeter {
        func greet()
      }

      enum Direction {
        case north
      }

      func topLevelHelper() -> Int { 0 }

      typealias Pair = (Int, Int)
      """

    let extraction = try extractor.extract(source: source, language: .swift)

    try #require(extraction.imports.map(\.raw) == ["Foundation", "Compass"])
    try #require(extraction.imports.map(\.line) == [1, 2])

    let names = extraction.symbols.map(\.name)
    try #require(names.contains("Animal"))
    try #require(names.contains("Point2D"))
    try #require(names.contains("Greeter"))
    try #require(names.contains("Direction"))
    try #require(names.contains("topLevelHelper"))
    try #require(names.contains("Pair"))
    try #require(names.contains("bark"))
    try #require(names.contains("greet"))

    let kindByName: [String: CodemapSymbolKind] = Dictionary(
      uniqueKeysWithValues: extraction.symbols.map { ($0.name, $0.kind) }
    )
    try #require(kindByName["Animal"] == .class)
    try #require(kindByName["Greeter"] == .interface)
    try #require(kindByName["topLevelHelper"] == .function)
    try #require(kindByName["Pair"] == .type)
    try #require(kindByName["bark"] == .function)
    try #require(kindByName["greet"] == .method)

    let animal = try #require(extraction.symbols.first { $0.name == "Animal" })
    try #require(animal.line == 4)
    try #require(animal.endLine > animal.line)
  }

  @Test
  func testTypeScriptFixtureExtractsClassFunctionInterface() throws {
    let source = """
      import { foo } from "./foo";
      import bar from "bar";

      export class Service {
        run(): void {}
      }

      export interface Greeter {
        greet(): string;
      }

      export function topLevel(): number {
        return 1;
      }

      export const arrow = (x: number): number => x + 1;

      export type Pair = [number, number];
      """

    let extraction = try extractor.extract(source: source, language: .typescript)

    try #require(extraction.imports.map(\.raw) == ["./foo", "bar"])
    let names = Set(extraction.symbols.map(\.name))
    try #require(names.contains("Service"))
    try #require(names.contains("Greeter"))
    try #require(names.contains("topLevel"))
    try #require(names.contains("Pair"))
    try #require(names.contains("arrow"))
    try #require(names.contains("run"))
  }

  @Test
  func testGoFixtureExtractsFunctionMethodStruct() throws {
    let source = """
      package main

      import "fmt"

      type Server struct {
        Name string
      }

      func (s *Server) Start() error { return nil }

      func New() *Server { return &Server{} }
      """

    let extraction = try extractor.extract(source: source, language: .go)

    try #require(extraction.imports.map(\.raw) == ["fmt"])
    let names = Set(extraction.symbols.map(\.name))
    try #require(names.contains("Server"))
    try #require(names.contains("Start"))
    try #require(names.contains("New"))
  }

  @Test
  func testRustFixtureExtractsRustTraitFunctionImpl() throws {
    let source = #"""
      use std::io;
      use serde::Serialize;

      pub struct Cache {
          size: usize,
      }

      pub trait Lookup {
          fn get(&self, key: &str) -> Option<String>;
      }

      impl Cache {
          pub fn new() -> Self { Self { size: 0 } }
      }

      pub fn version() -> &'static str { "1.0" }
      """#

    let extraction = try extractor.extract(source: source, language: .rust)

    try #require(extraction.imports.count == 2)
    let names = Set(extraction.symbols.map(\.name))
    try #require(names.contains("Cache"))
    try #require(names.contains("Lookup"))
    try #require(names.contains("version"))
    try #require(names.contains("new"))
  }

  @Test
  func testJavaScriptFixtureExtractsClassFunctionArrow() throws {
    let source = """
      import { x } from "./mod";

      export class Box {
        open() {}
      }

      export function topLevel() {}

      export const arrow = () => 42;
      """

    let extraction = try extractor.extract(source: source, language: .javascript)

    try #require(extraction.imports.map(\.raw) == ["./mod"])
    let names = Set(extraction.symbols.map(\.name))
    try #require(names.contains("Box"))
    try #require(names.contains("topLevel"))
    try #require(names.contains("arrow"))
    try #require(names.contains("open"))
  }

  @Test
  func testTSXFixtureSharesTypeScriptExtractor() throws {
    let source = """
      import React from "react";

      export class Panel extends React.Component {}

      export function Greeting(): JSX.Element {
        return <div>hi</div>;
      }
      """

    let extraction = try extractor.extract(source: source, language: .tsx)

    try #require(extraction.imports.map(\.raw) == ["react"])
    let names = Set(extraction.symbols.map(\.name))
    try #require(names.contains("Panel"))
    try #require(names.contains("Greeting"))
  }

  @Test
  func testLanguageRegistryResolvesByExtension() throws {
    try #require(CodemapLanguage.forFile(at: "Foo.swift") == .swift)
    try #require(CodemapLanguage.forFile(at: "src/foo.ts") == .typescript)
    try #require(CodemapLanguage.forFile(at: "src/Foo.tsx") == .tsx)
    try #require(CodemapLanguage.forFile(at: "src/foo.js") == .javascript)
    try #require(CodemapLanguage.forFile(at: "main.py") == nil)
    try #require(CodemapLanguage.forFile(at: "main.go") == .go)
    try #require(CodemapLanguage.forFile(at: "lib.rs") == .rust)
    try #require(CodemapLanguage.forFile(at: "Main.hs") == nil)
    try #require(CodemapLanguage.forFile(at: "README.md") == nil)
    try #require(CodemapLanguage.forFile(at: "Cargo.toml") == nil)
  }

  @Test
  func testLanguageRegistryResolvesMixedCaseExtensions() throws {
    try #require(CodemapLanguage.forFile(at: "Foo.SWIFT") == .swift)
    try #require(CodemapLanguage.forFile(at: "Foo.Swift") == .swift)
    try #require(CodemapLanguage.forFile(at: "Foo.TS") == .typescript)
    try #require(CodemapLanguage.forFile(at: "Foo.Tsx") == .tsx)
    try #require(CodemapLanguage.forFile(at: "Foo.JS") == .javascript)
    try #require(CodemapLanguage.forFile(at: "Foo.PY") == nil)
    try #require(CodemapLanguage.forFile(at: "Foo.GO") == .go)
    try #require(CodemapLanguage.forFile(at: "Foo.RS") == .rust)
    try #require(CodemapLanguage.forFile(at: "Foo.HS") == nil)
  }

  @Test
  func testLanguageRegistryUnrecognizedVariantExtensionsReturnNil() throws {
    // Unusual Swift spellings that are not in the extension map
    try #require(CodemapLanguage.forFile(at: "Foo.sx") == nil)
    try #require(CodemapLanguage.forFile(at: "Foo.sw") == nil)
    // Other genuinely unrecognized extensions
    try #require(CodemapLanguage.forFile(at: "foo.txt") == nil)
    try #require(CodemapLanguage.forFile(at: "foo.json") == nil)
    try #require(CodemapLanguage.forFile(at: "foo.xml") == nil)
    try #require(CodemapLanguage.forFile(at: "foo.scss") == nil)
  }
}

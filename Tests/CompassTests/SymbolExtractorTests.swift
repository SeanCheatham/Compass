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

    #require(extraction.imports.map(\.raw) == ["Foundation", "Compass"])
    #require(extraction.imports.map(\.line) == [1, 2])

    let names = extraction.symbols.map(\.name)
    #require(names.contains("Animal"))
    #require(names.contains("Point2D"))
    #require(names.contains("Greeter"))
    #require(names.contains("Direction"))
    #require(names.contains("topLevelHelper"))
    #require(names.contains("Pair"))
    #require(names.contains("bark"))
    #require(names.contains("greet"))

    let kindByName: [String: CodemapSymbolKind] = Dictionary(
      uniqueKeysWithValues: extraction.symbols.map { ($0.name, $0.kind) }
    )
    #require(kindByName["Animal"] == .class)
    #require(kindByName["Greeter"] == .interface)
    #require(kindByName["topLevelHelper"] == .function)
    #require(kindByName["Pair"] == .type)
    #require(kindByName["bark"] == .function)
    #require(kindByName["greet"] == .method)

    let animal = #require(extraction.symbols.first { $0.name == "Animal" })
    #require(animal.line == 4)
    #require(animal.endLine > animal.line)
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

    #require(extraction.imports.map(\.raw) == ["./foo", "bar"])
    let names = Set(extraction.symbols.map(\.name))
    #require(names.contains("Service"))
    #require(names.contains("Greeter"))
    #require(names.contains("topLevel"))
    #require(names.contains("Pair"))
    #require(names.contains("arrow"))
    #require(names.contains("run"))
  }

  @Test
  func testPythonFixtureExtractsFunctionAndClass() throws {
    let source = """
      import os
      from collections import OrderedDict

      def greet(name):
          return f"hi {name}"

      class Repo:
          def commit(self): ...
      """

    let extraction = try extractor.extract(source: source, language: .python)

    #require(extraction.imports.map(\.raw) == ["os", "collections"])
    let names = Set(extraction.symbols.map(\.name))
    #require(names.contains("greet"))
    #require(names.contains("Repo"))
    #require(names.contains("commit"))
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

    #require(extraction.imports.map(\.raw) == ["fmt"])
    let names = Set(extraction.symbols.map(\.name))
    #require(names.contains("Server"))
    #require(names.contains("Start"))
    #require(names.contains("New"))
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

    #require(extraction.imports.count == 2)
    let names = Set(extraction.symbols.map(\.name))
    #require(names.contains("Cache"))
    #require(names.contains("Lookup"))
    #require(names.contains("version"))
    #require(names.contains("new"))
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

    #require(extraction.imports.map(\.raw) == ["./mod"])
    let names = Set(extraction.symbols.map(\.name))
    #require(names.contains("Box"))
    #require(names.contains("topLevel"))
    #require(names.contains("arrow"))
    #require(names.contains("open"))
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

    #require(extraction.imports.map(\.raw) == ["react"])
    let names = Set(extraction.symbols.map(\.name))
    #require(names.contains("Panel"))
    #require(names.contains("Greeting"))
  }

  @Test
  func testLanguageRegistryResolvesByExtension() {
    #require(CodemapLanguage.forFile(at: "Foo.swift") == .swift)
    #require(CodemapLanguage.forFile(at: "src/foo.ts") == .typescript)
    #require(CodemapLanguage.forFile(at: "src/Foo.tsx") == .tsx)
    #require(CodemapLanguage.forFile(at: "src/foo.js") == .javascript)
    #require(CodemapLanguage.forFile(at: "main.py") == .python)
    #require(CodemapLanguage.forFile(at: "main.go") == .go)
    #require(CodemapLanguage.forFile(at: "lib.rs") == .rust)
    #require(CodemapLanguage.forFile(at: "README.md") == nil)
    #require(CodemapLanguage.forFile(at: "Cargo.toml") == nil)
  }
}

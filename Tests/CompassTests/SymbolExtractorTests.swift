import Foundation
import XCTest

@testable import Compass

final class SymbolExtractorTests: XCTestCase {
  private let extractor = SymbolExtractor()

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

    XCTAssertEqual(extraction.imports.map(\.raw), ["Foundation", "Compass"])
    XCTAssertEqual(extraction.imports.map(\.line), [1, 2])

    let names = extraction.symbols.map(\.name)
    XCTAssertTrue(names.contains("Animal"))
    XCTAssertTrue(names.contains("Point2D"))
    XCTAssertTrue(names.contains("Greeter"))
    XCTAssertTrue(names.contains("Direction"))
    XCTAssertTrue(names.contains("topLevelHelper"))
    XCTAssertTrue(names.contains("Pair"))
    XCTAssertTrue(names.contains("bark"))
    XCTAssertTrue(names.contains("greet"))

    let kindByName: [String: CodemapSymbolKind] = Dictionary(
      uniqueKeysWithValues: extraction.symbols.map { ($0.name, $0.kind) }
    )
    XCTAssertEqual(kindByName["Animal"], .class)
    XCTAssertEqual(kindByName["Greeter"], .interface)
    XCTAssertEqual(kindByName["topLevelHelper"], .function)
    XCTAssertEqual(kindByName["Pair"], .type)
    XCTAssertEqual(kindByName["bark"], .function)
    XCTAssertEqual(kindByName["greet"], .method)

    let animal = try XCTUnwrap(extraction.symbols.first { $0.name == "Animal" })
    XCTAssertEqual(animal.line, 4)
    XCTAssertGreaterThan(animal.endLine, animal.line)
  }

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

    XCTAssertEqual(extraction.imports.map(\.raw), ["./foo", "bar"])
    let names = Set(extraction.symbols.map(\.name))
    XCTAssertTrue(names.contains("Service"))
    XCTAssertTrue(names.contains("Greeter"))
    XCTAssertTrue(names.contains("topLevel"))
    XCTAssertTrue(names.contains("Pair"))
    XCTAssertTrue(names.contains("arrow"))
    XCTAssertTrue(names.contains("run"))
  }

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

    XCTAssertEqual(extraction.imports.map(\.raw), ["os", "collections"])
    let names = Set(extraction.symbols.map(\.name))
    XCTAssertTrue(names.contains("greet"))
    XCTAssertTrue(names.contains("Repo"))
    XCTAssertTrue(names.contains("commit"))
  }

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

    XCTAssertEqual(extraction.imports.map(\.raw), ["fmt"])
    let names = Set(extraction.symbols.map(\.name))
    XCTAssertTrue(names.contains("Server"))
    XCTAssertTrue(names.contains("Start"))
    XCTAssertTrue(names.contains("New"))
  }

  func testRustFixtureExtractsStructTraitFunctionImpl() throws {
    let source = """
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
      """

    let extraction = try extractor.extract(source: source, language: .rust)

    XCTAssertEqual(extraction.imports.count, 2)
    let names = Set(extraction.symbols.map(\.name))
    XCTAssertTrue(names.contains("Cache"))
    XCTAssertTrue(names.contains("Lookup"))
    XCTAssertTrue(names.contains("version"))
    XCTAssertTrue(names.contains("new"))
  }

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

    XCTAssertEqual(extraction.imports.map(\.raw), ["./mod"])
    let names = Set(extraction.symbols.map(\.name))
    XCTAssertTrue(names.contains("Box"))
    XCTAssertTrue(names.contains("topLevel"))
    XCTAssertTrue(names.contains("arrow"))
    XCTAssertTrue(names.contains("open"))
  }

  func testTSXFixtureSharesTypeScriptExtractor() throws {
    let source = """
      import React from "react";

      export class Panel extends React.Component {}

      export function Greeting(): JSX.Element {
        return <div>hi</div>;
      }
      """

    let extraction = try extractor.extract(source: source, language: .tsx)

    XCTAssertEqual(extraction.imports.map(\.raw), ["react"])
    let names = Set(extraction.symbols.map(\.name))
    XCTAssertTrue(names.contains("Panel"))
    XCTAssertTrue(names.contains("Greeting"))
  }

  func testLanguageRegistryResolvesByExtension() {
    XCTAssertEqual(CodemapLanguage.forFile(at: "Foo.swift"), .swift)
    XCTAssertEqual(CodemapLanguage.forFile(at: "src/foo.ts"), .typescript)
    XCTAssertEqual(CodemapLanguage.forFile(at: "src/Foo.tsx"), .tsx)
    XCTAssertEqual(CodemapLanguage.forFile(at: "src/foo.js"), .javascript)
    XCTAssertEqual(CodemapLanguage.forFile(at: "main.py"), .python)
    XCTAssertEqual(CodemapLanguage.forFile(at: "main.go"), .go)
    XCTAssertEqual(CodemapLanguage.forFile(at: "lib.rs"), .rust)
    XCTAssertNil(CodemapLanguage.forFile(at: "README.md"))
    XCTAssertNil(CodemapLanguage.forFile(at: "Cargo.toml"))
  }
}

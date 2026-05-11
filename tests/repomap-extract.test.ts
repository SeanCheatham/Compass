import { test } from "node:test";
import assert from "node:assert/strict";
import { detectLanguage, extract, extractSymbols } from "../src/repomap/extract.ts";

test("detectLanguage maps common extensions", () => {
  assert.equal(detectLanguage("foo.ts"), "ts");
  assert.equal(detectLanguage("foo.tsx"), "tsx");
  assert.equal(detectLanguage("foo.mts"), "ts");
  assert.equal(detectLanguage("a/b.js"), "js");
  assert.equal(detectLanguage("foo.cjs"), "js");
  assert.equal(detectLanguage("script.py"), "py");
  assert.equal(detectLanguage("main.go"), "go");
  assert.equal(detectLanguage("lib.rs"), "rs");
  assert.equal(detectLanguage("README.md"), "md");
  assert.equal(detectLanguage("docs/foo.markdown"), "md");
  assert.equal(detectLanguage("Dockerfile"), null);
});

// ---------- TS / JS / TSX

test("TS: top-level decls, signatures, return types, exports", () => {
  const text = `
import { x, y } from "./mod.js";
export function frobnicate(a: number, b: string): Promise<void> { return Promise.resolve(); }
export interface Foo { id: number; greet(name: string): string; }
export type Bar = string | number;
export enum Color { Red, Green }
export class Widget { name: string = "w"; greet(): string { return this.name; } }
export const exported = 1;
const internal = 2;
`;
  const { symbols, imports } = extract(text, "ts");
  const byName = Object.fromEntries(symbols.map((s) => [s.name, s]));

  assert.equal(byName.frobnicate!.kind, "function");
  assert.equal(byName.frobnicate!.signature, "a: number, b: string");
  assert.equal(byName.frobnicate!.returnType, "Promise<void>");
  assert.equal(byName.frobnicate!.exported, true);

  assert.equal(byName.Foo!.kind, "interface");
  assert.equal(byName.Foo!.exported, true);
  assert.ok(byName.Foo!.members && byName.Foo!.members.length >= 2);

  assert.equal(byName.Bar!.kind, "type");
  assert.equal(byName.Color!.kind, "enum");

  assert.equal(byName.Widget!.kind, "class");
  assert.ok(byName.Widget!.members);

  assert.equal(byName.exported!.kind, "const");
  assert.equal(byName.exported!.exported, true);
  // Unexported top-level consts are dropped to keep the map focused.
  assert.equal(byName.internal, undefined);

  assert.equal(imports.length, 1);
  assert.equal(imports[0]!.raw, "./mod.js");
  assert.equal(imports[0]!.resolved, null); // resolver runs separately
});

test("TS: arrow-function exports surface as functions", () => {
  const text = `export const add = (a: number, b: number): number => a + b;`;
  const syms = extractSymbols(text, "ts");
  const add = syms.find((s) => s.name === "add");
  assert.ok(add);
  assert.equal(add!.kind, "function");
  assert.equal(add!.signature, "a: number, b: number");
  assert.equal(add!.returnType, "number");
  assert.equal(add!.exported, true);
});

test("TS: class members include methods and fields", () => {
  const text = `
export class Widget {
  name: string = "w";
  count: number = 0;
  greet(): string { return this.name; }
  static make(name: string): Widget { return new Widget(); }
}`;
  const syms = extractSymbols(text, "ts");
  const widget = syms.find((s) => s.name === "Widget");
  assert.ok(widget?.members);
  const names = widget!.members!.map((m) => `${m.kind}:${m.name}`);
  assert.ok(names.includes("field:name"));
  assert.ok(names.includes("field:count"));
  assert.ok(names.includes("method:greet"));
  assert.ok(names.includes("method:make"));
});

test("TSX: parses JSX without erroring", () => {
  const text = `export function Hello(): JSX.Element { return <div>hi</div>; }`;
  const syms = extractSymbols(text, "tsx");
  const hello = syms.find((s) => s.name === "Hello");
  assert.ok(hello);
  assert.equal(hello!.kind, "function");
});

test("JS: extracts decls without type annotations", () => {
  const text = `
export function add(a, b) { return a + b; }
export const sq = (x) => x * x;
export class Foo { greet() { return "hi"; } }
`;
  const syms = extractSymbols(text, "js");
  const byName = Object.fromEntries(syms.map((s) => [s.name, s]));
  assert.equal(byName.add!.signature, "a, b");
  assert.equal(byName.add!.returnType, undefined); // JS has no return types
  assert.equal(byName.sq!.kind, "function");
  assert.equal(byName.Foo!.kind, "class");
});

// ---------- Python

test("PY: functions with return types, classes with methods, imports", () => {
  const text = `
import os
from .foo import bar
from typing import List
def hello(name: str) -> str:
    return name
async def asyncFn(x: int) -> int:
    return x
class Cat:
    def __init__(self, name: str): self.name = name
    def meow(self) -> str: return "meow"
    @classmethod
    def make(cls) -> "Cat": return cls("x")
`;
  const { symbols, imports } = extract(text, "py");
  const byName = Object.fromEntries(symbols.map((s) => [s.name, s]));

  assert.equal(byName.hello!.kind, "function");
  assert.equal(byName.hello!.signature, "name: str");
  assert.equal(byName.hello!.returnType, "str");

  assert.equal(byName.asyncFn!.kind, "function");
  assert.equal(byName.asyncFn!.returnType, "int");

  assert.equal(byName.Cat!.kind, "class");
  const memberNames = byName.Cat!.members!.map((m) => m.name);
  assert.ok(memberNames.includes("__init__"));
  assert.ok(memberNames.includes("meow"));
  assert.ok(memberNames.includes("make"), "decorated classmethod included");

  const importRaws = imports.map((i) => i.raw);
  assert.ok(importRaws.includes("os"));
  assert.ok(importRaws.includes(".foo"));
  assert.ok(importRaws.includes("typing"));
});

// ---------- Go

test("GO: types, functions, methods grouped under receiver", () => {
  const text = `package main
import (
  "fmt"
  "os"
)
type Foo struct { Name string; Count int }
type Bar interface { Greet() string }
func (f *Foo) Greet() string { return f.Name }
func (f *Foo) Bump() { f.Count++ }
func main() {}
const PI = 3.14
var counter int = 0
`;
  const { symbols, imports } = extract(text, "go");
  const byName = Object.fromEntries(symbols.map((s) => [s.name, s]));

  assert.equal(byName.Foo!.kind, "struct");
  // Struct fields + methods both surface as members.
  const fooMembers = byName.Foo!.members!.map((m) => `${m.kind}:${m.name}`);
  assert.ok(fooMembers.includes("field:Name"));
  assert.ok(fooMembers.includes("field:Count"));
  assert.ok(fooMembers.includes("method:Greet"));
  assert.ok(fooMembers.includes("method:Bump"));

  assert.equal(byName.Bar!.kind, "interface");
  assert.ok(byName.Bar!.members!.some((m) => m.name === "Greet"));

  assert.equal(byName.main!.kind, "func");
  assert.equal(byName.PI!.kind, "const");
  assert.equal(byName.counter!.kind, "var");

  const importRaws = imports.map((i) => i.raw);
  assert.ok(importRaws.includes("fmt"));
  assert.ok(importRaws.includes("os"));
});

// ---------- Rust

test("RS: items with members and pub visibility", () => {
  const text = `
use std::collections::HashMap;
pub struct Foo { pub name: String, count: u32 }
pub enum Color { Red, Green, Blue }
pub trait Greet { fn greet(&self) -> String; }
impl Greet for Foo { fn greet(&self) -> String { self.name.clone() } }
impl Foo { pub fn new(name: String) -> Self { Foo { name, count: 0 } } }
pub fn add(a: i32, b: i32) -> i32 { a + b }
pub const PI: f64 = 3.14;
fn private_fn() {}
`;
  const { symbols, imports } = extract(text, "rs");
  // Don't index-by-name: inherent `impl Foo` collides with `struct Foo`.
  const find = (kind: string, name: string) =>
    symbols.find((s) => s.kind === kind && s.name === name);

  const foo = find("struct", "Foo");
  assert.ok(foo);
  assert.equal(foo!.exported, true);
  assert.ok(foo!.members!.some((m) => m.name === "name"));

  const color = find("enum", "Color");
  assert.ok(color);
  assert.deepEqual(
    color!.members!.map((m) => m.name).sort(),
    ["Blue", "Green", "Red"]
  );

  assert.ok(find("trait", "Greet"));

  const add = find("fn", "add");
  assert.ok(add);
  assert.equal(add!.exported, true);
  assert.equal(add!.returnType, "i32");

  const priv = find("fn", "private_fn");
  assert.ok(priv);
  assert.equal(priv!.exported, undefined);

  // Two impl entries: one inherent (`Foo`), one trait impl (`Greet for Foo`).
  const impls = symbols.filter((s) => s.kind === "impl");
  assert.equal(impls.length, 2);

  assert.equal(imports.length, 1);
  assert.equal(imports[0]!.raw, "std::collections::HashMap");
});

// ---------- Markdown

test("MD: extracts column-0 h1/h2/h3 outside fences", () => {
  const text = `# Top

## Setup

\`\`\`md
## inside fence (ignored)
\`\`\`

### Notes
`;
  const syms = extractSymbols(text, "md");
  const kinds = syms.map((s) => `${s.kind}:${s.name}`);
  assert.deepEqual(kinds, ["h1:Top", "h2:Setup", "h3:Notes"]);
});

test("MD: malformed fences don't suppress later headings indefinitely", () => {
  // Open fence with backtick, "close" attempt with tilde — doesn't match, so
  // we should stay in-fence and suppress the heading.
  const text = `# Outside
\`\`\`
content
~~~
## still inside
\`\`\`
## now outside
`;
  const syms = extractSymbols(text, "md");
  const names = syms.map((s) => s.name);
  assert.deepEqual(names, ["Outside", "now outside"]);
});

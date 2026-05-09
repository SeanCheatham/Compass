import { test } from "node:test";
import assert from "node:assert/strict";
import { detectLanguage, extractSymbols } from "../src/repomap/extract.ts";

test("detectLanguage maps common extensions", () => {
  assert.equal(detectLanguage("foo.ts"), "ts");
  assert.equal(detectLanguage("foo.tsx"), "ts");
  assert.equal(detectLanguage("foo.mts"), "ts");
  assert.equal(detectLanguage("a/b.js"), "js");
  assert.equal(detectLanguage("foo.cjs"), "js");
  assert.equal(detectLanguage("script.py"), "py");
  assert.equal(detectLanguage("main.go"), "go");
  assert.equal(detectLanguage("lib.rs"), "rs");
  assert.equal(detectLanguage("README.md"), null);
  assert.equal(detectLanguage("Dockerfile"), null);
});

test("TypeScript: extracts top-level decls and skips nested", () => {
  const text = `import x from "y";

export interface Foo {
  field: string;
}

export type Bar = string | number;

export const enum Color { Red, Blue }

export function frobnicate(a: number): number {
  function inner() { return 1; }
  return inner();
}

export default class Widget {
  method() {}
}

function privateHelper() {}

export const SOME_CONST = 42;
`;
  const syms = extractSymbols(text, "ts");
  const names = syms.map((s) => `${s.kind}:${s.name}`);
  assert.ok(names.includes("interface:Foo"));
  assert.ok(names.includes("type:Bar"));
  assert.ok(names.includes("enum:Color"));
  assert.ok(names.includes("function:frobnicate"));
  assert.ok(names.includes("class:Widget"));
  assert.ok(names.includes("function:privateHelper"));
  assert.ok(names.includes("const:SOME_CONST"));
  // nested function should NOT be picked up (it's indented)
  assert.ok(!names.some((n) => n.endsWith(":inner")));
  // class method should NOT be picked up
  assert.ok(!names.some((n) => n.endsWith(":method")));
});

test("TypeScript: line numbers are 1-based and accurate", () => {
  const text = `// line 1
export function alpha() {}
export function beta() {}
`;
  const syms = extractSymbols(text, "ts");
  const alpha = syms.find((s) => s.name === "alpha");
  const beta = syms.find((s) => s.name === "beta");
  assert.equal(alpha?.line, 2);
  assert.equal(beta?.line, 3);
});

test("Python: extracts def and class, skips indented", () => {
  const text = `class Foo:
    def method(self):
        pass

def top_level():
    def inner():
        pass

async def async_top():
    pass
`;
  const syms = extractSymbols(text, "py");
  const names = syms.map((s) => `${s.kind}:${s.name}`);
  assert.ok(names.includes("class:Foo"));
  assert.ok(names.includes("function:top_level"));
  assert.ok(names.includes("function:async_top"));
  assert.ok(!names.some((n) => n.endsWith(":method")));
  assert.ok(!names.some((n) => n.endsWith(":inner")));
});

test("Go: extracts func, type, const, var; methods captured by name", () => {
  const text = `package foo

type User struct {
  Name string
}

func (u *User) Greet() string {
  return "hi"
}

func NewUser(name string) *User {
  return &User{Name: name}
}

const Pi = 3.14

var defaultName = "anon"
`;
  const syms = extractSymbols(text, "go");
  const names = syms.map((s) => `${s.kind}:${s.name}`);
  assert.ok(names.includes("type:User"));
  assert.ok(names.includes("func:Greet"));
  assert.ok(names.includes("func:NewUser"));
  assert.ok(names.includes("const:Pi"));
  assert.ok(names.includes("var:defaultName"));
});

test("Rust: extracts fn, struct, enum, trait, impl, mod", () => {
  const text = `pub mod widget;

pub struct Widget {
    name: String,
}

pub enum Color { Red, Blue }

pub trait Drawable {
    fn draw(&self);
}

impl Drawable for Widget {
    fn draw(&self) {}
}

impl Widget {
    pub fn new(name: String) -> Self { Widget { name } }
}

pub fn make_widget() -> Widget {
    Widget { name: String::new() }
}

pub const MAX: u32 = 100;
`;
  const syms = extractSymbols(text, "rs");
  const names = syms.map((s) => `${s.kind}:${s.name}`);
  assert.ok(names.includes("mod:widget"));
  assert.ok(names.includes("struct:Widget"));
  assert.ok(names.includes("enum:Color"));
  assert.ok(names.includes("trait:Drawable"));
  assert.ok(names.includes("impl:Drawable for Widget"));
  assert.ok(names.includes("impl:Widget"));
  assert.ok(names.includes("fn:make_widget"));
  assert.ok(names.includes("const:MAX"));
});

test("Rust: pub(crate) and async/unsafe modifiers don't break parsing", () => {
  const text = `pub(crate) fn helper() {}

pub async fn fetch() {}

pub unsafe fn dangerous() {}

pub(super) struct Internal;
`;
  const syms = extractSymbols(text, "rs");
  const names = syms.map((s) => `${s.kind}:${s.name}`);
  assert.ok(names.includes("fn:helper"));
  assert.ok(names.includes("fn:fetch"));
  assert.ok(names.includes("fn:dangerous"));
  assert.ok(names.includes("struct:Internal"));
});

test("dedup: same line not reported twice", () => {
  // `export const enum Color` would match both the enum and the (export const) const patterns
  const text = `export const enum Color { Red }\n`;
  const syms = extractSymbols(text, "ts");
  const colorEntries = syms.filter((s) => s.name === "Color");
  assert.equal(colorEntries.length, 1);
});

test("empty text returns no symbols", () => {
  assert.deepEqual(extractSymbols("", "ts"), []);
  assert.deepEqual(extractSymbols("\n\n\n", "py"), []);
});

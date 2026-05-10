import { test } from "node:test";
import assert from "node:assert/strict";
import {
  detectLanguage,
  extractGoReturnType,
  extractPythonReturnType,
  extractReturnType,
  extractRustReturnType,
  extractSignature,
  extractSymbols,
} from "../src/repomap/extract.ts";

test("detectLanguage maps common extensions", () => {
  assert.equal(detectLanguage("foo.ts"), "ts");
  assert.equal(detectLanguage("foo.tsx"), "ts");
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
  assert.equal(
    syms.find((s) => s.name === "frobnicate")?.signature,
    "a: number"
  );
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

test("extractSignature: simple TS function", () => {
  const text = "function foo(a, b) {}";
  const offset = "function foo".length;
  assert.equal(extractSignature(text, offset), "a, b");
});

test("extractSignature: typed multiline TS", () => {
  const text = `function foo(
  a: number,
  b: string
): void {}
`;
  const offset = "function foo".length;
  assert.equal(extractSignature(text, offset), "a: number, b: string");
});

test("extractSignature: nested parens (default value)", () => {
  const text = "function foo(a: number = (1 + 2)) {}";
  const offset = "function foo".length;
  assert.equal(extractSignature(text, offset), "a: number = (1 + 2)");
});

test("extractSignature: no args", () => {
  const text = "function foo() {}";
  const offset = "function foo".length;
  assert.equal(extractSignature(text, offset), "");
});

test("extractSignature: truncates over 80 chars", () => {
  const giantArg = "x".repeat(120);
  const text = `function foo(${giantArg}) {}`;
  const offset = "function foo".length;
  const sig = extractSignature(text, offset);
  assert.ok(sig !== null);
  assert.equal(sig!.length, 80);
  assert.equal(sig!.charAt(sig!.length - 1), "…");
});

test("extractSignature: returns null when no '(' within scan limit", () => {
  const text = "function foo" + "x".repeat(5000) + "(";
  const offset = "function foo".length;
  assert.equal(extractSignature(text, offset), null);
});

test("extractSymbols: Python def signature", () => {
  const text = "def foo(a, b):\n    pass\n";
  const syms = extractSymbols(text, "py");
  assert.equal(syms.find((s) => s.name === "foo")?.signature, "a, b");
});

test("extractSymbols: Go func signature ignores receiver", () => {
  const text = "func (u *User) Greet(name string) string {\n}\n";
  const syms = extractSymbols(text, "go");
  assert.equal(syms.find((s) => s.name === "Greet")?.signature, "name string");
});

test("extractSymbols: Rust fn signature", () => {
  const text = "pub fn foo(a: i32) -> i32 {}\n";
  const syms = extractSymbols(text, "rs");
  assert.equal(syms.find((s) => s.name === "foo")?.signature, "a: i32");
});

test("extractSymbols: non-function kinds get no signature", () => {
  const text = `export interface Foo {
  field: string;
}

export const SOME_CONST = 42;
`;
  const syms = extractSymbols(text, "ts");
  assert.equal(syms.find((s) => s.name === "Foo")?.signature, undefined);
  assert.equal(syms.find((s) => s.name === "SOME_CONST")?.signature, undefined);
});

test("extractReturnType: simple TS function", () => {
  const text = "function foo(): string {}";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "string");
});

test("extractReturnType: generic Promise", () => {
  const text = "function foo(a: number): Promise<void> {}";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "Promise<void>");
});

test("extractReturnType: arrow function type (=> handling)", () => {
  const text = "function foo(): (x: number) => string {}";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "(x: number) => string");
});

test("extractReturnType: type predicate", () => {
  const text = "function isFoo(x: any): x is Foo {}";
  const offset = "function isFoo".length;
  assert.equal(extractReturnType(text, offset), "x is Foo");
});

test("extractReturnType: asserts predicate", () => {
  const text = "function assertFoo(x: any): asserts x is Foo {}";
  const offset = "function assertFoo".length;
  assert.equal(extractReturnType(text, offset), "asserts x is Foo");
});

test("extractReturnType: ambient declaration (semicolon terminator)", () => {
  const text = "function foo(): string;";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "string");
});

test("extractReturnType: nested generic with object type inside", () => {
  const text = "function foo(): Promise<{ a: string }> {}";
  const offset = "function foo".length;
  assert.equal(
    extractReturnType(text, offset),
    "Promise<{ a: string }>"
  );
});

test("extractReturnType: tuple/array return", () => {
  const text = "function foo(): [string, number][] {}";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "[string, number][]");
});

test("extractReturnType: multiline return type", () => {
  const text = "function foo(\n  a: number\n): Promise<\n  string\n> {}";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "Promise< string >");
});

test("extractReturnType: no annotation returns null", () => {
  const text = "function foo() {}";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), null);
});

test("extractReturnType: leading whitespace before colon", () => {
  const text = "function foo()   :   number {}";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "number");
});

test("extractReturnType: truncates over MAX_RETURN_TYPE_CHARS", () => {
  const text = `function foo(): Record<string, ${"x".repeat(80)}> {}`;
  const offset = "function foo".length;
  const ret = extractReturnType(text, offset);
  assert.ok(ret !== null);
  assert.equal(ret!.length, 60);
  assert.equal(ret!.charAt(ret!.length - 1), "…");
});

test("extractReturnType: returns null when no '(' within scan limit", () => {
  const text = "function foo" + "x".repeat(5000) + "()";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), null);
});

test("extractReturnType: returns null on JS code (no annotation)", () => {
  const text = "function foo() { return 42; }";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), null);
});

test("extractSymbols: TS function gets returnType", () => {
  const text = "export function foo(a: number): Promise<string> {}";
  const syms = extractSymbols(text, "ts");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.signature, "a: number");
  assert.equal(foo?.returnType, "Promise<string>");
});

test("extractSymbols: TS function with no annotation has no returnType", () => {
  const text = "export function foo(a: number) {}";
  const syms = extractSymbols(text, "ts");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.signature, "a: number");
  assert.equal(foo?.returnType, undefined);
});

test("extractSymbols: JS function never gets returnType", () => {
  const text = "export function foo(a) { return a; }";
  const syms = extractSymbols(text, "js");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.signature, "a");
  assert.equal(foo?.returnType, undefined);
});

test("extractSymbols: non-function TS kinds have no returnType", () => {
  const text = "export interface Foo { x: string }\nexport const X = 1;";
  const syms = extractSymbols(text, "ts");
  assert.equal(syms.find((s) => s.name === "Foo")?.returnType, undefined);
  assert.equal(syms.find((s) => s.name === "X")?.returnType, undefined);
});

test("extractSymbols: typed multiline frobnicate gets return type", () => {
  const text = `export function frobnicate(a: number): number {
  return a + 1;
}
`;
  const syms = extractSymbols(text, "ts");
  const fn = syms.find((s) => s.name === "frobnicate");
  assert.equal(fn?.signature, "a: number");
  assert.equal(fn?.returnType, "number");
});

test("extractReturnType: inline object simple", () => {
  const text = "function foo(): { a: string } {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "{ a: string }");
});

test("extractReturnType: inline object empty", () => {
  const text = "function foo(): {} {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "{}");
});

test("extractReturnType: inline object nested", () => {
  const text = "function foo(): { a: { b: number } } {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "{ a: { b: number } }");
});

test("extractReturnType: intersection with inline object", () => {
  const text = "function foo(): Foo & { a: number } {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "Foo & { a: number }");
});

test("extractReturnType: union with inline object", () => {
  const text = "function foo(): string | { a: number } {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "string | { a: number }");
});

test("extractReturnType: inline object with method member", () => {
  const text = "function foo(): { foo(): void } {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "{ foo(): void }");
});

test("extractReturnType: inline object with semicolon separators", () => {
  const text = "function foo(): { a: number; b: string } {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "{ a: number; b: string }");
});

test("extractReturnType: inline object with arrow inside", () => {
  const text = "function foo(): { foo: () => string } {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "{ foo: () => string }");
});

test("extractReturnType: mapped type stays intact", () => {
  const text = "function foo(): { [K in keyof T]: T[K] } {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "{ [K in keyof T]: T[K] }");
});

test("extractReturnType: generic with inline object (regression)", () => {
  const text = "function foo(): Record<string, { a: number }> {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "Record<string, { a: number }>");
});

test("extractReturnType: plain string return (regression)", () => {
  const text = "function foo(): string {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "string");
});

test("extractReturnType: arrow type (regression)", () => {
  const text = "function foo(): () => string {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "() => string");
});

test("extractReturnType: tuple (regression)", () => {
  const text = "function foo(): [number, string] {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "[number, string]");
});

test("extractReturnType: union ending in identifier (regression)", () => {
  const text = "function foo(): number | undefined {";
  const offset = "function foo".length;
  assert.equal(extractReturnType(text, offset), "number | undefined");
});

test("extractReturnType: terminates at semicolon for inline object", () => {
  const text = "declare function foo(): { a: 1 };";
  const offset = "declare function foo".length;
  assert.equal(extractReturnType(text, offset), "{ a: 1 }");
});

test("extractReturnType: truncates over MAX_RETURN_TYPE_CHARS for inline object", () => {
  const text = `function foo(): { a: ${"x".repeat(80)} } {`;
  const offset = "function foo".length;
  const ret = extractReturnType(text, offset);
  assert.ok(ret !== null);
  assert.equal(ret!.length, 60);
  assert.equal(ret!.charAt(ret!.length - 1), "…");
});

test("extractSymbols: TS function with inline object return type", () => {
  const text = "export function foo(): { a: string } {\n}\n";
  const syms = extractSymbols(text, "ts");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.signature, "");
  assert.equal(foo?.returnType, "{ a: string }");
});

test("extractPythonReturnType: simple def", () => {
  const text = "def foo() -> int:";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), "int");
});

test("extractPythonReturnType: Optional generic", () => {
  const text = "def foo() -> Optional[int]:";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), "Optional[int]");
});

test("extractPythonReturnType: nested generic Dict[str, List[int]]", () => {
  const text = "def foo() -> Dict[str, List[int]]:";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), "Dict[str, List[int]]");
});

test("extractPythonReturnType: Callable with nested square brackets", () => {
  const text = "def foo() -> Callable[[int], str]:";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), "Callable[[int], str]");
});

test("extractPythonReturnType: PEP 604 union", () => {
  const text = "def foo() -> int | None:";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), "int | None");
});

test("extractPythonReturnType: paren-wrapped multiline return type", () => {
  const text = "def foo() -> (\n  Optional[int]\n):";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), "( Optional[int] )");
});

test("extractPythonReturnType: multiline arg list then -> on next line", () => {
  const text = "def foo(\n  a: int,\n) -> int:";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), "int");
});

test("extractPythonReturnType: forward reference (quoted)", () => {
  const text = "def foo() -> \"Foo\":";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), "\"Foo\"");
});

test("extractPythonReturnType: no annotation returns null", () => {
  const text = "def foo():";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), null);
});

test("extractPythonReturnType: empty annotation returns null", () => {
  const text = "def foo() ->:";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), null);
});

test("extractPythonReturnType: leading whitespace before arrow", () => {
  const text = "def foo()   ->   int:";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), "int");
});

test("extractPythonReturnType: truncates over MAX_RETURN_TYPE_CHARS", () => {
  const text = `def foo() -> Dict[str, ${"x".repeat(80)}]:`;
  const offset = "def foo".length;
  const ret = extractPythonReturnType(text, offset);
  assert.ok(ret !== null);
  assert.equal(ret!.length, 60);
  assert.equal(ret!.charAt(ret!.length - 1), "…");
});

test("extractPythonReturnType: returns null when no '(' within scan limit", () => {
  const text = "def foo" + "x".repeat(5000) + "() -> int:";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), null);
});

test("extractPythonReturnType: returns null when arrow missing (just colon)", () => {
  const text = "def foo() : int";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), null);
});

test("extractPythonReturnType: terminates at newline if no colon", () => {
  const text = "def foo() -> int\nrest_of_line";
  const offset = "def foo".length;
  assert.equal(extractPythonReturnType(text, offset), "int");
});

test("extractSymbols: Python def gets returnType", () => {
  const text = "def foo(a: int, b: str) -> Optional[int]:\n    pass\n";
  const syms = extractSymbols(text, "py");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.signature, "a: int, b: str");
  assert.equal(foo?.returnType, "Optional[int]");
});

test("extractSymbols: Python async def gets returnType", () => {
  const text = "async def foo() -> Awaitable[int]:\n    pass\n";
  const syms = extractSymbols(text, "py");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.returnType, "Awaitable[int]");
});

test("extractSymbols: Python def with no annotation has no returnType", () => {
  const text = "def foo(a):\n    pass\n";
  const syms = extractSymbols(text, "py");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.signature, "a");
  assert.equal(foo?.returnType, undefined);
});

test("extractSymbols: Python class has no returnType", () => {
  const text = "class Foo:\n    pass\n";
  const syms = extractSymbols(text, "py");
  const foo = syms.find((s) => s.name === "Foo");
  assert.equal(foo?.returnType, undefined);
});

test("extractRustReturnType: simple fn -> i32", () => {
  const text = "fn foo() -> i32 {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "i32");
});

test("extractRustReturnType: Result<T, E>", () => {
  const text = "fn foo() -> Result<T, E> {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "Result<T, E>");
});

test("extractRustReturnType: nested generics with no space (>>)", () => {
  const text = "fn foo() -> Vec<Box<dyn Trait>> {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "Vec<Box<dyn Trait>>");
});

test("extractRustReturnType: lifetime ref &'a mut T", () => {
  const text = "fn foo() -> &'a mut T {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "&'a mut T");
});

test("extractRustReturnType: tuple (T, U)", () => {
  const text = "fn foo() -> (T, U) {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "(T, U)");
});

test("extractRustReturnType: array [T; N] does not terminate on inner ;", () => {
  const text = "fn foo() -> [T; N] {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "[T; N]");
});

test("extractRustReturnType: impl Fn(i32) -> i32 (inner arrow doesn't underflow)", () => {
  const text = "fn foo() -> impl Fn(i32) -> i32 {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "impl Fn(i32) -> i32");
});

test("extractRustReturnType: where clause termination", () => {
  const text = "fn foo() -> T where T: Clone {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "T");
});

test("extractRustReturnType: where keyword inside identifier does not terminate", () => {
  const text = "fn foo() -> Twhereunto {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "Twhereunto");
});

test("extractRustReturnType: trait method semicolon terminator", () => {
  const text = "fn foo() -> T;";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "T");
});

test("extractRustReturnType: no annotation returns null", () => {
  const text = "fn foo() {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), null);
});

test("extractRustReturnType: empty annotation returns null", () => {
  const text = "fn foo() -> {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), null);
});

test("extractRustReturnType: leading whitespace before arrow", () => {
  const text = "fn foo()   ->   i32 {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "i32");
});

test("extractRustReturnType: multiline arg list then -> on next line", () => {
  const text = "fn foo(\n  a: i32,\n) -> i32 {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "i32");
});

test("extractRustReturnType: terminates at newline if no { or ;", () => {
  const text = "fn foo() -> i32\nrest_of_line";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), "i32");
});

test("extractRustReturnType: truncates over MAX_RETURN_TYPE_CHARS", () => {
  const text = `fn foo() -> Vec<${"x".repeat(80)}> {`;
  const offset = "fn foo".length;
  const ret = extractRustReturnType(text, offset);
  assert.ok(ret !== null);
  assert.equal(ret!.length, 60);
  assert.equal(ret!.charAt(ret!.length - 1), "…");
});

test("extractRustReturnType: returns null when no '(' within scan limit", () => {
  const text = "fn foo" + "x".repeat(5000) + "() -> i32 {";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), null);
});

test("extractRustReturnType: returns null when arrow missing", () => {
  const text = "fn foo() : i32";
  const offset = "fn foo".length;
  assert.equal(extractRustReturnType(text, offset), null);
});

test("extractSymbols: Rust fn gets returnType", () => {
  const text = "fn foo(a: i32) -> Result<i32, Error> {\n}\n";
  const syms = extractSymbols(text, "rs");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.signature, "a: i32");
  assert.equal(foo?.returnType, "Result<i32, Error>");
});

test("extractSymbols: Rust async fn gets returnType", () => {
  const text = "async fn foo() -> i32 {\n}\n";
  const syms = extractSymbols(text, "rs");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.returnType, "i32");
});

test("extractSymbols: Rust pub fn gets returnType", () => {
  const text = "pub fn foo() -> Box<dyn Trait> {\n}\n";
  const syms = extractSymbols(text, "rs");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.returnType, "Box<dyn Trait>");
});

test("extractSymbols: Rust fn with no annotation has no returnType", () => {
  const text = "fn foo(a: i32) {\n}\n";
  const syms = extractSymbols(text, "rs");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.signature, "a: i32");
  assert.equal(foo?.returnType, undefined);
});

test("extractSymbols: Rust struct has no returnType", () => {
  const text = "struct Foo { x: i32 }\n";
  const syms = extractSymbols(text, "rs");
  const foo = syms.find((s) => s.name === "Foo");
  assert.equal(foo?.returnType, undefined);
});

test("extractGoReturnType: simple func -> int", () => {
  const text = "func foo() int {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "int");
});

test("extractGoReturnType: pointer return *User", () => {
  const text = "func foo() *User {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "*User");
});

test("extractGoReturnType: slice []byte", () => {
  const text = "func foo() []byte {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "[]byte");
});

test("extractGoReturnType: map[string]int", () => {
  const text = "func foo() map[string]int {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "map[string]int");
});

test("extractGoReturnType: nested map of slices map[string][]int", () => {
  const text = "func foo() map[string][]int {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "map[string][]int");
});

test("extractGoReturnType: chan int", () => {
  const text = "func foo() chan int {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "chan int");
});

test("extractGoReturnType: send-only chan<- int", () => {
  const text = "func foo() chan<- int {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "chan<- int");
});

test("extractGoReturnType: receive-only <-chan int", () => {
  const text = "func foo() <-chan int {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "<-chan int");
});

test("extractGoReturnType: array [3]int", () => {
  const text = "func foo() [3]int {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "[3]int");
});

test("extractGoReturnType: function-typed return func(int) string", () => {
  const text = "func foo() func(int) string {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "func(int) string");
});

test("extractGoReturnType: nested function type func() func() int", () => {
  const text = "func foo() func() func() int {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "func() func() int");
});

test("extractGoReturnType: multi-return (int, error)", () => {
  const text = "func foo() (int, error) {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "(int, error)");
});

test("extractGoReturnType: named returns (a int, b error)", () => {
  const text = "func foo() (a int, b error) {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "(a int, b error)");
});

test("extractGoReturnType: shorthand multi-name (a, b int)", () => {
  const text = "func foo() (a, b int) {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "(a, b int)");
});

test("extractGoReturnType: no return type returns null", () => {
  const text = "func foo() {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), null);
});

test("extractGoReturnType: terminates at newline", () => {
  const text = "func foo() int\nrest_of_line";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "int");
});

test("extractGoReturnType: multiline arg list then return type", () => {
  const text = "func foo(\n  a int,\n) (int, error) {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "(int, error)");
});

test("extractGoReturnType: leading whitespace before type", () => {
  const text = "func foo()   int   {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "int");
});

test("extractGoReturnType: anonymous interface yields keyword only (acceptable loss)", () => {
  const text = "func foo() interface{} {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "interface");
});

test("extractGoReturnType: any alias works", () => {
  const text = "func foo() any {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "any");
});

test("extractGoReturnType: error type", () => {
  const text = "func foo() error {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), "error");
});

test("extractGoReturnType: truncates over MAX_RETURN_TYPE_CHARS", () => {
  const text = `func foo() map[string]${"x".repeat(80)} {`;
  const offset = "func foo".length;
  const ret = extractGoReturnType(text, offset);
  assert.ok(ret !== null);
  assert.equal(ret!.length, 60);
  assert.equal(ret!.charAt(ret!.length - 1), "…");
});

test("extractGoReturnType: returns null when no '(' within scan limit", () => {
  const text = "func foo" + "x".repeat(5000) + "() int {";
  const offset = "func foo".length;
  assert.equal(extractGoReturnType(text, offset), null);
});

test("extractSymbols: Go func gets returnType", () => {
  const text = "func foo(a int) (int, error) {\n}\n";
  const syms = extractSymbols(text, "go");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.signature, "a int");
  assert.equal(foo?.returnType, "(int, error)");
});

test("extractSymbols: Go method (with receiver) gets returnType", () => {
  const text = "func (r *R) foo() int {\n}\n";
  const syms = extractSymbols(text, "go");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.returnType, "int");
});

test("extractSymbols: Go func with no return type has no returnType", () => {
  const text = "func foo(a int) {\n}\n";
  const syms = extractSymbols(text, "go");
  const foo = syms.find((s) => s.name === "foo");
  assert.equal(foo?.signature, "a int");
  assert.equal(foo?.returnType, undefined);
});

test("extractSymbols: Go type decl has no returnType", () => {
  const text = "type Foo int\n";
  const syms = extractSymbols(text, "go");
  const foo = syms.find((s) => s.name === "Foo");
  assert.equal(foo?.returnType, undefined);
});

test("Markdown: extracts h1, h2, h3 with line numbers", () => {
  const text = `# Compass

Some intro text.

## Installation

Run \`npm install\`.

### Prerequisites

Node 22+.

## Usage
`;
  const syms = extractSymbols(text, "md");
  const compass = syms.find((s) => s.name === "Compass");
  assert.equal(compass?.kind, "h1");
  assert.equal(compass?.line, 1);
  const install = syms.find((s) => s.name === "Installation");
  assert.equal(install?.kind, "h2");
  assert.equal(install?.line, 5);
  const prereq = syms.find((s) => s.name === "Prerequisites");
  assert.equal(prereq?.kind, "h3");
  assert.equal(prereq?.line, 9);
  const usage = syms.find((s) => s.name === "Usage");
  assert.equal(usage?.kind, "h2");
  assert.equal(usage?.line, 13);
});

test("Markdown: ignores h4 and deeper", () => {
  assert.deepEqual(extractSymbols("#### too deep\n##### deeper\n", "md"), []);
});

test("Markdown: heading without space after # is not a heading", () => {
  const syms = extractSymbols("#nospace\n## valid\n", "md");
  assert.equal(syms.length, 1);
  assert.equal(syms[0].kind, "h2");
  assert.equal(syms[0].name, "valid");
});

test("Markdown: trailing whitespace and inline formatting preserved", () => {
  const syms = extractSymbols("## Hello **world**   \n", "md");
  assert.equal(syms.length, 1);
  assert.equal(syms[0].kind, "h2");
  assert.equal(syms[0].name, "Hello **world**");
});

test("Markdown: heading symbols have no signature", () => {
  const syms = extractSymbols("# Title\n## Sub\n", "md");
  for (const s of syms) {
    assert.equal(s.signature, undefined);
  }
});

test("Markdown: empty file returns no symbols", () => {
  assert.deepEqual(extractSymbols("", "md"), []);
});

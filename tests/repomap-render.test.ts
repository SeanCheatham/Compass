import { test } from "node:test";
import assert from "node:assert/strict";

import { renderRepoIndex, renderRepoMap } from "../src/repomap/render.ts";
import type { FileEntry, Symbol } from "../src/repomap/cache.ts";

function sym(name: string, line: number, extra: Partial<Symbol> = {}): Symbol {
  return { kind: "function", name, line, ...extra };
}

function entry(
  symbols: Symbol[],
  language: FileEntry["language"] = "ts",
  extra: Partial<FileEntry> = {}
): FileEntry {
  return {
    contentHash: "x",
    mtime: 0,
    size: 0,
    language,
    symbols,
    imports: [],
    ...extra,
  };
}

test("renderRepoMap: empty files map returns no-source-files fallback", () => {
  assert.equal(renderRepoMap({}), "_(no source files indexed yet)_");
});

test("renderRepoMap: all files have empty symbols returns no-top-level-symbols fallback", () => {
  const out = renderRepoMap({
    "a.ts": entry([]),
    "b.ts": entry([]),
  });
  assert.equal(out, "_(no top-level symbols found)_");
});

test("renderRepoMap: single file with single symbol and no signature/returnType", () => {
  const out = renderRepoMap({
    "src/foo.ts": entry([sym("foo", 1)]),
  });
  assert.equal(out, "src/foo.ts:\n  function foo (L1)");
});

test("renderRepoMap: symbol with signature only renders parens around signature", () => {
  const out = renderRepoMap({
    "f.ts": entry([sym("foo", 5, { signature: "x: number" })]),
  });
  assert.equal(out, "f.ts:\n  function foo(x: number) (L5)");
});

test("renderRepoMap: symbol with returnType only renders bare colon-type (no parens)", () => {
  const out = renderRepoMap({
    "f.ts": entry([sym("foo", 5, { returnType: "string" })]),
  });
  assert.equal(out, "f.ts:\n  function foo: string (L5)");
});

test("renderRepoMap: symbol with both signature and returnType concatenates them", () => {
  const out = renderRepoMap({
    "f.ts": entry([
      sym("foo", 5, { signature: "x: number", returnType: "string" }),
    ]),
  });
  assert.equal(out, "f.ts:\n  function foo(x: number): string (L5)");
});

test("renderRepoMap: empty-string signature renders empty parens (distinct from undefined)", () => {
  // Renderer uses `signature !== undefined`, so "" produces `()` while
  // undefined produces a bare name with no parens — these are intentionally
  // distinct cases per the lessons.md note on the renderer.
  const out = renderRepoMap({
    "f.ts": entry([sym("foo", 1, { signature: "" })]),
  });
  assert.equal(out, "f.ts:\n  function foo() (L1)");
});

test("renderRepoMap: empty-string returnType renders bare colon-space (distinct from undefined)", () => {
  // retPart = `: ${""}` = ": " — that's followed by ` (L1)`, so the literal
  // output has TWO spaces between the colon and `(L1)`. Looks ugly but is
  // the documented behaviour; pin it as-is rather than fix inline.
  const out = renderRepoMap({
    "f.ts": entry([sym("foo", 1, { returnType: "" })]),
  });
  assert.equal(out, "f.ts:\n  function foo:  (L1)");
});

test("renderRepoMap: multiple files render in alphabetical order regardless of input order", () => {
  const out = renderRepoMap({
    "z.ts": entry([sym("z", 1)]),
    "a.ts": entry([sym("a", 1)]),
  });
  assert.equal(
    out,
    "a.ts:\n  function a (L1)\nz.ts:\n  function z (L1)"
  );
});

test("renderRepoMap: multiple symbols within a file preserve input order (NOT line order)", () => {
  // Renderer iterates entry.symbols directly without re-sorting. If a future
  // iteration wants line-sorted output within a file, this test will fail and
  // make the change deliberate.
  const out = renderRepoMap({
    "f.ts": entry([sym("second", 5), sym("first", 1)]),
  });
  assert.equal(
    out,
    "f.ts:\n  function second (L5)\n  function first (L1)"
  );
});

test("renderRepoMap: empty-symbol files are skipped silently between non-empty files", () => {
  // b.ts has no symbols, so it never appears in the output. Confirms the
  // `if (entry.symbols.length === 0) continue` skip and indirectly that
  // empty-symbol files do not increment `included`.
  const out = renderRepoMap({
    "a.ts": entry([sym("a", 1)]),
    "b.ts": entry([]),
    "c.ts": entry([sym("c", 1)]),
  });
  assert.equal(
    out,
    "a.ts:\n  function a (L1)\nc.ts:\n  function c (L1)"
  );
});

test("renderRepoMap: budget overflow drops later files and uses plural form", () => {
  // Each block is "X.ts:\n  function foo (L1)" = 25 chars. With maxChars
  // sized to fit exactly the first block + its trailing newline accounting
  // (used += block.length + 1), the second iteration trips the cutoff.
  const block = "a.ts:\n  function foo (L1)";
  assert.equal(block.length, 25, "block length sanity check");
  const out = renderRepoMap(
    {
      "a.ts": entry([sym("foo", 1)]),
      "b.ts": entry([sym("foo", 1)]),
      "c.ts": entry([sym("foo", 1)]),
    },
    { maxChars: block.length + 1 }
  );
  assert.equal(
    out,
    "a.ts:\n  function foo (L1)\n(2 more files omitted)"
  );
});

test("renderRepoMap: budget overflow with exactly 1 omitted uses singular form", () => {
  // Two files, budget admits only the first. Pins the
  // `omitted === 1 ? "" : "s"` ternary.
  const block = "a.ts:\n  function foo (L1)";
  const out = renderRepoMap(
    {
      "a.ts": entry([sym("foo", 1)]),
      "b.ts": entry([sym("foo", 1)]),
    },
    { maxChars: block.length + 1 }
  );
  assert.equal(
    out,
    "a.ts:\n  function foo (L1)\n(1 more file omitted)"
  );
});

test("renderRepoMap: extremely tight budget still admits the first file (cutoff requires included > 0)", () => {
  // The cutoff guard `if (used + block.length + 1 > max && included > 0)`
  // requires `included > 0`, so the first file is admitted regardless of how
  // tight maxChars is. As a side effect, the `blocks.length === 0` final
  // fallback is unreachable via budget overflow alone — only no-symbols
  // anywhere (covered by the second test in this file) ever fires it.
  // NOTE: the original plan claimed this case should fall through to
  // `_(no top-level symbols found)_`. That's a misread of the renderer; this
  // test pins the actual behaviour so a future intentional change is
  // deliberate.
  const out = renderRepoMap(
    { "a.ts": entry([sym("foo", 1)]) },
    { maxChars: 1 }
  );
  assert.equal(out, "a.ts:\n  function foo (L1)");
});

// ---------- renderRepoIndex (slim, summary-aware)

test("renderRepoIndex: empty input returns no-files fallback", () => {
  assert.equal(renderRepoIndex({}), "_(no source files indexed yet)_");
});

test("renderRepoIndex: one file with summary renders path + symbol count + summary", () => {
  const out = renderRepoIndex({
    "src/foo.ts": entry([sym("foo", 1)], "ts", {
      summary: "Frobnicates the widget.",
    }),
  });
  assert.equal(out, "src/foo.ts  (ts, 1 symbol)\n  Frobnicates the widget.");
});

test("renderRepoIndex: file without summary still gets a header line", () => {
  const out = renderRepoIndex({
    "src/foo.ts": entry([sym("foo", 1), sym("bar", 2)]),
  });
  assert.equal(out, "src/foo.ts  (ts, 2 symbols)");
});

test("renderRepoIndex: long summaries are truncated with an ellipsis", () => {
  const long = "x".repeat(500);
  const out = renderRepoIndex({
    "f.ts": entry([sym("a", 1)], "ts", { summary: long }),
  });
  // Summary trailing line should fit under 240 chars and end with …
  const summaryLine = out.split("\n")[1]!;
  assert.ok(summaryLine.endsWith("…"));
  assert.ok(summaryLine.length <= 2 + 240); // "  " + capped summary
});

test("renderRepoIndex: budget overflow drops later files with omitted count", () => {
  const out = renderRepoIndex(
    {
      "a.ts": entry([sym("a", 1)]),
      "b.ts": entry([sym("b", 1)]),
      "c.ts": entry([sym("c", 1)]),
    },
    { maxChars: 30 }
  );
  // First file fits; subsequent ones overflow.
  assert.match(out, /a\.ts\s+\(ts, 1 symbol\)/);
  assert.match(out, /\(2 more files omitted\)/);
});

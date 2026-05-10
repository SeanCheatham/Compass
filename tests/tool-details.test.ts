import { test } from "node:test";
import assert from "node:assert/strict";

import { extractToolDetail } from "../src/agents/tool-details.ts";

// --- Bash -------------------------------------------------------------------

test("Bash with command only: summary is the command, full has only command key", () => {
  const out = extractToolDetail("Bash", { command: "ls -la" });
  assert.deepEqual(out, {
    summary: "ls -la",
    full: { command: "ls -la" },
  });
});

test("Bash with command + description + timeout: all three present, timeout stringified with ms suffix", () => {
  const out = extractToolDetail("Bash", {
    command: "npm test",
    description: "Run unit tests",
    timeout: 5000,
  });
  assert.deepEqual(out, {
    summary: "npm test",
    full: {
      command: "npm test",
      description: "Run unit tests",
      timeout: "5000ms",
    },
  });
});

test("Bash without command returns undefined", () => {
  assert.equal(extractToolDetail("Bash", {}), undefined);
});

test("Bash long command: summary truncated to 60 chars + '...' (63 total), full preserves original", () => {
  const cmd = "x".repeat(100);
  const out = extractToolDetail("Bash", { command: cmd });
  assert.ok(out);
  assert.equal(out.summary.length, 63);
  assert.ok(out.summary.endsWith("..."));
  assert.equal(out.summary.slice(0, 60), "x".repeat(60));
  assert.equal(out.full.command, cmd);
  assert.equal(out.full.command.length, 100);
});

// --- Read -------------------------------------------------------------------

test("Read with short file_path: shortenPath untouched (≤3 segments)", () => {
  const out = extractToolDetail("Read", { file_path: "foo.ts" });
  assert.deepEqual(out, {
    summary: "foo.ts",
    full: { file: "foo.ts" },
  });
});

test("Read with long file_path + offset + limit: summary shortened, full preserves untruncated path", () => {
  const fp = "src/foo/bar/baz/quux.ts"; // 5 segments
  const out = extractToolDetail("Read", { file_path: fp, offset: 100, limit: 50 });
  assert.ok(out);
  assert.equal(out.summary, ".../bar/baz/quux.ts");
  assert.equal(out.full.file, fp);
  assert.equal(out.full.offset, "line 100");
  assert.equal(out.full.limit, "50 lines");
});

test("Read without file_path returns undefined", () => {
  assert.equal(extractToolDetail("Read", {}), undefined);
});

// --- Write ------------------------------------------------------------------

test("Write with file_path: full has only file key", () => {
  const out = extractToolDetail("Write", { file_path: "a/b/c.ts" });
  assert.deepEqual(out, {
    summary: "a/b/c.ts", // 3 segments → not shortened
    full: { file: "a/b/c.ts" },
  });
});

test("Write without file_path returns undefined", () => {
  assert.equal(extractToolDetail("Write", {}), undefined);
});

// --- Edit -------------------------------------------------------------------

test("Edit with file_path only: full has only file key (no replacing/replace_all)", () => {
  const out = extractToolDetail("Edit", { file_path: "x.ts" });
  assert.deepEqual(out, {
    summary: "x.ts",
    full: { file: "x.ts" },
  });
});

test("Edit with old_string > 120 chars: full.replacing truncated to 120 + '...' (123 total)", () => {
  const old = "y".repeat(200);
  const out = extractToolDetail("Edit", { file_path: "x.ts", old_string: old });
  assert.ok(out);
  assert.equal(out.full.replacing.length, 123);
  assert.ok(out.full.replacing.endsWith("..."));
  assert.equal(out.full.replacing.slice(0, 120), "y".repeat(120));
});

test("Edit with replace_all === true: full.replace_all is the string 'true' (not boolean)", () => {
  const out = extractToolDetail("Edit", {
    file_path: "x.ts",
    old_string: "a",
    replace_all: true,
  });
  assert.ok(out);
  assert.equal(out.full.replace_all, "true");
  assert.equal(typeof out.full.replace_all, "string");
});

// --- Glob -------------------------------------------------------------------

test("Glob with pattern + path: both keys present in full", () => {
  const out = extractToolDetail("Glob", { pattern: "**/*.ts", path: "src" });
  assert.deepEqual(out, {
    summary: "**/*.ts",
    full: { pattern: "**/*.ts", path: "src" },
  });
});

test("Glob without pattern returns undefined", () => {
  assert.equal(extractToolDetail("Glob", { path: "src" }), undefined);
});

// --- Grep -------------------------------------------------------------------

test("Grep with pattern + path + glob + output_mode: all four present, output_mode renamed to mode", () => {
  const out = extractToolDetail("Grep", {
    pattern: "TODO",
    path: "src",
    glob: "*.ts",
    output_mode: "content",
  });
  assert.deepEqual(out, {
    summary: "TODO",
    full: {
      pattern: "TODO",
      path: "src",
      glob: "*.ts",
      mode: "content",
    },
  });
});

test("Grep with pattern only: full has only pattern (truthy-spread drops missing/empty optional fields)", () => {
  // Truthy-spread idiom in extractToolDetail means empty-string and 0 optional
  // fields are silently dropped from full — pinning that behaviour here.
  const out = extractToolDetail("Grep", { pattern: "foo", path: "", glob: "" });
  assert.deepEqual(out, {
    summary: "foo",
    full: { pattern: "foo" },
  });
});

test("Grep without pattern returns undefined", () => {
  assert.equal(extractToolDetail("Grep", { path: "src" }), undefined);
});

// --- LS ---------------------------------------------------------------------

test("LS with path: full.path matches input", () => {
  const out = extractToolDetail("LS", { path: "src/agents" });
  assert.deepEqual(out, {
    summary: "src/agents",
    full: { path: "src/agents" },
  });
});

test("LS without path: defaults to '.' in both summary and full", () => {
  const out = extractToolDetail("LS", {});
  assert.deepEqual(out, {
    summary: ".",
    full: { path: "." },
  });
});

// --- Agent ------------------------------------------------------------------

test("Agent with description + subagent_type: both present, subagent_type renamed to type", () => {
  const out = extractToolDetail("Agent", {
    description: "Find all TODOs",
    subagent_type: "general-purpose",
  });
  assert.deepEqual(out, {
    summary: "Find all TODOs",
    full: { description: "Find all TODOs", type: "general-purpose" },
  });
});

test("Agent without description returns undefined", () => {
  assert.equal(extractToolDetail("Agent", { subagent_type: "general-purpose" }), undefined);
});

// --- WebFetch / WebSearch ---------------------------------------------------

test("WebFetch with long url: summary truncated to 60+'...', full.url preserved", () => {
  const url = "https://example.com/" + "a".repeat(100);
  const out = extractToolDetail("WebFetch", { url });
  assert.ok(out);
  assert.equal(out.summary.length, 63);
  assert.ok(out.summary.endsWith("..."));
  assert.equal(out.full.url, url);
});

test("WebFetch without url returns undefined", () => {
  assert.equal(extractToolDetail("WebFetch", {}), undefined);
});

test("WebSearch with query: summary equals query (short), full has only query", () => {
  const out = extractToolDetail("WebSearch", { query: "claude agent sdk" });
  assert.deepEqual(out, {
    summary: "claude agent sdk",
    full: { query: "claude agent sdk" },
  });
});

test("WebSearch without query returns undefined", () => {
  assert.equal(extractToolDetail("WebSearch", {}), undefined);
});

// --- MCP fallback -----------------------------------------------------------

test("MCP tool with mixed value types: nested object dropped, number/boolean stringified", () => {
  const out = extractToolDetail("mcp__compass__set_state", {
    key1: "val1",
    key2: 42,
    key3: true,
    key4: { nested: "obj" },
  });
  assert.ok(out);
  assert.equal(out.summary, "set_state: val1");
  assert.deepEqual(out.full, {
    key1: "val1",
    key2: "42",
    key3: "true",
  });
  assert.equal(Object.keys(out.full).length, 3);
});

test("MCP tool with no string/number/boolean values: full is {} and summary is just short name", () => {
  const out = extractToolDetail("mcp__compass__do_thing", {
    nested: { a: 1 },
    arr: [1, 2, 3],
  });
  assert.ok(out);
  assert.deepEqual(out.full, {});
  assert.equal(out.summary, "do_thing");
});

test("MCP tool short-name extraction takes last segment after split on '__'", () => {
  const out = extractToolDetail("mcp__a__b__c__d", { x: "hello" });
  assert.ok(out);
  assert.equal(out.summary, "d: hello");
});

// --- Default / unknown ------------------------------------------------------

test("Unknown non-mcp tool name returns undefined", () => {
  assert.equal(extractToolDetail("NotARealTool", { x: 1 }), undefined);
});

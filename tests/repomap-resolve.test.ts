import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveImport } from "../src/repomap/resolve.ts";

const files = new Set([
  "src/foo.ts",
  "src/bar.tsx",
  "src/utils/index.ts",
  "src/utils/helper.ts",
  "scripts/run.mjs",
  "pkg/__init__.py",
  "pkg/sub/__init__.py",
  "pkg/sub/mod.py",
  "pkg/sibling.py",
  "main.go",
]);

test("TS: relative `.js` import resolves to `.ts` on disk (NodeNext convention)", () => {
  assert.equal(
    resolveImport("src/foo.ts", "./utils/helper.js", files, "ts"),
    "src/utils/helper.ts"
  );
});

test("TS: relative import to directory resolves via /index.ts", () => {
  assert.equal(
    resolveImport("src/foo.ts", "./utils", files, "ts"),
    "src/utils/index.ts"
  );
});

test("TS: relative import already pointing at .ts resolves directly", () => {
  assert.equal(
    resolveImport("src/foo.ts", "./utils/helper.ts", files, "ts"),
    "src/utils/helper.ts"
  );
});

test("TS: .tsx file is resolvable via `.js` swap", () => {
  assert.equal(
    resolveImport("src/foo.ts", "./bar.js", files, "ts"),
    "src/bar.tsx"
  );
});

test("TS: parent-relative import resolves up the tree", () => {
  assert.equal(
    resolveImport("src/utils/helper.ts", "../foo.js", files, "ts"),
    "src/foo.ts"
  );
});

test("TS: bare package specifiers stay unresolved", () => {
  assert.equal(resolveImport("src/foo.ts", "zod", files, "ts"), null);
  assert.equal(
    resolveImport("src/foo.ts", "@anthropic-ai/claude-agent-sdk", files, "ts"),
    null
  );
  assert.equal(resolveImport("src/foo.ts", "node:path", files, "ts"), null);
});

test("TS: relative to a non-existent target stays null", () => {
  assert.equal(
    resolveImport("src/foo.ts", "./missing.js", files, "ts"),
    null
  );
});

test("PY: single-dot relative resolves within current package", () => {
  assert.equal(
    resolveImport("pkg/sub/mod.py", ".sibling", new Set([...files, "pkg/sub/sibling.py"]), "py"),
    "pkg/sub/sibling.py"
  );
});

test("PY: double-dot relative climbs one package up", () => {
  assert.equal(
    resolveImport("pkg/sub/mod.py", "..sibling", files, "py"),
    "pkg/sibling.py"
  );
});

test("PY: relative pointing at a package resolves to __init__.py", () => {
  assert.equal(
    resolveImport("pkg/sub/mod.py", "..sub", files, "py"),
    "pkg/sub/__init__.py"
  );
});

test("PY: absolute imports stay unresolved (no package-root lookup)", () => {
  assert.equal(resolveImport("pkg/sub/mod.py", "typing", files, "py"), null);
});

test("Go: imports stay unresolved (would need go.mod parsing)", () => {
  assert.equal(resolveImport("main.go", "fmt", files, "go"), null);
});

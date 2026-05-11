import { test } from "node:test";
import assert from "node:assert/strict";
import { buildImporterIndex } from "../src/repomap/graph.ts";
import {
  CACHE_VERSION,
  type FileEntry,
  type RepoMapCache,
} from "../src/repomap/cache.ts";

function entry(imports: Array<{ raw: string; resolved: string | null }>): FileEntry {
  return {
    contentHash: "x",
    mtime: 1,
    size: 1,
    language: "ts",
    symbols: [],
    imports: imports.map((i, idx) => ({ ...i, line: idx + 1 })),
  };
}

test("buildImporterIndex: groups resolved imports into reverse adjacency", () => {
  const cache: RepoMapCache = {
    version: CACHE_VERSION,
    files: {
      "src/a.ts": entry([{ raw: "./b.js", resolved: "src/b.ts" }]),
      "src/b.ts": entry([]),
      "src/c.ts": entry([
        { raw: "./b.js", resolved: "src/b.ts" },
        { raw: "zod", resolved: null },
      ]),
    },
  };
  const idx = buildImporterIndex(cache);
  assert.deepEqual(idx.get("src/b.ts"), ["src/a.ts", "src/c.ts"]);
  assert.equal(idx.get("src/a.ts"), undefined);
});

test("buildImporterIndex: ignores unresolved imports entirely", () => {
  const cache: RepoMapCache = {
    version: CACHE_VERSION,
    files: {
      "src/a.ts": entry([{ raw: "zod", resolved: null }]),
    },
  };
  const idx = buildImporterIndex(cache);
  assert.equal(idx.size, 0);
});

test("buildImporterIndex: importer lists are sorted for determinism", () => {
  const cache: RepoMapCache = {
    version: CACHE_VERSION,
    files: {
      "src/z.ts": entry([{ raw: "./shared.js", resolved: "src/shared.ts" }]),
      "src/a.ts": entry([{ raw: "./shared.js", resolved: "src/shared.ts" }]),
      "src/m.ts": entry([{ raw: "./shared.js", resolved: "src/shared.ts" }]),
      "src/shared.ts": entry([]),
    },
  };
  const idx = buildImporterIndex(cache);
  assert.deepEqual(idx.get("src/shared.ts"), [
    "src/a.ts",
    "src/m.ts",
    "src/z.ts",
  ]);
});

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  CACHE_VERSION,
  hashContent,
  isStatFresh,
  readRepoMapCache,
  repoMapCachePath,
  writeRepoMapCache,
  type FileEntry,
} from "../src/repomap/cache.ts";
import { getWorkspaceConfig } from "../src/mcp/utils/workspace.ts";

async function tmpWorkspace() {
  const dir = await mkdtemp(join(tmpdir(), "compass-repomap-test-"));
  const config = getWorkspaceConfig(dir);
  await mkdir(config.workspacePath, { recursive: true });
  return {
    dir,
    config,
    cleanup: () => rm(dir, { recursive: true, force: true }),
  };
}

const sampleEntry: FileEntry = {
  contentHash: "deadbeef",
  mtime: 100,
  size: 200,
  language: "ts",
  symbols: [
    {
      kind: "function",
      name: "foo",
      line: 1,
      signature: "a: number",
      returnType: "void",
      exported: true,
    },
  ],
  imports: [{ raw: "./bar.js", resolved: "src/bar.ts", line: 2 }],
};

test("readRepoMapCache: missing file returns empty cache", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: CACHE_VERSION, files: {} });
  } finally {
    await cleanup();
  }
});

test("write then read round-trips with imports and members", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    const original = {
      version: CACHE_VERSION,
      files: {
        "src/foo.ts": sampleEntry,
        "src/bar.ts": {
          contentHash: "feedface",
          mtime: 200,
          size: 400,
          language: "ts" as const,
          symbols: [
            {
              kind: "class",
              name: "Widget",
              line: 1,
              members: [{ kind: "method", name: "greet", line: 2 }],
            },
          ],
          imports: [],
          summary: "Provides the Widget class for rendering things.",
          summaryHash: "feedface",
        },
      },
    };
    await writeRepoMapCache(config, original);
    const round = await readRepoMapCache(config);
    assert.deepEqual(round, original);
  } finally {
    await cleanup();
  }
});

test("readRepoMapCache: corrupt file returns empty (does not throw)", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(repoMapCachePath(config), "{ not valid json", "utf-8");
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: CACHE_VERSION, files: {} });
  } finally {
    await cleanup();
  }
});

test("readRepoMapCache: wrong version returns empty", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      repoMapCachePath(config),
      JSON.stringify({ version: 999, files: {} }),
      "utf-8"
    );
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: CACHE_VERSION, files: {} });
  } finally {
    await cleanup();
  }
});

test("legacy cache versions (1-9) are discarded", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    for (const v of [1, 2, 3, 4, 5, 6, 7, 8, 9]) {
      await writeFile(
        repoMapCachePath(config),
        JSON.stringify({
          version: v,
          files: { "x.ts": { mtime: 1, size: 1, language: "ts", symbols: [] } },
        }),
        "utf-8"
      );
      const cache = await readRepoMapCache(config);
      assert.deepEqual(cache, { version: CACHE_VERSION, files: {} }, `v${v} discarded`);
    }
  } finally {
    await cleanup();
  }
});

test("isStatFresh: matches mtime+size", () => {
  assert.equal(isStatFresh(sampleEntry, 100, 200), true);
  assert.equal(isStatFresh(sampleEntry, 101, 200), false);
  assert.equal(isStatFresh(sampleEntry, 100, 201), false);
  assert.equal(isStatFresh(undefined, 100, 200), false);
});

test("hashContent: same text → same hash; different text → different hash", () => {
  const a = hashContent("hello world");
  const b = hashContent("hello world");
  const c = hashContent("hello worlD");
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.match(a, /^[a-f0-9]{40}$/); // sha1 hex
});

test("written cache file is parseable JSON on disk", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeRepoMapCache(config, { version: CACHE_VERSION, files: {} });
    const raw = await readFile(repoMapCachePath(config), "utf-8");
    const parsed = JSON.parse(raw);
    assert.equal(parsed.version, CACHE_VERSION);
  } finally {
    await cleanup();
  }
});

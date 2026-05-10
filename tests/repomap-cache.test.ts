import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  readRepoMapCache,
  writeRepoMapCache,
  isFresh,
  repoMapCachePath,
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

test("readRepoMapCache: missing file returns empty cache", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: 9, files: {} });
  } finally {
    await cleanup();
  }
});

test("write then read round-trips", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    const original = {
      version: 9 as const,
      files: {
        "src/foo.ts": {
          mtime: 100,
          size: 200,
          language: "ts" as const,
          symbols: [
            {
              kind: "function",
              name: "foo",
              line: 1,
              signature: "a: number",
            },
          ],
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
    assert.deepEqual(cache, { version: 9, files: {} });
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
    assert.deepEqual(cache, { version: 9, files: {} });
  } finally {
    await cleanup();
  }
});

test("readRepoMapCache: legacy version 1 cache is discarded", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      repoMapCachePath(config),
      JSON.stringify({
        version: 1,
        files: {
          "x.ts": {
            mtime: 1,
            size: 1,
            language: "ts",
            symbols: [],
          },
        },
      }),
      "utf-8"
    );
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: 9, files: {} });
  } finally {
    await cleanup();
  }
});

test("readRepoMapCache: legacy version 2 cache is discarded", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      repoMapCachePath(config),
      JSON.stringify({
        version: 2,
        files: {
          "x.ts": {
            mtime: 1,
            size: 1,
            language: "ts",
            symbols: [
              {
                kind: "function",
                name: "foo",
                line: 1,
                signature: "a: number",
              },
            ],
          },
        },
      }),
      "utf-8"
    );
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: 9, files: {} });
  } finally {
    await cleanup();
  }
});

test("readRepoMapCache: legacy version 3 cache is discarded", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      repoMapCachePath(config),
      JSON.stringify({
        version: 3,
        files: {
          "x.ts": {
            mtime: 1,
            size: 1,
            language: "ts",
            symbols: [
              {
                kind: "function",
                name: "foo",
                line: 1,
                signature: "a: number",
                returnType: "void",
              },
            ],
          },
        },
      }),
      "utf-8"
    );
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: 9, files: {} });
  } finally {
    await cleanup();
  }
});

test("readRepoMapCache: legacy version 4 cache is discarded", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      repoMapCachePath(config),
      JSON.stringify({
        version: 4,
        files: {
          "x.rs": {
            mtime: 1,
            size: 1,
            language: "rs",
            symbols: [
              {
                kind: "fn",
                name: "foo",
                line: 1,
                signature: "a: i32",
              },
            ],
          },
        },
      }),
      "utf-8"
    );
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: 9, files: {} });
  } finally {
    await cleanup();
  }
});

test("readRepoMapCache: legacy version 5 cache is discarded", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      repoMapCachePath(config),
      JSON.stringify({
        version: 5,
        files: {
          "x.go": {
            mtime: 1,
            size: 1,
            language: "go",
            symbols: [
              {
                kind: "func",
                name: "foo",
                line: 1,
                signature: "a int",
              },
            ],
          },
        },
      }),
      "utf-8"
    );
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: 9, files: {} });
  } finally {
    await cleanup();
  }
});

test("readRepoMapCache: legacy version 6 cache is discarded", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      repoMapCachePath(config),
      JSON.stringify({
        version: 6,
        files: {
          "x.ts": {
            mtime: 1,
            size: 1,
            language: "ts",
            symbols: [
              {
                kind: "function",
                name: "foo",
                line: 1,
                signature: "",
              },
            ],
          },
        },
      }),
      "utf-8"
    );
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: 9, files: {} });
  } finally {
    await cleanup();
  }
});

test("readRepoMapCache: legacy version 7 cache is discarded", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      repoMapCachePath(config),
      JSON.stringify({
        version: 7,
        files: {
          "x.go": {
            mtime: 1,
            size: 1,
            language: "go",
            symbols: [
              {
                kind: "func",
                name: "foo",
                line: 1,
                signature: "",
                returnType: "interface",
              },
            ],
          },
        },
      }),
      "utf-8"
    );
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: 9, files: {} });
  } finally {
    await cleanup();
  }
});

test("readRepoMapCache: legacy version 8 cache is discarded", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      repoMapCachePath(config),
      JSON.stringify({
        version: 8,
        files: {
          "README.md": {
            mtime: 1,
            size: 1,
            language: "md",
            symbols: [
              {
                kind: "h1",
                name: "in fence",
                line: 4,
              },
            ],
          },
        },
      }),
      "utf-8"
    );
    const cache = await readRepoMapCache(config);
    assert.deepEqual(cache, { version: 9, files: {} });
  } finally {
    await cleanup();
  }
});

test("isFresh: matches mtime+size", () => {
  const entry = {
    mtime: 100,
    size: 200,
    language: "ts" as const,
    symbols: [],
  };
  assert.equal(isFresh(entry, 100, 200), true);
  assert.equal(isFresh(entry, 101, 200), false);
  assert.equal(isFresh(entry, 100, 201), false);
  assert.equal(isFresh(undefined, 100, 200), false);
});

test("written cache file is parseable JSON on disk", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeRepoMapCache(config, { version: 9, files: {} });
    const raw = await readFile(repoMapCachePath(config), "utf-8");
    const parsed = JSON.parse(raw);
    assert.equal(parsed.version, 9);
  } finally {
    await cleanup();
  }
});

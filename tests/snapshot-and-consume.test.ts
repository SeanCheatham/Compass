import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile, readFile, access } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { snapshotAndConsume } from "../src/mcp/utils/workspace.ts";

async function tmpDir(): Promise<{
  dir: string;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-snap-"));
  return { dir, cleanup: () => rm(dir, { recursive: true, force: true }) };
}

test("snapshotAndConsume: returns content and leaves an empty file behind", async () => {
  const { dir, cleanup } = await tmpDir();
  try {
    const path = join(dir, "drafts.md");
    await writeFile(path, "hello\nworld\n", "utf-8");

    const captured = await snapshotAndConsume(path);
    assert.equal(captured, "hello\nworld\n");

    // File still exists but is empty.
    const after = await readFile(path, "utf-8");
    assert.equal(after, "");
  } finally {
    await cleanup();
  }
});

test("snapshotAndConsume: returns empty string when source file does not exist", async () => {
  const { dir, cleanup } = await tmpDir();
  try {
    const path = join(dir, "missing.md");
    const captured = await snapshotAndConsume(path);
    assert.equal(captured, "");
    // Should not have created the file.
    await assert.rejects(() => access(path));
  } finally {
    await cleanup();
  }
});

test("snapshotAndConsume: cleans up the snapshot temp file", async () => {
  const { dir, cleanup } = await tmpDir();
  try {
    const path = join(dir, "drafts.md");
    await writeFile(path, "data", "utf-8");

    await snapshotAndConsume(path);

    await assert.rejects(() => access(`${path}.snapshot`));
  } finally {
    await cleanup();
  }
});

test("snapshotAndConsume: roundtrip with concurrent append-after-rename loses no in-flight write", async () => {
  // Simulates the runner snapshotting drafts.md while a draft submission is
  // landing. After rename, the new (empty) file is what subsequent writes
  // append to. The captured content is exactly the pre-rename state.
  const { dir, cleanup } = await tmpDir();
  try {
    const path = join(dir, "drafts.md");
    await writeFile(path, "old content\n", "utf-8");

    const captured = await snapshotAndConsume(path);
    assert.equal(captured, "old content\n");

    // Simulate a write that races in after the rename: the new file should be
    // empty + the new entry, NOT the old content + new entry.
    const newEntry = "- new draft\n";
    const existing = await readFile(path, "utf-8");
    await writeFile(path, existing + newEntry, "utf-8");

    const after = await readFile(path, "utf-8");
    assert.equal(after, newEntry);
  } finally {
    await cleanup();
  }
});

test("snapshotAndConsume: preserves multiline content faithfully", async () => {
  const { dir, cleanup } = await tmpDir();
  try {
    const path = join(dir, "feedback.md");
    const content =
      "# Notes\n\n- did the thing\n- saw a bug at line 42\n\nMore prose.\n";
    await writeFile(path, content, "utf-8");

    const captured = await snapshotAndConsume(path);
    assert.equal(captured, content);
  } finally {
    await cleanup();
  }
});

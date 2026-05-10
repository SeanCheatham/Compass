import { test } from "node:test";
import assert from "node:assert/strict";
import {
  mkdtemp,
  rm,
  writeFile,
  readFile,
  access,
  unlink,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import { acquireWorkspaceLock } from "../src/state/lock.ts";

async function tmpWorkspace(): Promise<{
  dir: string;
  pidfile: string;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-lock-"));
  return {
    dir,
    pidfile: join(dir, "compass.pid"),
    cleanup: () => rm(dir, { recursive: true, force: true }),
  };
}

// Sentinel PID guaranteed to be unallocated on Linux/macOS (above pid_max on
// every default config: Linux defaults to 4_194_304, macOS to 99_998). Used to
// simulate a stale pidfile without the PID-recycling flakiness of the
// spawn-child-and-wait pattern.
const STALE_PID = 2_147_483_646;

test("acquireWorkspaceLock: fresh acquire on empty workspace returns ok and writes pidfile with own PID", async () => {
  const { dir, pidfile, cleanup } = await tmpWorkspace();
  try {
    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, true);
    if (!result.ok) return; // narrow for TS

    const raw = await readFile(pidfile, "utf-8");
    assert.equal(parseInt(raw.trim(), 10), process.pid);

    await result.lock.release();
  } finally {
    await cleanup();
  }
});

test("acquireWorkspaceLock: creates workspace dir if missing (mkdir -p)", async () => {
  const { dir, cleanup } = await tmpWorkspace();
  try {
    const nested = join(dir, "nested/sub");
    const result = await acquireWorkspaceLock(nested);
    assert.equal(result.ok, true);
    if (!result.ok) return;

    // Directory must now exist.
    await access(nested);
    // And pidfile inside it.
    const raw = await readFile(join(nested, "compass.pid"), "utf-8");
    assert.equal(parseInt(raw.trim(), 10), process.pid);

    await result.lock.release();
  } finally {
    await cleanup();
  }
});

test("acquireWorkspaceLock: fails ok=false when pidfile contains a live other PID", async () => {
  const { dir, pidfile, cleanup } = await tmpWorkspace();
  try {
    await writeFile(pidfile, String(process.ppid), "utf-8");

    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, false);
    if (result.ok) return;

    assert.equal(result.pid, process.ppid);
    assert.ok(
      result.pidfilePath.endsWith("compass.pid"),
      `expected pidfilePath to end with compass.pid, got ${result.pidfilePath}`
    );

    // pidfile must be unchanged on disk.
    const raw = await readFile(pidfile, "utf-8");
    assert.equal(raw, String(process.ppid));
  } finally {
    await cleanup();
  }
});

test("acquireWorkspaceLock: stale (dead) PID is overwritten", async () => {
  const { dir, pidfile, cleanup } = await tmpWorkspace();
  try {
    await writeFile(pidfile, `${STALE_PID}\n`, "utf-8");

    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, true);
    if (!result.ok) return;

    const raw = await readFile(pidfile, "utf-8");
    assert.equal(parseInt(raw.trim(), 10), process.pid);

    await result.lock.release();
  } finally {
    await cleanup();
  }
});

test("acquireWorkspaceLock: malformed pidfile content treated as stale", async () => {
  const { dir, pidfile, cleanup } = await tmpWorkspace();
  try {
    await writeFile(pidfile, "not-a-number\n", "utf-8");

    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, true);
    if (!result.ok) return;

    const raw = await readFile(pidfile, "utf-8");
    assert.equal(parseInt(raw.trim(), 10), process.pid);

    await result.lock.release();
  } finally {
    await cleanup();
  }
});

test("acquireWorkspaceLock: empty pidfile treated as stale", async () => {
  const { dir, pidfile, cleanup } = await tmpWorkspace();
  try {
    await writeFile(pidfile, "", "utf-8");

    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, true);
    if (!result.ok) return;

    const raw = await readFile(pidfile, "utf-8");
    assert.equal(parseInt(raw.trim(), 10), process.pid);

    await result.lock.release();
  } finally {
    await cleanup();
  }
});

test("acquireWorkspaceLock: zero or negative PID treated as stale", async () => {
  // (a) zero
  {
    const { dir, pidfile, cleanup } = await tmpWorkspace();
    try {
      await writeFile(pidfile, "0\n", "utf-8");
      const result = await acquireWorkspaceLock(dir);
      assert.equal(result.ok, true);
      if (!result.ok) return;
      const raw = await readFile(pidfile, "utf-8");
      assert.equal(parseInt(raw.trim(), 10), process.pid);
      await result.lock.release();
    } finally {
      await cleanup();
    }
  }
  // (b) negative
  {
    const { dir, pidfile, cleanup } = await tmpWorkspace();
    try {
      await writeFile(pidfile, "-5\n", "utf-8");
      const result = await acquireWorkspaceLock(dir);
      assert.equal(result.ok, true);
      if (!result.ok) return;
      const raw = await readFile(pidfile, "utf-8");
      assert.equal(parseInt(raw.trim(), 10), process.pid);
      await result.lock.release();
    } finally {
      await cleanup();
    }
  }
});

test("acquireWorkspaceLock: trailing whitespace and surrounding noise tolerated", async () => {
  const { dir, pidfile, cleanup } = await tmpWorkspace();
  try {
    await writeFile(pidfile, `  ${process.ppid}  \n`, "utf-8");

    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, false);
    if (result.ok) return;

    assert.equal(result.pid, process.ppid);
  } finally {
    await cleanup();
  }
});

test("release: removes pidfile when our PID still matches", async () => {
  const { dir, pidfile, cleanup } = await tmpWorkspace();
  try {
    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, true);
    if (!result.ok) return;

    await result.lock.release();

    await assert.rejects(() => access(pidfile));
  } finally {
    await cleanup();
  }
});

test("release: does NOT remove pidfile if another process has rewritten it (TOCTOU correctness)", async () => {
  const { dir, pidfile, cleanup } = await tmpWorkspace();
  try {
    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, true);
    if (!result.ok) return;

    // Simulate another runner clobbering the pidfile after we acquired.
    await writeFile(pidfile, "99999\n", "utf-8");

    await result.lock.release();

    // File must still exist and still contain the foreign PID.
    const raw = await readFile(pidfile, "utf-8");
    assert.equal(raw, "99999\n");
  } finally {
    await cleanup();
  }
});

test("release: idempotent if pidfile already gone", async () => {
  const { dir, pidfile, cleanup } = await tmpWorkspace();
  try {
    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, true);
    if (!result.ok) return;

    await unlink(pidfile);

    // Must not throw.
    await result.lock.release();
  } finally {
    await cleanup();
  }
});

test("acquireWorkspaceLock: pidfile path is exactly `compass.pid` inside the workspace dir", async () => {
  const { dir, pidfile, cleanup } = await tmpWorkspace();
  try {
    // Use the failure branch so we can read result.pidfilePath directly.
    await writeFile(pidfile, String(process.ppid), "utf-8");

    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, false);
    if (result.ok) return;

    assert.equal(result.pidfilePath, resolve(dir, "compass.pid"));
  } finally {
    await cleanup();
  }
});

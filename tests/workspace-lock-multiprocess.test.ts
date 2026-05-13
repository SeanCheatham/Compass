import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, type ChildProcess } from "node:child_process";
import { mkdtemp, rm, readFile, access } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { acquireWorkspaceLock } from "../src/state/lock.ts";

const HELPER_PATH = resolve("tests/helpers/lock-holder.ts");

async function tmpWorkspace(): Promise<{
  dir: string;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-mplock-"));
  return { dir, cleanup: () => rm(dir, { recursive: true, force: true }) };
}

// Spawns the helper holder. Resolves `ready` once the helper prints "ready "
// to stdout (i.e. it has acquired the lock and written the pidfile).
// Rejects if the helper exits before becoming ready.
function spawnHolder(dir: string): { child: ChildProcess; ready: Promise<void> } {
  const child = spawn("node", ["--import", "tsx", HELPER_PATH, dir], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  const ready = new Promise<void>((resolveReady, rejectReady) => {
    let buf = "";
    let resolved = false;
    const onData = (chunk: Buffer): void => {
      buf += chunk.toString();
      if (!resolved && buf.includes("ready ")) {
        resolved = true;
        child.stdout!.off("data", onData);
        resolveReady();
      }
    };
    child.stdout!.on("data", onData);
    child.on("error", rejectReady);
    child.on("exit", (code) => {
      if (!resolved) {
        rejectReady(
          new Error(`helper exited code=${code} before ready; output=${buf}`)
        );
      }
    });
  });
  return { child, ready };
}

// Wait for the child to exit. Hard-kills + rejects after timeoutMs to keep
// CI fast on hangs.
function waitForExit(child: ChildProcess, timeoutMs = 5000): Promise<number | null> {
  return new Promise((resolveExit, rejectExit) => {
    const t = setTimeout(() => {
      child.kill("SIGKILL");
      rejectExit(new Error("helper did not exit within timeout"));
    }, timeoutMs);
    child.on("exit", (code) => {
      clearTimeout(t);
      resolveExit(code);
    });
  });
}

test("live child holds lock: parent acquire fails with pid === child.pid", async () => {
  const { dir, cleanup } = await tmpWorkspace();
  const { child, ready } = spawnHolder(dir);
  try {
    await ready;

    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, false);
    if (result.ok) return; // narrow for TS

    assert.equal(result.pid, child.pid);
    assert.equal(result.pidfilePath, resolve(dir, "compass.pid"));

    // pidfile must still contain the child's PID — our failed acquire should
    // not have touched it.
    const raw = await readFile(resolve(dir, "compass.pid"), "utf-8");
    assert.equal(parseInt(raw.trim(), 10), child.pid);
  } finally {
    child.stdin!.end();
    await waitForExit(child).catch(() => {
      /* best-effort */
    });
    await cleanup();
  }
});

test("released child: pidfile is gone, parent acquire succeeds", async () => {
  const { dir, cleanup } = await tmpWorkspace();
  const { child, ready } = spawnHolder(dir);
  try {
    await ready;

    // Tell helper to release and exit cleanly.
    child.stdin!.end();
    const code = await waitForExit(child);
    assert.equal(code, 0);

    // Pidfile should be gone after graceful release.
    await assert.rejects(() => access(resolve(dir, "compass.pid")));

    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    await result.lock.release();
  } finally {
    await cleanup();
  }
});

test("SIGKILL'd child leaves stale pidfile; parent overwrites it", async () => {
  const { dir, cleanup } = await tmpWorkspace();
  const { child, ready } = spawnHolder(dir);
  try {
    await ready;
    const childPid = child.pid!;
    assert.ok(childPid, "child must have a pid");

    // Sanity: pidfile contains the child's PID before we kill.
    const before = await readFile(resolve(dir, "compass.pid"), "utf-8");
    assert.equal(parseInt(before.trim(), 10), childPid);

    // Hard-kill: no graceful release path runs.
    child.kill("SIGKILL");
    await waitForExit(child);

    const result = await acquireWorkspaceLock(dir);
    assert.equal(result.ok, true);
    if (!result.ok) return;

    const after = await readFile(resolve(dir, "compass.pid"), "utf-8");
    assert.equal(parseInt(after.trim(), 10), process.pid);

    await result.lock.release();
  } finally {
    await cleanup();
  }
});

test("racing acquires: only one of N parallel processes wins", async () => {
  const { dir, cleanup } = await tmpWorkspace();
  const N = 6;
  const children: ChildProcess[] = [];
  try {
    const outcomes = await Promise.all(
      Array.from({ length: N }, () => {
        const { child, ready } = spawnHolder(dir);
        children.push(child);
        return ready
          .then(() => ({ child, outcome: "ready" as const }))
          .catch(() => ({
            child,
            outcome: { code: child.exitCode } as const,
          }));
      })
    );

    const winners = outcomes.filter((o) => o.outcome === "ready");
    const losers = outcomes.filter((o) => o.outcome !== "ready");
    assert.equal(
      winners.length,
      1,
      `expected exactly 1 winner, got ${winners.length}`
    );
    assert.equal(losers.length, N - 1);
    for (const l of losers) {
      assert.equal(
        (l.outcome as { code: number | null }).code,
        3,
        "loser must exit code 3 (acquire failed), not 1 (crash) or 2 (usage)"
      );
    }

    const winnerChild = (winners[0] as { child: ChildProcess }).child;
    const raw = await readFile(resolve(dir, "compass.pid"), "utf-8");
    assert.equal(parseInt(raw.trim(), 10), winnerChild.pid);

    winnerChild.stdin!.end();
    const exitCode = await waitForExit(winnerChild);
    assert.equal(exitCode, 0);
  } finally {
    await Promise.all(
      children.map(async (child) => {
        if (child.exitCode !== null || child.signalCode !== null) return;
        child.stdin?.end();
        await waitForExit(child).catch(() => {
          /* best-effort */
        });
      })
    );
    await cleanup();
  }
});

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile, access } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { createSessionTracker } from "../src/state/sessions.ts";

async function tmpWorkspace(): Promise<{
  path: string;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-sessions-"));
  return {
    path: join(dir, "sessions.json"),
    cleanup: () => rm(dir, { recursive: true, force: true }),
  };
}

/**
 * Suppress console.warn during a block so the corruption-tolerance tests don't
 * spam stderr in the test output.
 */
function silenceWarn<T>(fn: () => T): T {
  const orig = console.warn;
  console.warn = () => {};
  try {
    return fn();
  } finally {
    console.warn = orig;
  }
}

test("sessions persistence: round-trips across two trackers", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const t1 = createSessionTracker({ recordPath: path });
    t1.start(1);
    t1.setPlan("plan body", "npm test");
    t1.setBefore("aaa");
    t1.setAfter("bbb", [
      { sha: "bbb", short: "bbb0000", subject: "do thing" },
    ]);
    t1.addNote("a note");
    t1.end("succeeded");
    await t1.flush();

    const t2 = createSessionTracker({ recordPath: path });
    const records = t2.all();
    assert.equal(records.length, 1);
    const r = records[0];
    assert.equal(r.session, 1);
    assert.equal(r.plan, "plan body");
    assert.equal(r.verify, "npm test");
    assert.equal(r.beforeSha, "aaa");
    assert.equal(r.afterSha, "bbb");
    assert.deepEqual(r.commits, [
      { sha: "bbb", short: "bbb0000", subject: "do thing" },
    ]);
    assert.deepEqual(r.notes, ["a note"]);
    assert.equal(r.status, "succeeded");
    assert.equal(typeof r.startedAt, "number");
    assert.equal(typeof r.endedAt, "number");
  } finally {
    await cleanup();
  }
});

test("sessions persistence: malformed JSON yields empty tracker, no throw", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    await writeFile(path, "{not json", "utf-8");
    const t = silenceWarn(() => createSessionTracker({ recordPath: path }));
    assert.deepEqual(t.all(), []);
  } finally {
    await cleanup();
  }
});

test("sessions persistence: missing file yields empty tracker, no throw", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    // Sanity: file truly does not exist.
    await assert.rejects(() => access(path));
    const t = createSessionTracker({ recordPath: path });
    assert.deepEqual(t.all(), []);
  } finally {
    await cleanup();
  }
});

test("sessions persistence: iteration counter resumes from last persisted session", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const t1 = createSessionTracker({ recordPath: path });
    // Mirror the cli pattern: seed from existing records, then ++ before start.
    let iteration = t1.all().reduce((m, s) => Math.max(m, s.session), 0);
    iteration++;
    t1.start(iteration);
    t1.end("succeeded");
    iteration++;
    t1.start(iteration);
    t1.end("succeeded");
    await t1.flush();

    const t2 = createSessionTracker({ recordPath: path });
    let iteration2 = t2.all().reduce((m, s) => Math.max(m, s.session), 0);
    assert.equal(iteration2, 2);
    iteration2++;
    t2.start(iteration2);
    assert.equal(t2.current()?.session, 3);
    await t2.flush();

    const t3 = createSessionTracker({ recordPath: path });
    const max = t3.all().reduce((m, s) => Math.max(m, s.session), 0);
    assert.equal(max, 3);
  } finally {
    await cleanup();
  }
});

test("sessions persistence: malformed entries are dropped silently while valid ones survive", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const valid = {
      session: 1,
      startedAt: 100,
      endedAt: 200,
      plan: "p",
      verify: "v",
      beforeSha: null,
      afterSha: null,
      commits: [],
      status: "succeeded",
      notes: [],
    };
    const bad1 = { session: "not-a-number" };
    const bad2 = {
      session: 2,
      startedAt: 300,
      endedAt: null,
      plan: null,
      verify: null,
      beforeSha: null,
      afterSha: null,
      commits: [{ sha: "x" /* missing short/subject */ }],
      status: "developing",
      notes: [],
    };
    await writeFile(path, JSON.stringify([valid, bad1, bad2]), "utf-8");

    const t = createSessionTracker({ recordPath: path });
    const records = t.all();
    assert.equal(records.length, 1);
    assert.equal(records[0].session, 1);
  } finally {
    await cleanup();
  }
});

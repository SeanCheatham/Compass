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

test("sessions persistence: setVerifyOutput round-trips through disk", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const t1 = createSessionTracker({ recordPath: path });
    t1.start(1);
    t1.setPlan("plan body", "npm test");
    t1.setVerifyOutput({
      command: "npm test",
      exitCode: 1,
      tail: "FAIL\nfoo",
    });
    t1.end("failed");
    await t1.flush();

    const t2 = createSessionTracker({ recordPath: path });
    const records = t2.all();
    assert.equal(records.length, 1);
    const r = records[0];
    assert.deepEqual(r.verifyOutput, {
      command: "npm test",
      exitCode: 1,
      tail: "FAIL\nfoo",
    });
  } finally {
    await cleanup();
  }
});

test("sessions persistence: older sessions without verifyOutput load with verifyOutput: null", async () => {
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
      // Note: no verifyOutput field — mirrors older session files.
    };
    await writeFile(path, JSON.stringify([valid]), "utf-8");

    const t = createSessionTracker({ recordPath: path });
    const records = t.all();
    assert.equal(records.length, 1);
    assert.equal(records[0].verifyOutput, null);
  } finally {
    await cleanup();
  }
});

test("sessions persistence: priorRunsCount reflects records loaded from disk", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const rec = (n: number) => ({
      session: n,
      startedAt: 100 * n,
      endedAt: 100 * n + 50,
      plan: "p",
      verify: "v",
      beforeSha: null,
      afterSha: null,
      commits: [],
      status: "succeeded",
      notes: [],
    });
    await writeFile(path, JSON.stringify([rec(1), rec(2)]), "utf-8");

    const t = createSessionTracker({ recordPath: path });
    assert.equal(t.priorRunsCount(), 2);
    assert.equal(t.all().length, 2);
  } finally {
    await cleanup();
  }
});

test("sessions persistence: new sessions started after load are not counted as prior", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const rec = (n: number) => ({
      session: n,
      startedAt: 100 * n,
      endedAt: 100 * n + 50,
      plan: "p",
      verify: "v",
      beforeSha: null,
      afterSha: null,
      commits: [],
      status: "succeeded",
      notes: [],
    });
    await writeFile(path, JSON.stringify([rec(1), rec(2)]), "utf-8");

    const t = createSessionTracker({ recordPath: path });
    t.start(99);
    assert.equal(t.priorRunsCount(), 2);
    assert.equal(t.all().length, 3);
  } finally {
    await cleanup();
  }
});

test("sessions persistence: clearPriorRuns drops only prior records, persists, and resets the count", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const rec = (n: number) => ({
      session: n,
      startedAt: 100 * n,
      endedAt: 100 * n + 50,
      plan: "p",
      verify: "v",
      beforeSha: null,
      afterSha: null,
      commits: [],
      status: "succeeded",
      notes: [],
    });
    await writeFile(path, JSON.stringify([rec(1), rec(2)]), "utf-8");

    const t = createSessionTracker({ recordPath: path });
    t.start(99);
    t.clearPriorRuns();
    assert.equal(t.priorRunsCount(), 0);
    const remaining = t.all();
    assert.equal(remaining.length, 1);
    assert.equal(remaining[0].session, 99);

    await t.flush();

    const t2 = createSessionTracker({ recordPath: path });
    const reloaded = t2.all();
    assert.equal(reloaded.length, 1);
    assert.equal(reloaded[0].session, 99);
  } finally {
    await cleanup();
  }
});

test("sessions persistence: maxPersisted trims oldest records on load and rewrites file", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const rec = (n: number) => ({
      session: n,
      startedAt: 100 * n,
      endedAt: 100 * n + 50,
      plan: "p",
      verify: "v",
      beforeSha: null,
      afterSha: null,
      commits: [],
      status: "succeeded",
      notes: [],
    });
    await writeFile(
      path,
      JSON.stringify([rec(1), rec(2), rec(3), rec(4), rec(5)]),
      "utf-8"
    );

    const t = createSessionTracker({ recordPath: path, maxPersisted: 3 });
    assert.equal(t.all().length, 3);
    assert.deepEqual(
      t.all().map((r) => r.session),
      [3, 4, 5]
    );
    assert.equal(t.priorRunsCount(), 3);

    await t.flush();

    const t2 = createSessionTracker({ recordPath: path, maxPersisted: 100 });
    assert.equal(t2.all().length, 3);
    assert.deepEqual(
      t2.all().map((r) => r.session),
      [3, 4, 5]
    );
  } finally {
    await cleanup();
  }
});

test("sessions persistence: maxPersisted trims oldest when start() pushes past the cap", async () => {
  const t = createSessionTracker({ maxPersisted: 3 });
  t.start(1);
  t.end("succeeded");
  t.start(2);
  t.end("succeeded");
  t.start(3);
  t.end("succeeded");
  t.start(4);

  assert.equal(t.all().length, 3);
  assert.deepEqual(
    t.all().map((r) => r.session),
    [2, 3, 4]
  );
  assert.equal(t.current()?.session, 4);
});

test("sessions persistence: trimming during start decrements priorRunsCount when prior records are dropped", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const rec = (n: number) => ({
      session: n,
      startedAt: 100 * n,
      endedAt: 100 * n + 50,
      plan: "p",
      verify: "v",
      beforeSha: null,
      afterSha: null,
      commits: [],
      status: "succeeded",
      notes: [],
    });
    await writeFile(path, JSON.stringify([rec(1), rec(2), rec(3)]), "utf-8");

    const t = createSessionTracker({ recordPath: path, maxPersisted: 3 });
    assert.equal(t.priorRunsCount(), 3);

    t.start(99);

    assert.equal(t.all().length, 3);
    assert.equal(t.priorRunsCount(), 2);
    assert.equal(t.current()?.session, 99);
    assert.equal(t.all()[0].session, 2);
  } finally {
    await cleanup();
  }
});

test("sessions persistence: maxPersisted floors at 1 so the in-flight session is never dropped", async () => {
  const t = createSessionTracker({ maxPersisted: 0 });
  t.start(1);
  assert.equal(t.all().length, 1);
  assert.equal(t.current()?.session, 1);

  t.start(2);
  assert.equal(t.all().length, 1);
  assert.equal(t.current()?.session, 2);
});

test("validator: rejects record with non-string beforeSha; pins non-null happy path for beforeSha/afterSha", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const valid = {
      session: 1,
      startedAt: 100,
      endedAt: 200,
      plan: "p",
      verify: "v",
      beforeSha: "aaa", // non-null string — pins happy path for this branch
      afterSha: "bbb",
      commits: [],
      status: "succeeded",
      notes: [],
    };
    const bad = { ...valid, session: 2, beforeSha: 12345 }; // not string and not null → reject
    await writeFile(path, JSON.stringify([valid, bad]), "utf-8");
    const t = createSessionTracker({ recordPath: path });
    const records = t.all();
    assert.equal(records.length, 1);
    assert.equal(records[0].session, 1);
    assert.equal(records[0].beforeSha, "aaa");
    assert.equal(records[0].afterSha, "bbb");
  } finally {
    await cleanup();
  }
});

test("validator: rejects record where commits entry has non-string sha", async () => {
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
    const bad = {
      ...valid,
      session: 2,
      commits: [{ sha: 123, short: "xxx", subject: "oops" }],
    };
    await writeFile(path, JSON.stringify([valid, bad]), "utf-8");
    const t = createSessionTracker({ recordPath: path });
    const records = t.all();
    assert.equal(records.length, 1);
    assert.equal(records[0].session, 1);
  } finally {
    await cleanup();
  }
});

test("validator: rejects verifyOutput with non-finite exitCode by defaulting verifyOutput to null (record itself survives)", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const rec = {
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
      verifyOutput: { command: "npm test", exitCode: "not-a-number", tail: "" },
    };
    await writeFile(path, JSON.stringify([rec]), "utf-8");
    const t = createSessionTracker({ recordPath: path });
    const records = t.all();
    assert.equal(records.length, 1); // record survives — verifyOutput is tolerantly defaulted
    assert.equal(records[0].verifyOutput, null);
  } finally {
    await cleanup();
  }
});

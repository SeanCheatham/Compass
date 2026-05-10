import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  createOutputManager,
  type OutputEvent,
} from "../src/web/output-manager.ts";

async function tmpWorkspace(): Promise<{
  sessionsDir: string;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-output-"));
  return {
    sessionsDir: dir,
    cleanup: () => rm(dir, { recursive: true, force: true }),
  };
}

function ev(
  type: OutputEvent["type"],
  data: string,
  timestamp: number
): OutputEvent {
  return { type, data, timestamp };
}

function lines(events: OutputEvent[]): string {
  return events.map((e) => JSON.stringify(e)).join("\n") + "\n";
}

test("output-manager rehydrate: loads buffer from existing session-NNN.jsonl on construction", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const e1 = ev("log", "hello", 1);
    const e2 = ev("info", "world", 2);
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines([e1, e2]));

    const om = createOutputManager({ sessionsDir });
    const buf = om.getBuffer();
    assert.equal(buf.length, 2);
    assert.deepEqual(buf[0], e1);
    assert.deepEqual(buf[1], e2);
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: merges pre-session.jsonl before session-NNN files in chronological order", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const t1 = ev("log", "pre", 100);
    const t2 = ev("log", "s1", 200);
    const t3 = ev("log", "s2", 300);
    await writeFile(join(sessionsDir, "pre-session.jsonl"), lines([t1]));
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines([t2]));
    await writeFile(join(sessionsDir, "session-002.jsonl"), lines([t3]));

    const om = createOutputManager({ sessionsDir });
    const buf = om.getBuffer();
    assert.equal(buf.length, 3);
    assert.deepEqual(
      buf.map((e) => e.timestamp),
      [100, 200, 300]
    );
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: caps buffer at maxBuffer keeping the most recent events", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const events: OutputEvent[] = [];
    for (let i = 0; i < 10; i++) {
      events.push(ev("log", `msg-${i}`, i));
    }
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines(events));

    const om = createOutputManager({ sessionsDir, maxBuffer: 3 });
    const buf = om.getBuffer();
    assert.equal(buf.length, 3);
    assert.deepEqual(
      buf.map((e) => e.timestamp),
      [7, 8, 9]
    );
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: skips malformed JSON lines but keeps valid ones", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const e1 = ev("log", "a", 1);
    const e2 = ev("log", "b", 2);
    const e3 = ev("log", "c", 3);
    const content =
      JSON.stringify(e1) +
      "\n" +
      "not json" +
      "\n" +
      JSON.stringify(e2) +
      "\n" +
      "" +
      "\n" +
      JSON.stringify(e3) +
      "\n";
    await writeFile(join(sessionsDir, "session-001.jsonl"), content);

    const om = createOutputManager({ sessionsDir });
    const buf = om.getBuffer();
    assert.equal(buf.length, 3);
    assert.deepEqual(buf, [e1, e2, e3]);
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: skips lines that don't match the OutputEvent shape", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const valid = ev("log", "ok", 42);
    const content =
      JSON.stringify({}) +
      "\n" +
      JSON.stringify({ type: "log" }) +
      "\n" +
      JSON.stringify({ type: "log", timestamp: "oops", data: "x" }) +
      "\n" +
      // NaN serializes to null in JSON, which fails the typeof === "number"
      // check. Inject the literal NaN through a custom string instead.
      '{"type":"log","timestamp":NaN,"data":"x"}' +
      "\n" +
      JSON.stringify(valid) +
      "\n";
    await writeFile(join(sessionsDir, "session-001.jsonl"), content);

    const om = createOutputManager({ sessionsDir });
    const buf = om.getBuffer();
    assert.equal(buf.length, 1);
    assert.deepEqual(buf[0], valid);
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: tolerates missing sessions dir without throwing", async () => {
  const om = createOutputManager({
    sessionsDir: "/path/that/does/not/exist/compass-test",
  });
  assert.deepEqual(om.getBuffer(), []);
});

test("output-manager rehydrate: buffer empty when no sessionsDir is provided", () => {
  const om = createOutputManager({});
  assert.deepEqual(om.getBuffer(), []);
});

test("output-manager rehydrate: ignores files that don't match the jsonl naming pattern", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const valid = ev("log", "only-one", 5);
    await writeFile(join(sessionsDir, "random.txt"), "garbage");
    await writeFile(
      join(sessionsDir, "session-abc.jsonl"),
      JSON.stringify(ev("log", "should-not-load", 1)) + "\n"
    );
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines([valid]));

    const om = createOutputManager({ sessionsDir });
    const buf = om.getBuffer();
    assert.equal(buf.length, 1);
    assert.deepEqual(buf[0], valid);
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: new emissions still go to the buffer after rehydration", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const e1 = ev("log", "from-disk", 1);
    await writeFile(join(sessionsDir, "session-001.jsonl"), lines([e1]));

    const om = createOutputManager({ sessionsDir });
    om.log("hello");
    const buf = om.getBuffer();
    assert.equal(buf.length, 2);
    assert.deepEqual(buf[0], e1);
    assert.equal(buf[1].type, "log");
    assert.equal(buf[1].data, "hello");
  } finally {
    await cleanup();
  }
});

test("output-manager rehydrate: rehydrated events are NOT re-persisted to disk", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const e1 = ev("log", "from-disk", 1);
    const path = join(sessionsDir, "session-001.jsonl");
    await writeFile(path, lines([e1]));
    const sizeBefore = (await stat(path)).size;

    const _om = createOutputManager({ sessionsDir });
    // Let any pending async writes flush — there should be none from
    // rehydration, but we need to wait long enough that we'd catch one.
    await new Promise((r) => setTimeout(r, 50));

    const sizeAfter = (await stat(path)).size;
    assert.equal(sizeAfter, sizeBefore);
  } finally {
    await cleanup();
  }
});

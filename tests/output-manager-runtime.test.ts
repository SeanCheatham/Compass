import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, readFile } from "node:fs/promises";
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
  const dir = await mkdtemp(join(tmpdir(), "compass-output-runtime-"));
  return {
    sessionsDir: dir,
    cleanup: () => rm(dir, { recursive: true, force: true }),
  };
}

test("runtime: log() emits event with type=log, given message as data, no metadata", () => {
  const om = createOutputManager();
  const events: OutputEvent[] = [];
  om.onEvent((e) => events.push(e));
  const before = Date.now();
  om.log("hello");
  const after = Date.now();
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "log");
  assert.equal(events[0].data, "hello");
  assert.ok(events[0].timestamp >= before && events[0].timestamp <= after);
  assert.equal(events[0].metadata, undefined);
});

test("runtime: phase() emits event with type=phase", () => {
  const om = createOutputManager();
  const events: OutputEvent[] = [];
  om.onEvent((e) => events.push(e));
  const before = Date.now();
  om.phase("Dev");
  const after = Date.now();
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "phase");
  assert.equal(events[0].data, "Dev");
  assert.ok(events[0].timestamp >= before && events[0].timestamp <= after);
  assert.equal(events[0].metadata, undefined);
});

test("runtime: commit() emits event with type=commit", () => {
  const om = createOutputManager();
  const events: OutputEvent[] = [];
  om.onEvent((e) => events.push(e));
  const before = Date.now();
  om.commit("abc1234");
  const after = Date.now();
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "commit");
  assert.equal(events[0].data, "abc1234");
  assert.ok(events[0].timestamp >= before && events[0].timestamp <= after);
  assert.equal(events[0].metadata, undefined);
});

test("runtime: error() emits event with type=error", () => {
  const om = createOutputManager();
  const events: OutputEvent[] = [];
  om.onEvent((e) => events.push(e));
  const before = Date.now();
  om.error("boom");
  const after = Date.now();
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "error");
  assert.equal(events[0].data, "boom");
  assert.ok(events[0].timestamp >= before && events[0].timestamp <= after);
  assert.equal(events[0].metadata, undefined);
});

test("runtime: info() emits event with type=info", () => {
  const om = createOutputManager();
  const events: OutputEvent[] = [];
  om.onEvent((e) => events.push(e));
  const before = Date.now();
  om.info("fyi");
  const after = Date.now();
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "info");
  assert.equal(events[0].data, "fyi");
  assert.ok(events[0].timestamp >= before && events[0].timestamp <= after);
  assert.equal(events[0].metadata, undefined);
});

test("runtime: session() emits event with type=session and stringified number as data", () => {
  const om = createOutputManager();
  const events: OutputEvent[] = [];
  om.onEvent((e) => events.push(e));
  om.session(7);
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "session");
  assert.equal(events[0].data, "7");
  assert.equal(events[0].metadata, undefined);
});

test("runtime: tool() without detail produces metadata with only agent", () => {
  const om = createOutputManager();
  const events: OutputEvent[] = [];
  om.onEvent((e) => events.push(e));
  om.tool("Plan", "Bash");
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "tool");
  assert.equal(events[0].data, "Bash");
  assert.deepEqual(events[0].metadata, { agent: "Plan" });
});

test("runtime: tool() with detail spreads summary and full into metadata alongside agent", () => {
  const om = createOutputManager();
  const events: OutputEvent[] = [];
  om.onEvent((e) => events.push(e));
  om.tool("Dev", "Read", {
    summary: "file.ts",
    full: { path: "/a/b/file.ts" },
  });
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "tool");
  assert.equal(events[0].data, "Read");
  assert.deepEqual(events[0].metadata, {
    agent: "Dev",
    summary: "file.ts",
    full: { path: "/a/b/file.ts" },
  });
});

test("runtime: tool() spread fires even with empty-string summary or empty full map", () => {
  const om = createOutputManager();
  const events: OutputEvent[] = [];
  om.onEvent((e) => events.push(e));
  om.tool("Dev", "Edit", { summary: "", full: {} });
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "tool");
  assert.equal(events[0].data, "Edit");
  // The truthy check is on `detail` itself (a non-null object), NOT on
  // `detail.summary`/`detail.full` — so empty string and empty object still
  // appear in metadata.
  assert.deepEqual(events[0].metadata, {
    agent: "Dev",
    summary: "",
    full: {},
  });
});

test("runtime: agentStart() without context emits with metadata=undefined", () => {
  const om = createOutputManager();
  const events: OutputEvent[] = [];
  om.onEvent((e) => events.push(e));
  om.agentStart("Plan");
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "agent_start");
  assert.equal(events[0].data, "Plan");
  assert.equal(events[0].metadata, undefined);
});

test("runtime: agentStart and agentComplete attach metadata only when context/status truthy", () => {
  const om = createOutputManager();
  const events: OutputEvent[] = [];
  om.onEvent((e) => events.push(e));
  om.agentStart("Plan");
  om.agentStart("Plan", "why");
  om.agentComplete("Plan");
  om.agentComplete("Plan", "ok");
  assert.equal(events.length, 4);

  assert.equal(events[0].type, "agent_start");
  assert.equal(events[0].data, "Plan");
  assert.equal(events[0].metadata, undefined);

  assert.equal(events[1].type, "agent_start");
  assert.equal(events[1].data, "Plan");
  assert.deepEqual(events[1].metadata, { context: "why" });

  assert.equal(events[2].type, "agent_complete");
  assert.equal(events[2].data, "Plan");
  assert.equal(events[2].metadata, undefined);

  assert.equal(events[3].type, "agent_complete");
  assert.equal(events[3].data, "Plan");
  assert.deepEqual(events[3].metadata, { status: "ok" });
});

test("runtime: log()-then-session(N)-then-log() routes the second log to session-NNN.jsonl", async () => {
  const { sessionsDir, cleanup } = await tmpWorkspace();
  try {
    const om = createOutputManager({ sessionsDir });
    om.log("pre"); // -> pre-session.jsonl
    om.session(1); // -> session-001.jsonl + emits session event
    om.log("post"); // -> session-001.jsonl
    await new Promise((r) => setTimeout(r, 50));

    const pre = await readFile(
      join(sessionsDir, "pre-session.jsonl"),
      "utf-8"
    );
    const sess = await readFile(
      join(sessionsDir, "session-001.jsonl"),
      "utf-8"
    );
    const preLines = pre
      .trim()
      .split("\n")
      .map((l) => JSON.parse(l));
    const sessLines = sess
      .trim()
      .split("\n")
      .map((l) => JSON.parse(l));

    assert.equal(preLines.length, 1);
    assert.equal(preLines[0].type, "log");
    assert.equal(preLines[0].data, "pre");

    // The currentLogPath switch happens BEFORE the session event is persisted,
    // so the session event itself lands in session-001.jsonl, not pre-session.
    assert.equal(sessLines.length, 2);
    assert.equal(sessLines[0].type, "session");
    assert.equal(sessLines[0].data, "1");
    assert.equal(sessLines[1].type, "log");
    assert.equal(sessLines[1].data, "post");

    // Zero-padded to 3 digits.
    assert.equal(
      om.getActivityLogPath(),
      join(sessionsDir, "session-001.jsonl")
    );
  } finally {
    await cleanup();
  }
});

test("runtime: emitting more than maxBuffer events keeps only the most recent maxBuffer in getBuffer()", () => {
  const om = createOutputManager({ maxBuffer: 3 });
  om.log("a");
  om.log("b");
  om.log("c");
  om.log("d");
  om.log("e");
  const buf = om.getBuffer();
  assert.equal(buf.length, 3);
  assert.deepEqual(
    buf.map((e) => e.data),
    ["c", "d", "e"]
  );
});

test("runtime: onEvent() fans out to multiple subscribers", () => {
  const om = createOutputManager();
  const a: OutputEvent[] = [];
  const b: OutputEvent[] = [];
  om.onEvent((e) => a.push(e));
  om.onEvent((e) => b.push(e));
  om.log("hi");
  assert.equal(a.length, 1);
  assert.equal(b.length, 1);
  assert.equal(a[0].data, "hi");
  assert.equal(b[0].data, "hi");
});

test("runtime: onEvent() returns an unsubscribe that only removes the one listener", () => {
  const om = createOutputManager();
  const a: OutputEvent[] = [];
  const b: OutputEvent[] = [];
  const unsubA = om.onEvent((e) => a.push(e));
  om.onEvent((e) => b.push(e));
  om.log("first");
  unsubA();
  om.log("second");
  assert.deepEqual(
    a.map((e) => e.data),
    ["first"]
  );
  assert.deepEqual(
    b.map((e) => e.data),
    ["first", "second"]
  );
});

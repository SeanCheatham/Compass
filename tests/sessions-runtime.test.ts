import { test } from "node:test";
import assert from "node:assert/strict";

import {
  createSessionTracker,
  type SessionCommit,
} from "../src/state/sessions.ts";

test("runtime: setStatus updates current().status and is reflected by all()", () => {
  const t = createSessionTracker();
  t.start(1);
  assert.equal(t.current()?.status, "planning");
  t.setStatus("awaiting_approval");
  assert.equal(t.current()?.status, "awaiting_approval");
  t.setStatus("developing");
  assert.equal(t.current()?.status, "developing");
  assert.equal(t.all()[0].status, "developing");
});

test("runtime: onChange fires for every setter exactly once per call", () => {
  const t = createSessionTracker();
  let calls = 0;
  t.onChange(() => {
    calls++;
  });
  t.start(1); // 1
  t.setPlan("plan", "npm test"); // 2
  t.setStatus("developing"); // 3
  t.setBefore("aaa"); // 4
  t.setAfter("bbb", [{ sha: "bbb", short: "bbb0", subject: "" }]); // 5
  t.setVerifyOutput({ command: "npm test", exitCode: 0, tail: "ok" }); // 6
  t.addNote("note"); // 7
  t.end("succeeded"); // 8
  assert.equal(calls, 8);
});

test("runtime: onChange fans out to multiple subscribers", () => {
  const t = createSessionTracker();
  let a = 0;
  let b = 0;
  t.onChange(() => {
    a++;
  });
  t.onChange(() => {
    b++;
  });
  t.start(1);
  t.end("succeeded");
  assert.equal(a, 2);
  assert.equal(b, 2);
});

test("runtime: onChange returns an unsubscribe that only removes the one listener", () => {
  const t = createSessionTracker();
  let a = 0;
  let b = 0;
  const unsubA = t.onChange(() => {
    a++;
  });
  t.onChange(() => {
    b++;
  });
  t.start(1); // both fire: a=1, b=1
  unsubA();
  t.end("succeeded"); // only b: a=1, b=2
  assert.equal(a, 1);
  assert.equal(b, 2);
});

test("runtime: setters before any start() are no-ops, do not throw, do not emit", () => {
  const t = createSessionTracker();
  let calls = 0;
  t.onChange(() => {
    calls++;
  });
  // No start() yet.
  t.setPlan("p", "v");
  t.setStatus("developing");
  t.setBefore("aaa");
  t.setAfter("bbb", []);
  t.setVerifyOutput(null);
  t.addNote("n");
  t.end("succeeded");
  assert.equal(t.current(), null);
  assert.equal(t.all().length, 0);
  assert.equal(calls, 0);
});

test("runtime: clearPriorRuns is a no-op when priorRunsCount is 0 (no emit, no state change)", () => {
  const t = createSessionTracker(); // no recordPath → priorRunsCount = 0
  t.start(1);
  let calls = 0;
  t.onChange(() => {
    calls++;
  });
  t.clearPriorRuns();
  assert.equal(calls, 0); // early return: no emit
  assert.equal(t.priorRunsCount(), 0);
  assert.equal(t.all().length, 1); // current-run record untouched
  assert.equal(t.current()?.session, 1);
});

test("runtime: setAfter replaces commits array on each call", () => {
  const t = createSessionTracker();
  t.start(1);
  const c1: SessionCommit = { sha: "a", short: "a000", subject: "first" };
  const c2: SessionCommit = { sha: "b", short: "b000", subject: "second" };
  t.setAfter("a", [c1]);
  assert.deepEqual(t.current()?.commits, [c1]);
  t.setAfter("b", [c2]);
  assert.deepEqual(t.current()?.commits, [c2]); // replaced, not [c1, c2]
  assert.equal(t.current()?.afterSha, "b");
});

test("runtime: addNote appends in order", () => {
  const t = createSessionTracker();
  t.start(1);
  t.addNote("first");
  t.addNote("second");
  t.addNote("third");
  assert.deepEqual(t.current()?.notes, ["first", "second", "third"]);
});

test("runtime: end() sets endedAt to a finite timestamp and updates status", () => {
  const t = createSessionTracker();
  t.start(1);
  assert.equal(t.current()?.endedAt, null);
  const before = Date.now();
  t.end("failed");
  const after = Date.now();
  const r = t.current();
  assert.equal(r?.status, "failed");
  assert.ok(typeof r?.endedAt === "number");
  assert.ok(r!.endedAt! >= before && r!.endedAt! <= after);
});

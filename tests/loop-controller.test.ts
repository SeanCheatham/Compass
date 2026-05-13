import { test } from "node:test";
import assert from "node:assert/strict";

import {
  createLoopController,
  type LoopController,
  type LoopStatus,
} from "../src/state/control.ts";

function makeController(approveRequired = true): LoopController {
  return createLoopController({ approveRequired });
}

async function tick(ms = 10): Promise<void> {
  await new Promise((r) => setTimeout(r, ms));
}

test("loop-controller: initial status", () => {
  const c = makeController(true);
  const s = c.status();
  assert.equal(s.phase, "idle");
  assert.equal(s.paused, false);
  assert.equal(s.pauseMode, "immediate");
  assert.equal(s.approveRequired, true);
  assert.equal(s.session, 0);
  assert.equal(s.cancellationRequested, false);
  assert.equal(s.pendingApproval, null);

  const c2 = makeController(false);
  assert.equal(c2.status().approveRequired, false);
});

test("loop-controller: setPhase / setSession update status and notify listeners", () => {
  const c = makeController();
  let calls = 0;
  let last: LoopStatus | null = null;
  c.onChange((s) => {
    calls++;
    last = s;
  });
  c.setPhase("planning");
  c.setSession(7);
  assert.ok(calls >= 2, `expected at least 2 listener calls, got ${calls}`);
  assert.ok(last);
  assert.equal(last!.phase, "planning");
  assert.equal(last!.session, 7);
});

test("loop-controller: onChange returns an unsubscribe", () => {
  const c = makeController();
  let calls = 0;
  const off = c.onChange(() => {
    calls++;
  });
  off();
  c.setPhase("planning");
  assert.equal(calls, 0);
});

test("loop-controller: setApproveRequired toggles and emits", () => {
  const c = makeController(true);
  let calls = 0;
  c.onChange(() => {
    calls++;
  });
  c.setApproveRequired(false);
  assert.equal(c.status().approveRequired, false);
  assert.ok(calls >= 1);
});

test("loop-controller: pause() defaults to immediate", () => {
  const c = makeController();
  c.pause();
  const s = c.status();
  assert.equal(s.paused, true);
  assert.equal(s.pauseMode, "immediate");
});

test("loop-controller: pause('after_iteration') is honoured when not already paused", () => {
  const c = makeController();
  c.pause("after_iteration");
  const s = c.status();
  assert.equal(s.paused, true);
  assert.equal(s.pauseMode, "after_iteration");
});

test("loop-controller: upgrading after_iteration -> immediate works", () => {
  const c = makeController();
  c.pause("after_iteration");
  c.pause("immediate");
  assert.equal(c.status().pauseMode, "immediate");
  assert.equal(c.status().paused, true);
});

test("loop-controller: downgrading immediate -> after_iteration is a no-op; duplicate same-mode pause is a no-op", () => {
  const c = makeController();
  c.pause("immediate");
  let calls = 0;
  c.onChange(() => {
    calls++;
  });
  c.pause("after_iteration");
  assert.equal(c.status().pauseMode, "immediate");
  assert.equal(calls, 0);

  // Duplicate same-mode pause is a no-op (no extra emit).
  c.pause("immediate");
  assert.equal(calls, 0);
});

test("loop-controller: resume() on a non-paused controller is a no-op", () => {
  const c = makeController();
  let calls = 0;
  c.onChange(() => {
    calls++;
  });
  c.resume();
  assert.equal(calls, 0);
  assert.equal(c.status().paused, false);
});

test("loop-controller: resume() clears pause and resolves pending waitWhilePaused waiters with true", async () => {
  const c = makeController();
  c.pause();
  const ac = new AbortController();
  const p = c.waitWhilePaused(ac.signal);
  await tick();
  c.resume();
  const result = await p;
  assert.equal(result, true);
  const s = c.status();
  assert.equal(s.paused, false);
  assert.equal(s.pauseMode, "immediate");
});

test("loop-controller: waitWhilePaused returns true immediately when not paused", async () => {
  const c = makeController();
  const ac = new AbortController();
  const result = await c.waitWhilePaused(ac.signal);
  assert.equal(result, true);
});

test("loop-controller: waitWhilePaused returns false when the signal is already aborted", async () => {
  const c = makeController();
  c.pause();
  const result = await c.waitWhilePaused(AbortSignal.abort());
  assert.equal(result, false);
});

test("loop-controller: waitWhilePaused returns false when cancel() was already called", async () => {
  const c = makeController();
  c.pause();
  c.cancel();
  const ac = new AbortController();
  const result = await c.waitWhilePaused(ac.signal);
  assert.equal(result, false);
});

test("loop-controller: waitWhilePaused returns false if the signal aborts mid-wait", async () => {
  const c = makeController();
  c.pause();
  const ac = new AbortController();
  const p = c.waitWhilePaused(ac.signal);
  await tick();
  ac.abort();
  const result = await p;
  assert.equal(result, false);
});

test("loop-controller: awaitApproval short-circuits true when approveRequired === false", async () => {
  const c = makeController(false);
  const ac = new AbortController();
  const result = await c.awaitApproval(
    { plan: "p", verify: "v" },
    ac.signal
  );
  assert.equal(result, true);
  assert.equal(c.status().pendingApproval, null);
});

test("loop-controller: awaitApproval returns false when signal already aborted", async () => {
  const c = makeController(true);
  const result = await c.awaitApproval(
    { plan: "p", verify: "v" },
    AbortSignal.abort()
  );
  assert.equal(result, false);
});

test("loop-controller: awaitApproval returns false when cancel() was already called", async () => {
  const c = makeController(true);
  c.cancel();
  const ac = new AbortController();
  const result = await c.awaitApproval(
    { plan: "p", verify: "v" },
    ac.signal
  );
  assert.equal(result, false);
});

test("loop-controller: awaitApproval sets pendingApproval, emits, and resolves true on approve()", async () => {
  const c = makeController(true);
  let calls = 0;
  c.onChange(() => {
    calls++;
  });
  const ac = new AbortController();
  const pending = { plan: "the plan", verify: "npm test" };
  const p = c.awaitApproval(pending, ac.signal);
  await tick();
  assert.deepEqual(c.status().pendingApproval, pending);
  assert.ok(calls >= 1);
  c.approve();
  const result = await p;
  assert.equal(result, true);
  assert.equal(c.status().pendingApproval, null);
});

test("loop-controller: approve() is a no-op when no pendingApproval", () => {
  const c = makeController(true);
  let calls = 0;
  c.onChange(() => {
    calls++;
  });
  c.approve();
  assert.equal(calls, 0);
});

test("loop-controller: awaitApproval resolves false and clears pendingApproval when signal aborts mid-wait", async () => {
  const c = makeController(true);
  const ac = new AbortController();
  const pending = { plan: "p", verify: "v" };
  const p = c.awaitApproval(pending, ac.signal);
  await tick();
  assert.deepEqual(c.status().pendingApproval, pending);
  ac.abort();
  const result = await p;
  assert.equal(result, false);
  assert.equal(c.status().pendingApproval, null);
});

test("loop-controller: cancel() aborts the current iteration signal", () => {
  const c = makeController();
  const parent = new AbortController();
  const sig = c.iterationSignal(parent.signal);
  assert.equal(sig.aborted, false);
  assert.equal(c.status().cancellationRequested, false);
  c.cancel();
  assert.equal(sig.aborted, true);
  assert.equal(c.status().cancellationRequested, true);
});

test("loop-controller: cancel() releases blocked awaitApproval and waitWhilePaused with false", async () => {
  const c = makeController(true);
  c.pause();
  const ac1 = new AbortController();
  const ac2 = new AbortController();
  const pPause = c.waitWhilePaused(ac1.signal);
  const pApprove = c.awaitApproval({ plan: "p", verify: "v" }, ac2.signal);
  await tick();
  c.cancel();
  const [r1, r2] = await Promise.all([pPause, pApprove]);
  assert.equal(r1, false);
  assert.equal(r2, false);
});

test("loop-controller: cancel() clears pendingApproval and emits", async () => {
  const c = makeController(true);
  const ac = new AbortController();
  const p = c.awaitApproval({ plan: "p", verify: "v" }, ac.signal);
  await tick();
  assert.notEqual(c.status().pendingApproval, null);
  let calls = 0;
  c.onChange(() => {
    calls++;
  });
  c.cancel();
  await p;
  assert.equal(c.status().pendingApproval, null);
  assert.ok(calls >= 1);
});

test("loop-controller: iterationSignal returns an already-aborted signal when parent is already aborted", () => {
  const c = makeController();
  const sig = c.iterationSignal(AbortSignal.abort());
  assert.equal(sig.aborted, true);
});

test("loop-controller: iterationSignal returns an already-aborted signal when controller is in a cancelled state", () => {
  const c = makeController();
  c.cancel();
  const parent = new AbortController();
  const sig = c.iterationSignal(parent.signal);
  assert.equal(sig.aborted, true);
});

test("loop-controller: iterationSignal aborts when parent aborts later", async () => {
  const c = makeController();
  const parent = new AbortController();
  const sig = c.iterationSignal(parent.signal);
  assert.equal(sig.aborted, false);
  parent.abort();
  await tick();
  assert.equal(sig.aborted, true);
});

test("loop-controller: resetIteration() clears the cancelled flag", async () => {
  const c = makeController();
  c.cancel();
  assert.equal(c.status().cancellationRequested, true);
  c.resetIteration();
  assert.equal(c.status().cancellationRequested, false);

  const parent = new AbortController();
  const sig = c.iterationSignal(parent.signal);
  assert.equal(sig.aborted, false);

  // And waitWhilePaused (when not paused) returns true rather than false.
  const ac = new AbortController();
  const result = await c.waitWhilePaused(ac.signal);
  assert.equal(result, true);
});

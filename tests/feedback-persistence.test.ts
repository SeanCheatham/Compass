import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile, access } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { createFeedbackBus } from "../src/state/feedback.ts";

async function tmpWorkspace(): Promise<{
  path: string;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-feedback-"));
  return {
    path: join(dir, "feedback.json"),
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

test("feedback persistence: round-trips across two buses", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const t1 = createFeedbackBus({ recordPath: path });
    t1.set("hello world");
    await t1.flush();

    const t2 = createFeedbackBus({ recordPath: path });
    assert.equal(t2.current(), "hello world");
  } finally {
    await cleanup();
  }
});

test("feedback persistence: missing file yields empty bus, no throw", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    await assert.rejects(() => access(path));
    const t = createFeedbackBus({ recordPath: path });
    assert.equal(t.current(), "");
  } finally {
    await cleanup();
  }
});

test("feedback persistence: malformed JSON yields empty bus, no throw", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    await writeFile(path, "{not json", "utf-8");
    const t = silenceWarn(() => createFeedbackBus({ recordPath: path }));
    assert.equal(t.current(), "");
  } finally {
    await cleanup();
  }
});

test("feedback persistence: wrong-shape JSON yields empty bus, no throw", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    await writeFile(path, JSON.stringify({ unrelated: "thing" }), "utf-8");
    const t = silenceWarn(() => createFeedbackBus({ recordPath: path }));
    assert.equal(t.current(), "");

    await writeFile(path, JSON.stringify(["oops"]), "utf-8");
    const t2 = silenceWarn(() => createFeedbackBus({ recordPath: path }));
    assert.equal(t2.current(), "");
  } finally {
    await cleanup();
  }
});

test("feedback persistence: clear() persists empty state so next startup sees nothing", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const t1 = createFeedbackBus({ recordPath: path });
    t1.set("carry me");
    await t1.flush();
    t1.clear();
    await t1.flush();

    const t2 = createFeedbackBus({ recordPath: path });
    assert.equal(t2.current(), "");
  } finally {
    await cleanup();
  }
});

test("feedback persistence: in-memory only when no recordPath", async () => {
  const t = createFeedbackBus();
  t.set("x");
  await t.flush();
  assert.equal(t.current(), "x");
});

test("feedback persistence: simulates crash between set and consume", async () => {
  const { path, cleanup } = await tmpWorkspace();
  try {
    const t1 = createFeedbackBus({ recordPath: path });
    t1.set("feedback from dev run");
    await t1.flush();
    // No clear() — simulating a crash before Plan ran.

    const t2 = createFeedbackBus({ recordPath: path });
    assert.equal(t2.current(), "feedback from dev run");

    // Mirror what runCompass does: read current, then clear.
    const carried = t2.current();
    t2.clear();
    await t2.flush();

    const t3 = createFeedbackBus({ recordPath: path });
    assert.equal(t3.current(), "");
    assert.equal(carried, "feedback from dev run");
  } finally {
    await cleanup();
  }
});

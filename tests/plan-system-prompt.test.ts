import { test } from "node:test";
import assert from "node:assert/strict";

import {
  buildPlanSystemPrompt,
  LESSONS_COMPACT_THRESHOLD_BYTES,
} from "../src/agents/prompts/plan-system.ts";

function baseContext(
  overrides: Partial<Parameters<typeof buildPlanSystemPrompt>[0]> = {},
) {
  return {
    stateJson: "{}",
    drafts: "",
    feedback: "",
    lessons: "",
    repoMap: "",
    ...overrides,
  };
}

test("plan system prompt: empty lessons → no compaction nudge", () => {
  const prompt = buildPlanSystemPrompt(baseContext());
  assert.equal(prompt.includes("Compaction nudge"), false);
});

test("plan system prompt: small lessons → no compaction nudge", () => {
  const prompt = buildPlanSystemPrompt(
    baseContext({ lessons: "- one short bullet\n- another\n" }),
  );
  assert.equal(prompt.includes("Compaction nudge"), false);
});

test("plan system prompt: lessons exactly at threshold → no nudge (boundary)", () => {
  const lessons = "x".repeat(LESSONS_COMPACT_THRESHOLD_BYTES);
  const prompt = buildPlanSystemPrompt(baseContext({ lessons }));
  assert.equal(prompt.includes("Compaction nudge"), false);
});

test("plan system prompt: lessons just over threshold → nudge appears with byte count", () => {
  const lessons = "x".repeat(LESSONS_COMPACT_THRESHOLD_BYTES + 1);
  const prompt = buildPlanSystemPrompt(baseContext({ lessons }));
  assert.ok(prompt.includes("Compaction nudge"));
  assert.ok(prompt.includes(String(LESSONS_COMPACT_THRESHOLD_BYTES + 1)));
  assert.ok(prompt.includes("set_lessons"));
});

test("plan system prompt: multibyte chars are counted as UTF-8 bytes, not JS chars", () => {
  // The grinning-face emoji is 4 UTF-8 bytes but 2 JS code units. We need
  // bytes > threshold but chars <= threshold to prove we use Buffer.byteLength.
  const emojiCount = Math.ceil((LESSONS_COMPACT_THRESHOLD_BYTES + 1) / 4);
  const lessons = "\u{1F600}".repeat(emojiCount);
  assert.ok(Buffer.byteLength(lessons, "utf-8") > LESSONS_COMPACT_THRESHOLD_BYTES);
  assert.ok(lessons.length <= LESSONS_COMPACT_THRESHOLD_BYTES);

  const prompt = buildPlanSystemPrompt(baseContext({ lessons }));
  assert.ok(prompt.includes("Compaction nudge"));
});

test("plan system prompt: nudge sits between lessons block and drafts heading", () => {
  const lessons = "x".repeat(LESSONS_COMPACT_THRESHOLD_BYTES + 1);
  const prompt = buildPlanSystemPrompt(baseContext({ lessons }));

  const lessonsHeadingIdx = prompt.indexOf("## Lessons");
  const nudgeIdx = prompt.indexOf("Compaction nudge");
  const draftsHeadingIdx = prompt.indexOf("## Drafts");

  assert.notEqual(lessonsHeadingIdx, -1);
  assert.notEqual(nudgeIdx, -1);
  assert.notEqual(draftsHeadingIdx, -1);
  assert.ok(nudgeIdx > lessonsHeadingIdx);
  assert.ok(nudgeIdx < draftsHeadingIdx);
});

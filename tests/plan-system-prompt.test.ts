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
    vision: "",
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

test("plan system prompt: empty vision renders the placeholder", () => {
  const prompt = buildPlanSystemPrompt(baseContext());
  assert.ok(prompt.includes("## Vision"));
  assert.ok(prompt.includes("no vision set"));
});

test("plan system prompt: non-empty vision is included verbatim", () => {
  const vision = "Build a recursive iteration tool. Stay simple.";
  const prompt = buildPlanSystemPrompt(baseContext({ vision }));
  assert.ok(prompt.includes(vision));
  assert.equal(prompt.includes("no vision set"), false);
});

test("plan system prompt: vision is marked as user-owned and read-only", () => {
  const prompt = buildPlanSystemPrompt(baseContext({ vision: "ship it" }));
  // The agent must understand it cannot edit the file.
  assert.ok(/CANNOT edit/i.test(prompt) || /read-only/i.test(prompt));
});

test("plan system prompt: vision section comes before the state block", () => {
  const prompt = buildPlanSystemPrompt(baseContext({ vision: "north star" }));
  const visionIdx = prompt.indexOf("## Vision");
  const stateIdx = prompt.indexOf("## state.json");
  assert.notEqual(visionIdx, -1);
  assert.notEqual(stateIdx, -1);
  assert.ok(visionIdx < stateIdx);
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

test("plan system prompt: volatile sections come after stable instructional sections", () => {
  // Cache-prefix invariant: stable instructional content must precede the
  // per-iteration volatile blocks (state.json, repo map, drafts, feedback)
  // so the SDK's prompt cache can hit on the stable prefix.
  const prompt = buildPlanSystemPrompt(baseContext());
  const stateIdx = prompt.indexOf("## state.json");
  const stableHeadings = [
    "## Vision",
    "## Tools you must use",
    "## Three horizons",
    "## Lessons",
    "## Your job, every iteration",
    "## Idling is rare",
    "## Hard rules",
  ];
  for (const h of stableHeadings) {
    assert.ok(
      prompt.indexOf(h) < stateIdx,
      `stable heading "${h}" must appear before the volatile state.json block`,
    );
  }

  const volatileHeadings = [
    "## state.json",
    "## Drafts",
    "## Feedback",
  ];
  let lastIdx = -1;
  for (const h of volatileHeadings) {
    const idx = prompt.indexOf(h);
    assert.notEqual(idx, -1, `missing heading: ${h}`);
    assert.ok(idx > lastIdx, `${h} appears out of order in the volatile zone`);
    lastIdx = idx;
  }
});

test("plan system prompt: schema block names immediate/midTerm/longTerm", () => {
  const prompt = buildPlanSystemPrompt(baseContext());
  assert.ok(prompt.includes('"immediate"'));
  assert.ok(prompt.includes('"midTerm"'));
  assert.ok(prompt.includes('"longTerm"'));
  assert.equal(prompt.includes('"followUp"'), false);
});

test("plan system prompt: three horizons section explains all three tiers", () => {
  const prompt = buildPlanSystemPrompt(baseContext());
  const horizonsIdx = prompt.indexOf("## Three horizons");
  assert.notEqual(horizonsIdx, -1);
  // The section names each horizon and explains its purpose.
  const section = prompt.slice(horizonsIdx);
  assert.ok(/\*\*Immediate\*\*/.test(section));
  assert.ok(/\*\*Mid-term\*\*/.test(section));
  assert.ok(/\*\*Long-term\*\*/.test(section));
});

import { test } from "node:test";
import assert from "node:assert/strict";

import { buildDevSystemPrompt } from "../src/agents/prompts/dev-system.ts";
import type { PlanNext } from "../src/state/types.ts";

function baseContext(
  overrides: Partial<Parameters<typeof buildDevSystemPrompt>[0]> = {},
) {
  const next: PlanNext = { plan: "Default plan body.", verify: "npm test" };
  return {
    next,
    lessons: "",
    vision: "",
    repoIndex: "",
    ...overrides,
  };
}

test("dev system prompt: empty lessons → fallback rendered", () => {
  const prompt = buildDevSystemPrompt(baseContext({ lessons: "" }));
  assert.ok(prompt.includes("_(no lessons recorded yet)_"));
});

test("dev system prompt: whitespace-only lessons → fallback rendered", () => {
  const prompt = buildDevSystemPrompt(baseContext({ lessons: "   \n\t  \n" }));
  assert.ok(prompt.includes("_(no lessons recorded yet)_"));
});

test("dev system prompt: non-empty lessons → rendered verbatim, fallback absent", () => {
  const lessons = "## Section A\n- bullet one\n- bullet two\n";
  const prompt = buildDevSystemPrompt(baseContext({ lessons }));
  assert.ok(prompt.includes("## Section A"));
  assert.ok(prompt.includes("- bullet one"));
  assert.ok(prompt.includes("- bullet two"));
  assert.equal(prompt.includes("_(no lessons recorded yet)_"), false);
});

test("dev system prompt: next.plan content is rendered", () => {
  const next: PlanNext = {
    plan: "Refactor the widget renderer to use the new API.",
    verify: "npm test",
  };
  const prompt = buildDevSystemPrompt(baseContext({ next }));
  assert.ok(prompt.includes("Refactor the widget renderer to use the new API."));
});

test("dev system prompt: next.verify is rendered inside a fenced code block", () => {
  const next: PlanNext = { plan: "x", verify: "npm run build && npm test" };
  const prompt = buildDevSystemPrompt(baseContext({ next }));
  // The template wraps verify in ```\n…\n``` — assert that exact framing.
  assert.ok(prompt.includes("```\nnpm run build && npm test\n```"));
});

test("dev system prompt: lessons render inside a fenced code block", () => {
  const lessons = "- gotcha one\n- gotcha two";
  const prompt = buildDevSystemPrompt(baseContext({ lessons }));
  // Lessons section uses ```\n…\n``` framing too.
  assert.ok(prompt.includes("```\n- gotcha one\n- gotcha two\n```"));
});

test("dev system prompt: special chars in plan are NOT escaped", () => {
  const next: PlanNext = {
    plan: "Run `npm test` and check $HOME and ${VAR}; also use ```triple backticks``` if needed.",
    verify: "true",
  };
  const prompt = buildDevSystemPrompt(baseContext({ next }));
  assert.ok(prompt.includes("`npm test`"));
  assert.ok(prompt.includes("$HOME"));
  assert.ok(prompt.includes("${VAR}"));
  assert.ok(prompt.includes("```triple backticks```"));
});

test("dev system prompt: multi-line plan preserves newlines", () => {
  const next: PlanNext = {
    plan: "Step 1: do the thing.\nStep 2: do the next thing.\n\nStep 3: ship.",
    verify: "true",
  };
  const prompt = buildDevSystemPrompt(baseContext({ next }));
  assert.ok(prompt.includes("Step 1: do the thing.\nStep 2: do the next thing."));
  assert.ok(prompt.includes("Step 2: do the next thing.\n\nStep 3: ship."));
});

test("dev system prompt: required sections appear in canonical order", () => {
  const prompt = buildDevSystemPrompt(baseContext());
  // Stable instructional sections come first (cacheable across turns/iterations);
  // volatile per-iteration sections (plan body, verify command) come last.
  const headings = [
    "## Tools you must use",
    "## Vision",
    "## Lessons (long-term memory)",
    "## Workflow",
    "## Post-checks (enforced by the runner, AFTER `complete`)",
    "## Hard rules",
    "## The plan to implement",
    "## Verify command",
  ];
  let lastIdx = -1;
  for (const h of headings) {
    const idx = prompt.indexOf(h);
    assert.notEqual(idx, -1, `missing heading: ${h}`);
    assert.ok(idx > lastIdx, `${h} appears out of order`);
    lastIdx = idx;
  }
});

test("dev system prompt: volatile sections (plan, verify) come after stable instructional sections", () => {
  // The whole point of the reorder is cache-prefix wins. If something stable
  // ever drifts below the volatile zone, this test should fail.
  const prompt = buildDevSystemPrompt(baseContext());
  const planIdx = prompt.indexOf("## The plan to implement");
  const stableHeadings = [
    "## Tools you must use",
    "## Vision",
    "## Lessons (long-term memory)",
    "## Workflow",
    "## Post-checks (enforced by the runner, AFTER `complete`)",
    "## Hard rules",
  ];
  for (const h of stableHeadings) {
    assert.ok(
      prompt.indexOf(h) < planIdx,
      `stable heading "${h}" must appear before the volatile plan body`,
    );
  }
});

test("dev system prompt: empty vision renders the placeholder", () => {
  const prompt = buildDevSystemPrompt(baseContext());
  assert.ok(prompt.includes("## Vision"));
  assert.ok(prompt.includes("no vision set"));
});

test("dev system prompt: non-empty vision is included verbatim", () => {
  const vision = "Recursive iteration tool. Plan/Develop loop. Stay simple.";
  const prompt = buildDevSystemPrompt(baseContext({ vision }));
  assert.ok(prompt.includes(vision));
  assert.equal(prompt.includes("no vision set"), false);
});

test("dev system prompt: vision is marked read-only for the agent", () => {
  const prompt = buildDevSystemPrompt(baseContext({ vision: "ship it" }));
  assert.ok(/CANNOT edit/i.test(prompt) || /read-only/i.test(prompt));
});

test("dev system prompt: explicitly names the complete + lessons MCP tools", () => {
  const prompt = buildDevSystemPrompt(baseContext());
  assert.ok(prompt.includes("`complete({ feedback, bypassVerify? })`"));
  assert.ok(prompt.includes("`read_lessons()`"));
  assert.ok(prompt.includes("`set_lessons(text)`"));
  assert.ok(prompt.includes("`append_lesson(text)`"));
});

test("dev system prompt: documents bypassVerify on complete", () => {
  const prompt = buildDevSystemPrompt(baseContext());
  assert.ok(prompt.includes("bypassVerify"));
  // Should explain when to use it and that the clean-tree check still applies.
  assert.ok(/clean-tree.*still applies/i.test(prompt));
});

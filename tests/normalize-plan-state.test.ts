import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  normalizePlanState,
  readPlanState,
  StateParseError,
  getWorkspaceConfig,
} from "../src/mcp/utils/workspace.ts";

async function tmpWorkspace(): Promise<{
  dir: string;
  config: ReturnType<typeof getWorkspaceConfig>;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-test-"));
  const config = getWorkspaceConfig(dir);
  await mkdir(config.workspacePath, { recursive: true });
  return {
    dir,
    config,
    cleanup: () => rm(dir, { recursive: true, force: true }),
  };
}

test("normalizePlanState: valid empty state", () => {
  const result = normalizePlanState({
    completed: [],
    immediate: null,
    midTerm: "",
    longTerm: "",
  });
  assert.deepEqual(result, {
    completed: [],
    immediate: null,
    midTerm: "",
    longTerm: "",
  });
});

test("normalizePlanState: valid populated state", () => {
  const result = normalizePlanState({
    completed: ["did a thing", "did another thing"],
    immediate: { plan: "do thing", verify: "npm test" },
    midTerm: "next few iterations",
    longTerm: "strategic arc",
  });
  assert.deepEqual(result, {
    completed: ["did a thing", "did another thing"],
    immediate: { plan: "do thing", verify: "npm test" },
    midTerm: "next few iterations",
    longTerm: "strategic arc",
  });
});

test("normalizePlanState: trims plan and verify", () => {
  const result = normalizePlanState({
    completed: [],
    immediate: { plan: "  plan  ", verify: "  npm test  " },
    midTerm: "",
    longTerm: "",
  });
  assert.deepEqual(result?.immediate, { plan: "plan", verify: "npm test" });
});

test("normalizePlanState: rejects non-array completed", () => {
  assert.equal(
    normalizePlanState({
      completed: "not an array",
      immediate: null,
      midTerm: "",
      longTerm: "",
    }),
    null
  );
});

test("normalizePlanState: rejects immediate without plan/verify", () => {
  assert.equal(
    normalizePlanState({
      completed: [],
      immediate: { plan: "" },
      midTerm: "",
      longTerm: "",
    }),
    null
  );
  assert.equal(
    normalizePlanState({
      completed: [],
      immediate: { plan: "x", verify: "" },
      midTerm: "",
      longTerm: "",
    }),
    null
  );
});

test("normalizePlanState: rejects null/non-object input", () => {
  assert.equal(normalizePlanState(null), null);
  assert.equal(normalizePlanState("string"), null);
  assert.equal(normalizePlanState(42), null);
});

test("normalizePlanState: rejects unexpected immediate type", () => {
  assert.equal(
    normalizePlanState({
      completed: [],
      immediate: "weird",
      midTerm: "",
      longTerm: "",
    }),
    null
  );
});

test("normalizePlanState: filters non-string completed entries", () => {
  const r = normalizePlanState({
    completed: ["a", 1, null, "b"],
    immediate: null,
    midTerm: "",
    longTerm: "",
  });
  assert.deepEqual(r?.completed, ["a", "b"]);
});

test("normalizePlanState: defaults missing midTerm/longTerm to empty string", () => {
  const r = normalizePlanState({
    completed: [],
    immediate: null,
  });
  assert.deepEqual(r, {
    completed: [],
    immediate: null,
    midTerm: "",
    longTerm: "",
  });
});

test("normalizePlanState: ignores legacy `next` and `followUp` fields", () => {
  // Hard cut: the renamed schema does not auto-migrate. Legacy keys are
  // silently dropped (their values are unreachable through the new shape).
  const r = normalizePlanState({
    completed: [],
    next: { plan: "legacy", verify: "npm test" },
    followUp: "legacy followup",
  });
  assert.deepEqual(r, {
    completed: [],
    immediate: null,
    midTerm: "",
    longTerm: "",
  });
});

test("readPlanState: missing file returns EMPTY", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    const result = await readPlanState(config);
    assert.deepEqual(result, {
      completed: [],
      immediate: null,
      midTerm: "",
      longTerm: "",
    });
  } finally {
    await cleanup();
  }
});

test("readPlanState: empty file returns EMPTY", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(config.statePath, "", "utf-8");
    const result = await readPlanState(config);
    assert.deepEqual(result, {
      completed: [],
      immediate: null,
      midTerm: "",
      longTerm: "",
    });

    await writeFile(config.statePath, "   \n  \n", "utf-8");
    const result2 = await readPlanState(config);
    assert.deepEqual(result2, {
      completed: [],
      immediate: null,
      midTerm: "",
      longTerm: "",
    });
  } finally {
    await cleanup();
  }
});

test("readPlanState: invalid JSON throws StateParseError (does NOT silently empty)", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(config.statePath, "{ not valid json", "utf-8");
    await assert.rejects(() => readPlanState(config), (err) => {
      assert.ok(err instanceof StateParseError);
      assert.equal(err.path, config.statePath);
      assert.match(err.raw, /not valid json/);
      return true;
    });
  } finally {
    await cleanup();
  }
});

test("readPlanState: shape-invalid JSON throws StateParseError", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      config.statePath,
      JSON.stringify({
        completed: "not an array",
        immediate: null,
        midTerm: "",
        longTerm: "",
      }),
      "utf-8"
    );
    await assert.rejects(() => readPlanState(config), StateParseError);
  } finally {
    await cleanup();
  }
});

test("readPlanState: parses valid state file", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      config.statePath,
      JSON.stringify({
        completed: ["x"],
        immediate: { plan: "y", verify: "z" },
        midTerm: "more",
        longTerm: "horizon",
      }),
      "utf-8"
    );
    const result = await readPlanState(config);
    assert.deepEqual(result, {
      completed: ["x"],
      immediate: { plan: "y", verify: "z" },
      midTerm: "more",
      longTerm: "horizon",
    });
  } finally {
    await cleanup();
  }
});

test("normalizePlanState: accepts positive verifyTimeoutMs", () => {
  const result = normalizePlanState({
    completed: [],
    immediate: { plan: "x", verify: "y", verifyTimeoutMs: 60000 },
    midTerm: "",
    longTerm: "",
  });
  assert.deepEqual(result?.immediate, {
    plan: "x",
    verify: "y",
    verifyTimeoutMs: 60000,
  });
});

test("normalizePlanState: omits verifyTimeoutMs when absent", () => {
  const result = normalizePlanState({
    completed: [],
    immediate: { plan: "x", verify: "y" },
    midTerm: "",
    longTerm: "",
  });
  assert.deepEqual(result?.immediate, { plan: "x", verify: "y" });
  assert.ok(result?.immediate);
  assert.equal(
    Object.prototype.hasOwnProperty.call(result.immediate, "verifyTimeoutMs"),
    false
  );
});

test("normalizePlanState: drops zero/negative/non-integer/non-finite verifyTimeoutMs", () => {
  for (const bad of [0, -100, 1.5, Infinity]) {
    const result = normalizePlanState({
      completed: [],
      immediate: { plan: "x", verify: "y", verifyTimeoutMs: bad },
      midTerm: "",
      longTerm: "",
    });
    assert.deepEqual(
      result?.immediate,
      { plan: "x", verify: "y" },
      `expected verifyTimeoutMs=${bad} to be dropped`
    );
    assert.ok(result?.immediate);
    assert.equal(
      Object.prototype.hasOwnProperty.call(result.immediate, "verifyTimeoutMs"),
      false,
      `expected verifyTimeoutMs key absent for bad value ${bad}`
    );
  }
});

test("normalizePlanState: drops non-numeric verifyTimeoutMs", () => {
  const result = normalizePlanState({
    completed: [],
    immediate: { plan: "x", verify: "y", verifyTimeoutMs: "60000" },
    midTerm: "",
    longTerm: "",
  });
  assert.deepEqual(result?.immediate, { plan: "x", verify: "y" });
  assert.ok(result?.immediate);
  assert.equal(
    Object.prototype.hasOwnProperty.call(result.immediate, "verifyTimeoutMs"),
    false
  );
});

test("readPlanState: round-trips verifyTimeoutMs from disk", async () => {
  const { config, cleanup } = await tmpWorkspace();
  try {
    await writeFile(
      config.statePath,
      JSON.stringify({
        completed: ["x"],
        immediate: { plan: "y", verify: "z", verifyTimeoutMs: 120000 },
        midTerm: "more",
        longTerm: "horizon",
      }),
      "utf-8"
    );
    const result = await readPlanState(config);
    assert.deepEqual(result, {
      completed: ["x"],
      immediate: { plan: "y", verify: "z", verifyTimeoutMs: 120000 },
      midTerm: "more",
      longTerm: "horizon",
    });
  } finally {
    await cleanup();
  }
});

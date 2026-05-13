import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  runCompass,
  type CompassAgentRunners,
} from "../src/cli/commands.ts";
import { createLoopController } from "../src/state/control.ts";
import { createSessionTracker } from "../src/state/sessions.ts";
import type { PlanState } from "../src/state/types.ts";
import { createOutputManager } from "../src/web/output-manager.ts";
import {
  appendDraft,
  readLoopControlStatus,
} from "../src/mcp/utils/workspace.ts";
import { initializeWorkspace } from "../src/state/workspace.ts";
import { commit, initRepo } from "../src/mcp/utils/git.ts";

function git(cwd: string, args: string[]): string {
  const r = spawnSync("git", args, { cwd, encoding: "utf-8" });
  if (r.status !== 0) {
    throw new Error(`git ${args.join(" ")} failed: ${r.stderr}`);
  }
  return r.stdout.trim();
}

async function testRepo(): Promise<{
  dir: string;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-loop-"));
  await initRepo(dir);
  git(dir, ["config", "--local", "user.email", "test@compass.local"]);
  git(dir, ["config", "--local", "user.name", "Compass Test"]);
  await writeFile(join(dir, "README.md"), "# Test\n", "utf-8");
  await commit(dir, "initial");
  return { dir, cleanup: () => rm(dir, { recursive: true, force: true }) };
}

function withoutReflect<T>(fn: () => Promise<T>): Promise<T> {
  const prev = process.env.COMPASS_REFLECT_EVERY;
  process.env.COMPASS_REFLECT_EVERY = "0";
  return fn().finally(() => {
    if (prev === undefined) delete process.env.COMPASS_REFLECT_EVERY;
    else process.env.COMPASS_REFLECT_EVERY = prev;
  });
}

test("runCompass: fake Plan/Develop ship one iteration and thread feedback", async () => {
  await withoutReflect(async () => {
    const { dir, cleanup } = await testRepo();
    try {
      const config = await initializeWorkspace(dir);
      await appendDraft(config, "Add the thing");

      const abort = new AbortController();
      let planCalls = 0;
      let developCalls = 0;
      let secondPlanFeedback = "";

      const firstState: PlanState = {
        completed: [],
        immediate: {
          plan: "Implement the fake thing",
          verify: "npm test",
          estimatedDifficulty: "low",
        },
        midTerm: "",
        longTerm: "",
      };

      const agents: Partial<CompassAgentRunners> = {
        plan: async (_config, input) => {
          planCalls++;
          if (planCalls === 1) {
            assert.match(input.drafts, /Add the thing/);
            return { cancelled: false, state: firstState };
          }
          secondPlanFeedback = input.feedback;
          abort.abort();
          return {
            cancelled: false,
            state: {
              completed: ["fake thing shipped"],
              immediate: null,
              midTerm: "",
              longTerm: "",
            },
          };
        },
        develop: async (_config, next) => {
          developCalls++;
          assert.equal(next.plan, "Implement the fake thing");
          assert.equal(next.estimatedDifficulty, "low");
          return {
            succeeded: true,
            cancelled: false,
            issues: [],
            verifyOutput: null,
            feedback: "Develop shipped the fake thing.",
          };
        },
      };

      const sessions = createSessionTracker();
      await runCompass(dir, {
        output: createOutputManager(),
        controller: createLoopController({ approveRequired: false }),
        sessions,
        codexSidecar: { mode: "off" },
        signal: abort.signal,
        agents,
      });

      assert.equal(planCalls, 2);
      assert.equal(developCalls, 1);
      assert.equal(secondPlanFeedback, "Develop shipped the fake thing.");
      assert.deepEqual(
        sessions.all().map((s) => s.status),
        ["succeeded", "skipped"]
      );
      const controlStatus = await readLoopControlStatus(config);
      assert.equal(controlStatus?.status.phase, "idle");
      assert.equal(controlStatus?.status.session, 2);
      assert.equal(controlStatus?.status.cancellationRequested, false);
    } finally {
      await cleanup();
    }
  });
});

test("runCompass: fake Develop failure records notes and verify output", async () => {
  await withoutReflect(async () => {
    const { dir, cleanup } = await testRepo();
    try {
      const config = await initializeWorkspace(dir);
      await appendDraft(config, "Break predictably");

      const abort = new AbortController();
      let planCalls = 0;

      const agents: Partial<CompassAgentRunners> = {
        plan: async () => {
          planCalls++;
          if (planCalls === 1) {
            return {
              cancelled: false,
              state: {
                completed: [],
                immediate: { plan: "fail once", verify: "npm test" },
                midTerm: "",
                longTerm: "",
              },
            };
          }
          abort.abort();
          return {
            cancelled: false,
            state: { completed: [], immediate: null, midTerm: "", longTerm: "" },
          };
        },
        develop: async () => ({
          succeeded: false,
          cancelled: false,
          issues: ["fake issue"],
          verifyOutput: {
            command: "npm test",
            exitCode: 1,
            tail: "expected failure",
          },
          feedback: "Develop could not ship.",
        }),
      };

      const sessions = createSessionTracker();
      await runCompass(dir, {
        output: createOutputManager(),
        controller: createLoopController({ approveRequired: false }),
        sessions,
        codexSidecar: { mode: "off" },
        signal: abort.signal,
        agents,
      });

      const failed = sessions.all()[0]!;
      assert.equal(failed.status, "failed");
      assert.deepEqual(failed.notes, ["fake issue"]);
      assert.deepEqual(failed.verifyOutput, {
        command: "npm test",
        exitCode: 1,
        tail: "expected failure",
      });
      assert.equal(failed.feedback, "Develop could not ship.");
    } finally {
      await cleanup();
    }
  });
});

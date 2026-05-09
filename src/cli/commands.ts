import { watch } from "node:fs";
import { initializeWorkspace } from "../state/workspace.js";
import { runPlanAgent } from "../agents/plan.js";
import { runDevAgent } from "../agents/dev.js";
import {
  readDrafts,
  readPlanState,
  getWorkspaceConfig,
  snapshotAndClearDrafts,
  snapshotAndClearFeedback,
} from "../mcp/utils/workspace.js";
import type { WorkspaceConfig } from "../state/types.js";
import type { OutputManager } from "../web/output-manager.js";

export interface RunOptions {
  output: OutputManager;
  /** Abort signal to stop the loop on shutdown. */
  signal?: AbortSignal;
}

export async function runCompass(
  cwd: string,
  options: RunOptions
): Promise<void> {
  const output = options.output;
  const signal = options.signal;

  output.info("Compass — Plan + Develop loop\n");

  const config = await initializeWorkspace(cwd);

  output.info(`Repo:      ${config.implRepoPath}`);
  output.info(`Workspace: ${config.workspacePath}\n`);

  let iteration = 0;

  while (!signal?.aborted) {
    if (!(await hasWork(config))) {
      output.info("Idle — waiting for drafts. Add one in the UI to get started.");
      const woke = await waitForWork(config, signal);
      if (!woke) break; // aborted
      continue;
    }

    iteration++;
    output.session(iteration);

    output.phase("Plan");

    // Race-free handoff: rotate drafts/feedback into snapshots before Plan starts.
    const drafts = await snapshotAndClearDrafts(config);
    const feedback = await snapshotAndClearFeedback(config);

    const planResult = await runPlanAgent(config, { drafts, feedback }, output);

    if (planResult.done) {
      output.info(
        `\nPlan signaled done${planResult.doneReason ? `: ${planResult.doneReason}` : ""}.`
      );
      continue;
    }

    const state = await readPlanState(config);
    if (!state.next) {
      output.info(
        "\nPlan finished but state.json has no next. Idling until drafts arrive."
      );
      continue;
    }

    output.phase("Develop");
    output.info(`Plan: ${state.next.plan.split("\n")[0].slice(0, 200)}`);
    output.info(`Verify: ${state.next.verify}`);
    await runDevAgent(config, state.next, output);
  }

  output.info("\nLoop stopped.");
}

async function hasWork(config: WorkspaceConfig): Promise<boolean> {
  const drafts = await readDrafts(config);
  if (drafts.trim().length > 0) return true;

  const state = await readPlanState(config);
  return state.next !== null;
}

/**
 * Block until either work appears in the workspace or the abort signal fires.
 * Uses fs.watch on the workspace directory, with a defensive re-check window so we
 * don't miss writes that race the watcher setup.
 */
async function waitForWork(
  config: WorkspaceConfig,
  signal: AbortSignal | undefined
): Promise<boolean> {
  if (await hasWork(config)) return true;

  return new Promise<boolean>((resolve) => {
    let settled = false;

    const settle = (val: boolean) => {
      if (settled) return;
      settled = true;
      try {
        watcher.close();
      } catch {
        // ignore
      }
      signal?.removeEventListener("abort", onAbort);
      resolve(val);
    };

    const onAbort = () => settle(false);

    if (signal?.aborted) {
      resolve(false);
      return;
    }
    signal?.addEventListener("abort", onAbort, { once: true });

    const watcher = watch(config.workspacePath, { persistent: false }, () => {
      void hasWork(config).then((work) => {
        if (work) settle(true);
      });
    });

    watcher.on("error", () => {
      // Fall back: settle on next hasWork tick rather than spinning.
      void hasWork(config).then((work) => settle(work));
    });

    // Defensive: re-check once shortly after attaching the watcher in case a write
    // landed between our initial hasWork() and watch() returning.
    setTimeout(() => {
      void hasWork(config).then((work) => {
        if (work) settle(true);
      });
    }, 100);
  });
}

export async function showStatus(cwd: string): Promise<void> {
  const config = getWorkspaceConfig(cwd);
  const state = await readPlanState(config);
  const drafts = await readDrafts(config);

  console.log("Compass status\n");
  console.log(`Workspace: ${config.workspacePath}\n`);

  console.log("--- Completed ---");
  if (state.completed.length === 0) {
    console.log("(none)");
  } else {
    for (const c of state.completed) console.log(`- ${c}`);
  }
  console.log();

  console.log("--- Next ---");
  if (state.next) {
    console.log(state.next.plan);
    console.log(`\n[verify] ${state.next.verify}`);
  } else {
    console.log("(none)");
  }
  console.log();

  console.log("--- Follow-up ---");
  console.log(state.followUp.trim() || "(empty)");
  console.log();

  console.log("--- Drafts ---");
  console.log(drafts.trim() || "(empty)");
}

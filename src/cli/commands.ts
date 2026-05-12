import { watch } from "node:fs";
import { initializeWorkspace } from "../state/workspace.js";
import { runPlanAgent } from "../agents/plan.js";
import { runDevAgent } from "../agents/dev.js";
import { runReflectAgent } from "../agents/reflect.js";
import {
  readDrafts,
  readLessons,
  tryReadPlanState,
  backupStateFile,
  writePlanState,
  getWorkspaceConfig,
  snapshotAndClearDrafts,
} from "../mcp/utils/workspace.js";
import type { WorkspaceConfig } from "../state/types.js";
import type { OutputManager } from "../web/output-manager.js";
import type { LoopController } from "../state/control.js";
import type { SessionTracker } from "../state/sessions.js";
import { commitsBetween, tryGetCurrentCommit } from "../mcp/utils/git.js";

export interface RunOptions {
  output: OutputManager;
  controller: LoopController;
  sessions: SessionTracker;
  /** Abort signal to stop the loop on shutdown. */
  signal: AbortSignal;
}

const DEFAULT_REFLECT_EVERY = 5;
/** Window of past sessions handed to Reflect — roughly 2× the cadence. */
const REFLECT_SESSION_WINDOW = 10;

/**
 * How often Reflect runs, in iterations. `COMPASS_REFLECT_EVERY=0` disables.
 * Unparseable values fall back to the default rather than crashing the loop.
 */
function parseReflectEvery(): number {
  const raw = process.env.COMPASS_REFLECT_EVERY;
  if (raw === undefined || raw === "") return DEFAULT_REFLECT_EVERY;
  const parsed = parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 0) return DEFAULT_REFLECT_EVERY;
  return parsed;
}

export async function runCompass(
  cwd: string,
  options: RunOptions
): Promise<void> {
  const { output, controller, sessions, signal } = options;

  output.info("Compass — Plan + Develop loop\n");

  const config = await initializeWorkspace(cwd);

  output.info(`Repo:      ${config.implRepoPath}`);
  output.info(`Workspace: ${config.workspacePath}\n`);

  // Seed from prior persisted sessions so iteration counts continue across
  // restarts instead of resetting to 1.
  let iteration = sessions.all().reduce(
    (m, s) => Math.max(m, s.session),
    0
  );

  const reflectEvery = parseReflectEvery();
  if (reflectEvery > 0) {
    output.info(
      `Reflect cadence: every ${reflectEvery} iterations (set COMPASS_REFLECT_EVERY to override; 0 to disable).`
    );
  } else {
    output.info("Reflect disabled (COMPASS_REFLECT_EVERY=0).");
  }

  while (!signal.aborted) {
    if (!(await hasWork(config))) {
      controller.setPhase("idle");
      output.info("Idle — waiting for drafts. Add one in the UI to get started.");
      const woke = await waitForWork(config, signal);
      if (!woke) break;
      continue;
    }

    // Honour pause between iterations. If cancelled while paused, exit.
    if (controller.status().paused) {
      controller.setPhase("paused");
      const resumed = await controller.waitWhilePaused(signal);
      if (!resumed) {
        if (signal.aborted) break;
        continue;
      }
    }

    iteration++;
    controller.resetIteration();
    controller.setSession(iteration);
    output.session(iteration);

    sessions.start(iteration);

    const beforeSha = await tryGetCurrentCommit(config.implRepoPath);
    if (beforeSha) sessions.setBefore(beforeSha);

    // Backup state.json once per iteration, before any agent can mutate it.
    // Reflect (if it runs) and Plan both write state; one backup covers both.
    try {
      await backupStateFile(config);
    } catch (err) {
      output.error(`Could not back up state.json: ${err}`);
    }

    // ---- Reflect phase (every Nth iteration) -----------------------------
    if (reflectEvery > 0 && iteration % reflectEvery === 0) {
      controller.setPhase("planning");
      output.phase("Reflect");

      // Hand Reflect roughly twice its cadence in past sessions, most recent
      // first, excluding the in-flight record we just started.
      const all = sessions.all();
      const recentSessions = all
        .slice(0, all.length - 1)
        .slice(-REFLECT_SESSION_WINDOW)
        .reverse();

      const reflectSignal = controller.iterationSignal(signal);
      const reflectResult = await runReflectAgent(
        config,
        { recentSessions, iteration },
        output,
        { signal: reflectSignal }
      );

      if (reflectResult.cancelled) {
        sessions.end("cancelled");
        output.info("Iteration cancelled during Reflect.");
        continue;
      }

      if (reflectResult.state) {
        await writePlanState(config, reflectResult.state);
        output.info("Reflect updated state.json; Plan will see the revised midTerm/longTerm.");
      } else {
        output.info("Reflect: on course, no state changes.");
      }
    }

    // ---- Plan phase ------------------------------------------------------
    controller.setPhase("planning");
    output.phase("Plan");

    // Race-free handoff for drafts. Feedback now lives on the prior session
    // record; we pull it from there so the current in-flight record stays
    // empty until Develop calls set_feedback.
    const drafts = await snapshotAndClearDrafts(config);
    const carriedFeedback = sessions.previousFeedback();

    const planSignal = controller.iterationSignal(signal);
    const planResult = await runPlanAgent(
      config,
      { drafts, feedback: carriedFeedback },
      output,
      { signal: planSignal }
    );

    if (planResult.cancelled) {
      sessions.end("cancelled");
      output.info("Iteration cancelled.");
      continue;
    }

    let state;
    if (planResult.state) {
      await writePlanState(config, planResult.state);
      state = planResult.state;
    } else {
      output.info(
        "Plan finished without calling set_state; carrying forward existing state."
      );
      state = await tryReadPlanState(config);
    }

    if (!state.immediate) {
      sessions.end("skipped");
      output.info(
        "\nPlan finished but state has no immediate plan. Idling until drafts arrive."
      );
      continue;
    }

    sessions.setPlan(state.immediate.plan, state.immediate.verify);

    // ---- Approval gate ---------------------------------------------------
    if (controller.status().approveRequired) {
      controller.setPhase("awaiting_approval");
      sessions.setStatus("awaiting_approval");
      output.info("Waiting for approval before Develop runs. Approve in the UI to continue.");
      const approved = await controller.awaitApproval(state.immediate, signal);
      if (!approved) {
        sessions.end("cancelled");
        output.info("Iteration cancelled while awaiting approval.");
        continue;
      }
    }

    // Honour a pause that landed during Plan or while awaiting approval.
    // "after_iteration" mode skips this gate so Develop runs and the loop only
    // pauses once the iteration completes.
    {
      const status = controller.status();
      if (status.paused && status.pauseMode === "immediate") {
        controller.setPhase("paused");
        const resumed = await controller.waitWhilePaused(signal);
        if (!resumed) {
          sessions.end("cancelled");
          if (signal.aborted) break;
          continue;
        }
      }
    }

    // ---- Develop phase ---------------------------------------------------
    controller.setPhase("developing");
    sessions.setStatus("developing");
    output.phase("Develop");
    output.info(`Plan: ${state.immediate.plan.split("\n")[0].slice(0, 200)}`);
    output.info(`Verify: ${state.immediate.verify}`);

    const devSignal = controller.iterationSignal(signal);
    const devResult = await runDevAgent(config, state.immediate, output, {
      signal: devSignal,
    });

    if (devResult.feedback) {
      sessions.setFeedback(devResult.feedback);
    }

    // Record commits regardless of outcome (lets the user see partials too).
    const afterSha = await tryGetCurrentCommit(config.implRepoPath);
    if (afterSha) {
      const commits = await commitsBetween(
        config.implRepoPath,
        beforeSha,
        afterSha
      );
      sessions.setAfter(
        afterSha,
        commits.map((c) => ({ sha: c.sha, short: c.short, subject: c.subject }))
      );
    }

    if (devResult.cancelled) {
      sessions.end("cancelled");
      output.info("Develop cancelled.");
      continue;
    }
    if (devResult.succeeded) {
      sessions.end("succeeded");
    } else {
      if (devResult.verifyOutput) {
        sessions.setVerifyOutput(devResult.verifyOutput);
      }
      for (const issue of devResult.issues) sessions.addNote(issue);
      sessions.end("failed");
    }
  }

  controller.setPhase("idle");
  output.info("\nLoop stopped.");
}

async function hasWork(config: WorkspaceConfig): Promise<boolean> {
  const drafts = await readDrafts(config);
  if (drafts.trim().length > 0) return true;

  const state = await tryReadPlanState(config);
  return state.immediate !== null;
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
  const state = await tryReadPlanState(config);
  const drafts = await readDrafts(config);
  const lessons = await readLessons(config);

  console.log("Compass status\n");
  console.log(`Workspace: ${config.workspacePath}\n`);

  console.log("--- Completed ---");
  if (state.completed.length === 0) {
    console.log("(none)");
  } else {
    for (const c of state.completed) console.log(`- ${c}`);
  }
  console.log();

  console.log("--- Immediate ---");
  if (state.immediate) {
    console.log(state.immediate.plan);
    console.log(`\n[verify] ${state.immediate.verify}`);
  } else {
    console.log("(none)");
  }
  console.log();

  console.log("--- Mid-term ---");
  console.log(state.midTerm.trim() || "(empty)");
  console.log();

  console.log("--- Long-term ---");
  console.log(state.longTerm.trim() || "(empty)");
  console.log();

  console.log("--- Drafts ---");
  console.log(drafts.trim() || "(empty)");
  console.log();

  console.log("--- Lessons ---");
  console.log(lessons.trim() || "(empty)");
}

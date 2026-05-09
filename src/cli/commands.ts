import { initializeWorkspace } from "../state/workspace.js";
import { runPlanAgent } from "../agents/plan.js";
import { runDevAgent } from "../agents/dev.js";
import {
  readState,
  readDrafts,
  getWorkspaceConfig,
} from "../mcp/utils/workspace.js";
import type { WorkspaceConfig } from "../state/types.js";
import type { OutputManager } from "../web/output-manager.js";

export interface RunOptions {
  output: OutputManager;
  /** Polling interval (ms) when idle waiting for drafts. */
  idlePollMs?: number;
  /** Abort signal to stop the loop on shutdown. */
  signal?: AbortSignal;
}

export async function runCompass(
  cwd: string,
  options: RunOptions
): Promise<void> {
  const output = options.output;
  const idlePollMs = options.idlePollMs ?? 3000;
  const signal = options.signal;

  output.info("Compass — Plan + Develop loop\n");

  const config = await initializeWorkspace(cwd);

  output.info(`Repo:      ${config.implRepoPath}`);
  output.info(`Workspace: ${config.workspacePath}\n`);

  let iteration = 0;

  while (!signal?.aborted) {
    const haveWork = await hasWork(config);
    if (!haveWork) {
      output.info("Idle — waiting for drafts. Add one in the UI to get started.");
      const woke = await waitForWork(config, idlePollMs, signal);
      if (!woke) break; // aborted
      continue;
    }

    iteration++;
    output.session(iteration);

    output.phase("Plan");
    const planResult = await runPlanAgent(config, output);

    if (planResult.done) {
      output.info(
        `\nPlan signaled done${planResult.doneReason ? `: ${planResult.doneReason}` : ""}.`
      );
      // Drop into idle — drafts can wake us back up.
      continue;
    }

    const next = extractNext(await readState(config));
    if (!next) {
      output.info(
        "\nPlan finished but state.md has no Next. Idling until drafts arrive."
      );
      continue;
    }

    output.phase("Develop");
    output.info(`Plan: ${next.split("\n")[0].slice(0, 200)}`);
    await runDevAgent(config, next, output);
  }

  output.info("\nLoop stopped.");
}

async function hasWork(config: WorkspaceConfig): Promise<boolean> {
  const drafts = await readDrafts(config);
  if (drafts.trim().length > 0) return true;

  const next = extractNext(await readState(config));
  return next.length > 0;
}

async function waitForWork(
  config: WorkspaceConfig,
  pollMs: number,
  signal: AbortSignal | undefined
): Promise<boolean> {
  while (!signal?.aborted) {
    if (await hasWork(config)) return true;
    await sleep(pollMs, signal);
  }
  return false;
}

function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    if (signal?.aborted) return resolve();
    const t = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(t);
      resolve();
    };
    signal?.addEventListener("abort", onAbort, { once: true });
  });
}

/**
 * Extract the body under `## Next` from state.md. Trimmed; "" means no plan.
 */
export function extractNext(state: string): string {
  const lines = state.split("\n");
  const startIdx = lines.findIndex((l) => /^##\s+next\b/i.test(l.trim()));
  if (startIdx === -1) return "";

  const body: string[] = [];
  for (let i = startIdx + 1; i < lines.length; i++) {
    if (/^##\s+/.test(lines[i].trim())) break;
    body.push(lines[i]);
  }
  return body.join("\n").trim();
}

export async function showStatus(cwd: string): Promise<void> {
  const config = getWorkspaceConfig(cwd);
  const state = await readState(config);
  const drafts = await readDrafts(config);

  console.log("Compass status\n");
  console.log(`Workspace: ${config.workspacePath}\n`);

  console.log("--- state.md ---");
  console.log(state.trim() || "(empty)");
  console.log();

  console.log("--- drafts.md ---");
  console.log(drafts.trim() || "(empty)");
}

#!/usr/bin/env node

import { Command } from "commander";
import { CLI_NAME, CLI_VERSION, CLI_DESCRIPTION } from "./cli/config.js";
import { runCompass, showStatus } from "./cli/commands.js";
import { createOutputManager } from "./web/output-manager.js";
import { startWebServer } from "./web/server.js";
import { initializeWorkspace } from "./state/workspace.js";
import { hasUncommittedChanges, stashChanges } from "./mcp/utils/git.js";
import { createLoopController } from "./state/control.js";
import { createSessionTracker } from "./state/sessions.js";
import { acquireWorkspaceLock } from "./state/lock.js";
import { parseCodexSidecarMode } from "./agents/codex-sidecar.js";

const program = new Command();

program
  .name(CLI_NAME)
  .version(CLI_VERSION)
  .description(CLI_DESCRIPTION);

program
  .command("run", { isDefault: true })
  .description("Start the Plan + Develop loop, driven by drafts from the UI")
  .option(
    "--auto-stash",
    "Stash uncommitted changes on startup instead of refusing to start",
    false
  )
  .option(
    "--require-approval",
    "Require manual approval of each plan before Develop runs (default: auto-accept)",
    false
  )
  .option(
    "--codex-sidecar <mode>",
    "Optional Codex CLI sidecar mode: auto, verify-failures, diff-review, or off (default: auto, or COMPASS_CODEX_SIDECAR)",
    process.env.COMPASS_CODEX_SIDECAR ?? "auto"
  )
  .action(async (opts: {
    autoStash: boolean;
    requireApproval: boolean;
    codexSidecar: string;
  }) => {
    const cwd = process.cwd();
    const codexSidecar = {
      mode: parseCodexSidecarMode(opts.codexSidecar),
    };

    const config = await initializeWorkspace(cwd);

    // Refuse to run twice on the same workspace.
    const lockResult = await acquireWorkspaceLock(config.workspacePath);
    if (!lockResult.ok) {
      console.error(
        `Another compass process appears to be running (pid ${lockResult.pid}, ` +
          `pidfile ${lockResult.pidfilePath}). Stop it first, or remove the pidfile if it's stale.`
      );
      process.exit(1);
    }
    const lock = lockResult.lock;

    if (await hasUncommittedChanges(cwd)) {
      if (opts.autoStash) {
        console.log("Uncommitted changes — stashing as 'compass-auto-stash' (--auto-stash).");
        await stashChanges(cwd);
        console.log("Recover with: git stash list  /  git stash pop\n");
      } else {
        console.error(
          "Refusing to start: working tree has uncommitted changes."
        );
        console.error(
          "  - Commit or stash them yourself, OR"
        );
        console.error(
          "  - Re-run with --auto-stash to have Compass stash them for you."
        );
        await lock.release();
        process.exit(1);
      }
    }

    const output = createOutputManager({ sessionsDir: config.sessionsPath });
    const controller = createLoopController({
      approveRequired: opts.requireApproval,
    });
    const sessions = createSessionTracker({
      recordPath: config.sessionsRecordPath,
    });

    const server = await startWebServer({
      config,
      output,
      controller,
      sessions,
    });

    console.log(`\nCompass UI: ${server.url}`);
    console.log(
      `(URL contains a per-run access token; treat it like a password — anyone ` +
        `with the URL can run code via the Develop agent.)\n`
    );

    const abortController = new AbortController();
    let shuttingDown = false;
    const shutdown = async () => {
      if (shuttingDown) return;
      shuttingDown = true;
      output.info("\nShutting down...");
      abortController.abort();
      await sessions.flush();
      await server.close();
      await lock.release();
      process.exit(0);
    };

    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);

    // runCompass only returns when abortController fires, which is the same
    // signal the SIGINT/SIGTERM handlers raise. The loop itself never "exits"
    // on its own — when there's nothing to do it idles and waits for drafts.
    await runCompass(cwd, {
      output,
      controller,
      sessions,
      codexSidecar,
      signal: abortController.signal,
    });
  });

program
  .command("status")
  .description("Show current state.json and drafts.md")
  .action(async () => {
    await showStatus(process.cwd());
  });

program.parse();

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
    "--no-approve-required",
    "Skip the approval gate before each Develop run (default: gate enabled)"
  )
  .action(async (opts: { autoStash: boolean; approveRequired: boolean }) => {
    const cwd = process.cwd();

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
      approveRequired: opts.approveRequired,
    });
    const sessions = createSessionTracker();

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
      await server.close();
      await lock.release();
      process.exit(0);
    };

    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);

    try {
      await runCompass(cwd, {
        output,
        controller,
        sessions,
        signal: abortController.signal,
      });
    } finally {
      output.info("Loop ended. Service still running. Press Ctrl+C to exit.");
    }
  });

program
  .command("status")
  .description("Show current state.json and drafts.md")
  .action(async () => {
    await showStatus(process.cwd());
  });

program.parse();

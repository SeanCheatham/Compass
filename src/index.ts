#!/usr/bin/env node

import { Command } from "commander";
import { CLI_NAME, CLI_VERSION, CLI_DESCRIPTION } from "./cli/config.js";
import { runCompass, showStatus } from "./cli/commands.js";
import { createOutputManager } from "./web/output-manager.js";
import { startWebServer } from "./web/server.js";
import { initializeWorkspace } from "./state/workspace.js";
import { hasUncommittedChanges, stashChanges } from "./mcp/utils/git.js";

const program = new Command();

program
  .name(CLI_NAME)
  .version(CLI_VERSION)
  .description(CLI_DESCRIPTION);

program
  .command("run", { isDefault: true })
  .description("Start the Plan + Develop loop, driven by drafts from the UI")
  .action(async () => {
    const cwd = process.cwd();

    const config = await initializeWorkspace(cwd);

    if (await hasUncommittedChanges(cwd)) {
      console.log("Stashing uncommitted changes...");
      await stashChanges(cwd);
    }

    const output = createOutputManager();

    const server = await startWebServer(config, output);
    console.log(`\nCompass UI: http://localhost:${server.port}\n`);

    const abortController = new AbortController();
    let shuttingDown = false;
    const shutdown = async () => {
      if (shuttingDown) return;
      shuttingDown = true;
      output.info("\nShutting down...");
      abortController.abort();
      await server.close();
      process.exit(0);
    };

    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);

    await runCompass(cwd, { output, signal: abortController.signal });

    output.info("Loop ended. Service still running. Press Ctrl+C to exit.");
  });

program
  .command("status")
  .description("Show current state.json and drafts.md")
  .action(async () => {
    await showStatus(process.cwd());
  });

program.parse();

#!/usr/bin/env node

import { Command } from "commander";
import { CLI_NAME, CLI_VERSION, CLI_DESCRIPTION } from "./cli/config.js";
import { runCompass, showStatus } from "./cli/commands.js";
import { createOutputManager } from "./web/output-manager.js";
import { startWebServer } from "./web/server.js";
import { initializeWorkspace, hasCompassFile } from "./state/workspace.js";
import { hasUncommittedChanges, stashChanges } from "./mcp/utils/git.js";

const program = new Command();

program
  .name(CLI_NAME)
  .version(CLI_VERSION)
  .description(CLI_DESCRIPTION);

program
  .command("run", { isDefault: true })
  .description("Start or continue autonomous development from COMPASS.md")
  .option("-m, --max-iterations <n>", "Maximum number of iterations", "100")
  .action(async (options) => {
    const maxIterations = parseInt(options.maxIterations, 10);
    const cwd = process.cwd();

    // Check for COMPASS.md first
    if (!(await hasCompassFile(cwd))) {
      console.error("Error: COMPASS.md not found in current directory.");
      console.error(
        "Create a COMPASS.md file with your project vision to get started."
      );
      process.exit(1);
    }

    // Initialize workspace to get config and compass content
    const { config, compassContent } = await initializeWorkspace(cwd);

    // Auto-stash uncommitted changes before proceeding
    if (await hasUncommittedChanges(cwd)) {
      console.log("Stashing uncommitted changes...");
      await stashChanges(cwd);
    }

    // Create output manager
    const output = createOutputManager();

    // Start web server
    const server = await startWebServer(
      config,
      compassContent,
      output
    );

    console.log(`\nCompass UI: http://localhost:${server.port}\n`);

    // Handle graceful shutdown
    const shutdown = async () => {
      output.info("\nShutting down...");
      await server.close();
      process.exit(0);
    };

    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);

    // Run compass with the output manager
    await runCompass(cwd, { maxIterations, output });

    // Keep service running after loop completes
    output.info("Compass loop finished. Service still running. Press Ctrl+C to exit.");
  });

program
  .command("status")
  .description("Show current plan status")
  .action(async () => {
    await showStatus(process.cwd());
  });

program.parse();

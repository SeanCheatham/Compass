#!/usr/bin/env node

import { Command } from "commander";
import { CLI_NAME, CLI_VERSION, CLI_DESCRIPTION } from "./cli/config.js";
import { runCompass, showStatus } from "./cli/commands.js";

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
    await runCompass(process.cwd(), { maxIterations });
  });

program
  .command("status")
  .description("Show current plan status")
  .action(async () => {
    await showStatus(process.cwd());
  });

program.parse();

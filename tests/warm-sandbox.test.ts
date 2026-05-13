import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  commit,
  createWorktreeBranch,
  deleteBranch,
  initRepo,
  removeWorktree,
} from "../src/mcp/utils/git.ts";
import {
  warmDevSandboxCaches,
  warmSandboxForTest,
} from "../src/agents/warm-sandbox.ts";

function git(cwd: string, args: string[]): string {
  const r = spawnSync("git", args, { cwd, encoding: "utf-8" });
  if (r.status !== 0) {
    throw new Error(
      `git ${args.join(" ")} failed (status ${r.status}): ${r.stderr}`
    );
  }
  return r.stdout.trim();
}

async function initializedRepo(): Promise<{
  dir: string;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-warm-sandbox-"));
  await initRepo(dir);
  git(dir, ["config", "--local", "user.email", "test@compass.local"]);
  git(dir, ["config", "--local", "user.name", "Compass Test"]);
  await writeFile(join(dir, ".gitkeep"), "", "utf-8");
  await commit(dir, "initial");
  return { dir, cleanup: () => rm(dir, { recursive: true, force: true }) };
}

function captureOutput(): {
  output: { info: (message: string) => void; error: (message: string) => void };
  messages: string[];
} {
  const messages: string[] = [];
  return {
    messages,
    output: {
      info: (message) => messages.push(`info:${message}`),
      error: (message) => messages.push(`error:${message}`),
    },
  };
}

test("warm sandbox spec defaults to auto and parses explicit modes", () => {
  const { parseWarmSandboxSpec } = warmSandboxForTest;

  assert.deepEqual(parseWarmSandboxSpec(undefined), {
    disabled: false,
    auto: true,
    entries: [],
    warnings: [],
  });
  assert.deepEqual(parseWarmSandboxSpec("off"), {
    disabled: true,
    auto: false,
    entries: [],
    warnings: [],
  });
  assert.deepEqual(parseWarmSandboxSpec("target,node_modules:clone,.venv:link"), {
    disabled: false,
    auto: false,
    entries: [
      { path: "target", mode: "link" },
      { path: "node_modules", mode: "clone" },
      { path: ".venv", mode: "link" },
    ],
    warnings: [],
  });
});

test("warm sandbox path normalization rejects escapes", () => {
  const { normalizeWarmPath } = warmSandboxForTest;

  assert.equal(normalizeWarmPath("target"), "target");
  assert.equal(normalizeWarmPath("foo/../target"), null);
  assert.equal(normalizeWarmPath("../target"), null);
  assert.equal(normalizeWarmPath("/tmp/target"), null);
});

test("warm sandbox auto mode shares Rust target by symlink", async () => {
  const { dir, cleanup } = await initializedRepo();
  const parent = await mkdtemp(join(tmpdir(), "compass-warm-worktree-"));
  const worktree = join(parent, "wt");
  const branch = "compass/test-warm-target";
  const { output, messages } = captureOutput();

  try {
    await writeFile(join(dir, ".gitignore"), "/target/\n", "utf-8");
    await writeFile(join(dir, "Cargo.toml"), "[workspace]\n", "utf-8");
    await mkdir(join(dir, "target", "debug"), { recursive: true });
    await writeFile(join(dir, "target", "debug", "cache.txt"), "warm", "utf-8");
    await commit(dir, "add rust workspace");
    const head = git(dir, ["rev-parse", "HEAD"]);

    await createWorktreeBranch(dir, worktree, branch, head);
    await warmDevSandboxCaches({
      mainRepoPath: dir,
      worktreePath: worktree,
      output,
      env: { COMPASS_WARM_SANDBOX: "auto" },
      platform: "darwin",
    });

    assert.equal((await lstat(join(worktree, "target"))).isDirectory(), true);
    assert.equal(
      (await lstat(join(worktree, "target", "debug"))).isSymbolicLink(),
      true
    );
    assert.equal(
      await readFile(join(worktree, "target", "debug", "cache.txt"), "utf-8"),
      "warm"
    );
    assert.ok(
      messages.some((m) => m.includes("Warm sandbox: shared target via symlinks")),
      messages.join("\n")
    );
  } finally {
    await removeWorktree(dir, worktree).catch(() => {});
    await deleteBranch(dir, branch).catch(() => {});
    await rm(parent, { recursive: true, force: true });
    await cleanup();
  }
});

test(
  "warm sandbox auto mode APFS-clones node_modules on macOS",
  { skip: process.platform !== "darwin" },
  async () => {
    const { dir, cleanup } = await initializedRepo();
    const worktree = await mkdtemp(join(tmpdir(), "compass-warm-node-"));
    const { output, messages } = captureOutput();

    try {
      await writeFile(join(dir, ".gitignore"), "/node_modules/\n", "utf-8");
      await writeFile(join(dir, "package.json"), "{}\n", "utf-8");
      await mkdir(join(dir, "node_modules", "pkg"), { recursive: true });
      await writeFile(join(dir, "node_modules", "pkg", "index.js"), "module.exports = 1;\n", "utf-8");
      await commit(dir, "add node workspace");

      await warmDevSandboxCaches({
        mainRepoPath: dir,
        worktreePath: worktree,
        output,
        env: { COMPASS_WARM_SANDBOX: "auto" },
        platform: "darwin",
      });

      assert.equal(
        await readFile(join(worktree, "node_modules", "pkg", "index.js"), "utf-8"),
        "module.exports = 1;\n"
      );
      assert.ok(
        messages.some((m) => m.includes("Warm sandbox: APFS-cloned node_modules")),
        messages.join("\n")
      );
    } finally {
      await rm(worktree, { recursive: true, force: true });
      await cleanup();
    }
  }
);

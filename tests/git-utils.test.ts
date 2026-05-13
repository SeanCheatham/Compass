import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

import {
  initRepo,
  isGitRepo,
  getCurrentCommit,
  getShortCommit,
  tryGetCurrentCommit,
  hasUncommittedChanges,
  stageAllChanges,
  commit,
  stashChanges,
  discardChanges,
  resetHard,
  createWorktreeBranch,
  removeWorktree,
  deleteBranch,
  mergeFastForward,
  isValidCommit,
  commitsBetween,
  listTrackedAndUntracked,
} from "../src/mcp/utils/git.ts";

// Tiny shell-out helper for setup/verification work that the git utility
// module doesn't expose (config, diff --cached, log --pretty, rev-parse
// tree). spawnSync avoids the shell entirely so there's no quoting hazard.
function git(cwd: string, args: string[]): string {
  const r = spawnSync("git", args, { cwd, encoding: "utf-8" });
  if (r.status !== 0) {
    throw new Error(
      `git ${args.join(" ")} failed (status ${r.status}): ${r.stderr}`
    );
  }
  return r.stdout.trim();
}

// Bare tmpdir, NO git init.
async function tmpDir(): Promise<{
  dir: string;
  cleanup: () => Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "compass-git-"));
  return { dir, cleanup: () => rm(dir, { recursive: true, force: true }) };
}

// tmpdir + `git init` + `git config --local user.email/name` + initial commit.
// Returns the SHA of the initial commit so tests can use it as a baseline.
//
// CRITICAL: --local so we never touch the user's global git config. CI and
// fresh dev machines often lack global identity, so we set it per-repo.
async function initializedRepo(): Promise<{
  dir: string;
  initialSha: string;
  cleanup: () => Promise<void>;
}> {
  const { dir, cleanup } = await tmpDir();
  await initRepo(dir);
  git(dir, ["config", "--local", "user.email", "test@compass.local"]);
  git(dir, ["config", "--local", "user.name", "Compass Test"]);
  await writeFile(join(dir, ".gitkeep"), "", "utf-8");
  const initialSha = await commit(dir, "initial");
  return { dir, initialSha, cleanup };
}

// ---------- initRepo + isGitRepo ----------

test("initRepo creates a git repo", async () => {
  const { dir, cleanup } = await tmpDir();
  try {
    assert.equal(isGitRepo(dir), false);
    await initRepo(dir);
    assert.equal(isGitRepo(dir), true);
  } finally {
    await cleanup();
  }
});

test("isGitRepo returns false on plain directory", async () => {
  const { dir, cleanup } = await tmpDir();
  try {
    assert.equal(isGitRepo(dir), false);
  } finally {
    await cleanup();
  }
});

test("isGitRepo returns false on missing directory", async () => {
  // Pointing at a non-existent path makes runGitSync throw → caught → false.
  const missing = join(tmpdir(), "compass-git-does-not-exist-xyz-" + Date.now());
  assert.equal(isGitRepo(missing), false);
});

// ---------- Commit lifecycle on empty / fresh repo ----------

test("tryGetCurrentCommit returns null on empty repo", async () => {
  const { dir, cleanup } = await tmpDir();
  try {
    await initRepo(dir);
    const result = await tryGetCurrentCommit(dir);
    assert.equal(result, null);
  } finally {
    await cleanup();
  }
});

test("getCurrentCommit throws on empty repo", async () => {
  const { dir, cleanup } = await tmpDir();
  try {
    await initRepo(dir);
    await assert.rejects(
      () => getCurrentCommit(dir),
      /Failed to get current commit/
    );
  } finally {
    await cleanup();
  }
});

test("getCurrentCommit returns full SHA after first commit", async () => {
  const { dir, initialSha, cleanup } = await initializedRepo();
  try {
    assert.match(initialSha, /^[0-9a-f]{40}$/);
    const live = await getCurrentCommit(dir);
    assert.equal(live, initialSha);
  } finally {
    await cleanup();
  }
});

test("getShortCommit returns short SHA after first commit", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    const short = await getShortCommit(dir);
    assert.match(short, /^[0-9a-f]{7,}$/);
    assert.ok(short.length < 40);
  } finally {
    await cleanup();
  }
});

// ---------- hasUncommittedChanges ----------

test("hasUncommittedChanges false on clean repo", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    assert.equal(await hasUncommittedChanges(dir), false);
  } finally {
    await cleanup();
  }
});

test("hasUncommittedChanges true after writing untracked file", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "foo.txt"), "hello", "utf-8");
    assert.equal(await hasUncommittedChanges(dir), true);
  } finally {
    await cleanup();
  }
});

test("hasUncommittedChanges true after stageAllChanges (staged but not committed)", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "foo.txt"), "hello", "utf-8");
    await stageAllChanges(dir);
    assert.equal(await hasUncommittedChanges(dir), true);
  } finally {
    await cleanup();
  }
});

// ---------- stageAllChanges + commit ----------

test("stageAllChanges adds untracked files to index", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "foo.txt"), "hello", "utf-8");
    await stageAllChanges(dir);
    const staged = git(dir, ["diff", "--cached", "--name-only"]).split("\n");
    assert.ok(staged.includes("foo.txt"), `staged=${JSON.stringify(staged)}`);
  } finally {
    await cleanup();
  }
});

test("commit returns the SHA of the new HEAD", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "foo.txt"), "hello", "utf-8");
    const newSha = await commit(dir, "second");
    const head = await getCurrentCommit(dir);
    assert.equal(newSha, head);
    assert.match(newSha, /^[0-9a-f]{40}$/);
  } finally {
    await cleanup();
  }
});

test("commit round-trips a simple message", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "foo.txt"), "hello", "utf-8");
    await commit(dir, "round trip subject");
    const subject = git(dir, ["log", "-1", "--pretty=%s"]);
    assert.equal(subject, "round trip subject");
  } finally {
    await cleanup();
  }
});

test("commit escapes embedded double-quotes", async () => {
  // Pins that double-quotes in commit messages round-trip cleanly. With
  // execFile (no shell), no escaping is needed — args go through verbatim.
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "foo.txt"), "hello", "utf-8");
    await commit(dir, 'a "quoted" word');
    const subject = git(dir, ["log", "-1", "--pretty=%s"]);
    assert.equal(subject, 'a "quoted" word');
  } finally {
    await cleanup();
  }
});

test("commit handles backticks literally (no shell expansion)", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "foo.txt"), "hello", "utf-8");
    const msg = "with `injected` backticks";
    await commit(dir, msg);
    const subject = git(dir, ["log", "-1", "--pretty=%s"]);
    assert.equal(subject, msg);
  } finally {
    await cleanup();
  }
});

test("commit handles $VAR literally (no shell expansion)", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "foo.txt"), "hello", "utf-8");
    const msg = "path is $HOME literal";
    await commit(dir, msg);
    const subject = git(dir, ["log", "-1", "--pretty=%s"]);
    assert.equal(subject, msg);
  } finally {
    await cleanup();
  }
});

test("commit handles $(...) literally (no shell expansion)", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "foo.txt"), "hello", "utf-8");
    // Use $(true) — even if the fix regressed and the shell expanded this,
    // `true` produces no output, so the assertion would catch the empty
    // string mismatch without polluting the test environment.
    const msg = "contains $(true) literal";
    await commit(dir, msg);
    const subject = git(dir, ["log", "-1", "--pretty=%s"]);
    assert.equal(subject, msg);
  } finally {
    await cleanup();
  }
});

// ---------- stashChanges, discardChanges, resetHard ----------

test("stashChanges removes uncommitted from working tree", async () => {
  // `git stash push` (no -u) only stashes tracked changes by default, so we
  // modify the tracked .gitkeep file rather than create an untracked one.
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, ".gitkeep"), "modified", "utf-8");
    assert.equal(await hasUncommittedChanges(dir), true);
    await stashChanges(dir);
    assert.equal(await hasUncommittedChanges(dir), false);
  } finally {
    await cleanup();
  }
});

test("discardChanges restores tracked file and removes untracked", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, ".gitkeep"), "modified", "utf-8");
    await writeFile(join(dir, "untracked.txt"), "junk", "utf-8");
    assert.equal(await hasUncommittedChanges(dir), true);
    await discardChanges(dir);
    assert.equal(await hasUncommittedChanges(dir), false);
    // Tracked file is restored (.gitkeep), untracked is gone.
    const entries = await readdir(dir);
    assert.ok(entries.includes(".gitkeep"));
    assert.ok(!entries.includes("untracked.txt"));
  } finally {
    await cleanup();
  }
});

test("resetHard rolls HEAD back to old commit", async () => {
  const { dir, initialSha, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "second.txt"), "x", "utf-8");
    const secondSha = await commit(dir, "second");
    assert.notEqual(secondSha, initialSha);
    await resetHard(dir, initialSha);
    assert.equal(await getCurrentCommit(dir), initialSha);
    assert.equal(await hasUncommittedChanges(dir), false);
  } finally {
    await cleanup();
  }
});

test("resetHard rejects on bad SHA", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await assert.rejects(
      () => resetHard(dir, "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"),
      /Failed to reset/
    );
  } finally {
    await cleanup();
  }
});

// ---------- isValidCommit ----------

test("isValidCommit true for HEAD", async () => {
  const { dir, initialSha, cleanup } = await initializedRepo();
  try {
    assert.equal(await isValidCommit(dir, initialSha), true);
  } finally {
    await cleanup();
  }
});

test("isValidCommit false for non-existent SHA and for non-commit objects", async () => {
  // Pins both branches: result.success === false (bad SHA) AND
  // result.success === true with stdout !== "commit" (a tree SHA).
  const { dir, cleanup } = await initializedRepo();
  try {
    // Branch 1: cat-file fails → success false → false.
    assert.equal(
      await isValidCommit(dir, "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"),
      false
    );
    // Branch 2: cat-file succeeds but returns "tree" → false.
    const treeSha = git(dir, ["rev-parse", "HEAD^{tree}"]);
    assert.match(treeSha, /^[0-9a-f]{40}$/);
    assert.equal(await isValidCommit(dir, treeSha), false);
  } finally {
    await cleanup();
  }
});

// ---------- commitsBetween ----------

test("commitsBetween returns [] when before === after", async () => {
  const { dir, initialSha, cleanup } = await initializedRepo();
  try {
    const result = await commitsBetween(dir, initialSha, initialSha);
    assert.deepEqual(result, []);
  } finally {
    await cleanup();
  }
});

test("commitsBetween with null before returns the single commit at after", async () => {
  const { dir, initialSha, cleanup } = await initializedRepo();
  try {
    const result = await commitsBetween(dir, null, initialSha);
    assert.equal(result.length, 1);
    assert.equal(result[0].sha, initialSha);
    assert.equal(result[0].subject, "initial");
    assert.match(result[0].short, /^[0-9a-f]{7,}$/);
  } finally {
    await cleanup();
  }
});

test("commitsBetween A..B returns intermediate commits in oldest-first order", async () => {
  const { dir, initialSha, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "b.txt"), "b", "utf-8");
    const shaB = await commit(dir, "B");
    await writeFile(join(dir, "c.txt"), "c", "utf-8");
    const shaC = await commit(dir, "C");
    const result = await commitsBetween(dir, initialSha, shaC);
    assert.equal(result.length, 2);
    assert.equal(result[0].sha, shaB);
    assert.equal(result[0].subject, "B");
    assert.equal(result[1].sha, shaC);
    assert.equal(result[1].subject, "C");
  } finally {
    await cleanup();
  }
});

test("commitsBetween preserves tab in subject", async () => {
  // Pins the `rest.join("\t")` join — without it, a tab in the subject would
  // be silently dropped because the format string uses %x09 as the field
  // separator.
  const { dir, initialSha, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "x.txt"), "x", "utf-8");
    const tabSha = await commit(dir, "has\ttab");
    const result = await commitsBetween(dir, initialSha, tabSha);
    assert.equal(result.length, 1);
    assert.equal(result[0].subject, "has\ttab");
  } finally {
    await cleanup();
  }
});

test("commitsBetween returns [] on bad range", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    const result = await commitsBetween(
      dir,
      "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
      "cafef00dcafef00dcafef00dcafef00dcafef00d"
    );
    assert.deepEqual(result, []);
  } finally {
    await cleanup();
  }
});

// ---------- listTrackedAndUntracked ----------

test("listTrackedAndUntracked lists tracked files", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    const files = await listTrackedAndUntracked(dir);
    assert.ok(files.includes(".gitkeep"), `files=${JSON.stringify(files)}`);
  } finally {
    await cleanup();
  }
});

test("listTrackedAndUntracked lists untracked files", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, "foo.txt"), "hello", "utf-8");
    const files = await listTrackedAndUntracked(dir);
    assert.ok(files.includes(".gitkeep"));
    assert.ok(files.includes("foo.txt"));
  } finally {
    await cleanup();
  }
});

test("listTrackedAndUntracked excludes gitignored files", async () => {
  const { dir, cleanup } = await initializedRepo();
  try {
    await writeFile(join(dir, ".gitignore"), "secret.txt\n", "utf-8");
    await commit(dir, "add gitignore");
    await writeFile(join(dir, "secret.txt"), "shh", "utf-8");
    const files = await listTrackedAndUntracked(dir);
    assert.ok(files.includes(".gitkeep"));
    assert.ok(files.includes(".gitignore"));
    assert.ok(
      !files.includes("secret.txt"),
      `secret.txt should be excluded; files=${JSON.stringify(files)}`
    );
  } finally {
    await cleanup();
  }
});

test("worktree branch can be committed, fast-forward promoted, and cleaned up", async () => {
  const { dir, initialSha, cleanup } = await initializedRepo();
  const parent = await mkdtemp(join(tmpdir(), "compass-git-worktree-"));
  const worktree = join(parent, "wt");
  const branch = "compass/test-worktree";
  try {
    await createWorktreeBranch(dir, worktree, branch, initialSha);
    git(worktree, ["config", "--local", "user.email", "test@compass.local"]);
    git(worktree, ["config", "--local", "user.name", "Compass Test"]);
    await writeFile(join(worktree, "feature.txt"), "hello", "utf-8");
    await commit(worktree, "feature");

    await mergeFastForward(dir, branch);
    assert.equal(git(dir, ["log", "-1", "--pretty=%s"]), "feature");
    assert.equal(await hasUncommittedChanges(dir), false);

    await removeWorktree(dir, worktree);
    await deleteBranch(dir, branch);
    assert.equal(git(dir, ["branch", "--list", branch]), "");
  } finally {
    await removeWorktree(dir, worktree).catch(() => {});
    await deleteBranch(dir, branch).catch(() => {});
    await rm(parent, { recursive: true, force: true });
    await cleanup();
  }
});

import { execFile } from "node:child_process";
import { mkdir, readdir, rm, stat, symlink } from "node:fs/promises";
import { basename, dirname, isAbsolute, normalize, resolve } from "node:path";
import { performance } from "node:perf_hooks";
import { promisify } from "node:util";
import type { OutputManager } from "../web/output-manager.js";
import { isGitIgnored } from "../mcp/utils/git.js";

const execFileAsync = promisify(execFile);

export type WarmSandboxMode = "clone" | "link";

interface WarmSandboxEntry {
  path: string;
  mode: WarmSandboxMode;
}

interface ParsedWarmSandboxSpec {
  disabled: boolean;
  auto: boolean;
  entries: WarmSandboxEntry[];
  warnings: string[];
}

export interface WarmDevSandboxOptions {
  mainRepoPath: string;
  worktreePath: string;
  output: Pick<OutputManager, "info" | "error">;
  env?: NodeJS.ProcessEnv;
  platform?: NodeJS.Platform;
}

const DEFAULT_CLONE_TIMEOUT_MS = 30_000;

/**
 * Warm disposable Develop worktrees with large ignored local caches.
 *
 * On macOS, APFS clone copies are excellent for moderately sized dependency
 * caches such as node_modules. Rust target directories are different: they can
 * be hundreds of thousands of files, so auto mode shares target by symlinks
 * instead of spending a minute duplicating metadata every iteration.
 */
export async function warmDevSandboxCaches(
  opts: WarmDevSandboxOptions
): Promise<void> {
  const env = opts.env ?? process.env;
  const platform = opts.platform ?? process.platform;
  const spec = parseWarmSandboxSpec(env.COMPASS_WARM_SANDBOX);

  for (const warning of spec.warnings) {
    opts.output.error(`Warm sandbox: ${warning}`);
  }

  if (spec.disabled) return;

  if (platform !== "darwin") {
    if (!spec.auto || spec.entries.length > 0) {
      opts.output.info("Warm sandbox: skipped; cache warming is macOS-only.");
    }
    return;
  }

  const entries = spec.auto
    ? await autoWarmEntries(opts.mainRepoPath)
    : spec.entries;

  if (entries.length === 0) return;

  const cloneTimeoutMs = parsePositiveInt(
    env.COMPASS_WARM_SANDBOX_TIMEOUT_MS,
    DEFAULT_CLONE_TIMEOUT_MS
  );

  for (const entry of entries) {
    await warmEntry({
      ...opts,
      entry,
      cloneTimeoutMs,
    });
  }
}

async function autoWarmEntries(repoPath: string): Promise<WarmSandboxEntry[]> {
  const entries: WarmSandboxEntry[] = [];

  if (await pathExists(resolve(repoPath, "Cargo.toml"))) {
    entries.push({ path: "target", mode: "link" });
  }

  if (
    (await pathExists(resolve(repoPath, "package-lock.json"))) ||
    (await pathExists(resolve(repoPath, "pnpm-lock.yaml"))) ||
    (await pathExists(resolve(repoPath, "yarn.lock"))) ||
    (await pathExists(resolve(repoPath, "package.json")))
  ) {
    entries.push({ path: "node_modules", mode: "clone" });
  }

  return entries;
}

async function warmEntry(args: {
  mainRepoPath: string;
  worktreePath: string;
  output: Pick<OutputManager, "info" | "error">;
  entry: WarmSandboxEntry;
  cloneTimeoutMs: number;
}): Promise<void> {
  const { entry, mainRepoPath, worktreePath, output } = args;
  const safePath = normalizeWarmPath(entry.path);
  if (!safePath) {
    output.error(`Warm sandbox: ignoring unsafe path \`${entry.path}\`.`);
    return;
  }

  const source = resolve(mainRepoPath, safePath);
  const dest = resolve(worktreePath, safePath);

  if (!(await isDirectory(source))) return;

  if (await pathExists(dest)) {
    output.info(`Warm sandbox: ${safePath} already exists in Develop worktree; leaving it alone.`);
    return;
  }

  if (!(await isGitIgnored(mainRepoPath, safePath))) {
    output.info(`Warm sandbox: skipping ${safePath}; it is not ignored by git.`);
    return;
  }

  try {
    await mkdir(dirname(dest), { recursive: true });
    const started = performance.now();
    if (entry.mode === "link") {
      await linkDirectoryContents(source, dest);
      output.info(
        `Warm sandbox: shared ${safePath} via symlinks (${formatDuration(performance.now() - started)}).`
      );
    } else {
      await cloneDirectory(source, dest, args.cloneTimeoutMs);
      output.info(
        `Warm sandbox: APFS-cloned ${safePath} (${formatDuration(performance.now() - started)}).`
      );
    }
  } catch (err) {
    await rm(dest, { recursive: true, force: true }).catch(() => {});
    output.error(`Warm sandbox: could not warm ${safePath}: ${formatError(err)}`);
  }
}

async function linkDirectoryContents(source: string, dest: string): Promise<void> {
  await mkdir(dest, { recursive: true });
  const entries = await readdir(source, { withFileTypes: true });
  for (const entry of entries) {
    const sourceChild = resolve(source, entry.name);
    const destChild = resolve(dest, entry.name);
    await symlink(sourceChild, destChild, entry.isDirectory() ? "dir" : "file");
  }
}

async function cloneDirectory(
  source: string,
  dest: string,
  timeoutMs: number
): Promise<void> {
  await execFileAsync("cp", ["-cR", source, dest], {
    timeout: timeoutMs,
    maxBuffer: 1024 * 1024,
  });
}

function parseWarmSandboxSpec(raw: string | undefined): ParsedWarmSandboxSpec {
  const value = raw?.trim();
  if (!value || value.toLowerCase() === "auto") {
    return { disabled: false, auto: true, entries: [], warnings: [] };
  }

  if (["0", "false", "no", "none", "off"].includes(value.toLowerCase())) {
    return { disabled: true, auto: false, entries: [], warnings: [] };
  }

  const entries: WarmSandboxEntry[] = [];
  const warnings: string[] = [];
  for (const rawPart of value.split(",")) {
    const part = rawPart.trim();
    if (!part) continue;
    const [path, rawMode, ...extra] = part.split(":");
    if (!path || extra.length > 0) {
      warnings.push(`ignoring invalid warm entry \`${part}\`.`);
      continue;
    }
    const mode = parseMode(rawMode, path);
    if (!mode) {
      warnings.push(
        `ignoring warm entry \`${part}\`; mode must be clone or link.`
      );
      continue;
    }
    entries.push({ path, mode });
  }

  return { disabled: false, auto: false, entries, warnings };
}

function parseMode(
  rawMode: string | undefined,
  path: string
): WarmSandboxMode | null {
  if (!rawMode) return basename(path) === "target" ? "link" : "clone";
  const mode = rawMode.trim().toLowerCase();
  if (mode === "clone" || mode === "link") return mode;
  return null;
}

function normalizeWarmPath(path: string): string | null {
  if (!path.trim() || isAbsolute(path)) return null;
  if (path.split(/[\\/]+/).includes("..")) return null;
  const normalized = normalize(path).replaceAll("\\", "/");
  if (
    normalized === "." ||
    normalized === ".." ||
    normalized.startsWith("../") ||
    normalized.includes("/../")
  ) {
    return null;
  }
  return normalized;
}

async function isDirectory(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isDirectory();
  } catch {
    return false;
  }
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await stat(path);
    return true;
  } catch {
    return false;
  }
}

function parsePositiveInt(raw: string | undefined, fallback: number): number {
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${Math.round(ms)}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

function formatError(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}

export const warmSandboxForTest = {
  parseWarmSandboxSpec,
  normalizeWarmPath,
};

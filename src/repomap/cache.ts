import { dirname, resolve } from "node:path";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import type { Language, Symbol } from "./extract.js";
import type { WorkspaceConfig } from "../state/types.js";

export const REPOMAP_FILE = "repomap.json";

export interface FileEntry {
  mtime: number;
  size: number;
  language: Language;
  symbols: Symbol[];
}

export interface RepoMapCache {
  version: 9;
  files: Record<string, FileEntry>;
}

const EMPTY_CACHE: RepoMapCache = { version: 9, files: {} };

export function repoMapCachePath(config: WorkspaceConfig): string {
  return resolve(config.workspacePath, REPOMAP_FILE);
}

export async function readRepoMapCache(
  config: WorkspaceConfig
): Promise<RepoMapCache> {
  const path = repoMapCachePath(config);
  let raw: string;
  try {
    raw = await readFile(path, "utf-8");
  } catch {
    return { version: 9, files: {} };
  }
  if (!raw.trim()) return { version: 9, files: {} };

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { version: 9, files: {} };
  }

  if (
    !parsed ||
    typeof parsed !== "object" ||
    (parsed as { version?: unknown }).version !== 9 ||
    typeof (parsed as { files?: unknown }).files !== "object"
  ) {
    return { ...EMPTY_CACHE, files: {} };
  }

  return parsed as RepoMapCache;
}

export async function writeRepoMapCache(
  config: WorkspaceConfig,
  cache: RepoMapCache
): Promise<void> {
  const path = repoMapCachePath(config);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, JSON.stringify(cache) + "\n", "utf-8");
}

export function isFresh(
  entry: FileEntry | undefined,
  mtime: number,
  size: number
): boolean {
  if (!entry) return false;
  return entry.mtime === mtime && entry.size === size;
}

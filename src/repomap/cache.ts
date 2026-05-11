import { createHash } from "node:crypto";
import { dirname, extname, resolve } from "node:path";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import type { WorkspaceConfig } from "../state/types.js";

export const REPOMAP_FILE = "repomap.json";
export const CACHE_VERSION = 10 as const;

export type Language = "ts" | "tsx" | "js" | "py" | "go" | "rs" | "md";

const LANG_BY_EXT: Record<string, Language> = {
  ".ts": "ts",
  ".mts": "ts",
  ".cts": "ts",
  ".tsx": "tsx",
  ".js": "js",
  ".jsx": "js",
  ".mjs": "js",
  ".cjs": "js",
  ".py": "py",
  ".go": "go",
  ".rs": "rs",
  ".md": "md",
  ".markdown": "md",
};

export function detectLanguage(path: string): Language | null {
  return LANG_BY_EXT[extname(path).toLowerCase()] ?? null;
}

/** A nested declaration inside a top-level symbol (class method, struct field, enum variant, impl item, …). */
export interface Member {
  kind: string;
  name: string;
  line: number;
  /** Parameter list for function-like members, e.g. `"a: number, b: string"`. */
  signature?: string;
  /** Return type for function-like members where the language carries one. */
  returnType?: string;
}

/** A top-level declaration in a source file. */
export interface Symbol {
  kind: string;
  name: string;
  line: number;
  /** Parameter list for function-like decls. Absent for non-functions. */
  signature?: string;
  /** Return type for function-like decls where the language carries one. */
  returnType?: string;
  /** True for `export`ed decls (TS/JS) or `pub` items (Rust). */
  exported?: boolean;
  /** Class methods, struct fields, enum variants, impl items, interface members, etc. */
  members?: Member[];
}

/** A single `import`/`from`/`use`/`require` reference pulled from the file. */
export interface ImportRef {
  /** The literal module string from source, e.g. `"./foo.js"` or `"@anthropic-ai/sdk"`. */
  raw: string;
  /**
   * Repo-relative path the import resolves to (TS/JS/Python only for v1).
   * Null when the import is external (a package), unresolvable, or not yet
   * supported by the resolver.
   */
  resolved: string | null;
  line: number;
}

export interface FileEntry {
  /** sha1 of the file content at parse time. Primary freshness key. */
  contentHash: string;
  /** Stat mtime in ms, kept as a cheap fast-path before hashing. */
  mtime: number;
  /** Stat size in bytes, kept as a cheap fast-path before hashing. */
  size: number;
  language: Language;
  symbols: Symbol[];
  imports: ImportRef[];
  /**
   * Haiku-generated one-paragraph "what does this file do" summary. Absent
   * until the summarizer runs. Carried across cache rebuilds as long as the
   * contentHash hasn't changed since `summaryHash` was recorded.
   */
  summary?: string;
  /** The contentHash that was current when `summary` was generated. */
  summaryHash?: string;
}

export interface RepoMapCache {
  version: typeof CACHE_VERSION;
  files: Record<string, FileEntry>;
}

const EMPTY_CACHE: RepoMapCache = { version: CACHE_VERSION, files: {} };

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
    return { version: CACHE_VERSION, files: {} };
  }
  if (!raw.trim()) return { version: CACHE_VERSION, files: {} };

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { version: CACHE_VERSION, files: {} };
  }

  if (
    !parsed ||
    typeof parsed !== "object" ||
    (parsed as { version?: unknown }).version !== CACHE_VERSION ||
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

/**
 * Fast path: stat matches what's in the cache, so content hasn't changed.
 * When this returns false we still might be content-fresh — call `hashContent`
 * and compare to `entry.contentHash` to find out for sure.
 */
export function isStatFresh(
  entry: FileEntry | undefined,
  mtime: number,
  size: number
): boolean {
  if (!entry) return false;
  return entry.mtime === mtime && entry.size === size;
}

export function hashContent(text: string): string {
  return createHash("sha1").update(text).digest("hex");
}

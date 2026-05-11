import { resolve } from "node:path";
import { readFile, stat } from "node:fs/promises";
import type { WorkspaceConfig } from "../state/types.js";
import { extract } from "./extract.js";
import {
  detectLanguage,
  hashContent,
  isStatFresh,
  readRepoMapCache,
  writeRepoMapCache,
  CACHE_VERSION,
  type FileEntry,
  type RepoMapCache,
} from "./cache.js";
import { renderRepoMap } from "./render.js";
import { resolveImport } from "./resolve.js";
import { summarizeMissing, type SummarizeResult } from "./summary.js";
import { listTrackedAndUntracked } from "../mcp/utils/git.js";

export interface BuildRepoMapOptions {
  /** Hard cap on output character count. */
  maxChars?: number;
  /** Skip files larger than this. Default 1 MiB. */
  maxFileBytes?: number;
}

const DEFAULT_MAX_FILE_BYTES = 1024 * 1024;

/**
 * Build the repo map for `config.implRepoPath`. Updates the on-disk cache
 * (parsing only files whose content hash changed) and returns the rendered
 * string ready to inject into a system prompt. The cache also keeps imports
 * and Haiku-generated summaries; tooling reads those separately via the cache.
 */
export async function buildRepoMap(
  config: WorkspaceConfig,
  opts: BuildRepoMapOptions = {}
): Promise<string> {
  const cache = await rebuildRepoMapCache(config, opts);
  return renderRepoMap(cache.files, { maxChars: opts.maxChars });
}

/**
 * Rebuild the on-disk cache and return the fresh object. Exposed separately
 * from `buildRepoMap` so MCP query tools can consume the structured data
 * without going through the rendered string.
 */
export async function rebuildRepoMapCache(
  config: WorkspaceConfig,
  opts: BuildRepoMapOptions = {}
): Promise<RepoMapCache> {
  const maxFileBytes = opts.maxFileBytes ?? DEFAULT_MAX_FILE_BYTES;

  const cache = await readRepoMapCache(config);
  const next: RepoMapCache = { version: CACHE_VERSION, files: {} };

  const all = await listTrackedAndUntracked(config.implRepoPath);
  const sourceFiles = all.filter((p) => detectLanguage(p) !== null);

  for (const rel of sourceFiles) {
    const language = detectLanguage(rel);
    if (!language) continue;

    const abs = resolve(config.implRepoPath, rel);
    let mtime: number;
    let size: number;
    try {
      const s = await stat(abs);
      mtime = s.mtimeMs;
      size = s.size;
    } catch {
      continue;
    }

    if (size > maxFileBytes) continue;

    const cached = cache.files[rel];

    // Fast path: stat hasn't changed since last build. Skip the read entirely.
    if (isStatFresh(cached, mtime, size) && cached.language === language) {
      next.files[rel] = cached;
      continue;
    }

    let text: string;
    try {
      text = await readFile(abs, "utf-8");
    } catch {
      continue;
    }

    const contentHash = hashContent(text);

    // Hash-fresh path: stat differs (rebase, clean checkout) but the bytes
    // didn't actually change. Carry the cached symbols/imports forward and
    // update mtime/size so the next build hits the fast path.
    if (
      cached &&
      cached.contentHash === contentHash &&
      cached.language === language
    ) {
      next.files[rel] = { ...cached, mtime, size };
      continue;
    }

    const { symbols, imports } = extract(text, language);
    const entry: FileEntry = {
      contentHash,
      mtime,
      size,
      language,
      symbols,
      imports,
    };
    // Preserve an existing summary if it still matches the new contentHash —
    // i.e. the same content was previously summarized and just got re-parsed.
    // Almost never hits in practice but keeps the data model clean.
    if (cached?.summary && cached.summaryHash === contentHash) {
      entry.summary = cached.summary;
      entry.summaryHash = cached.summaryHash;
    }
    next.files[rel] = entry;
  }

  // Second pass: resolve each file's imports against the now-known file set.
  // Done after extraction so we have the full set of valid targets and so
  // rebuilds catch added/removed files even when the importer's content
  // hasn't changed.
  const fileSet = new Set(Object.keys(next.files));
  for (const [rel, entry] of Object.entries(next.files)) {
    if (entry.imports.length === 0) continue;
    let mutated = false;
    const resolved = entry.imports.map((imp) => {
      const r = resolveImport(rel, imp.raw, fileSet, entry.language);
      if (r !== imp.resolved) mutated = true;
      return r === imp.resolved ? imp : { ...imp, resolved: r };
    });
    if (mutated) next.files[rel] = { ...entry, imports: resolved };
  }

  await writeRepoMapCache(config, next);
  return next;
}

export interface PrepareCodemapOptions {
  signal?: AbortSignal;
  /** Called after each summary completes during the Haiku pass. */
  onSummaryProgress?: (done: number, total: number) => void;
}

export interface PrepareCodemapResult {
  cache: RepoMapCache;
  summaryResult: SummarizeResult;
}

/**
 * One-stop helper for agent startup: rebuilds the symbol/import cache, then
 * generates Haiku summaries for any files whose `summary` is missing or
 * stale. Returns the fully-populated cache and the summary pass stats.
 */
export async function prepareCodemap(
  config: WorkspaceConfig,
  opts: PrepareCodemapOptions = {}
): Promise<PrepareCodemapResult> {
  await rebuildRepoMapCache(config);
  const summaryResult = await summarizeMissing(config, {
    signal: opts.signal,
    onProgress: opts.onSummaryProgress,
  });
  // Re-read after the summary pass since it wrote back updated entries.
  const cache = await readRepoMapCache(config);
  return { cache, summaryResult };
}

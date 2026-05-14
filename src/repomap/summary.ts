import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import type { WorkspaceConfig } from "../state/types.js";
import {
  readRepoMapCache,
  writeRepoMapCache,
  type RepoMapCache,
} from "./cache.js";
import {
  CODEMAP_MODEL_ENV,
  DEFAULT_CODEMAP_MODEL,
  codexModelFromEnv,
  runCodexReadOnlyTurn,
} from "../agents/codex-client.js";

const DEFAULT_CONCURRENCY = 4;
/** Truncate huge files before sending to Codex — beyond this the summary won't change meaningfully. */
const MAX_FILE_CHARS = 60_000;
/** Files smaller than this are skipped — usually trivial re-exports or stubs. */
const MIN_FILE_CHARS = 80;

const SUMMARY_SYSTEM_PROMPT = `You are summarizing a single source file for an indexer that helps agents find relevant code. Read the file and produce one OR two short sentences that capture:
- The file's responsibility within the project.
- Its key exported types, classes, or functions and what they do.
- Any non-obvious behaviours (side effects, IO, concurrency, ordering invariants, gotchas).

Return ONLY the summary text. No path, no markdown headers, no bullet lists, no preamble. Plain prose.`;

export interface SummarizeOptions {
  signal?: AbortSignal;
  concurrency?: number;
  /** Called after each file completes (success or failure) with running counts. */
  onProgress?: (done: number, total: number) => void;
}

export interface SummarizeResult {
  generated: number;
  skipped: number;
  errors: number;
}

/**
 * Return the cached summary for a single file, generating it via Codex if
 * missing or stale. Persists the updated cache. Returns null if the file is
 * not indexed or is too small to summarize.
 */
export async function ensureSummary(
  config: WorkspaceConfig,
  rel: string,
  signal?: AbortSignal
): Promise<string | null> {
  const cache = await readRepoMapCache(config);
  const entry = cache.files[rel];
  if (!entry) return null;
  if (entry.summary && entry.summaryHash === entry.contentHash) {
    return entry.summary;
  }

  const abs = resolve(config.implRepoPath, rel);
  let text: string;
  try {
    text = await readFile(abs, "utf-8");
  } catch {
    return null;
  }
  if (text.length < MIN_FILE_CHARS) return null;
  const snippet =
    text.length > MAX_FILE_CHARS
      ? text.slice(0, MAX_FILE_CHARS) + "\n…(truncated)…"
      : text;

  const summary = await summarizeOne(rel, snippet, config.implRepoPath, signal);
  if (summary.length === 0) return null;

  cache.files[rel] = { ...entry, summary, summaryHash: entry.contentHash };
  await writeRepoMapCache(config, cache);
  return summary;
}

/**
 * Walk the cache, generate Codex summaries for any file whose `summary` is
 * absent or stale (summaryHash !== contentHash), and persist the updated
 * cache. Concurrency-limited; fire-and-forget safe via the `signal`.
 */
export async function summarizeMissing(
  config: WorkspaceConfig,
  opts: SummarizeOptions = {}
): Promise<SummarizeResult> {
  const cache = await readRepoMapCache(config);
  const targets = pickTargets(cache);
  if (targets.length === 0) return { generated: 0, skipped: 0, errors: 0 };

  const concurrency = Math.max(1, opts.concurrency ?? DEFAULT_CONCURRENCY);
  let cursor = 0;
  let generated = 0;
  let skipped = 0;
  let errors = 0;

  const worker = async (): Promise<void> => {
    while (cursor < targets.length) {
      if (opts.signal?.aborted) return;
      const i = cursor++;
      const rel = targets[i]!;
      const entry = cache.files[rel];
      if (!entry) continue;

      const abs = resolve(config.implRepoPath, rel);
      let text: string;
      try {
        text = await readFile(abs, "utf-8");
      } catch {
        errors++;
        opts.onProgress?.(generated + skipped + errors, targets.length);
        continue;
      }
      if (text.length < MIN_FILE_CHARS) {
        skipped++;
        opts.onProgress?.(generated + skipped + errors, targets.length);
        continue;
      }
      const snippet =
        text.length > MAX_FILE_CHARS
          ? text.slice(0, MAX_FILE_CHARS) + "\n…(truncated)…"
          : text;
      try {
        const summary = await summarizeOne(
          rel,
          snippet,
          config.implRepoPath,
          opts.signal
        );
        if (summary.length > 0) {
          cache.files[rel] = {
            ...entry,
            summary,
            summaryHash: entry.contentHash,
          };
          generated++;
        } else {
          errors++;
        }
      } catch {
        errors++;
      }
      opts.onProgress?.(generated + skipped + errors, targets.length);
    }
  };

  const workers: Promise<void>[] = [];
  for (let i = 0; i < concurrency; i++) workers.push(worker());
  await Promise.all(workers);

  await writeRepoMapCache(config, cache);
  return { generated, skipped, errors };
}

function pickTargets(cache: RepoMapCache): string[] {
  const out: string[] = [];
  for (const [rel, entry] of Object.entries(cache.files)) {
    if (entry.symbols.length === 0) continue;
    if (entry.summary && entry.summaryHash === entry.contentHash) continue;
    out.push(rel);
  }
  return out.sort();
}

async function summarizeOne(
  path: string,
  content: string,
  cwd: string,
  signal?: AbortSignal
): Promise<string> {
  return runCodexReadOnlyTurn({
    prompt: `${SUMMARY_SYSTEM_PROMPT}

File path: ${path}

\`\`\`
${content}
\`\`\``,
    cwd,
    reasoningEffort: "low",
    model: codexModelFromEnv(CODEMAP_MODEL_ENV, DEFAULT_CODEMAP_MODEL),
    signal,
  });
}

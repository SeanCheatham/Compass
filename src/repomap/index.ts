import { resolve } from "node:path";
import { readFile, stat } from "node:fs/promises";
import type { WorkspaceConfig } from "../state/types.js";
import { detectLanguage, extractSymbols } from "./extract.js";
import {
  isFresh,
  readRepoMapCache,
  writeRepoMapCache,
  type FileEntry,
  type RepoMapCache,
} from "./cache.js";
import { renderRepoMap } from "./render.js";
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
 * (parsing only files whose mtime+size changed) and returns the rendered
 * string ready to inject into a system prompt.
 */
export async function buildRepoMap(
  config: WorkspaceConfig,
  opts: BuildRepoMapOptions = {}
): Promise<string> {
  const maxFileBytes = opts.maxFileBytes ?? DEFAULT_MAX_FILE_BYTES;

  const cache = await readRepoMapCache(config);
  const next: RepoMapCache = { version: 3, files: {} };

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
    if (isFresh(cached, mtime, size) && cached.language === language) {
      next.files[rel] = cached;
      continue;
    }

    let text: string;
    try {
      text = await readFile(abs, "utf-8");
    } catch {
      continue;
    }

    const symbols = extractSymbols(text, language);
    const entry: FileEntry = { mtime, size, language, symbols };
    next.files[rel] = entry;
  }

  await writeRepoMapCache(config, next);
  return renderRepoMap(next.files, { maxChars: opts.maxChars });
}

import type { RepoMapCache } from "./cache.js";

/**
 * Build a reverse-import index from the cache: for each repo-relative path,
 * the list of files that resolved an import to it. Used by the `importers_of`
 * MCP tool so agents can answer "what breaks if I change this?" cheaply.
 */
export function buildImporterIndex(cache: RepoMapCache): Map<string, string[]> {
  const out = new Map<string, string[]>();
  for (const [importer, entry] of Object.entries(cache.files)) {
    for (const imp of entry.imports) {
      if (!imp.resolved) continue;
      const list = out.get(imp.resolved);
      if (list) list.push(importer);
      else out.set(imp.resolved, [importer]);
    }
  }
  for (const list of out.values()) list.sort();
  return out;
}

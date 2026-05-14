/**
 * MCP tools that expose the repo map's structured data to agents. Both Plan
 * and Develop mount these via the shared `codemapTools(config)` helper, so
 * either agent can query the index without round-tripping through prompts.
 *
 * Tool surface:
 *   - outline(path)           — symbol tree for one file (with members)
 *   - find_symbol({name,...}) — substring/exact lookup across all files
 *   - list_files({dir?,...})  — filtered file listing from the cache
 *   - importers_of(path)      — reverse-import lookup
 *   - summary(path)           — Codex-generated one-paragraph summary (lazy)
 *   - search({query,limit?})  — Codex-ranked relevance over file summaries
 */

import { z } from "zod";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import type { WorkspaceConfig } from "../state/types.js";
import {
  readRepoMapCache,
  type FileEntry,
  type RepoMapCache,
} from "../repomap/cache.js";
import { buildImporterIndex } from "../repomap/graph.js";
import { ensureSummary } from "../repomap/summary.js";
import {
  CODEMAP_MODEL_ENV,
  DEFAULT_CODEMAP_MODEL,
  codexModelFromEnv,
  runCodexReadOnlyTurn,
} from "../agents/codex-client.js";

const DEFAULT_SEARCH_LIMIT = 8;
const MAX_SEARCH_LIMIT = 25;
const RANK_SCHEMA = {
  type: "object",
  properties: {
    ids: {
      type: "array",
      items: { type: "integer" },
      maxItems: MAX_SEARCH_LIMIT,
    },
  },
  required: ["ids"],
  additionalProperties: false,
} as const;

export interface CompassToolDefinition {
  name: string;
  description: string;
  inputSchema: Record<string, z.ZodType>;
  handler: (args: Record<string, unknown>) => Promise<CallToolResult>;
}

function textResult(text: string, isError = false): CallToolResult {
  return {
    content: [{ type: "text", text }],
    ...(isError ? { isError: true } : {}),
  };
}

function renderFileOutline(rel: string, entry: FileEntry): string {
  const lines: string[] = [`${rel} (${entry.language}):`];
  if (entry.symbols.length === 0) {
    lines.push("  _(no top-level symbols)_");
  }
  for (const sym of entry.symbols) {
    const sig = sym.signature !== undefined ? `(${sym.signature})` : "";
    const ret = sym.returnType !== undefined ? `: ${sym.returnType}` : "";
    const exp = sym.exported ? " [exported]" : "";
    lines.push(`  ${sym.kind} ${sym.name}${sig}${ret}${exp} (L${sym.line})`);
    if (sym.members) {
      for (const m of sym.members) {
        const msig = m.signature !== undefined ? `(${m.signature})` : "";
        const mret = m.returnType !== undefined ? `: ${m.returnType}` : "";
        lines.push(`    ${m.kind} ${m.name}${msig}${mret} (L${m.line})`);
      }
    }
  }
  if (entry.imports.length > 0) {
    lines.push("  imports:");
    for (const imp of entry.imports) {
      const tag = imp.resolved ? ` → ${imp.resolved}` : " (external)";
      lines.push(`    "${imp.raw}"${tag} (L${imp.line})`);
    }
  }
  if (entry.summary) {
    lines.push("  summary:");
    lines.push(`    ${entry.summary}`);
  }
  return lines.join("\n");
}

interface SymbolHit {
  path: string;
  line: number;
  kind: string;
  name: string;
  parent?: string;
}

function searchSymbols(
  cache: RepoMapCache,
  query: string,
  exact: boolean
): SymbolHit[] {
  const needle = query.toLowerCase();
  const out: SymbolHit[] = [];
  for (const [path, entry] of Object.entries(cache.files)) {
    for (const sym of entry.symbols) {
      const match = exact
        ? sym.name === query
        : sym.name.toLowerCase().includes(needle);
      if (match) out.push({ path, line: sym.line, kind: sym.kind, name: sym.name });
      if (sym.members) {
        for (const m of sym.members) {
          const mMatch = exact
            ? m.name === query
            : m.name.toLowerCase().includes(needle);
          if (mMatch) {
            out.push({
              path,
              line: m.line,
              kind: m.kind,
              name: m.name,
              parent: sym.name,
            });
          }
        }
      }
    }
  }
  return out;
}

async function rankBySummary(
  userQuery: string,
  candidates: Array<{ path: string; summary: string }>,
  cwd: string,
  limit: number,
  signal?: AbortSignal
): Promise<Array<{ path: string; summary: string }>> {
  if (candidates.length === 0) return [];
  if (candidates.length <= limit) return candidates;

  // Build a compact catalog. Each entry has a numeric ID so Codex can return
  // a small JSON array of IDs instead of repeating long paths.
  const numbered = candidates.map((c, i) => `${i}: ${c.path}\n  ${c.summary}`);
  const prompt = `User query: ${userQuery}

Rank the following indexed files by relevance to the query. Return JSON matching this shape exactly:
{"ids":[3,17,0,22]}

The ids array must contain the top ${limit} integer IDs in descending relevance. If fewer than ${limit} files are clearly relevant, return fewer IDs. No prose, no markdown, no trailing text.

Files:

${numbered.join("\n\n")}`;

  const text = await runCodexReadOnlyTurn({
    prompt,
    cwd,
    reasoningEffort: "medium",
    model: codexModelFromEnv(CODEMAP_MODEL_ENV, DEFAULT_CODEMAP_MODEL),
    signal,
    outputSchema: RANK_SCHEMA,
  });

  const ids = parseRankedIds(text);
  const picked: Array<{ path: string; summary: string }> = [];
  const seen = new Set<number>();
  for (const id of ids) {
    if (Number.isInteger(id) && id >= 0 && id < candidates.length && !seen.has(id)) {
      seen.add(id);
      picked.push(candidates[id]!);
      if (picked.length >= limit) break;
    }
  }
  if (picked.length === 0) return candidates.slice(0, limit);
  return picked;
}

function parseRankedIds(text: string): number[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    const match = text.match(/\[\s*\d+(?:\s*,\s*\d+)*\s*\]/);
    if (!match) return [];
    try {
      parsed = JSON.parse(match[0]);
    } catch {
      return [];
    }
  }
  if (Array.isArray(parsed)) return parsed.filter(Number.isInteger);
  if (parsed && typeof parsed === "object") {
    const ids = (parsed as { ids?: unknown }).ids;
    if (Array.isArray(ids)) return ids.filter(Number.isInteger);
  }
  return [];
}

export function codemapToolDefinitions(
  config: WorkspaceConfig
): CompassToolDefinition[] {
  return [
    {
      name: "outline",
      description:
        "Return the full symbol outline for one source file from the cached repo map: top-level decls (with signatures and return types), their members (class methods, struct fields, enum variants, etc.), import edges, and the cached summary if available. Use this when you know the file you care about and want its structure without reading the raw bytes.",
      inputSchema: {
        path: z
          .string()
          .min(1)
          .describe("Repo-relative path, e.g. `src/repomap/cache.ts`."),
      },
      handler: async ({ path }) => {
        const cache = await readRepoMapCache(config);
        const rel = String(path);
        const entry = cache.files[rel];
        if (!entry) {
          return textResult(
            `No cached entry for \`${rel}\`. The file may not be tracked by git, may be in a language the indexer doesn't support, or the cache may need a rebuild.`,
            true
          );
        }
        return textResult(renderFileOutline(rel, entry));
      },
    },
    {
      name: "find_symbol",
      description:
        "Search the cached repo map for symbols by name (top-level decls AND members like class methods or struct fields). Default match is case-insensitive substring; pass `exact: true` for strict equality. Returns up to 50 hits with file path, line, kind, and parent (if any).",
      inputSchema: {
        name: z.string().min(1).describe("Symbol name or substring to match."),
        exact: z
          .boolean()
          .optional()
          .describe("If true, require exact-name equality. Default substring."),
      },
      handler: async ({ name, exact }) => {
        const cache = await readRepoMapCache(config);
        const queryText = String(name);
        const hits = searchSymbols(cache, queryText, exact === true);
        if (hits.length === 0) {
          return textResult(`No symbols matching \`${queryText}\` in the cache.`);
        }
        const capped = hits.slice(0, 50);
        const lines = capped.map((h) => {
          const parent = h.parent ? ` (in ${h.parent})` : "";
          return `${h.path}:${h.line}  ${h.kind} ${h.name}${parent}`;
        });
        if (hits.length > capped.length) {
          lines.push(`…(${hits.length - capped.length} more hits truncated)`);
        }
        return textResult(lines.join("\n"));
      },
    },
    {
      name: "list_files",
      description:
        "List indexed files from the cached repo map. Optionally filter by `dir` (repo-relative directory prefix) and `pattern` (case-insensitive substring on the path). Useful for exploring what's in a subtree.",
      inputSchema: {
        dir: z
          .string()
          .optional()
          .describe("Repo-relative directory prefix, e.g. `src/repomap`."),
        pattern: z
          .string()
          .optional()
          .describe("Case-insensitive substring filter on the path."),
      },
      handler: async ({ dir, pattern }) => {
        const cache = await readRepoMapCache(config);
        let paths = Object.keys(cache.files).sort();
        if (typeof dir === "string" && dir.length > 0) {
          const prefix = dir.endsWith("/") ? dir : `${dir}/`;
          paths = paths.filter((p) => p === dir || p.startsWith(prefix));
        }
        if (typeof pattern === "string" && pattern.length > 0) {
          const needle = pattern.toLowerCase();
          paths = paths.filter((p) => p.toLowerCase().includes(needle));
        }
        if (paths.length === 0) return textResult("(no matching files)");
        const lines = paths.map((p) => {
          const e = cache.files[p]!;
          return `${p}  (${e.language}, ${e.symbols.length} symbol${e.symbols.length === 1 ? "" : "s"})`;
        });
        return textResult(lines.join("\n"));
      },
    },
    {
      name: "importers_of",
      description:
        "Return the list of files whose resolved imports point at the given path. Use this to answer 'what breaks if I change this file?'. Only TS/JS/Python imports are resolved today; Go and Rust modules show up as external and won't appear here.",
      inputSchema: {
        path: z
          .string()
          .min(1)
          .describe("Repo-relative path of the file you want importers for."),
      },
      handler: async ({ path }) => {
        const cache = await readRepoMapCache(config);
        const index = buildImporterIndex(cache);
        const rel = String(path);
        const importers = index.get(rel) ?? [];
        if (importers.length === 0) {
          return textResult(
            `No resolved importers of \`${rel}\`. Either no files import it, or its callers are in a language whose imports aren't resolved (Go/Rust).`
          );
        }
        return textResult(importers.join("\n"));
      },
    },
    {
      name: "summary",
      description:
        "Return the Codex-generated one-paragraph summary of a single file. If the file's summary is missing or stale, generates one on the fly (and persists it). Returns null-ish text if the file isn't indexed or is too small to summarize.",
      inputSchema: {
        path: z
          .string()
          .min(1)
          .describe("Repo-relative path to summarize."),
      },
      handler: async ({ path }) => {
        const rel = String(path);
        const summary = await ensureSummary(config, rel);
        if (!summary) {
          return textResult(
            `No summary available for \`${rel}\` (not indexed, unreadable, or too small).`,
            true
          );
        }
        return textResult(summary);
      },
    },
    {
      name: "search",
      description:
        "Semantic search over the cached repo: ranks indexed files by relevance to a natural-language query using their Codex-generated summaries. Returns the top matches with their path and summary. Use this when you don't know which file to look at yet (e.g. 'where is the runner's abort signal threaded through?').",
      inputSchema: {
        query: z
          .string()
          .min(1)
          .describe("Natural-language query."),
        limit: z
          .number()
          .int()
          .positive()
          .max(MAX_SEARCH_LIMIT)
          .optional()
          .describe(
            `Max results to return (default ${DEFAULT_SEARCH_LIMIT}, hard cap ${MAX_SEARCH_LIMIT}).`
          ),
      },
      handler: async ({ query: q, limit }) => {
        const cache = await readRepoMapCache(config);
        const candidates: Array<{ path: string; summary: string }> = [];
        for (const [path, entry] of Object.entries(cache.files)) {
          if (entry.summary) candidates.push({ path, summary: entry.summary });
        }
        if (candidates.length === 0) {
          return textResult(
            "No file summaries available yet — search needs the codemap to be summarized first.",
            true
          );
        }
        const parsedLimit =
          typeof limit === "number" && Number.isFinite(limit)
            ? limit
            : DEFAULT_SEARCH_LIMIT;
        const cap = Math.min(parsedLimit, MAX_SEARCH_LIMIT);
        const ranked = await rankBySummary(
          String(q),
          candidates,
          config.implRepoPath,
          cap
        );
        const lines = ranked.map(
          (r) => `${r.path}\n  ${r.summary}`
        );
        return textResult(lines.join("\n\n"));
      },
    },
  ];
}

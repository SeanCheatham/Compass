/**
 * Built-in Compass guidance docs exposed as MCP tools. These are deliberately
 * small, local Markdown files: cheap to search, exact to read, and stable
 * enough to steer agents without bloating every prompt.
 */

import { readdir, readFile } from "node:fs/promises";
import { basename } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import { tool } from "@anthropic-ai/claude-agent-sdk";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";

interface BuiltinDoc {
  id: string;
  title: string;
  summary: string;
  body: string;
}

const DOCS_DIR = fileURLToPath(new URL("../docs/", import.meta.url));
const MAX_RESULTS = 10;

let docsCache: Promise<BuiltinDoc[]> | null = null;

function textResult(text: string, isError = false): CallToolResult {
  return {
    content: [{ type: "text", text }],
    ...(isError ? { isError: true } : {}),
  };
}

async function loadDocs(): Promise<BuiltinDoc[]> {
  if (!docsCache) docsCache = readDocs();
  return docsCache;
}

async function readDocs(): Promise<BuiltinDoc[]> {
  let names: string[];
  try {
    names = await readdir(DOCS_DIR);
  } catch {
    return [];
  }

  const docs: BuiltinDoc[] = [];
  for (const name of names.sort()) {
    if (!name.endsWith(".md")) continue;
    const path = `${DOCS_DIR}/${name}`;
    let body: string;
    try {
      body = await readFile(path, "utf-8");
    } catch {
      continue;
    }
    const id = basename(name, ".md");
    docs.push({
      id,
      title: extractTitle(body) ?? id,
      summary: extractSummary(body),
      body,
    });
  }
  return docs;
}

function extractTitle(body: string): string | null {
  for (const line of body.split("\n")) {
    const m = line.match(/^#\s+(.+?)\s*$/);
    if (m) return m[1]!;
  }
  return null;
}

function extractSummary(body: string): string {
  const lines = body.split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    return trimmed;
  }
  return "";
}

function terms(query: string): string[] {
  return query
    .toLowerCase()
    .split(/[^a-z0-9_/-]+/)
    .filter((t) => t.length > 1);
}

function scoreDoc(doc: BuiltinDoc, queryTerms: string[]): number {
  const title = doc.title.toLowerCase();
  const id = doc.id.toLowerCase();
  const summary = doc.summary.toLowerCase();
  const body = doc.body.toLowerCase();
  let score = 0;
  for (const term of queryTerms) {
    if (id.includes(term)) score += 8;
    if (title.includes(term)) score += 6;
    if (summary.includes(term)) score += 4;
    if (body.includes(term)) score += 1;
  }
  return score;
}

function snippet(doc: BuiltinDoc, queryTerms: string[]): string {
  const paragraphs = doc.body
    .split(/\n\s*\n/)
    .map((p) => p.replace(/\s+/g, " ").trim())
    .filter(Boolean);
  for (const p of paragraphs) {
    const lower = p.toLowerCase();
    if (queryTerms.some((term) => lower.includes(term))) {
      return p.length > 220 ? `${p.slice(0, 217)}...` : p;
    }
  }
  return doc.summary;
}

export async function searchBuiltinDocs(
  query: string,
  limit = 5
): Promise<string> {
  const all = await loadDocs();
  const queryTerms = terms(query);
  const ranked = all
    .map((doc) => ({
      doc,
      score: scoreDoc(doc, queryTerms),
    }))
    .filter((r) => r.score > 0)
    .sort((a, b) => b.score - a.score || a.doc.id.localeCompare(b.doc.id))
    .slice(0, Math.min(Math.max(1, limit), MAX_RESULTS));

  if (ranked.length === 0) return "(no matching docs)";
  return ranked
    .map(({ doc }) => {
      return `- ${doc.id}: ${doc.title}\n  ${snippet(doc, queryTerms)}`;
    })
    .join("\n");
}

export async function readBuiltinDoc(
  id: string
): Promise<{ ok: true; text: string } | { ok: false; text: string }> {
  const all = await loadDocs();
  const doc = all.find((d) => d.id === id);
  if (!doc) {
    const ids = all.map((d) => d.id).join(", ") || "(none)";
    return { ok: false, text: `Unknown doc id \`${id}\`. Available docs: ${ids}` };
  }
  return { ok: true, text: doc.body };
}

export function docsTools() {
  return [
    tool(
      "search_docs",
      "Search Compass's built-in Markdown guidance docs by natural-language query. Use this before broad implementation choices when you want the local factory conventions for quality, tests, workflow, or agent behaviour.",
      {
        query: z.string().min(1).describe("What guidance to search for."),
        limit: z
          .number()
          .int()
          .positive()
          .max(MAX_RESULTS)
          .optional()
          .describe(`Max results to return (default 5, hard cap ${MAX_RESULTS}).`),
      },
      async ({ query, limit }) => {
        return textResult(await searchBuiltinDocs(query, limit ?? 5));
      }
    ),
    tool(
      "read_doc",
      "Read one complete built-in Compass Markdown guidance doc by id. Use an id returned by search_docs.",
      {
        id: z.string().min(1).describe("Doc id, e.g. `software-quality`."),
      },
      async ({ id }) => {
        const result = await readBuiltinDoc(id);
        return textResult(result.text, !result.ok);
      }
    ),
  ];
}

import { extname } from "node:path";

export type Language = "ts" | "js" | "py" | "go" | "rs";

export interface Symbol {
  kind: string;
  name: string;
  line: number;
}

const LANG_BY_EXT: Record<string, Language> = {
  ".ts": "ts",
  ".tsx": "ts",
  ".mts": "ts",
  ".cts": "ts",
  ".js": "js",
  ".jsx": "js",
  ".mjs": "js",
  ".cjs": "js",
  ".py": "py",
  ".go": "go",
  ".rs": "rs",
};

export function detectLanguage(path: string): Language | null {
  return LANG_BY_EXT[extname(path).toLowerCase()] ?? null;
}

interface PatternSet {
  kind: string;
  pattern: RegExp;
}

const TS_JS: PatternSet[] = [
  {
    kind: "function",
    pattern:
      /^(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s*\*?\s+([A-Za-z_$][\w$]*)/gm,
  },
  {
    kind: "class",
    pattern:
      /^(?:export\s+(?:default\s+)?)?(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)/gm,
  },
  {
    kind: "interface",
    pattern: /^(?:export\s+)?interface\s+([A-Za-z_$][\w$]*)/gm,
  },
  {
    kind: "type",
    pattern: /^(?:export\s+)?type\s+([A-Za-z_$][\w$]*)\s*=/gm,
  },
  {
    kind: "enum",
    pattern: /^(?:export\s+)?(?:const\s+)?enum\s+([A-Za-z_$][\w$]*)/gm,
  },
  {
    kind: "const",
    pattern: /^export\s+(?:const|let|var)\s+([A-Za-z_$][\w$]*)/gm,
  },
];

const PY: PatternSet[] = [
  { kind: "function", pattern: /^(?:async\s+)?def\s+([A-Za-z_]\w*)/gm },
  { kind: "class", pattern: /^class\s+([A-Za-z_]\w*)/gm },
];

const GO: PatternSet[] = [
  { kind: "func", pattern: /^func\s+(?:\([^)]*\)\s+)?([A-Za-z_]\w*)/gm },
  { kind: "type", pattern: /^type\s+([A-Za-z_]\w*)/gm },
  { kind: "const", pattern: /^const\s+([A-Za-z_]\w*)/gm },
  { kind: "var", pattern: /^var\s+([A-Za-z_]\w*)/gm },
];

const RUST: PatternSet[] = [
  {
    kind: "fn",
    pattern:
      /^(?:pub(?:\([^)]*\))?\s+)?(?:const\s+|async\s+|unsafe\s+)*fn\s+([A-Za-z_]\w*)/gm,
  },
  {
    kind: "struct",
    pattern: /^(?:pub(?:\([^)]*\))?\s+)?struct\s+([A-Za-z_]\w*)/gm,
  },
  {
    kind: "enum",
    pattern: /^(?:pub(?:\([^)]*\))?\s+)?enum\s+([A-Za-z_]\w*)/gm,
  },
  {
    kind: "trait",
    pattern: /^(?:pub(?:\([^)]*\))?\s+)?(?:unsafe\s+)?trait\s+([A-Za-z_]\w*)/gm,
  },
  {
    kind: "type",
    pattern: /^(?:pub(?:\([^)]*\))?\s+)?type\s+([A-Za-z_]\w*)/gm,
  },
  {
    kind: "mod",
    pattern: /^(?:pub(?:\([^)]*\))?\s+)?mod\s+([A-Za-z_]\w*)/gm,
  },
  {
    kind: "const",
    pattern: /^(?:pub(?:\([^)]*\))?\s+)?const\s+([A-Z_][A-Z0-9_]*)/gm,
  },
  {
    kind: "static",
    pattern: /^(?:pub(?:\([^)]*\))?\s+)?static\s+([A-Z_][A-Z0-9_]*)/gm,
  },
  {
    kind: "impl",
    pattern:
      /^impl(?:\s*<[^>]*>)?\s+([A-Za-z_]\w*(?:\s*<[^>]*>)?)\s+for\s+([A-Za-z_]\w*)/gm,
  },
  {
    kind: "impl",
    pattern: /^impl(?:\s*<[^>]*>)?\s+([A-Za-z_]\w*)\b(?!\s+for)/gm,
  },
];

const PATTERNS_BY_LANG: Record<Language, PatternSet[]> = {
  ts: TS_JS,
  js: TS_JS,
  py: PY,
  go: GO,
  rs: RUST,
};

function attachLineNumbers<T extends { offset: number }>(
  text: string,
  matches: T[]
): Array<T & { line: number }> {
  if (matches.length === 0) return [];

  const sorted = [...matches].sort((a, b) => a.offset - b.offset);
  const result: Array<T & { line: number }> = [];

  let cursor = 0;
  let line = 1;
  for (const m of sorted) {
    while (cursor < m.offset) {
      if (text.charCodeAt(cursor) === 10) line++;
      cursor++;
    }
    result.push({ ...m, line });
  }
  return result;
}

export function extractSymbols(text: string, language: Language): Symbol[] {
  const patterns = PATTERNS_BY_LANG[language];
  if (!patterns) return [];

  type RawMatch = { offset: number; kind: string; name: string };
  const raw: RawMatch[] = [];

  for (const { kind, pattern } of patterns) {
    pattern.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = pattern.exec(text)) !== null) {
      const name =
        kind === "impl" && m[2]
          ? `${m[1].replace(/\s+/g, " ").trim()} for ${m[2]}`
          : m[1];
      raw.push({ offset: m.index, kind, name });
    }
  }

  const withLines = attachLineNumbers(text, raw);

  const seen = new Set<string>();
  const out: Symbol[] = [];
  for (const r of withLines) {
    const key = `${r.line}:${r.name}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ kind: r.kind, name: r.name, line: r.line });
  }
  return out;
}

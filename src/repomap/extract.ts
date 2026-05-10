import { extname } from "node:path";

export type Language = "ts" | "js" | "py" | "go" | "rs" | "md";

export interface Symbol {
  kind: string;
  name: string;
  line: number;
  /** Parameter list for function-like decls, e.g. `"a: number, b: string"`. Empty string for no-arg functions. Absent for non-functions. */
  signature?: string;
  /** Return type for TS function-like decls, e.g. `"Promise<void>"`. Absent if no annotation, JS, or non-function. */
  returnType?: string;
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
  ".md": "md",
  ".markdown": "md",
};

/** Function-like kinds whose signatures we extract. */
const SIGNATURE_KINDS = new Set(["function", "func", "fn"]);

/** Cap rendered signature length. */
const MAX_SIGNATURE_CHARS = 80;

/** Cap rendered return type length. */
const MAX_RETURN_TYPE_CHARS = 60;

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

const MD: PatternSet[] = [
  { kind: "h1", pattern: /^#\s+(.+?)\s*$/gm },
  { kind: "h2", pattern: /^##\s+(.+?)\s*$/gm },
  { kind: "h3", pattern: /^###\s+(.+?)\s*$/gm },
];

const PATTERNS_BY_LANG: Record<Language, PatternSet[]> = {
  ts: TS_JS,
  js: TS_JS,
  py: PY,
  go: GO,
  rs: RUST,
  md: MD,
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

/**
 * Given the full file text and an offset (typically the end of a `function`/`def`/`func`/`fn` regex match),
 * scan forward for the next `(`, then walk to find the matching `)`. Returns the inner text with whitespace
 * collapsed to single spaces and truncated to `MAX_SIGNATURE_CHARS` (with `…` suffix if exceeded).
 * Returns `null` if no balanced `(...)` is found within a reasonable scan window.
 */
export function extractSignature(text: string, fromOffset: number): string | null {
  const SCAN_LIMIT = 4096; // don't scan to EOF for malformed input
  const open = text.indexOf("(", fromOffset);
  if (open === -1 || open - fromOffset > SCAN_LIMIT) return null;

  let depth = 0;
  for (let i = open; i < text.length && i - open < SCAN_LIMIT; i++) {
    const c = text.charCodeAt(i);
    if (c === 40) depth++;       // (
    else if (c === 41) {         // )
      depth--;
      if (depth === 0) {
        const inner = text.slice(open + 1, i).replace(/\s+/g, " ").trim();
        if (inner.length <= MAX_SIGNATURE_CHARS) return inner;
        return inner.slice(0, MAX_SIGNATURE_CHARS - 1) + "…";
      }
    }
  }
  return null;
}

/**
 * Given the full file text and an offset (typically the end of a `function` regex match),
 * scan forward to the args' closing `)`, then look for `:` (TS return-type annotation).
 * Walk balanced `<>`, `()`, `[]` until hitting a depth-0 `{`, `;`, or newline. Returns the
 * inner text with whitespace collapsed and truncated to MAX_RETURN_TYPE_CHARS (suffix `…`).
 * Returns null if no `(...)`, no `:`, or the type would be empty. Treats `=>` as a token
 * (does not decrement depth on the `>` of `=>`).
 */
export function extractReturnType(text: string, fromOffset: number): string | null {
  const SCAN_LIMIT = 4096;
  // Step 1: find args' close paren.
  const open = text.indexOf("(", fromOffset);
  if (open === -1 || open - fromOffset > SCAN_LIMIT) return null;
  let depth = 0;
  let close = -1;
  for (let i = open; i < text.length && i - open < SCAN_LIMIT; i++) {
    const c = text.charCodeAt(i);
    if (c === 40) depth++;
    else if (c === 41) {
      depth--;
      if (depth === 0) {
        close = i;
        break;
      }
    }
  }
  if (close === -1) return null;

  // Step 2: skip whitespace, expect ':'.
  let i = close + 1;
  while (i < text.length && /\s/.test(text[i]!)) i++;
  if (text[i] !== ":") return null;
  i++;
  // Skip whitespace after ':'.
  while (i < text.length && (text[i] === " " || text[i] === "\t")) i++;

  // Step 3: walk return type with bracket depth tracking.
  const start = i;
  let bd = 0;
  for (; i < text.length && i - start < SCAN_LIMIT; i++) {
    const c = text.charCodeAt(i);
    if (c === 60 /* < */ || c === 40 /* ( */ || c === 91 /* [ */) bd++;
    else if (c === 62 /* > */) {
      // Don't underflow on the '>' of '=>'.
      if (i > start && text.charCodeAt(i - 1) === 61 /* = */) {
        // skip
      } else bd--;
    } else if (c === 41 /* ) */ || c === 93 /* ] */) bd--;
    else if (
      bd === 0 &&
      (c === 123 /* { */ || c === 59 /* ; */ || c === 10 /* \n */)
    ) {
      break;
    }
  }

  const inner = text.slice(start, i).replace(/\s+/g, " ").trim();
  if (inner.length === 0) return null;
  if (inner.length <= MAX_RETURN_TYPE_CHARS) return inner;
  return inner.slice(0, MAX_RETURN_TYPE_CHARS - 1) + "…";
}

export function extractSymbols(text: string, language: Language): Symbol[] {
  const patterns = PATTERNS_BY_LANG[language];
  if (!patterns) return [];

  type RawMatch = { offset: number; kind: string; name: string; matchEnd: number };
  const raw: RawMatch[] = [];

  for (const { kind, pattern } of patterns) {
    pattern.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = pattern.exec(text)) !== null) {
      const name =
        kind === "impl" && m[2]
          ? `${m[1].replace(/\s+/g, " ").trim()} for ${m[2]}`
          : m[1];
      raw.push({ offset: m.index, kind, name, matchEnd: m.index + m[0].length });
    }
  }

  const withLines = attachLineNumbers(text, raw);

  const seen = new Set<string>();
  const out: Symbol[] = [];
  for (const r of withLines) {
    const key = `${r.line}:${r.name}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const sym: Symbol = { kind: r.kind, name: r.name, line: r.line };
    if (SIGNATURE_KINDS.has(r.kind)) {
      const sig = extractSignature(text, r.matchEnd);
      if (sig !== null) sym.signature = sig;
      // Only TS gets return types; for JS the parser returns null because there's no `:`.
      if (language === "ts") {
        const ret = extractReturnType(text, r.matchEnd);
        if (ret !== null) sym.returnType = ret;
      }
    }
    out.push(sym);
  }
  return out;
}

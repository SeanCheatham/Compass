import { extname } from "node:path";

export type Language = "ts" | "js" | "py" | "go" | "rs" | "md";

export interface Symbol {
  kind: string;
  name: string;
  line: number;
  /** Parameter list for function-like decls, e.g. `"a: number, b: string"`. Empty string for no-arg functions. Absent for non-functions. */
  signature?: string;
  /** Return type for TS/Python/Rust/Go function-like decls (TS `: Type`, Python/Rust `-> Type`, Go bare/parenthesized after args). Absent if no annotation, JS, or non-function. */
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

const PATTERNS_BY_LANG: Partial<Record<Language, PatternSet[]>> = {
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
 * TS variant: given the full file text and an offset (typically the end of a function regex match),
 * scan forward to the args' closing `)`, then look for `:` (TS return-type annotation).
 * Walk balanced `<>`, `()`, `[]`, `{}` until hitting a depth-0 `{` (body), `;`, or newline.
 * `{}` tracking lets inline object types like `{ a: string }`, intersections (`Foo & { x }`), and
 * unions (`string | { x }`) be captured as part of the return type. Body `{` is distinguished from
 * inline-object `{` by the previous non-whitespace char: body `{` follows a type-end (`)`, `]`, `>`,
 * `}`, alphanumeric, `_`, `$`, `?`); inline-object `{` follows an operator/separator (`:`, `&`, `|`,
 * `(`, `<`, `[`, `,`) or is the first non-whitespace char. Treats `=>` as a token (does not
 * decrement depth on the `>` of `=>`). Returns the inner text with whitespace collapsed and
 * truncated to MAX_RETURN_TYPE_CHARS (suffix `…`). Returns null if no `(...)`, no `:`, or empty inner.
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
  // Track `{}` depth so inline object types like `{ a: string }`, intersections (`Foo & { x }`),
  // and unions (`string | { x }`) are walked as part of the return type. Distinguish the body `{`
  // from an inline-object `{` by the previous non-whitespace char: body `{` follows a type-end
  // (`)`, `]`, `>`, `}`, or alphanumeric/`_`/`$`/`?`); inline-object `{` follows an operator/
  // separator (`:`, `&`, `|`, `(`, `<`, `[`, `,`) or is the first non-whitespace char of the type.
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
    } else if (c === 41 /* ) */ || c === 93 /* ] */ || c === 125 /* } */) bd--;
    else if (c === 123 /* { */) {
      if (bd > 0) {
        // Already inside something; this `{` is type-internal.
        bd++;
      } else {
        // bd === 0. Look back at last non-whitespace char to decide body vs inline-object.
        let j = i - 1;
        while (j >= start && /\s/.test(text[j]!)) j--;
        const prev = j >= start ? text.charCodeAt(j) : -1;
        const isTypeEnd =
          prev === 41 /* ) */ ||
          prev === 93 /* ] */ ||
          prev === 62 /* > */ ||
          prev === 125 /* } */ ||
          prev === 63 /* ? */ ||
          (prev >= 48 && prev <= 57) /* 0-9 */ ||
          (prev >= 65 && prev <= 90) /* A-Z */ ||
          (prev >= 97 && prev <= 122) /* a-z */ ||
          prev === 95 /* _ */ ||
          prev === 36 /* $ */;
        if (isTypeEnd) break; // body `{` — terminate.
        bd++; // inline-object `{` — push depth.
      }
    } else if (bd === 0 && (c === 59 /* ; */ || c === 10 /* \n */)) break;
  }

  const inner = text.slice(start, i).replace(/\s+/g, " ").trim();
  if (inner.length === 0) return null;
  if (inner.length <= MAX_RETURN_TYPE_CHARS) return inner;
  return inner.slice(0, MAX_RETURN_TYPE_CHARS - 1) + "…";
}

/**
 * Python variant: given the full file text and an offset (typically the end of a `def` regex match),
 * scan forward to the args' closing `)`, then look for `->`. Walk balanced `[]`, `()`, `{}` until
 * hitting a depth-0 `:` (signature end) or `\n` (defensive). Returns the inner text with whitespace
 * collapsed and truncated to MAX_RETURN_TYPE_CHARS (suffix `…`). Returns null if no `(...)`,
 * no `->`, or the type would be empty.
 */
export function extractPythonReturnType(text: string, fromOffset: number): string | null {
  const SCAN_LIMIT = 4096;
  // Step 1: find args' close paren (same as TS version).
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

  // Step 2: skip whitespace (incl. newlines), expect `->`.
  let i = close + 1;
  while (i < text.length && /\s/.test(text[i]!)) i++;
  if (text[i] !== "-" || text[i + 1] !== ">") return null;
  i += 2;
  // Skip whitespace after '->' (allow newlines too — multiline annotations).
  while (i < text.length && /\s/.test(text[i]!)) i++;

  // Step 3: walk return type with bracket depth on [, (, {.
  const start = i;
  let bd = 0;
  for (; i < text.length && i - start < SCAN_LIMIT; i++) {
    const c = text.charCodeAt(i);
    if (c === 91 /* [ */ || c === 40 /* ( */ || c === 123 /* { */) bd++;
    else if (c === 93 /* ] */ || c === 41 /* ) */ || c === 125 /* } */) bd--;
    else if (bd === 0 && (c === 58 /* : */ || c === 10 /* \n */)) break;
  }

  const inner = text.slice(start, i).replace(/\s+/g, " ").trim();
  if (inner.length === 0) return null;
  if (inner.length <= MAX_RETURN_TYPE_CHARS) return inner;
  return inner.slice(0, MAX_RETURN_TYPE_CHARS - 1) + "…";
}

/**
 * Rust variant: given the full file text and an offset (typically the end of an `fn` regex match),
 * scan forward to the args' closing `)`, then look for `->`. Walk balanced `<>`, `()`, `[]` (NOT `{}` —
 * `{` opens the function body) until hitting a depth-0 `{` (body), `;` (trait method), `\n` (defensive),
 * or the literal token `where` (clause start). Returns the inner text with whitespace collapsed and
 * truncated to MAX_RETURN_TYPE_CHARS (suffix `…`). Returns null if no `(...)`, no `->`, or the type
 * would be empty. Treats `->` as a token (does not decrement depth on the `>` of `->`).
 */
export function extractRustReturnType(text: string, fromOffset: number): string | null {
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

  // Step 2: skip whitespace, expect `->`.
  let i = close + 1;
  while (i < text.length && /\s/.test(text[i]!)) i++;
  if (text[i] !== "-" || text[i + 1] !== ">") return null;
  i += 2;
  while (i < text.length && /\s/.test(text[i]!)) i++;

  // Step 3: walk return type. Depth on `<`, `(`, `[`. Don't underflow on `>` of `->`.
  const start = i;
  let bd = 0;
  for (; i < text.length && i - start < SCAN_LIMIT; i++) {
    const c = text.charCodeAt(i);
    if (c === 60 /* < */ || c === 40 /* ( */ || c === 91 /* [ */) bd++;
    else if (c === 62 /* > */) {
      // Don't underflow on the '>' of '->'.
      if (i > start && text.charCodeAt(i - 1) === 45 /* - */) {
        // skip
      } else bd--;
    } else if (c === 41 /* ) */ || c === 93 /* ] */) bd--;
    else if (bd === 0) {
      if (c === 123 /* { */ || c === 59 /* ; */ || c === 10 /* \n */) break;
      // `where` keyword: must be preceded and followed by non-word characters.
      if (
        c === 119 /* 'w' */ &&
        text.charCodeAt(i + 1) === 104 /* 'h' */ &&
        text.charCodeAt(i + 2) === 101 /* 'e' */ &&
        text.charCodeAt(i + 3) === 114 /* 'r' */ &&
        text.charCodeAt(i + 4) === 101 /* 'e' */ &&
        (i === start || /\W/.test(text[i - 1]!)) &&
        (i + 5 >= text.length || /\W/.test(text[i + 5]!))
      ) break;
    }
  }

  const inner = text.slice(start, i).replace(/\s+/g, " ").trim();
  if (inner.length === 0) return null;
  if (inner.length <= MAX_RETURN_TYPE_CHARS) return inner;
  return inner.slice(0, MAX_RETURN_TYPE_CHARS - 1) + "…";
}

/**
 * Go variant: given the full file text and an offset (typically the end of a `func` regex match),
 * scan forward to the args' closing `)`, then read the bare/parenthesized return type up to body
 * `{` or newline. Walks balanced `[]`, `()`, and `{}` (the latter only when type-internal or when
 * preceded by the `interface`/`struct` keyword — the only Go forms where `{` belongs to the type).
 * Body `{` at depth 0 is distinguished from an anonymous-type `{` by inspecting the run of word
 * characters immediately preceding (after whitespace): only `interface` or `struct` triggers an
 * inline-type push. Does NOT track `<>` since Go uses `<-` / `chan<-` as standalone tokens, not
 * brackets. If first non-whitespace after args' `)` is `{`, returns null (no return type). Returns
 * the inner text with whitespace collapsed and truncated to MAX_RETURN_TYPE_CHARS (suffix `…`).
 */
export function extractGoReturnType(text: string, fromOffset: number): string | null {
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
      if (depth === 0) { close = i; break; }
    }
  }
  if (close === -1) return null;

  // Step 2: skip whitespace (incl. newlines) past args' `)`.
  let i = close + 1;
  while (i < text.length && /\s/.test(text[i]!)) i++;
  // No `->` to find; if first non-ws is `{`, there is no return type.
  if (text[i] === "{") return null;

  // Step 3: walk return type. Depth on `[`, `(`, and `{` (latter only when type-internal
  // or when the `{` follows the `interface`/`struct` keyword — the only Go syntactic forms
  // where `{` is part of the type rather than the function body). Distinguish body `{` from
  // an anonymous-type `{` at depth 0 by inspecting the previous run of word characters.
  const start = i;
  let bd = 0;
  for (; i < text.length && i - start < SCAN_LIMIT; i++) {
    const c = text.charCodeAt(i);
    if (c === 91 /* [ */ || c === 40 /* ( */) bd++;
    else if (c === 93 /* ] */ || c === 41 /* ) */ || c === 125 /* } */) bd--;
    else if (c === 123 /* { */) {
      if (bd > 0) {
        bd++; // type-internal
      } else {
        // bd === 0: distinguish anonymous `interface{`/`struct{` from body `{`.
        let j = i - 1;
        while (j >= start && /\s/.test(text[j]!)) j--;
        const wordEnd = j + 1;
        while (j >= start) {
          const cc = text.charCodeAt(j);
          const isWord =
            (cc >= 48 && cc <= 57) /* 0-9 */ ||
            (cc >= 65 && cc <= 90) /* A-Z */ ||
            (cc >= 97 && cc <= 122) /* a-z */ ||
            cc === 95 /* _ */;
          if (!isWord) break;
          j--;
        }
        const word = text.slice(j + 1, wordEnd);
        if (word === "interface" || word === "struct") {
          bd++;
        } else {
          break; // body `{` — terminate.
        }
      }
    } else if (bd === 0 && c === 10 /* \n */) break;
  }

  const inner = text.slice(start, i).replace(/\s+/g, " ").trim();
  if (inner.length === 0) return null;
  if (inner.length <= MAX_RETURN_TYPE_CHARS) return inner;
  return inner.slice(0, MAX_RETURN_TYPE_CHARS - 1) + "…";
}

/**
 * Markdown variant: walk the file line-by-line, tracking fenced-code-block state.
 * Emit h1/h2/h3 symbols only for column-0 heading lines that fall OUTSIDE a fence.
 * Recognizes both backtick and tilde fences with up to 3 leading spaces;
 * a close fence must use the same character, with length >= open, and only whitespace
 * after the marker run. Unclosed fences suppress headings until EOF.
 */
function extractMarkdownSymbols(text: string): Symbol[] {
  const out: Symbol[] = [];
  let inFence = false;
  let fenceChar = ""; // "`" or "~"
  let fenceLen = 0;

  const fenceRe = /^( {0,3})(`{3,}|~{3,})(.*)$/;
  const headingRe = /^(#{1,3})\s+(.+?)\s*$/;

  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const lineText = lines[i]!;
    const lineNum = i + 1;

    // Fence detection: up to 3 leading spaces, then a run of >=3 backticks or >=3 tildes.
    const fenceMatch = lineText.match(fenceRe);
    if (fenceMatch) {
      const marker = fenceMatch[2]!;
      const after = fenceMatch[3]!;
      const ch = marker[0]!;
      const len = marker.length;
      if (!inFence) {
        // Open fence. Info string allowed.
        inFence = true;
        fenceChar = ch;
        fenceLen = len;
        continue;
      }
      // Close-fence candidate: same char, length >= open, only whitespace after.
      if (ch === fenceChar && len >= fenceLen && /^\s*$/.test(after)) {
        inFence = false;
        fenceChar = "";
        fenceLen = 0;
        continue;
      }
      // Otherwise fall through — treat as content within the open fence.
    }

    if (inFence) continue;

    // Heading match — column-0 anchored, identical to legacy regex semantics.
    const h = lineText.match(headingRe);
    if (h) {
      const level = h[1]!.length;
      out.push({ kind: `h${level}`, name: h[2]!, line: lineNum });
    }
  }

  return out;
}

export function extractSymbols(text: string, language: Language): Symbol[] {
  if (language === "md") return extractMarkdownSymbols(text);

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
      if (language === "ts") {
        const ret = extractReturnType(text, r.matchEnd);
        if (ret !== null) sym.returnType = ret;
      } else if (language === "py") {
        const ret = extractPythonReturnType(text, r.matchEnd);
        if (ret !== null) sym.returnType = ret;
      } else if (language === "rs") {
        const ret = extractRustReturnType(text, r.matchEnd);
        if (ret !== null) sym.returnType = ret;
      } else if (language === "go") {
        const ret = extractGoReturnType(text, r.matchEnd);
        if (ret !== null) sym.returnType = ret;
      }
    }
    out.push(sym);
  }
  return out;
}

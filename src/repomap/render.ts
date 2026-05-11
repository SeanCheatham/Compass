import type { FileEntry } from "./cache.js";

export interface RenderOptions {
  /** Hard cap on output character count. Defaults to ~32k chars. */
  maxChars?: number;
}

const DEFAULT_MAX_CHARS = 32_000;

/**
 * Render the cache as a compact symbol map, grouped by file.
 * Files are sorted alphabetically. If the budget overflows, later files
 * are dropped and a `(N more files omitted)` line is appended. Members
 * (class methods, struct fields, etc.) are indented under their parent
 * symbol; agents can still query the full structured data via MCP tools.
 */
export function renderRepoMap(
  files: Record<string, FileEntry>,
  opts: RenderOptions = {}
): string {
  const max = opts.maxChars ?? DEFAULT_MAX_CHARS;
  const paths = Object.keys(files).sort();
  if (paths.length === 0) return "_(no source files indexed yet)_";

  const blocks: string[] = [];
  let used = 0;
  let included = 0;

  for (const path of paths) {
    const entry = files[path];
    if (entry.symbols.length === 0) continue;

    const lines: string[] = [`${path}:`];
    for (const sym of entry.symbols) {
      const sigPart = sym.signature !== undefined ? `(${sym.signature})` : "";
      const retPart = sym.returnType !== undefined ? `: ${sym.returnType}` : "";
      lines.push(`  ${sym.kind} ${sym.name}${sigPart}${retPart} (L${sym.line})`);
      if (sym.members) {
        for (const m of sym.members) {
          const msig = m.signature !== undefined ? `(${m.signature})` : "";
          const mret = m.returnType !== undefined ? `: ${m.returnType}` : "";
          lines.push(`    ${m.kind} ${m.name}${msig}${mret} (L${m.line})`);
        }
      }
    }
    const block = lines.join("\n");

    if (used + block.length + 1 > max && included > 0) {
      const omitted = paths.length - included;
      blocks.push(`(${omitted} more file${omitted === 1 ? "" : "s"} omitted)`);
      break;
    }

    blocks.push(block);
    used += block.length + 1;
    included++;
  }

  if (blocks.length === 0) return "_(no top-level symbols found)_";
  return blocks.join("\n");
}

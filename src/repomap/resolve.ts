import { dirname, posix } from "node:path";
import type { Language } from "./cache.js";

/**
 * Resolve a raw import string against the importer's location and the set of
 * known repo-relative paths. Returns a repo-relative path if the import points
 * inside the repo, or null if it's external/unresolvable.
 *
 * Currently supports TS/TSX/JS (relative + index files, with the NodeNext
 * `.js` → `.ts` swap) and Python (relative `from .pkg import …` only). Go
 * and Rust use module-path imports that would need go.mod / mod-tree parsing
 * to resolve and stay unresolved for now.
 */
export function resolveImport(
  importerRel: string,
  raw: string,
  fileSet: ReadonlySet<string>,
  language: Language
): string | null {
  switch (language) {
    case "ts":
    case "tsx":
    case "js":
      return resolveJsLike(importerRel, raw, fileSet);
    case "py":
      return resolvePython(importerRel, raw, fileSet);
    default:
      return null;
  }
}

// ------------------------------------------------------------------ TS / JS / TSX

const TS_LIKE_CANDIDATE_EXTS = [
  // Try exact (raw may already include the ext) first.
  "",
  ".ts",
  ".tsx",
  ".js",
  ".jsx",
  ".mts",
  ".cts",
  ".mjs",
  ".cjs",
];

const TS_LIKE_INDEX_EXTS = [
  "/index.ts",
  "/index.tsx",
  "/index.js",
  "/index.jsx",
  "/index.mts",
  "/index.cts",
  "/index.mjs",
  "/index.cjs",
];

function resolveJsLike(
  importerRel: string,
  raw: string,
  fileSet: ReadonlySet<string>
): string | null {
  if (!raw.startsWith("./") && !raw.startsWith("../") && raw !== "." && raw !== "..") {
    // Bare specifier, scoped package, builtin, or absolute URL — external.
    return null;
  }

  const importerDir = dirname(importerRel);
  // NodeNext convention: source written with `.js` resolves to `.ts` on disk.
  const candidates = generateJsLikeCandidates(raw);

  for (const cand of candidates) {
    const joined = posix.normalize(posix.join(importerDir, cand));
    if (fileSet.has(joined)) return joined;
  }
  return null;
}

function generateJsLikeCandidates(raw: string): string[] {
  const out: string[] = [];
  // If the import already has an explicit known extension, try it as-is and
  // also try the .ts swap.
  const knownExt = /\.(?:[mc]?[jt]sx?)$/i.test(raw);

  for (const ext of TS_LIKE_CANDIDATE_EXTS) {
    if (ext === "") {
      if (knownExt) out.push(raw);
      // skip bare extensionless: handled via the explicit ext loop
    } else {
      // Strip trailing `.js`/`.mjs`/`.cjs`/`.jsx` so we can append `.ts` etc.
      const stripped = raw.replace(/\.(?:[mc]?[jt]sx?)$/i, "");
      out.push(stripped + ext);
    }
  }
  for (const idx of TS_LIKE_INDEX_EXTS) {
    const stripped = raw.replace(/\.(?:[mc]?[jt]sx?)$/i, "");
    out.push(stripped + idx);
  }
  return out;
}

// ---------------------------------------------------------------- Python

function resolvePython(
  importerRel: string,
  raw: string,
  fileSet: ReadonlySet<string>
): string | null {
  if (!raw.startsWith(".")) {
    // Absolute / package import — would need a package-root lookup to resolve.
    return null;
  }

  // Count leading dots: `.foo` = current pkg, `..foo` = parent, etc.
  let dots = 0;
  while (raw[dots] === ".") dots++;
  const rest = raw.slice(dots);

  let baseDir = dirname(importerRel);
  // First dot is the current package (no upward step). Each subsequent dot
  // moves up one directory.
  for (let i = 1; i < dots; i++) {
    baseDir = dirname(baseDir);
    if (baseDir === ".") {
      baseDir = "";
      break;
    }
  }

  const subPath = rest.replace(/\./g, "/");
  const candidates: string[] = [];
  const baseJoin = (p: string) =>
    posix.normalize(posix.join(baseDir || ".", p));
  if (subPath.length > 0) {
    candidates.push(baseJoin(`${subPath}.py`));
    candidates.push(baseJoin(`${subPath}/__init__.py`));
  } else {
    candidates.push(baseJoin("__init__.py"));
  }

  for (const cand of candidates) {
    const norm = cand.startsWith("./") ? cand.slice(2) : cand;
    if (fileSet.has(norm)) return norm;
  }
  return null;
}

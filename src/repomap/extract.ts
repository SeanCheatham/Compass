import Parser from "tree-sitter";
import TS from "tree-sitter-typescript";
import JS from "tree-sitter-javascript";
import PY from "tree-sitter-python";
import GO from "tree-sitter-go";
import RS from "tree-sitter-rust";
import type {
  ImportRef,
  Language,
  Member,
  Symbol as RepoSymbol,
} from "./cache.js";

export type { Language, Member, RepoSymbol as Symbol };
export { detectLanguage } from "./cache.js";

/** Cap rendered signature length. */
const MAX_SIGNATURE_CHARS = 80;
/** Cap rendered return type length. */
const MAX_RETURN_TYPE_CHARS = 60;

export interface ExtractResult {
  symbols: RepoSymbol[];
  imports: ImportRef[];
}

// Lazy parser cache. Tree-sitter parsers are stateful but reusable; we keep
// one per language to amortize the C-side init cost across files.
const parsers = new Map<Language, Parser>();

function getParser(language: Language): Parser | null {
  const cached = parsers.get(language);
  if (cached) return cached;
  const lang = languageGrammar(language);
  if (!lang) return null;
  const p = new Parser();
  // Tree-sitter grammar packages don't ship matching TS types for the Language
  // object; cast through unknown to satisfy the strict setLanguage signature.
  p.setLanguage(lang as Parser.Language);
  parsers.set(language, p);
  return p;
}

function languageGrammar(language: Language): unknown {
  switch (language) {
    case "ts":
      return (TS as unknown as { typescript: unknown }).typescript;
    case "tsx":
      return (TS as unknown as { tsx: unknown }).tsx;
    case "js":
      return JS;
    case "py":
      return PY;
    case "go":
      return GO;
    case "rs":
      return RS;
    case "md":
      return null;
  }
}

export function extractSymbols(text: string, language: Language): RepoSymbol[] {
  return extract(text, language).symbols;
}

export function extract(text: string, language: Language): ExtractResult {
  if (language === "md") {
    return { symbols: extractMarkdownSymbols(text), imports: [] };
  }
  const parser = getParser(language);
  if (!parser) return { symbols: [], imports: [] };

  let tree: Parser.Tree;
  try {
    tree = parser.parse(text);
  } catch {
    return { symbols: [], imports: [] };
  }
  const root = tree.rootNode;

  switch (language) {
    case "ts":
    case "tsx":
    case "js":
      return extractTsLike(root, text, language);
    case "py":
      return extractPython(root, text);
    case "go":
      return extractGo(root, text);
    case "rs":
      return extractRust(root, text);
    default:
      return { symbols: [], imports: [] };
  }
}

function lineOf(node: Parser.SyntaxNode): number {
  return node.startPosition.row + 1;
}

function condenseText(text: string, max: number): string {
  const collapsed = text.replace(/\s+/g, " ").trim();
  if (collapsed.length <= max) return collapsed;
  return collapsed.slice(0, max - 1) + "…";
}

/** Strip the outer `(...)` from a parameter-list node's text and condense whitespace. */
function paramListInner(node: Parser.SyntaxNode, source: string): string {
  const raw = source.slice(node.startIndex, node.endIndex);
  const trimmed = raw.replace(/^\(/, "").replace(/\)$/, "");
  return condenseText(trimmed, MAX_SIGNATURE_CHARS);
}

// ---------------------------------------------------------------- TS / JS / TSX

interface TsLikeOptions {
  hasTypes: boolean; // true for ts/tsx, false for js
}

function extractTsLike(
  root: Parser.SyntaxNode,
  source: string,
  language: Language
): ExtractResult {
  const opts: TsLikeOptions = { hasTypes: language !== "js" };
  const symbols: RepoSymbol[] = [];
  const imports: ImportRef[] = [];

  for (let i = 0; i < root.namedChildCount; i++) {
    const child = root.namedChild(i)!;
    visitTsTop(child, source, opts, symbols, imports, false);
  }

  return { symbols, imports };
}

function visitTsTop(
  node: Parser.SyntaxNode,
  source: string,
  opts: TsLikeOptions,
  out: RepoSymbol[],
  imports: ImportRef[],
  exported: boolean
): void {
  switch (node.type) {
    case "export_statement": {
      // `export default class Foo {}`, `export const x = 1`, `export function f() {}`, etc.
      // Walk the declaration child(ren) with `exported=true`.
      for (let i = 0; i < node.namedChildCount; i++) {
        const inner = node.namedChild(i)!;
        // Skip the bare `export { a, b }` re-export specifier children — they
        // don't define new symbols here. The named declaration child (if any)
        // is what we want.
        if (
          inner.type === "export_clause" ||
          inner.type === "export_specifier" ||
          inner.type === "string"
        ) {
          continue;
        }
        visitTsTop(inner, source, opts, out, imports, true);
      }
      return;
    }
    case "function_declaration":
    case "generator_function_declaration": {
      const sym = tsFunctionSymbol(node, source, opts);
      if (sym) {
        sym.exported = exported || undefined;
        out.push(sym);
      }
      return;
    }
    case "class_declaration":
    case "abstract_class_declaration": {
      const sym = tsClassSymbol(node, source, opts);
      if (sym) {
        sym.exported = exported || undefined;
        out.push(sym);
      }
      return;
    }
    case "interface_declaration": {
      const sym = tsInterfaceSymbol(node, source, opts);
      if (sym) {
        sym.exported = exported || undefined;
        out.push(sym);
      }
      return;
    }
    case "type_alias_declaration": {
      const name = node.childForFieldName("name");
      if (name) {
        out.push({
          kind: "type",
          name: source.slice(name.startIndex, name.endIndex),
          line: lineOf(node),
          ...(exported ? { exported: true } : {}),
        });
      }
      return;
    }
    case "enum_declaration": {
      const name = node.childForFieldName("name");
      if (name) {
        out.push({
          kind: "enum",
          name: source.slice(name.startIndex, name.endIndex),
          line: lineOf(node),
          ...(exported ? { exported: true } : {}),
        });
      }
      return;
    }
    case "lexical_declaration":
    case "variable_declaration": {
      // const / let / var. Only emit `exported` ones at top level (matches the
      // old regex behaviour). Unexported top-level consts are typically too
      // noisy.
      if (!exported) return;
      for (let i = 0; i < node.namedChildCount; i++) {
        const decl = node.namedChild(i)!;
        if (decl.type !== "variable_declarator") continue;
        const name = decl.childForFieldName("name");
        if (!name) continue;
        // Arrow function or function expression on the RHS → treat as function.
        const value = decl.childForFieldName("value");
        if (
          value &&
          (value.type === "arrow_function" || value.type === "function_expression")
        ) {
          const params = value.childForFieldName("parameters");
          const ret = value.childForFieldName("return_type");
          out.push({
            kind: "function",
            name: source.slice(name.startIndex, name.endIndex),
            line: lineOf(decl),
            ...(params ? { signature: paramListInner(params, source) } : {}),
            ...(opts.hasTypes && ret
              ? { returnType: condenseTypeAnnotation(ret, source) }
              : {}),
            exported: true,
          });
        } else {
          out.push({
            kind: "const",
            name: source.slice(name.startIndex, name.endIndex),
            line: lineOf(decl),
            exported: true,
          });
        }
      }
      return;
    }
    case "import_statement": {
      const ref = tsImportRef(node, source);
      if (ref) imports.push(ref);
      return;
    }
    default:
      return;
  }
}

function tsFunctionSymbol(
  node: Parser.SyntaxNode,
  source: string,
  opts: TsLikeOptions
): RepoSymbol | null {
  const name = node.childForFieldName("name");
  if (!name) return null;
  const params = node.childForFieldName("parameters");
  const ret = node.childForFieldName("return_type");
  const sym: RepoSymbol = {
    kind: "function",
    name: source.slice(name.startIndex, name.endIndex),
    line: lineOf(node),
  };
  if (params) sym.signature = paramListInner(params, source);
  if (opts.hasTypes && ret) sym.returnType = condenseTypeAnnotation(ret, source);
  return sym;
}

function tsClassSymbol(
  node: Parser.SyntaxNode,
  source: string,
  opts: TsLikeOptions
): RepoSymbol | null {
  const name = node.childForFieldName("name");
  if (!name) return null;
  const body = node.childForFieldName("body");
  const members: Member[] = [];
  if (body) {
    for (let i = 0; i < body.namedChildCount; i++) {
      const m = body.namedChild(i)!;
      const member = tsClassMember(m, source, opts);
      if (member) members.push(member);
    }
  }
  const sym: RepoSymbol = {
    kind: "class",
    name: source.slice(name.startIndex, name.endIndex),
    line: lineOf(node),
  };
  if (members.length > 0) sym.members = members;
  return sym;
}

function tsClassMember(
  node: Parser.SyntaxNode,
  source: string,
  opts: TsLikeOptions
): Member | null {
  switch (node.type) {
    case "method_definition":
    case "method_signature": {
      const name = node.childForFieldName("name");
      if (!name) return null;
      const params = node.childForFieldName("parameters");
      const ret = node.childForFieldName("return_type");
      const m: Member = {
        kind: "method",
        name: source.slice(name.startIndex, name.endIndex),
        line: lineOf(node),
      };
      if (params) m.signature = paramListInner(params, source);
      if (opts.hasTypes && ret) m.returnType = condenseTypeAnnotation(ret, source);
      return m;
    }
    case "public_field_definition":
    case "property_signature": {
      const name = node.childForFieldName("name");
      if (!name) return null;
      const type = node.childForFieldName("type");
      const m: Member = {
        kind: "field",
        name: source.slice(name.startIndex, name.endIndex),
        line: lineOf(node),
      };
      if (opts.hasTypes && type) {
        const t = condenseTypeAnnotation(type, source);
        if (t) m.returnType = t;
      }
      return m;
    }
    default:
      return null;
  }
}

function tsInterfaceSymbol(
  node: Parser.SyntaxNode,
  source: string,
  opts: TsLikeOptions
): RepoSymbol | null {
  const name = node.childForFieldName("name");
  if (!name) return null;
  const body = node.childForFieldName("body");
  const members: Member[] = [];
  if (body) {
    for (let i = 0; i < body.namedChildCount; i++) {
      const m = body.namedChild(i)!;
      const member = tsClassMember(m, source, opts);
      if (member) members.push(member);
    }
  }
  const sym: RepoSymbol = {
    kind: "interface",
    name: source.slice(name.startIndex, name.endIndex),
    line: lineOf(node),
  };
  if (members.length > 0) sym.members = members;
  return sym;
}

/** A `type_annotation` node wraps a leading `:` plus the type; strip it. */
function condenseTypeAnnotation(
  node: Parser.SyntaxNode,
  source: string
): string {
  const raw = source.slice(node.startIndex, node.endIndex).replace(/^:\s*/, "");
  return condenseText(raw, MAX_RETURN_TYPE_CHARS);
}

function tsImportRef(
  node: Parser.SyntaxNode,
  source: string
): ImportRef | null {
  // `import_statement` has a `source` field on the string literal.
  const src = node.childForFieldName("source");
  const stringNode =
    src ??
    findChildOfType(node, "string"); // bare side-effect import: `import "x"`
  if (!stringNode) return null;
  // Unwrap to the inner string_fragment (or strip quotes ourselves).
  const fragment = findChildOfType(stringNode, "string_fragment");
  const raw = fragment
    ? source.slice(fragment.startIndex, fragment.endIndex)
    : source
        .slice(stringNode.startIndex, stringNode.endIndex)
        .replace(/^['"`]|['"`]$/g, "");
  return { raw, resolved: null, line: lineOf(node) };
}

function findChildOfType(
  node: Parser.SyntaxNode,
  type: string
): Parser.SyntaxNode | null {
  for (let i = 0; i < node.namedChildCount; i++) {
    const c = node.namedChild(i)!;
    if (c.type === type) return c;
  }
  return null;
}

// ---------------------------------------------------------------- Python

function extractPython(
  root: Parser.SyntaxNode,
  source: string
): ExtractResult {
  const symbols: RepoSymbol[] = [];
  const imports: ImportRef[] = [];

  for (let i = 0; i < root.namedChildCount; i++) {
    const child = root.namedChild(i)!;
    visitPyTop(child, source, symbols, imports);
  }

  return { symbols, imports };
}

function visitPyTop(
  node: Parser.SyntaxNode,
  source: string,
  out: RepoSymbol[],
  imports: ImportRef[]
): void {
  switch (node.type) {
    case "decorated_definition": {
      // Walk into the inner definition.
      const def =
        node.childForFieldName("definition") ??
        node.namedChild(node.namedChildCount - 1);
      if (def) visitPyTop(def, source, out, imports);
      return;
    }
    case "function_definition": {
      const sym = pyFunctionSymbol(node, source, "function");
      if (sym) out.push(sym);
      return;
    }
    case "class_definition": {
      const name = node.childForFieldName("name");
      if (!name) return;
      const body = node.childForFieldName("body");
      const members: Member[] = [];
      if (body) {
        for (let i = 0; i < body.namedChildCount; i++) {
          const m = body.namedChild(i)!;
          const wrapped =
            m.type === "decorated_definition"
              ? m.childForFieldName("definition") ??
                m.namedChild(m.namedChildCount - 1)
              : m;
          if (wrapped && wrapped.type === "function_definition") {
            const fn = pyFunctionSymbol(wrapped, source, "method");
            if (fn) members.push(memberFromSymbol(fn));
          }
        }
      }
      const sym: RepoSymbol = {
        kind: "class",
        name: source.slice(name.startIndex, name.endIndex),
        line: lineOf(node),
      };
      if (members.length > 0) sym.members = members;
      out.push(sym);
      return;
    }
    case "import_statement": {
      // `import a, b.c as d, …`
      for (let i = 0; i < node.namedChildCount; i++) {
        const c = node.namedChild(i)!;
        if (c.type === "dotted_name") {
          imports.push({
            raw: source.slice(c.startIndex, c.endIndex),
            resolved: null,
            line: lineOf(node),
          });
        } else if (c.type === "aliased_import") {
          const inner = c.childForFieldName("name") ?? c.namedChild(0);
          if (inner) {
            imports.push({
              raw: source.slice(inner.startIndex, inner.endIndex),
              resolved: null,
              line: lineOf(node),
            });
          }
        }
      }
      return;
    }
    case "import_from_statement": {
      // `from .foo import bar` or `from typing import List, Dict`.
      const moduleNode =
        node.childForFieldName("module_name") ?? node.namedChild(0);
      if (moduleNode) {
        imports.push({
          raw: source.slice(moduleNode.startIndex, moduleNode.endIndex),
          resolved: null,
          line: lineOf(node),
        });
      }
      return;
    }
    default:
      return;
  }
}

function pyFunctionSymbol(
  node: Parser.SyntaxNode,
  source: string,
  kind: "function" | "method"
): RepoSymbol | null {
  const name = node.childForFieldName("name");
  if (!name) return null;
  const params = node.childForFieldName("parameters");
  const ret = node.childForFieldName("return_type");
  const sym: RepoSymbol = {
    kind,
    name: source.slice(name.startIndex, name.endIndex),
    line: lineOf(node),
  };
  if (params) sym.signature = paramListInner(params, source);
  if (ret) {
    const t = condenseText(
      source.slice(ret.startIndex, ret.endIndex),
      MAX_RETURN_TYPE_CHARS
    );
    if (t) sym.returnType = t;
  }
  return sym;
}

function memberFromSymbol(sym: RepoSymbol): Member {
  const m: Member = { kind: sym.kind, name: sym.name, line: sym.line };
  if (sym.signature !== undefined) m.signature = sym.signature;
  if (sym.returnType !== undefined) m.returnType = sym.returnType;
  return m;
}

// ---------------------------------------------------------------- Go

function extractGo(root: Parser.SyntaxNode, source: string): ExtractResult {
  const symbols: RepoSymbol[] = [];
  const imports: ImportRef[] = [];

  // Group method_declarations by their receiver type so we can attach them to
  // the corresponding struct/interface as members.
  type GoMethod = { name: string; line: number; signature?: string; returnType?: string };
  const methodsByReceiver = new Map<string, GoMethod[]>();

  for (let i = 0; i < root.namedChildCount; i++) {
    const child = root.namedChild(i)!;
    switch (child.type) {
      case "import_declaration": {
        collectGoImports(child, source, imports);
        break;
      }
      case "type_declaration": {
        for (let j = 0; j < child.namedChildCount; j++) {
          const spec = child.namedChild(j)!;
          if (spec.type !== "type_spec") continue;
          const name = spec.childForFieldName("name");
          const typeNode = spec.childForFieldName("type");
          if (!name) continue;
          const kind =
            typeNode?.type === "struct_type"
              ? "struct"
              : typeNode?.type === "interface_type"
                ? "interface"
                : "type";
          const sym: RepoSymbol = {
            kind,
            name: source.slice(name.startIndex, name.endIndex),
            line: lineOf(spec),
          };
          const members = goTypeMembers(typeNode, source);
          if (members.length > 0) sym.members = members;
          symbols.push(sym);
        }
        break;
      }
      case "function_declaration": {
        const name = child.childForFieldName("name");
        if (!name) break;
        const params = child.childForFieldName("parameters");
        const result = child.childForFieldName("result");
        const sym: RepoSymbol = {
          kind: "func",
          name: source.slice(name.startIndex, name.endIndex),
          line: lineOf(child),
        };
        if (params) sym.signature = paramListInner(params, source);
        if (result) {
          const t = condenseText(
            source.slice(result.startIndex, result.endIndex),
            MAX_RETURN_TYPE_CHARS
          );
          if (t) sym.returnType = t;
        }
        symbols.push(sym);
        break;
      }
      case "method_declaration": {
        const receiver = child.childForFieldName("receiver");
        const name = child.childForFieldName("name");
        const params = child.childForFieldName("parameters");
        const result = child.childForFieldName("result");
        if (!name) break;
        const recvType = parseGoReceiverType(receiver, source);
        const method: GoMethod = {
          name: source.slice(name.startIndex, name.endIndex),
          line: lineOf(child),
        };
        if (params) method.signature = paramListInner(params, source);
        if (result) {
          const t = condenseText(
            source.slice(result.startIndex, result.endIndex),
            MAX_RETURN_TYPE_CHARS
          );
          if (t) method.returnType = t;
        }
        if (recvType) {
          const list = methodsByReceiver.get(recvType) ?? [];
          list.push(method);
          methodsByReceiver.set(recvType, list);
        } else {
          // Receiver had no parseable type — emit as a bare func so it isn't lost.
          symbols.push({
            kind: "func",
            name: method.name,
            line: method.line,
            ...(method.signature ? { signature: method.signature } : {}),
            ...(method.returnType ? { returnType: method.returnType } : {}),
          });
        }
        break;
      }
      case "const_declaration":
      case "var_declaration": {
        const kind = child.type === "const_declaration" ? "const" : "var";
        for (let j = 0; j < child.namedChildCount; j++) {
          const spec = child.namedChild(j)!;
          if (spec.type !== "const_spec" && spec.type !== "var_spec") continue;
          for (let k = 0; k < spec.namedChildCount; k++) {
            const id = spec.namedChild(k)!;
            if (id.type !== "identifier") continue;
            symbols.push({
              kind,
              name: source.slice(id.startIndex, id.endIndex),
              line: lineOf(spec),
            });
          }
        }
        break;
      }
      default:
        break;
    }
  }

  // Attach buffered methods to their receiver types.
  for (const sym of symbols) {
    if (sym.kind !== "struct" && sym.kind !== "interface") continue;
    const methods = methodsByReceiver.get(sym.name);
    if (!methods) continue;
    const members: Member[] = (sym.members ?? []).slice();
    for (const m of methods) {
      members.push({
        kind: "method",
        name: m.name,
        line: m.line,
        ...(m.signature ? { signature: m.signature } : {}),
        ...(m.returnType ? { returnType: m.returnType } : {}),
      });
    }
    if (members.length > 0) sym.members = members;
    methodsByReceiver.delete(sym.name);
  }

  // Orphan methods (receiver type not declared in this file) → emit as bare funcs.
  for (const [, methods] of methodsByReceiver) {
    for (const m of methods) {
      symbols.push({
        kind: "func",
        name: m.name,
        line: m.line,
        ...(m.signature ? { signature: m.signature } : {}),
        ...(m.returnType ? { returnType: m.returnType } : {}),
      });
    }
  }

  return { symbols, imports };
}

function collectGoImports(
  node: Parser.SyntaxNode,
  source: string,
  out: ImportRef[]
): void {
  for (let i = 0; i < node.namedChildCount; i++) {
    const c = node.namedChild(i)!;
    if (c.type === "import_spec") {
      const path = c.childForFieldName("path") ?? findChildOfType(c, "interpreted_string_literal");
      if (path) {
        const raw = source
          .slice(path.startIndex, path.endIndex)
          .replace(/^['"`]|['"`]$/g, "");
        out.push({ raw, resolved: null, line: lineOf(c) });
      }
    } else if (c.type === "import_spec_list") {
      collectGoImports(c, source, out);
    }
  }
}

function goTypeMembers(
  typeNode: Parser.SyntaxNode | null,
  source: string
): Member[] {
  if (!typeNode) return [];
  const members: Member[] = [];
  if (typeNode.type === "struct_type") {
    const fields = findChildOfType(typeNode, "field_declaration_list");
    if (!fields) return members;
    for (let i = 0; i < fields.namedChildCount; i++) {
      const field = fields.namedChild(i)!;
      if (field.type !== "field_declaration") continue;
      const typeChild = field.childForFieldName("type");
      const typeText = typeChild
        ? condenseText(
            source.slice(typeChild.startIndex, typeChild.endIndex),
            MAX_RETURN_TYPE_CHARS
          )
        : undefined;
      for (let j = 0; j < field.namedChildCount; j++) {
        const id = field.namedChild(j)!;
        if (id.type !== "field_identifier") continue;
        members.push({
          kind: "field",
          name: source.slice(id.startIndex, id.endIndex),
          line: lineOf(field),
          ...(typeText ? { returnType: typeText } : {}),
        });
      }
    }
  } else if (typeNode.type === "interface_type") {
    for (let i = 0; i < typeNode.namedChildCount; i++) {
      const m = typeNode.namedChild(i)!;
      if (m.type === "method_elem" || m.type === "method_spec") {
        const name = m.childForFieldName("name") ?? findChildOfType(m, "field_identifier");
        if (!name) continue;
        const params = m.childForFieldName("parameters");
        const result = m.childForFieldName("result");
        members.push({
          kind: "method",
          name: source.slice(name.startIndex, name.endIndex),
          line: lineOf(m),
          ...(params ? { signature: paramListInner(params, source) } : {}),
          ...(result
            ? {
                returnType: condenseText(
                  source.slice(result.startIndex, result.endIndex),
                  MAX_RETURN_TYPE_CHARS
                ),
              }
            : {}),
        });
      }
    }
  }
  return members;
}

function parseGoReceiverType(
  receiver: Parser.SyntaxNode | null,
  source: string
): string | null {
  if (!receiver) return null;
  // receiver is a parameter_list with one parameter_declaration whose type is
  // either a type_identifier (`Foo`) or pointer_type (`*Foo`).
  for (let i = 0; i < receiver.namedChildCount; i++) {
    const param = receiver.namedChild(i)!;
    if (param.type !== "parameter_declaration") continue;
    const typeNode = param.childForFieldName("type");
    if (!typeNode) continue;
    if (typeNode.type === "type_identifier") {
      return source.slice(typeNode.startIndex, typeNode.endIndex);
    }
    if (typeNode.type === "pointer_type") {
      const inner = typeNode.namedChild(0);
      if (inner && inner.type === "type_identifier") {
        return source.slice(inner.startIndex, inner.endIndex);
      }
    }
  }
  return null;
}

// ---------------------------------------------------------------- Rust

function extractRust(root: Parser.SyntaxNode, source: string): ExtractResult {
  const symbols: RepoSymbol[] = [];
  const imports: ImportRef[] = [];

  for (let i = 0; i < root.namedChildCount; i++) {
    const child = root.namedChild(i)!;
    visitRustTop(child, source, symbols, imports);
  }

  return { symbols, imports };
}

function visitRustTop(
  node: Parser.SyntaxNode,
  source: string,
  out: RepoSymbol[],
  imports: ImportRef[]
): void {
  const exported = hasRustPub(node);

  switch (node.type) {
    case "use_declaration": {
      // Argument is the imported path (scoped_identifier / use_list / etc.).
      const arg = node.childForFieldName("argument") ?? node.namedChild(0);
      if (arg) {
        imports.push({
          raw: condenseText(source.slice(arg.startIndex, arg.endIndex), 200),
          resolved: null,
          line: lineOf(node),
        });
      }
      return;
    }
    case "function_item": {
      const name = node.childForFieldName("name");
      if (!name) return;
      const params = node.childForFieldName("parameters");
      const ret = node.childForFieldName("return_type");
      const sym: RepoSymbol = {
        kind: "fn",
        name: source.slice(name.startIndex, name.endIndex),
        line: lineOf(node),
      };
      if (params) sym.signature = paramListInner(params, source);
      if (ret) {
        const t = condenseText(
          source.slice(ret.startIndex, ret.endIndex),
          MAX_RETURN_TYPE_CHARS
        );
        if (t) sym.returnType = t;
      }
      if (exported) sym.exported = true;
      out.push(sym);
      return;
    }
    case "struct_item": {
      const name = node.childForFieldName("name");
      if (!name) return;
      const body = node.childForFieldName("body");
      const members = rustFieldMembers(body, source);
      const sym: RepoSymbol = {
        kind: "struct",
        name: source.slice(name.startIndex, name.endIndex),
        line: lineOf(node),
      };
      if (members.length > 0) sym.members = members;
      if (exported) sym.exported = true;
      out.push(sym);
      return;
    }
    case "enum_item": {
      const name = node.childForFieldName("name");
      if (!name) return;
      const body = node.childForFieldName("body");
      const members: Member[] = [];
      if (body) {
        for (let i = 0; i < body.namedChildCount; i++) {
          const v = body.namedChild(i)!;
          if (v.type !== "enum_variant") continue;
          const vname = v.childForFieldName("name") ?? findChildOfType(v, "identifier");
          if (!vname) continue;
          members.push({
            kind: "variant",
            name: source.slice(vname.startIndex, vname.endIndex),
            line: lineOf(v),
          });
        }
      }
      const sym: RepoSymbol = {
        kind: "enum",
        name: source.slice(name.startIndex, name.endIndex),
        line: lineOf(node),
      };
      if (members.length > 0) sym.members = members;
      if (exported) sym.exported = true;
      out.push(sym);
      return;
    }
    case "trait_item": {
      const name = node.childForFieldName("name");
      if (!name) return;
      const body = node.childForFieldName("body");
      const members = rustTraitMembers(body, source);
      const sym: RepoSymbol = {
        kind: "trait",
        name: source.slice(name.startIndex, name.endIndex),
        line: lineOf(node),
      };
      if (members.length > 0) sym.members = members;
      if (exported) sym.exported = true;
      out.push(sym);
      return;
    }
    case "impl_item": {
      const traitNode = node.childForFieldName("trait");
      const typeNode = node.childForFieldName("type");
      const typeText = typeNode
        ? source.slice(typeNode.startIndex, typeNode.endIndex)
        : "?";
      const name = traitNode
        ? `${source.slice(traitNode.startIndex, traitNode.endIndex)} for ${typeText}`
        : typeText;
      const body = node.childForFieldName("body");
      const members = rustTraitMembers(body, source); // same shape: function_item / signature_item
      out.push({
        kind: "impl",
        name: condenseText(name, MAX_SIGNATURE_CHARS),
        line: lineOf(node),
        ...(members.length > 0 ? { members } : {}),
      });
      return;
    }
    case "type_item": {
      const name = node.childForFieldName("name");
      if (name) {
        out.push({
          kind: "type",
          name: source.slice(name.startIndex, name.endIndex),
          line: lineOf(node),
          ...(exported ? { exported: true } : {}),
        });
      }
      return;
    }
    case "mod_item": {
      const name = node.childForFieldName("name");
      if (name) {
        out.push({
          kind: "mod",
          name: source.slice(name.startIndex, name.endIndex),
          line: lineOf(node),
          ...(exported ? { exported: true } : {}),
        });
      }
      return;
    }
    case "const_item":
    case "static_item": {
      const name = node.childForFieldName("name");
      if (name) {
        out.push({
          kind: node.type === "const_item" ? "const" : "static",
          name: source.slice(name.startIndex, name.endIndex),
          line: lineOf(node),
          ...(exported ? { exported: true } : {}),
        });
      }
      return;
    }
    default:
      return;
  }
}

function hasRustPub(node: Parser.SyntaxNode): boolean {
  for (let i = 0; i < node.namedChildCount; i++) {
    if (node.namedChild(i)!.type === "visibility_modifier") return true;
  }
  return false;
}

function rustFieldMembers(
  body: Parser.SyntaxNode | null,
  source: string
): Member[] {
  if (!body) return [];
  const out: Member[] = [];
  for (let i = 0; i < body.namedChildCount; i++) {
    const f = body.namedChild(i)!;
    if (f.type !== "field_declaration") continue;
    const name = f.childForFieldName("name");
    const typeNode = f.childForFieldName("type");
    if (!name) continue;
    out.push({
      kind: "field",
      name: source.slice(name.startIndex, name.endIndex),
      line: lineOf(f),
      ...(typeNode
        ? {
            returnType: condenseText(
              source.slice(typeNode.startIndex, typeNode.endIndex),
              MAX_RETURN_TYPE_CHARS
            ),
          }
        : {}),
    });
  }
  return out;
}

function rustTraitMembers(
  body: Parser.SyntaxNode | null,
  source: string
): Member[] {
  if (!body) return [];
  const out: Member[] = [];
  for (let i = 0; i < body.namedChildCount; i++) {
    const m = body.namedChild(i)!;
    if (m.type !== "function_item" && m.type !== "function_signature_item") {
      continue;
    }
    const name = m.childForFieldName("name");
    if (!name) continue;
    const params = m.childForFieldName("parameters");
    const ret = m.childForFieldName("return_type");
    out.push({
      kind: "method",
      name: source.slice(name.startIndex, name.endIndex),
      line: lineOf(m),
      ...(params ? { signature: paramListInner(params, source) } : {}),
      ...(ret
        ? {
            returnType: condenseText(
              source.slice(ret.startIndex, ret.endIndex),
              MAX_RETURN_TYPE_CHARS
            ),
          }
        : {}),
    });
  }
  return out;
}

// ---------------------------------------------------------------- Markdown
// Kept on the original line-scan path. Tree-sitter-markdown is heavyweight for
// what's essentially "find column-0 #/##/### headings outside fenced code blocks".

function extractMarkdownSymbols(text: string): RepoSymbol[] {
  const out: RepoSymbol[] = [];
  let inFence = false;
  let fenceChar = "";
  let fenceLen = 0;

  const fenceRe = /^( {0,3})(`{3,}|~{3,})(.*)$/;
  const headingRe = /^(#{1,3})\s+(.+?)\s*$/;

  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const lineText = lines[i]!;
    const lineNum = i + 1;

    const fenceMatch = lineText.match(fenceRe);
    if (fenceMatch) {
      const marker = fenceMatch[2]!;
      const after = fenceMatch[3]!;
      const ch = marker[0]!;
      const len = marker.length;
      if (!inFence) {
        inFence = true;
        fenceChar = ch;
        fenceLen = len;
        continue;
      }
      if (ch === fenceChar && len >= fenceLen && /^\s*$/.test(after)) {
        inFence = false;
        fenceChar = "";
        fenceLen = 0;
        continue;
      }
    }

    if (inFence) continue;

    const h = lineText.match(headingRe);
    if (h) {
      const level = h[1]!.length;
      out.push({ kind: `h${level}`, name: h[2]!, line: lineNum });
    }
  }

  return out;
}


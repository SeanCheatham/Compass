Vendored external scanners for tree-sitter grammars whose upstream
`Package.swift` files use a runtime `FileManager.default.fileExists(...)`
check to decide whether to compile `src/scanner.c`. That check evaluates
to false inside SPM's sandboxed manifest evaluation, leaving the
external-scanner symbols undefined at link time.

Files in this target:

- `python_scanner.c` — copied verbatim from
  `tree-sitter/tree-sitter-python` (`src/scanner.c`), MIT licensed.
- `include/tree_sitter/{parser,array,alloc}.h` — copied verbatim from
  the same grammar's `src/tree_sitter/` directory. They are the
  standard ABI headers shared by all tree-sitter grammars and identical
  across them; we pin one copy here so the vendored scanners build
  without needing each grammar package's private include path.

When upstream Package.swift files are fixed to unconditionally list
`src/scanner.c`, this target can be deleted.

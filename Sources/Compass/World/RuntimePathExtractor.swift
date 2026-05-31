import Foundation
import SwiftTreeSitter

enum RuntimePathConstructKind: String, Sendable, Equatable {
  case branch
  case loop
  case switchCase
  case errorPath
}

struct RuntimePathEntrypoint: Sendable, Equatable {
  var name: String
  var line: Int
  var endLine: Int
  var confidence: WorldConfidence
  var reason: String
}

struct RuntimePathConstruct: Sendable, Equatable {
  var kind: RuntimePathConstructKind
  var label: String
  var line: Int
  var endLine: Int
  var confidence: WorldConfidence
}

struct RuntimePathCall: Sendable, Equatable {
  var callee: String
  var line: Int
  var endLine: Int
  var confidence: WorldConfidence
}

struct RuntimePathExtraction: Sendable, Equatable {
  var entrypoints: [RuntimePathEntrypoint]
  var constructs: [RuntimePathConstruct]
  var calls: [RuntimePathCall]

  static let empty = RuntimePathExtraction(entrypoints: [], constructs: [], calls: [])
}

struct RuntimePathExtractor: Sendable {
  enum ExtractorError: Error, Equatable {
    case unsupportedLanguage(CodemapLanguage)
    case parseFailed
  }

  let registry: LanguageRegistry

  init(registry: LanguageRegistry = .shared) {
    self.registry = registry
  }

  func extract(
    source: String,
    language: CodemapLanguage,
    relativePath: String,
    symbols: [CodemapSymbol]
  ) throws -> RuntimePathExtraction {
    guard let entry = registry.entry(for: language) else {
      throw ExtractorError.unsupportedLanguage(language)
    }

    let parser = Parser()
    try parser.setLanguage(entry.tsLanguage)
    guard let tree = parser.parse(source), let root = tree.rootNode else {
      throw ExtractorError.parseFailed
    }

    var constructs: [RuntimePathConstruct] = []
    var calls: [RuntimePathCall] = []
    let nodeKinds = LanguageRegistry.runtimeNodeKinds(for: language)

    func visit(_ node: Node) {
      guard let nodeType = node.nodeType else { return }
      let location = sourceLocation(for: node)

      if nodeKinds.branchTypes.contains(nodeType) {
        constructs.append(
          RuntimePathConstruct(
            kind: .branch,
            label: label(for: node, source: source, fallback: "Branch"),
            line: location.line,
            endLine: location.endLine,
            confidence: .high
          )
        )
      } else if nodeKinds.loopTypes.contains(nodeType) {
        constructs.append(
          RuntimePathConstruct(
            kind: .loop,
            label: label(for: node, source: source, fallback: "Loop"),
            line: location.line,
            endLine: location.endLine,
            confidence: .high
          )
        )
      } else if nodeKinds.switchTypes.contains(nodeType) {
        constructs.append(
          RuntimePathConstruct(
            kind: .switchCase,
            label: label(for: node, source: source, fallback: "Switch"),
            line: location.line,
            endLine: location.endLine,
            confidence: .high
          )
        )
      } else if nodeKinds.errorTypes.contains(nodeType) {
        constructs.append(
          RuntimePathConstruct(
            kind: .errorPath,
            label: label(for: node, source: source, fallback: "Error path"),
            line: location.line,
            endLine: location.endLine,
            confidence: nodeType == "try_expression" ? .medium : .high
          )
        )
      }

      if nodeKinds.callTypes.contains(nodeType),
        let callee = calleeName(for: node, source: source)
      {
        calls.append(
          RuntimePathCall(
            callee: callee,
            line: location.line,
            endLine: location.endLine,
            confidence: .medium
          )
        )
      }

      for index in 0..<node.namedChildCount {
        if let child = node.namedChild(at: index) {
          visit(child)
        }
      }
    }

    visit(root)

    return RuntimePathExtraction(
      entrypoints: Self.detectEntrypoints(
        source: source,
        language: language,
        relativePath: relativePath,
        symbols: symbols
      ),
      constructs: dedupeConstructs(constructs),
      calls: dedupeCalls(calls)
    )
  }

  static func detectEntrypoints(
    source: String,
    language: CodemapLanguage,
    relativePath: String,
    symbols: [CodemapSymbol]
  ) -> [RuntimePathEntrypoint] {
    var entrypoints: [RuntimePathEntrypoint] = []
    let fileName = (relativePath as NSString).lastPathComponent
    let stem = (fileName as NSString).deletingPathExtension.lowercased()
    let lines = source.components(separatedBy: .newlines)

    func add(
      name: String,
      line: Int,
      endLine: Int,
      confidence: WorldConfidence,
      reason: String
    ) {
      let entry = RuntimePathEntrypoint(
        name: name,
        line: line,
        endLine: max(line, endLine),
        confidence: confidence,
        reason: reason
      )
      if !entrypoints.contains(entry) {
        entrypoints.append(entry)
      }
    }

    switch language {
    case .swift:
      if let mainAttributeLine = lines.firstIndex(where: { $0.contains("@main") }) {
        let line = mainAttributeLine + 1
        let symbol = symbols.first { symbol in
          symbol.line >= line && [.class, .struct, .enum].contains(symbol.kind)
        }
        add(
          name: symbol?.name ?? "@main",
          line: symbol?.line ?? line,
          endLine: symbol?.endLine ?? line,
          confidence: .high,
          reason: "@main application entry"
        )
      }
      if fileName == "main.swift" {
        add(
          name: "main.swift",
          line: 1,
          endLine: max(1, lines.count),
          confidence: .high,
          reason: "Swift top-level main.swift"
        )
      }

    case .go:
      let isPackageMain = lines.contains { $0.trimmingCharacters(in: .whitespaces) == "package main" }
      if isPackageMain, let symbol = symbols.first(where: { $0.name == "main" && $0.kind == .function }) {
        add(
          name: "main",
          line: symbol.line,
          endLine: symbol.endLine,
          confidence: .high,
          reason: "Go package main entrypoint"
        )
      }

    case .rust:
      if let symbol = symbols.first(where: { $0.name == "main" && $0.kind == .function }) {
        add(
          name: "main",
          line: symbol.line,
          endLine: symbol.endLine,
          confidence: .high,
          reason: "Rust fn main entrypoint"
        )
      }

    case .javascript, .typescript, .tsx:
      if let symbol = symbols.first(where: { $0.name == "main" && $0.kind == .function }) {
        add(
          name: "main",
          line: symbol.line,
          endLine: symbol.endLine,
          confidence: .medium,
          reason: "main function convention"
        )
      }
      if ["index", "main", "app", "server"].contains(stem) {
        add(
          name: fileName,
          line: 1,
          endLine: min(max(1, lines.count), 80),
          confidence: .medium,
          reason: "\(fileName) entrypoint convention"
        )
      }
      if source.contains("import.meta.main") || source.contains("process.argv") {
        add(
          name: fileName,
          line: firstLine(containingAny: ["import.meta.main", "process.argv"], in: lines) ?? 1,
          endLine: min(max(1, lines.count), 80),
          confidence: .medium,
          reason: "CLI/runtime argument convention"
        )
      }
    }

    return entrypoints.sorted {
      if $0.confidence != $1.confidence {
        return confidenceRank($0.confidence) < confidenceRank($1.confidence)
      }
      if $0.line != $1.line { return $0.line < $1.line }
      return $0.name < $1.name
    }
  }

  private func sourceLocation(for node: Node) -> (line: Int, endLine: Int) {
    let range = node.pointRange
    let startLine = Int(range.lowerBound.row) + 1
    var endLine = Int(range.upperBound.row) + 1
    if range.upperBound.column == 0 && endLine > startLine {
      endLine -= 1
    }
    return (startLine, endLine)
  }

  private func label(for node: Node, source: String, fallback: String) -> String {
    let line = sourceLocation(for: node).line
    let snippet = lineText(line, in: source)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !snippet.isEmpty else { return fallback }
    return String(snippet.prefix(90))
  }

  private func calleeName(for node: Node, source: String) -> String? {
    if let functionNode = node.child(byFieldName: "function"),
      let name = compactText(for: functionNode, source: source)
    {
      return cleanCalleeName(name)
    }

    let line = lineText(sourceLocation(for: node).line, in: source)
    guard let paren = line.firstIndex(of: "(") else { return nil }
    let beforeParen = line[..<paren]
    let candidate =
      beforeParen
      .split { character in
        character == " " || character == "\t" || character == "=" || character == "{" || character == ";"
      }
      .last
      .map(String.init)
    return candidate.flatMap(cleanCalleeName)
  }

  private func compactText(for node: Node, source: String) -> String? {
    let location = sourceLocation(for: node)
    let lines = source.components(separatedBy: .newlines)
    guard location.line >= 1, location.line <= lines.count else { return nil }
    if location.line == location.endLine {
      return String(lines[location.line - 1].prefix(120))
    }
    return String(lines[location.line - 1].prefix(120))
  }

  private func cleanCalleeName(_ raw: String) -> String? {
    var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while name.hasPrefix("try ") || name.hasPrefix("await ") || name.hasPrefix("return ") {
      if let range = name.range(of: " ") {
        name = String(name[range.upperBound...])
      } else {
        break
      }
    }
    name = name.trimmingCharacters(in: CharacterSet(charactersIn: "!.?;:,{}[]()"))
    if let dot = name.lastIndex(of: ".") {
      name = String(name[name.index(after: dot)...])
    }
    if let colon = name.lastIndex(of: ":") {
      name = String(name[name.index(after: colon)...])
    }
    guard !name.isEmpty, name.rangeOfCharacter(from: .letters) != nil else { return nil }
    guard !["if", "for", "while", "switch", "catch", "return", "guard"].contains(name) else {
      return nil
    }
    return String(name.prefix(80))
  }

  private func lineText(_ line: Int, in source: String) -> String {
    let lines = source.components(separatedBy: .newlines)
    guard line >= 1, line <= lines.count else { return "" }
    return lines[line - 1]
  }

  private func dedupeConstructs(_ constructs: [RuntimePathConstruct]) -> [RuntimePathConstruct] {
    var seen: Set<String> = []
    return constructs.filter { construct in
      seen.insert("\(construct.kind.rawValue):\(construct.line):\(construct.label)").inserted
    }
  }

  private func dedupeCalls(_ calls: [RuntimePathCall]) -> [RuntimePathCall] {
    var seen: Set<String> = []
    return calls.filter { call in
      seen.insert("\(call.callee):\(call.line)").inserted
    }
  }

  private static func firstLine(containingAny needles: [String], in lines: [String]) -> Int? {
    for (index, line) in lines.enumerated() {
      if needles.contains(where: { line.contains($0) }) {
        return index + 1
      }
    }
    return nil
  }

  private static func confidenceRank(_ confidence: WorldConfidence) -> Int {
    switch confidence {
    case .high: return 0
    case .medium: return 1
    case .low: return 2
    }
  }
}

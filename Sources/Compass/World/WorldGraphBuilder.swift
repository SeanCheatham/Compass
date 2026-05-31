import Foundation

actor WorldGraphCache {
  static let shared = WorldGraphCache()

  private var graphs: [String: WorldGraph] = [:]

  func graph(for fingerprint: String) -> WorldGraph? {
    graphs[fingerprint]
  }

  func store(_ graph: WorldGraph, for fingerprint: String) {
    graphs[fingerprint] = graph
    if graphs.count > 8 {
      let keysToDrop = graphs.keys.sorted().prefix(graphs.count - 8)
      for key in keysToDrop {
        graphs.removeValue(forKey: key)
      }
    }
  }

  func removeAll() {
    graphs.removeAll()
  }
}

struct WorldGraphBuilder: Sendable {
  let repoURL: URL
  let codemapDirectory: URL
  let extractor: RuntimePathExtractor
  let maxRuntimeFactsPerFile: Int

  init(
    repoURL: URL,
    codemapDirectory: URL,
    extractor: RuntimePathExtractor = RuntimePathExtractor(),
    maxRuntimeFactsPerFile: Int = 80
  ) {
    self.repoURL = repoURL.standardizedFileURL
    self.codemapDirectory = codemapDirectory.standardizedFileURL
    self.extractor = extractor
    self.maxRuntimeFactsPerFile = maxRuntimeFactsPerFile
  }

  func buildCached() async -> WorldGraph {
    let entries = loadEntries()
    let fingerprint = Self.fingerprint(repoURL: repoURL, entries: entries)
    if let cached = await WorldGraphCache.shared.graph(for: fingerprint) {
      return cached
    }
    var graph = build(entries: entries)
    graph.fingerprint = fingerprint
    graph = WorldGraphLayout.applyingLayout(to: graph)
    await WorldGraphCache.shared.store(graph, for: fingerprint)
    return graph
  }

  func build(entries: [CodemapEntry]? = nil) -> WorldGraph {
    let entries = entries ?? loadEntries()
    var graph = WorldGraph()
    var fileIDsByPath: [String: String] = [:]
    var symbolIDsByPathAndLine: [String: String] = [:]
    var symbolIDsByName: [String: [String]] = [:]
    var symbolsByPath: [String: [CodemapSymbol]] = [:]

    for entry in entries {
      let moduleID = Self.moduleID(for: entry.relativePath)
      let moduleName = Self.moduleName(for: entry.relativePath)
      graph.addNode(
        WorldNode(
          id: moduleID,
          kind: .module,
          label: moduleName,
          detail: "Region for \(moduleName)",
          language: nil,
          location: nil,
          confidence: .high,
          position: .zero
        )
      )

      let fileID = Self.fileID(for: entry.relativePath)
      fileIDsByPath[entry.relativePath] = fileID
      symbolsByPath[entry.relativePath] = entry.symbols
      graph.addNode(
        WorldNode(
          id: fileID,
          kind: .file,
          label: (entry.relativePath as NSString).lastPathComponent,
          detail: entry.relativePath,
          language: entry.language,
          location: WorldSourceLocation(
            filePath: entry.relativePath,
            line: 1,
            endLine: max(1, entry.symbols.map(\.endLine).max() ?? 1)
          ),
          confidence: .high,
          position: .zero
        )
      )
      graph.addEdge(from: moduleID, to: fileID, kind: .contains, confidence: .high)

      for symbol in entry.symbols {
        let nodeID = Self.symbolID(path: entry.relativePath, symbol: symbol)
        symbolIDsByPathAndLine[Self.symbolLookupKey(path: entry.relativePath, line: symbol.line)] =
          nodeID
        symbolIDsByName[symbol.name, default: []].append(nodeID)
        graph.addNode(
          WorldNode(
            id: nodeID,
            kind: Self.nodeKind(for: symbol),
            label: symbol.name,
            detail: symbol.kind.rawValue,
            language: entry.language,
            location: WorldSourceLocation(
              filePath: entry.relativePath,
              line: symbol.line,
              endLine: symbol.endLine
            ),
            confidence: .high,
            position: .zero
          )
        )
        graph.addEdge(from: fileID, to: nodeID, kind: .contains, confidence: .high)
      }

      for container in entry.symbols where Self.nodeKind(for: container) == .type {
        let containerID = Self.symbolID(path: entry.relativePath, symbol: container)
        for child in entry.symbols where [.function, .method].contains(child.kind) {
          guard child.line > container.line, child.endLine <= container.endLine else { continue }
          let childID = Self.symbolID(path: entry.relativePath, symbol: child)
          graph.addEdge(from: containerID, to: childID, kind: .contains, confidence: .high)
        }
      }
    }

    for entry in entries {
      guard let fileID = fileIDsByPath[entry.relativePath] else { continue }
      let sourceURL = repoURL.appendingPathComponent(entry.relativePath)
      guard
        let data = try? Data(contentsOf: sourceURL),
        let source = String(data: data, encoding: .utf8)
      else {
        continue
      }

      let extraction =
        (try? extractor.extract(
          source: source,
          language: entry.language,
          relativePath: entry.relativePath,
          symbols: entry.symbols
        )) ?? .empty

      for entrypoint in extraction.entrypoints {
        let nodeID = entrypointNodeID(
          entrypoint,
          entry: entry,
          fileID: fileID,
          symbolIDsByPathAndLine: symbolIDsByPathAndLine,
          graph: &graph
        )
        graph.markEntrypoint(nodeID)
      }

      for construct in extraction.constructs.prefix(maxRuntimeFactsPerFile) {
        let nodeID = Self.constructID(
          path: entry.relativePath,
          kind: construct.kind,
          line: construct.line,
          label: construct.label
        )
        let ownerID =
          ownerSymbolID(
            for: construct.line,
            entry: entry,
            symbolIDsByPathAndLine: symbolIDsByPathAndLine
          ) ?? fileID
        let nodeKind = Self.nodeKind(for: construct.kind)
        graph.addNode(
          WorldNode(
            id: nodeID,
            kind: nodeKind,
            label: Self.displayLabel(for: construct),
            detail: construct.label,
            language: entry.language,
            location: WorldSourceLocation(
              filePath: entry.relativePath,
              line: construct.line,
              endLine: construct.endLine
            ),
            confidence: construct.confidence,
            position: .zero
          )
        )
        graph.addEdge(
          from: ownerID,
          to: nodeID,
          kind: Self.edgeKind(for: construct.kind),
          label: construct.kind.rawValue,
          confidence: construct.confidence
        )
      }

      for call in extraction.calls.prefix(maxRuntimeFactsPerFile) {
        let ownerID =
          ownerSymbolID(for: call.line, entry: entry, symbolIDsByPathAndLine: symbolIDsByPathAndLine)
          ?? fileID
        if let targetID = resolveCall(call, entry: entry, symbolIDsByName: symbolIDsByName) {
          graph.addEdge(
            from: ownerID,
            to: targetID,
            kind: .calls,
            label: call.callee,
            confidence: call.confidence
          )
        } else {
          let unresolvedID = Self.unresolvedID(
            path: entry.relativePath,
            line: call.line,
            callee: call.callee
          )
          graph.addNode(
            WorldNode(
              id: unresolvedID,
              kind: .unresolvedPassage,
              label: call.callee,
              detail: "Dynamic or external call",
              language: entry.language,
              location: WorldSourceLocation(
                filePath: entry.relativePath,
                line: call.line,
                endLine: call.endLine
              ),
              confidence: .low,
              position: .zero
            )
          )
          graph.addEdge(
            from: ownerID,
            to: unresolvedID,
            kind: .calls,
            label: call.callee,
            confidence: .low
          )
        }
      }

      for rawImport in entry.imports {
        if let targetID = importTargetID(rawImport.raw, fileIDsByPath: fileIDsByPath) {
          graph.addEdge(
            from: fileID,
            to: targetID,
            kind: .imports,
            label: rawImport.raw,
            confidence: .medium
          )
        }
      }
    }

    return WorldGraphLayout.applyingLayout(to: graph)
  }

  private func loadEntries() -> [CodemapEntry] {
    CodemapStore(directory: codemapDirectory)
      .loadAllEntries()
      .sorted { $0.relativePath < $1.relativePath }
  }

  private func entrypointNodeID(
    _ entrypoint: RuntimePathEntrypoint,
    entry: CodemapEntry,
    fileID: String,
    symbolIDsByPathAndLine: [String: String],
    graph: inout WorldGraph
  ) -> String {
    if let symbol = entry.symbols.first(where: { symbol in
      symbol.name == entrypoint.name || (symbol.line...symbol.endLine).contains(entrypoint.line)
    }) {
      let key = Self.symbolLookupKey(path: entry.relativePath, line: symbol.line)
      if let nodeID = symbolIDsByPathAndLine[key] {
        return nodeID
      }
    }

    let nodeID = Self.entrypointID(path: entry.relativePath, entrypoint: entrypoint)
    graph.addNode(
      WorldNode(
        id: nodeID,
        kind: .function,
        label: entrypoint.name,
        detail: entrypoint.reason,
        language: entry.language,
        location: WorldSourceLocation(
          filePath: entry.relativePath,
          line: entrypoint.line,
          endLine: entrypoint.endLine
        ),
        confidence: entrypoint.confidence,
        position: .zero
      )
    )
    graph.addEdge(from: fileID, to: nodeID, kind: .contains, confidence: entrypoint.confidence)
    return nodeID
  }

  private func ownerSymbolID(
    for line: Int,
    entry: CodemapEntry,
    symbolIDsByPathAndLine: [String: String]
  ) -> String? {
    let owner = entry.symbols
      .filter { symbol in
        (symbol.line...symbol.endLine).contains(line)
          && [.function, .method].contains(symbol.kind)
      }
      .sorted {
        let lhsSpan = $0.endLine - $0.line
        let rhsSpan = $1.endLine - $1.line
        if lhsSpan != rhsSpan { return lhsSpan < rhsSpan }
        return $0.line > $1.line
      }
      .first
    guard let owner else { return nil }
    return symbolIDsByPathAndLine[Self.symbolLookupKey(path: entry.relativePath, line: owner.line)]
  }

  private func resolveCall(
    _ call: RuntimePathCall,
    entry: CodemapEntry,
    symbolIDsByName: [String: [String]]
  ) -> String? {
    guard var candidates = symbolIDsByName[call.callee], !candidates.isEmpty else {
      return nil
    }
    candidates.sort {
      let lhsSameFile = $0.contains(":\(entry.relativePath):")
      let rhsSameFile = $1.contains(":\(entry.relativePath):")
      if lhsSameFile != rhsSameFile { return lhsSameFile }
      return $0 < $1
    }
    return candidates.first
  }

  private func importTargetID(_ rawImport: String, fileIDsByPath: [String: String]) -> String? {
    let candidates = [
      rawImport,
      rawImport + ".swift",
      rawImport + ".ts",
      rawImport + ".tsx",
      rawImport + ".js",
      rawImport + ".go",
      rawImport + ".rs",
      "Sources/" + rawImport,
      "Sources/" + rawImport + ".swift",
    ]
    return candidates.lazy.compactMap { fileIDsByPath[$0] }.first
  }

  static func fingerprint(repoURL: URL, entries: [CodemapEntry]) -> String {
    let body = entries
      .sorted { $0.relativePath < $1.relativePath }
      .map { "\($0.relativePath):\($0.contentHash):\($0.symbols.count):\($0.imports.count)" }
      .joined(separator: "|")
    return CodemapHash.sha256Hex(repoURL.standardizedFileURL.path + "|" + body)
  }

  static func moduleName(for path: String) -> String {
    String(path.split(separator: "/").first ?? "Root")
  }

  static func moduleID(for path: String) -> String {
    "module:\(moduleName(for: path))"
  }

  static func fileID(for path: String) -> String {
    "file:\(path)"
  }

  static func symbolID(path: String, symbol: CodemapSymbol) -> String {
    "symbol:\(path):\(symbol.line):\(symbol.kind.rawValue):\(symbol.name)"
  }

  static func constructID(
    path: String,
    kind: RuntimePathConstructKind,
    line: Int,
    label: String
  ) -> String {
    let labelHash = CodemapHash.sha256Hex(label).prefix(8)
    return "construct:\(path):\(line):\(kind.rawValue):\(labelHash)"
  }

  static func unresolvedID(path: String, line: Int, callee: String) -> String {
    "unresolved:\(path):\(line):\(callee)"
  }

  static func entrypointID(path: String, entrypoint: RuntimePathEntrypoint) -> String {
    "entry:\(path):\(entrypoint.line):\(entrypoint.name)"
  }

  static func symbolLookupKey(path: String, line: Int) -> String {
    "\(path):\(line)"
  }

  static func nodeKind(for symbol: CodemapSymbol) -> WorldNodeKind {
    switch symbol.kind {
    case .function, .method, .macro:
      return .function
    case .class, .interface, .struct, .enum, .trait, .module, .type, .impl, .extension:
      return .type
    case .property, .constant:
      return .type
    }
  }

  static func nodeKind(for construct: RuntimePathConstructKind) -> WorldNodeKind {
    switch construct {
    case .branch: return .branch
    case .loop: return .loop
    case .switchCase: return .switchCase
    case .errorPath: return .errorPath
    }
  }

  static func edgeKind(for construct: RuntimePathConstructKind) -> WorldEdgeKind {
    switch construct {
    case .branch: return .branches
    case .loop: return .loops
    case .switchCase: return .branches
    case .errorPath: return .`throws`
    }
  }

  static func displayLabel(for construct: RuntimePathConstruct) -> String {
    switch construct.kind {
    case .branch:
      return "Branch L\(construct.line)"
    case .loop:
      return "Loop L\(construct.line)"
    case .switchCase:
      return "Decision L\(construct.line)"
    case .errorPath:
      return "Error path L\(construct.line)"
    }
  }
}

extension WorldPosition {
  static let zero = WorldPosition(x: 0, y: 0, z: 0)
}

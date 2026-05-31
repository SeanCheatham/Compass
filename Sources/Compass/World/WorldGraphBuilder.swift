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
  let maxWorldFiles: Int
  let maxSymbolsPerFile: Int
  let maxRuntimeFactsPerFile: Int
  let maxSourceBytes: Int

  init(
    repoURL: URL,
    codemapDirectory: URL,
    extractor: RuntimePathExtractor = RuntimePathExtractor(),
    maxWorldFiles: Int = 32,
    maxSymbolsPerFile: Int = 18,
    maxRuntimeFactsPerFile: Int = 10,
    maxSourceBytes: Int = 512_000
  ) {
    self.repoURL = repoURL.standardizedFileURL
    self.codemapDirectory = codemapDirectory.standardizedFileURL
    self.extractor = extractor
    self.maxWorldFiles = maxWorldFiles
    self.maxSymbolsPerFile = maxSymbolsPerFile
    self.maxRuntimeFactsPerFile = maxRuntimeFactsPerFile
    self.maxSourceBytes = maxSourceBytes
  }

  func buildCached() async -> WorldGraph {
    let entries = loadEntries()
    let fingerprint = Self.fingerprint(
      repoURL: repoURL,
      entries: entries,
      maxWorldFiles: maxWorldFiles,
      maxSymbolsPerFile: maxSymbolsPerFile,
      maxRuntimeFactsPerFile: maxRuntimeFactsPerFile
    )
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
    let allEntries = entries ?? loadEntries()
    var sourceCache: [String: String] = [:]
    let entries = focusedEntries(from: allEntries, sourceCache: &sourceCache)
    var graph = WorldGraph()
    var fileIDsByPath: [String: String] = [:]
    var symbolIDsByPathAndLine: [String: String] = [:]
    var symbolIDsByName: [String: [String]] = [:]

    for entry in entries {
      let retainedSymbols = Self.retainedSymbols(for: entry, limit: maxSymbolsPerFile)
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

      for symbol in retainedSymbols {
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

      for container in retainedSymbols where Self.nodeKind(for: container) == .type {
        let containerID = Self.symbolID(path: entry.relativePath, symbol: container)
        for child in retainedSymbols where [.function, .method].contains(child.kind) {
          guard child.line > container.line, child.endLine <= container.endLine else { continue }
          let childID = Self.symbolID(path: entry.relativePath, symbol: child)
          graph.addEdge(from: containerID, to: childID, kind: .contains, confidence: .high)
        }
      }
    }

    for entry in entries {
      guard let fileID = fileIDsByPath[entry.relativePath] else { continue }
      guard let source = source(for: entry, sourceCache: &sourceCache) else { continue }

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

  private func focusedEntries(
    from entries: [CodemapEntry],
    sourceCache: inout [String: String]
  ) -> [CodemapEntry] {
    let sortedEntries = entries.sorted { $0.relativePath < $1.relativePath }
    guard sortedEntries.count > maxWorldFiles else { return sortedEntries }

    let entryByPath = Dictionary(uniqueKeysWithValues: sortedEntries.map { ($0.relativePath, $0) })
    let filePaths = Set(entryByPath.keys)
    let ranked = sortedEntries
      .map { entry -> (entry: CodemapEntry, score: Int) in
        (entry, focusScore(for: entry, source: source(for: entry, sourceCache: &sourceCache)))
      }
      .sorted { lhs, rhs in
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        return lhs.entry.relativePath < rhs.entry.relativePath
      }

    var selectedPaths: Set<String> = []

    func select(_ path: String) {
      guard selectedPaths.count < maxWorldFiles, filePaths.contains(path) else { return }
      selectedPaths.insert(path)
    }

    for item in ranked where item.score >= 220 {
      select(item.entry.relativePath)
    }

    let seedPaths = selectedPaths
    for path in seedPaths.sorted() {
      guard let entry = entryByPath[path] else { continue }
      for rawImport in entry.imports.map(\.raw) {
        if let targetPath = Self.importTargetPath(rawImport, filePaths: filePaths) {
          select(targetPath)
        }
      }
    }

    for item in ranked {
      guard selectedPaths.count < maxWorldFiles else { break }
      select(item.entry.relativePath)
    }

    return sortedEntries.filter { selectedPaths.contains($0.relativePath) }
  }

  private func source(
    for entry: CodemapEntry,
    sourceCache: inout [String: String]
  ) -> String? {
    if let cached = sourceCache[entry.relativePath] {
      return cached
    }
    guard entry.sizeBytes <= maxSourceBytes else { return nil }
    let sourceURL = repoURL.appendingPathComponent(entry.relativePath)
    guard
      let data = try? Data(contentsOf: sourceURL),
      let source = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    sourceCache[entry.relativePath] = source
    return source
  }

  private func focusScore(for entry: CodemapEntry, source: String?) -> Int {
    let path = entry.relativePath
    let fileName = (path as NSString).lastPathComponent
    let stem = ((fileName as NSString).deletingPathExtension).lowercased()
    var score = 0

    if path.hasPrefix("Sources/") || path.contains("/Sources/") { score += 50 }
    if path.hasPrefix("Tests/") || path.contains("/Tests/") { score -= 900 }
    if entry.isGenerated { score -= 220 }
    if fileName == "main.swift" { score += 520 }
    if ["index", "main", "app", "server"].contains(stem) { score += 160 }
    if stem.hasSuffix("app") { score += 80 }

    for symbol in entry.symbols {
      if symbol.name == "main", [.function, .method].contains(symbol.kind) { score += 260 }
      if symbol.name.hasSuffix("App"), [.class, .struct].contains(symbol.kind) { score += 90 }
      if [.function, .method].contains(symbol.kind) { score += 2 }
    }

    if let source {
      if source.contains("@main") { score += 520 }
      if source.contains("package main") { score += 260 }
      if source.contains("import.meta.main") || source.contains("process.argv") { score += 180 }
    }

    return score
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
    Self.importTargetPath(rawImport, filePaths: Set(fileIDsByPath.keys))
      .flatMap { fileIDsByPath[$0] }
  }

  static func retainedSymbols(for entry: CodemapEntry, limit: Int) -> [CodemapSymbol] {
    guard entry.symbols.count > limit else { return entry.symbols }
    return entry.symbols
      .sorted { lhs, rhs in
        let lhsScore = symbolDisplayScore(lhs)
        let rhsScore = symbolDisplayScore(rhs)
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.name < rhs.name
      }
      .prefix(limit)
      .sorted { lhs, rhs in
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.name < rhs.name
      }
  }

  static func importTargetPath(_ rawImport: String, filePaths: Set<String>) -> String? {
    let clean = rawImport
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let withoutDotSlash = clean.hasPrefix("./") ? String(clean.dropFirst(2)) : clean
    let candidates = [
      clean,
      clean + ".swift",
      clean + ".ts",
      clean + ".tsx",
      clean + ".js",
      clean + ".go",
      clean + ".rs",
      withoutDotSlash,
      withoutDotSlash + ".swift",
      withoutDotSlash + ".ts",
      withoutDotSlash + ".tsx",
      withoutDotSlash + ".js",
      "Sources/" + withoutDotSlash,
      "Sources/" + withoutDotSlash + ".swift",
    ]
    return candidates.first { filePaths.contains($0) }
  }

  private static func symbolDisplayScore(_ symbol: CodemapSymbol) -> Int {
    var score = 0
    switch symbol.kind {
    case .function, .method:
      score += 120
    case .class, .struct, .enum, .interface, .trait, .type, .impl, .extension, .module:
      score += 90
    case .macro:
      score += 60
    case .property, .constant:
      score += 15
    }
    if symbol.name == "main" { score += 260 }
    if symbol.name.hasSuffix("App") { score += 120 }
    return score
  }

  static func fingerprint(
    repoURL: URL,
    entries: [CodemapEntry],
    maxWorldFiles: Int,
    maxSymbolsPerFile: Int,
    maxRuntimeFactsPerFile: Int
  ) -> String {
    let body = entries
      .sorted { $0.relativePath < $1.relativePath }
      .map { "\($0.relativePath):\($0.contentHash):\($0.symbols.count):\($0.imports.count)" }
      .joined(separator: "|")
    let limits = "world:v2:\(maxWorldFiles):\(maxSymbolsPerFile):\(maxRuntimeFactsPerFile)"
    return CodemapHash.sha256Hex(repoURL.standardizedFileURL.path + "|\(limits)|" + body)
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

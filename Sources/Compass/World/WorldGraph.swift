import Foundation

enum WorldNodeKind: String, Codable, Sendable, CaseIterable {
  case module
  case file
  case type
  case function
  case branch
  case loop
  case switchCase
  case errorPath
  case unresolvedPassage
}

enum WorldEdgeKind: String, Codable, Sendable, CaseIterable {
  case contains
  case imports
  case calls
  case branches
  case loops
  case returns
  case `throws`
}

enum WorldConfidence: String, Codable, Sendable, CaseIterable {
  case high
  case medium
  case low
}

struct WorldSourceLocation: Codable, Hashable, Sendable {
  var filePath: String
  var line: Int
  var endLine: Int

  var lineLabel: String {
    if line == endLine {
      return "L\(line)"
    }
    return "L\(line)-\(endLine)"
  }
}

struct WorldPosition: Codable, Hashable, Sendable {
  var x: Float
  var y: Float
  var z: Float
}

struct WorldNode: Identifiable, Codable, Hashable, Sendable {
  var id: String
  var kind: WorldNodeKind
  var label: String
  var detail: String?
  var language: CodemapLanguage?
  var location: WorldSourceLocation?
  var confidence: WorldConfidence
  var position: WorldPosition
}

struct WorldEdge: Identifiable, Codable, Hashable, Sendable {
  var id: String
  var sourceID: String
  var targetID: String
  var kind: WorldEdgeKind
  var label: String?
  var confidence: WorldConfidence
}

struct WorldGraph: Codable, Equatable, Sendable {
  var nodes: [WorldNode] = []
  var edges: [WorldEdge] = []
  var entrypointIDs: [String] = []
  var fingerprint: String = ""

  var isEmpty: Bool {
    nodes.isEmpty
  }

  var nodeByID: [String: WorldNode] {
    Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
  }

  var entrypoints: [WorldNode] {
    let lookup = nodeByID
    return entrypointIDs.compactMap { lookup[$0] }
  }

  func outgoingEdges(from nodeID: String, kinds: Set<WorldEdgeKind>? = nil) -> [WorldEdge] {
    edges.filter { edge in
      edge.sourceID == nodeID && (kinds?.contains(edge.kind) ?? true)
    }
  }

  func incomingEdges(to nodeID: String, kinds: Set<WorldEdgeKind>? = nil) -> [WorldEdge] {
    edges.filter { edge in
      edge.targetID == nodeID && (kinds?.contains(edge.kind) ?? true)
    }
  }

  mutating func addNode(_ node: WorldNode) {
    guard !nodes.contains(where: { $0.id == node.id }) else { return }
    nodes.append(node)
  }

  mutating func addEdge(
    from sourceID: String,
    to targetID: String,
    kind: WorldEdgeKind,
    label: String? = nil,
    confidence: WorldConfidence = .medium
  ) {
    guard sourceID != targetID else { return }
    let id = "\(sourceID)->\(targetID):\(kind.rawValue):\(label ?? "")"
    guard !edges.contains(where: { $0.id == id }) else { return }
    edges.append(
      WorldEdge(
        id: id,
        sourceID: sourceID,
        targetID: targetID,
        kind: kind,
        label: label,
        confidence: confidence
      )
    )
  }

  mutating func markEntrypoint(_ nodeID: String) {
    guard !entrypointIDs.contains(nodeID) else { return }
    entrypointIDs.append(nodeID)
  }

  mutating func sortForDeterminism() {
    nodes.sort {
      if $0.position.z != $1.position.z { return $0.position.z > $1.position.z }
      if $0.position.x != $1.position.x { return $0.position.x < $1.position.x }
      return $0.id < $1.id
    }
    edges.sort {
      if $0.sourceID != $1.sourceID { return $0.sourceID < $1.sourceID }
      if $0.targetID != $1.targetID { return $0.targetID < $1.targetID }
      return $0.kind.rawValue < $1.kind.rawValue
    }
    entrypointIDs.sort()
  }
}

struct WorldGraphLayout {
  static func applyingLayout(to graph: WorldGraph) -> WorldGraph {
    var graph = graph
    let depths = depthByNode(in: graph)
    let grouped = Dictionary(grouping: graph.nodes) { depths[$0.id] ?? 0 }
    var positions: [String: WorldPosition] = [:]

    for depth in grouped.keys.sorted() {
      let group = (grouped[depth] ?? []).sorted { lhs, rhs in
        if lhs.kind != rhs.kind {
          return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.id < rhs.id
      }
      let center = Float(max(0, group.count - 1)) / 2
      for (index, node) in group.enumerated() {
        let x = (Float(index) - center) * 2.6
        let y = yOffset(for: node.kind)
        let z = -Float(depth) * 3.2
        positions[node.id] = WorldPosition(x: x, y: y, z: z)
      }
    }

    graph.nodes = graph.nodes.map { node in
      var node = node
      node.position = positions[node.id] ?? node.position
      return node
    }
    graph.sortForDeterminism()
    return graph
  }

  private static func depthByNode(in graph: WorldGraph) -> [String: Int] {
    var depths: [String: Int] = [:]
    var queue: [(String, Int)] = []

    let starts = graph.entrypointIDs.isEmpty
      ? graph.nodes.filter { $0.kind == .file || $0.kind == .module }.map(\.id)
      : graph.entrypointIDs

    for start in starts.sorted() {
      depths[start] = min(depths[start] ?? Int.max, 0)
      queue.append((start, 0))
    }

    var cursor = 0
    while cursor < queue.count {
      let (nodeID, depth) = queue[cursor]
      cursor += 1
      let nextEdges = graph.edges.filter { edge in
        edge.sourceID == nodeID
          && [.contains, .branches, .loops, .calls, .`throws`].contains(edge.kind)
      }
      for edge in nextEdges {
        let nextDepth = depth + 1
        if let existing = depths[edge.targetID], existing <= nextDepth {
          continue
        }
        depths[edge.targetID] = nextDepth
        queue.append((edge.targetID, nextDepth))
      }
    }

    var fallbackDepth = (depths.values.max() ?? 0) + 1
    for node in graph.nodes.sorted(by: { $0.id < $1.id }) where depths[node.id] == nil {
      depths[node.id] = fallbackDepth
      fallbackDepth += 1
    }
    return depths
  }

  private static func yOffset(for kind: WorldNodeKind) -> Float {
    switch kind {
    case .module: return 0.45
    case .file: return 0.25
    case .type: return 0.55
    case .function: return 0.8
    case .branch: return 1.15
    case .loop: return 1.0
    case .switchCase: return 1.2
    case .errorPath: return 1.05
    case .unresolvedPassage: return 0.7
    }
  }
}

enum WorldNavigator {
  static func route(in graph: WorldGraph, from entrypointID: String?) -> [String] {
    let startID = entrypointID ?? graph.entrypointIDs.first ?? graph.nodes.first?.id
    guard let startID else { return [] }

    var route: [String] = []
    var visited: Set<String> = []

    func walk(_ nodeID: String, depth: Int) {
      guard depth < 80, !visited.contains(nodeID) else { return }
      visited.insert(nodeID)
      route.append(nodeID)

      let orderedEdges = graph.outgoingEdges(
        from: nodeID,
        kinds: [.branches, .loops, .calls, .`throws`, .contains]
      )
      .sorted { lhs, rhs in
        let lhsRank = routeRank(lhs.kind)
        let rhsRank = routeRank(rhs.kind)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.targetID < rhs.targetID
      }

      for edge in orderedEdges.prefix(4) {
        walk(edge.targetID, depth: depth + 1)
      }
    }

    walk(startID, depth: 0)
    return route
  }

  static func branchChoices(in graph: WorldGraph, at nodeID: String?) -> [WorldNode] {
    guard let nodeID else { return [] }
    let lookup = graph.nodeByID
    return graph.outgoingEdges(from: nodeID, kinds: [.branches])
      .compactMap { lookup[$0.targetID] }
      .sorted { $0.label < $1.label }
  }

  private static func routeRank(_ kind: WorldEdgeKind) -> Int {
    switch kind {
    case .branches: return 0
    case .loops: return 1
    case .calls: return 2
    case .`throws`: return 3
    case .contains: return 4
    case .imports: return 5
    case .returns: return 6
    }
  }
}

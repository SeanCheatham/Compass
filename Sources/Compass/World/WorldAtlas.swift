import Foundation

struct WorldAtlas: Equatable, Sendable {
  struct Metric: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var value: String
    var detail: String
  }

  struct Terrain: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var count: Int
    var detail: String
    var systemImageName: String
  }

  struct Notice: Identifiable, Equatable, Sendable {
    enum Severity: String, Equatable, Sendable {
      case info
      case warning
      case danger
    }

    var id: String
    var label: String
    var detail: String
    var severity: Severity
  }

  struct RouteStop: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var detail: String
    var isCurrent: Bool
  }

  var title: String
  var detail: String
  var progressLabel: String
  var metrics: [Metric]
  var terrain: [Terrain]
  var notices: [Notice]
  var routeStops: [RouteStop]

  init(
    graph: WorldGraph,
    route: [String],
    routeIndex: Int,
    selectedNodeID: String?
  ) {
    let nodeCounts = Dictionary(grouping: graph.nodes, by: \.kind).mapValues(\.count)
    let navigableEdges = graph.edges.filter { $0.kind != .imports }
    let decisionCount =
      (nodeCounts[.branch] ?? 0)
      + (nodeCounts[.switchCase] ?? 0)
      + (nodeCounts[.loop] ?? 0)
    let safeRouteIndex = route.isEmpty ? 0 : min(max(routeIndex, 0), route.count - 1)
    let lookup = graph.nodeByID

    title = "World Atlas"
    detail = Self.summary(
      nodeCount: graph.nodes.count,
      entrypointCount: graph.entrypointIDs.count,
      edgeCount: navigableEdges.count,
      routeCount: route.count,
      routeStart: route.first.flatMap { lookup[$0]?.label }
    )
    progressLabel =
      route.isEmpty ? "No route selected" : "Step \(safeRouteIndex + 1) of \(route.count)"
    metrics = [
      Metric(
        id: "entrypoints",
        label: "Entrances",
        value: "\(graph.entrypointIDs.count)",
        detail: "Starting points Compass can follow"
      ),
      Metric(
        id: "nodes",
        label: "Chambers",
        value: "\(graph.nodes.count)",
        detail: "Code places in this world"
      ),
      Metric(
        id: "paths",
        label: "Paths",
        value: "\(navigableEdges.count)",
        detail: "Non-import relationships"
      ),
      Metric(
        id: "decisions",
        label: "Decisions",
        value: "\(decisionCount)",
        detail: "Branches, loops, and cases"
      ),
    ]
    terrain = Self.terrain(from: nodeCounts)
    notices = Self.notices(
      graph: graph,
      nodeCounts: nodeCounts,
      route: route,
      selectedNodeID: selectedNodeID,
      lookup: lookup
    )
    routeStops = Self.routeStops(
      route: route,
      routeIndex: safeRouteIndex,
      lookup: lookup
    )
  }

  private static func summary(
    nodeCount: Int,
    entrypointCount: Int,
    edgeCount: Int,
    routeCount: Int,
    routeStart: String?
  ) -> String {
    guard nodeCount > 0 else {
      return "Index the project to turn code facts into a navigable world."
    }

    let entranceText = pluralized(entrypointCount, singular: "entrance", plural: "entrances")
    let chamberText = pluralized(nodeCount, singular: "chamber", plural: "chambers")
    let pathText = pluralized(edgeCount, singular: "path", plural: "paths")

    guard routeCount > 0 else {
      return
        "This world has \(chamberText), \(entranceText), and \(pathText). Pick an entrance to begin a guided walk."
    }

    let start = routeStart.map { " from \($0)" } ?? ""
    let stopText = pluralized(routeCount, singular: "stop", plural: "stops")
    return "Following \(stopText)\(start) through \(chamberText), \(entranceText), and \(pathText)."
  }

  private static func terrain(from nodeCounts: [WorldNodeKind: Int]) -> [Terrain] {
    WorldNodeKind.allCases.compactMap { kind in
      guard let count = nodeCounts[kind], count > 0 else { return nil }
      return Terrain(
        id: kind.rawValue,
        label: label(for: kind),
        count: count,
        detail: detail(for: kind, count: count),
        systemImageName: systemImageName(for: kind)
      )
    }
  }

  private static func notices(
    graph: WorldGraph,
    nodeCounts: [WorldNodeKind: Int],
    route: [String],
    selectedNodeID: String?,
    lookup: [String: WorldNode]
  ) -> [Notice] {
    var notices: [Notice] = []

    if graph.nodes.isEmpty {
      notices.append(
        Notice(
          id: "emptyWorld",
          label: "No atlas yet",
          detail: "Run indexing so Compass can draw the first map.",
          severity: .info
        )
      )
      return notices
    }

    if graph.entrypointIDs.isEmpty {
      notices.append(
        Notice(
          id: "missingEntrances",
          label: "No entrances found",
          detail: "Compass can still show nearby code, but it cannot start a guided route.",
          severity: .warning
        )
      )
    }

    if route.isEmpty {
      notices.append(
        Notice(
          id: "emptyRoute",
          label: "No guided walk",
          detail: "Choose an entrance to get a step-by-step path through this world.",
          severity: .info
        )
      )
    }

    let unresolvedCount = nodeCounts[.unresolvedPassage] ?? 0
    if unresolvedCount > 0 {
      notices.append(
        Notice(
          id: "unresolvedPassages",
          label: pluralized(
            unresolvedCount, singular: "Unknown passage", plural: "Unknown passages"),
          detail: "These calls or jumps could not be linked to a known destination.",
          severity: .warning
        )
      )
    }

    let errorPathCount = nodeCounts[.errorPath] ?? 0
    if errorPathCount > 0 {
      notices.append(
        Notice(
          id: "errorPaths",
          label: pluralized(errorPathCount, singular: "Error path", plural: "Error paths"),
          detail: "These are exits where the code can throw or fail.",
          severity: .danger
        )
      )
    }

    let lowConfidenceCount =
      graph.nodes.filter { $0.confidence == .low }.count
      + graph.edges.filter { $0.confidence == .low }.count
    if lowConfidenceCount > 0 {
      notices.append(
        Notice(
          id: "lowConfidence",
          label: pluralized(
            lowConfidenceCount, singular: "Low-confidence clue", plural: "Low-confidence clues"),
          detail: "Compass inferred these from partial information; treat them as leads.",
          severity: .warning
        )
      )
    }

    if let selectedNodeID,
      !route.isEmpty,
      !route.contains(selectedNodeID),
      let selectedNode = lookup[selectedNodeID]
    {
      notices.append(
        Notice(
          id: "offRouteSelection",
          label: "Off-route selection",
          detail: "\(selectedNode.label) is nearby but not part of the current walk.",
          severity: .info
        )
      )
    }

    return notices
  }

  private static func routeStops(
    route: [String],
    routeIndex: Int,
    lookup: [String: WorldNode]
  ) -> [RouteStop] {
    guard !route.isEmpty else { return [] }
    let limit = 6
    let start = max(0, min(routeIndex - 2, max(0, route.count - limit)))
    let end = min(route.count, start + limit)

    return route[start..<end].enumerated().compactMap { offset, nodeID in
      let absoluteIndex = start + offset
      guard let node = lookup[nodeID] else { return nil }
      return RouteStop(
        id: "\(absoluteIndex)-\(nodeID)",
        label: node.label,
        detail: "\(label(for: node.kind)) - \(stepLabel(absoluteIndex, of: route.count))",
        isCurrent: absoluteIndex == routeIndex
      )
    }
  }

  private static func label(for kind: WorldNodeKind) -> String {
    switch kind {
    case .module: return "Region"
    case .file: return "File chamber"
    case .type: return "Structure"
    case .function: return "Action"
    case .branch: return "Decision"
    case .loop: return "Loop"
    case .switchCase: return "Case"
    case .errorPath: return "Error path"
    case .unresolvedPassage: return "Unknown passage"
    }
  }

  private static func detail(for kind: WorldNodeKind, count: Int) -> String {
    switch kind {
    case .module:
      return
        "\(pluralized(count, singular: "region", plural: "regions")) grouping files or features."
    case .file:
      return "\(pluralized(count, singular: "file", plural: "files")) that contain the chambers."
    case .type:
      return
        "\(pluralized(count, singular: "structure", plural: "structures")) that hold behavior or state."
    case .function:
      return "\(pluralized(count, singular: "action", plural: "actions")) where behavior happens."
    case .branch:
      return "\(pluralized(count, singular: "decision", plural: "decisions")) that split the walk."
    case .loop:
      return "\(pluralized(count, singular: "loop", plural: "loops")) where work repeats."
    case .switchCase:
      return
        "\(pluralized(count, singular: "case", plural: "cases")) inside switch-style decisions."
    case .errorPath:
      return "\(pluralized(count, singular: "error exit", plural: "error exits")) worth checking."
    case .unresolvedPassage:
      return
        "\(pluralized(count, singular: "unknown jump", plural: "unknown jumps")) Compass could not link yet."
    }
  }

  private static func systemImageName(for kind: WorldNodeKind) -> String {
    switch kind {
    case .module: return "map"
    case .file: return "doc.text"
    case .type: return "shippingbox"
    case .function: return "circle.hexagongrid"
    case .branch: return "arrow.triangle.branch"
    case .loop: return "arrow.2.circlepath"
    case .switchCase: return "switch.2"
    case .errorPath: return "exclamationmark.triangle"
    case .unresolvedPassage: return "questionmark.diamond"
    }
  }

  private static func stepLabel(_ index: Int, of count: Int) -> String {
    "step \(index + 1) of \(count)"
  }

  private static func pluralized(_ count: Int, singular: String, plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
  }
}

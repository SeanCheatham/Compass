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

  struct Spotlight: Equatable, Sendable {
    enum Tone: String, Equatable, Sendable {
      case neutral
      case ready
      case warning
      case danger
    }

    var title: String
    var detail: String
    var systemImageName: String
    var tone: Tone
  }

  var title: String
  var detail: String
  var progressLabel: String
  var spotlight: Spotlight
  var metrics: [Metric]
  var terrain: [Terrain]
  var notices: [Notice]
  var routeStops: [RouteStop]
  var narrationIdentifier: String

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
    let builtMetrics = [
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
    let builtTerrain = Self.terrain(from: nodeCounts)
    let builtNotices = Self.notices(
      graph: graph,
      nodeCounts: nodeCounts,
      route: route,
      selectedNodeID: selectedNodeID,
      lookup: lookup
    )
    let builtRouteStops = Self.routeStops(
      route: route,
      routeIndex: safeRouteIndex,
      lookup: lookup
    )
    let builtSpotlight = Self.spotlight(
      graph: graph,
      route: route,
      routeStops: builtRouteStops,
      notices: builtNotices
    )

    spotlight = builtSpotlight
    metrics = builtMetrics
    terrain = builtTerrain
    notices = builtNotices
    routeStops = builtRouteStops
    narrationIdentifier = Self.narrationIdentifier(
      graph: graph,
      route: route,
      routeIndex: safeRouteIndex,
      selectedNodeID: selectedNodeID,
      metrics: builtMetrics,
      terrain: builtTerrain,
      spotlight: builtSpotlight,
      notices: builtNotices,
      routeStops: builtRouteStops
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

  private static func spotlight(
    graph: WorldGraph,
    route: [String],
    routeStops: [RouteStop],
    notices: [Notice]
  ) -> Spotlight {
    if graph.nodes.isEmpty {
      return Spotlight(
        title: "Build the map",
        detail: "Index the project to draw the first code-path world.",
        systemImageName: "cube.transparent",
        tone: .neutral
      )
    }

    if let current = routeStops.first(where: \.isCurrent) {
      return Spotlight(
        title: "Now visiting \(current.label)",
        detail: current.detail,
        systemImageName: "location.fill",
        tone: .ready
      )
    }

    if route.isEmpty, !graph.entrypointIDs.isEmpty {
      return Spotlight(
        title: "Pick an entrance",
        detail: "Start a guided walk from one of the discovered entrypoints.",
        systemImageName: "door.left.hand.open",
        tone: .neutral
      )
    }

    if let notice = notices.first(where: { $0.severity == .danger }) {
      return Spotlight(
        title: notice.label,
        detail: notice.detail,
        systemImageName: "exclamationmark.triangle.fill",
        tone: .danger
      )
    }

    if let notice = notices.first(where: { $0.severity == .warning }) {
      return Spotlight(
        title: notice.label,
        detail: notice.detail,
        systemImageName: "exclamationmark.triangle",
        tone: .warning
      )
    }

    return Spotlight(
      title: "Explore nearby chambers",
      detail: "Select a symbol or search for a file to inspect its place in the world.",
      systemImageName: "sparkle.magnifyingglass",
      tone: .neutral
    )
  }

  private static func narrationIdentifier(
    graph: WorldGraph,
    route: [String],
    routeIndex: Int,
    selectedNodeID: String?,
    metrics: [Metric],
    terrain: [Terrain],
    spotlight: Spotlight,
    notices: [Notice],
    routeStops: [RouteStop]
  ) -> String {
    let graphKey =
      graph.fingerprint.isEmpty
      ? "nodes:\(graph.nodes.count)|edges:\(graph.edges.count)|entrypoints:\(graph.entrypointIDs.count)"
      : graph.fingerprint
    let raw = [
      "graph:\(graphKey)",
      "route:\(route.joined(separator: ">"))",
      "routeIndex:\(routeIndex)",
      "selected:\(selectedNodeID ?? "none")",
      "metrics:\(metrics.map { "\($0.id)=\($0.value)" }.joined(separator: ","))",
      "terrain:\(terrain.map { "\($0.id)=\($0.count)" }.joined(separator: ","))",
      "spotlight:\(spotlight.title):\(spotlight.detail):\(spotlight.tone.rawValue)",
      "notices:\(notices.map(\.id).joined(separator: ","))",
      "walk:\(routeStops.map { "\($0.label):\($0.detail):\($0.isCurrent)" }.joined(separator: ","))",
    ].joined(separator: "|")
    return StringUtils.boundedText(raw, limit: 1_200)
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

struct WorldAtlasClipboardPayload: Equatable, Sendable {
  static let textLimit = 2_600

  var text: String

  init(atlas: WorldAtlas, narration: WorldAtlasNarration? = nil) {
    var sections = [
      "Compass World Atlas Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded code-map context. Do not invent files, functions, risks, or outcomes.",
      "- Use the World facts to orient the next explanation, review, or implementation step.",
      "- If a notice says Compass is uncertain, treat it as a lead instead of a confirmed bug.",
      "",
      "Overview:",
      atlas.detail,
      "Progress: \(atlas.progressLabel)",
      "Spotlight: \(atlas.spotlight.title) - \(atlas.spotlight.detail)",
    ]

    if let narrationText = narration?.text.trimmingCharacters(in: .whitespacesAndNewlines),
      !narrationText.isEmpty
    {
      sections.append(contentsOf: ["", "On-device guide:", narrationText])
    }

    sections.append(contentsOf: ["", "Metrics:"])
    sections.append(
      contentsOf:
        atlas.metrics.prefix(8).map {
          "- \($0.label): \($0.value) - \($0.detail)"
        }
    )

    sections.append(contentsOf: ["", "Terrain:"])
    if atlas.terrain.isEmpty {
      sections.append("- No terrain available yet.")
    } else {
      sections.append(
        contentsOf:
          atlas.terrain.prefix(8).map {
            "- \($0.label): \($0.count) - \($0.detail)"
          }
      )
    }

    sections.append(contentsOf: ["", "Notices:"])
    if atlas.notices.isEmpty {
      sections.append("- No current notices.")
    } else {
      sections.append(
        contentsOf:
          atlas.notices.prefix(8).map {
            "- \($0.severity.rawValue): \($0.label) - \($0.detail)"
          }
      )
    }

    sections.append(contentsOf: ["", "Walk:"])
    if atlas.routeStops.isEmpty {
      sections.append("- No guided walk selected.")
    } else {
      sections.append(
        contentsOf:
          atlas.routeStops.prefix(8).map {
            "- \($0.isCurrent ? "Current" : "Stop"): \($0.label) - \($0.detail)"
          }
      )
    }

    text = WorldAtlasClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private enum WorldAtlasClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

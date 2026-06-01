import Foundation

struct WorldTourScript: Equatable, Sendable {
  struct Step: Identifiable, Equatable, Sendable {
    var id: String
    var nodeID: String
    var ordinal: Int
    var title: String
    var subtitle: String
    var narration: String
    var filePath: String?
    var lineLabel: String?
    var kind: WorldNodeKind
    var sceneCue: SceneCue
    var isCurrent: Bool
  }

  enum SceneCue: String, Equatable, Sendable {
    case entrance
    case region
    case chamber
    case structure
    case action
    case decision
    case warning
    case unknown
  }

  var id: String
  var title: String
  var overview: String
  var progressLabel: String
  var steps: [Step]

  var currentStep: Step? {
    steps.first(where: \.isCurrent) ?? steps.first
  }

  init(
    graph: WorldGraph,
    atlas: WorldAtlas,
    route: [String],
    routeIndex: Int,
    selectedNodeID: String?,
    narration: WorldAtlasNarration?
  ) {
    let lookup = graph.nodeByID
    let safeRouteIndex = route.isEmpty ? 0 : min(max(routeIndex, 0), route.count - 1)
    let selectedNode = selectedNodeID.flatMap { lookup[$0] }
    let overview = narration?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let scriptOverview = overview?.isEmpty == false ? overview! : atlas.detail

    self.id = atlas.narrationIdentifier
    self.title = selectedNode.map { "Walking \($0.label)" } ?? "World Walk"
    self.overview = scriptOverview
    self.progressLabel = atlas.progressLabel
    self.steps = route.enumerated().compactMap { index, nodeID in
      guard let node = lookup[nodeID] else { return nil }
      return Step(
        id: "\(index)-\(node.id)",
        nodeID: node.id,
        ordinal: index + 1,
        title: node.label,
        subtitle: Self.subtitle(for: node),
        narration: Self.narration(for: node, index: index, count: route.count),
        filePath: node.location?.filePath,
        lineLabel: node.location?.lineLabel,
        kind: node.kind,
        sceneCue: Self.sceneCue(for: node),
        isCurrent: index == safeRouteIndex
      )
    }
  }

  private static func subtitle(for node: WorldNode) -> String {
    var parts = [label(for: node.kind)]
    if let location = node.location {
      parts.append(location.filePath)
      parts.append(location.lineLabel)
    } else if let language = node.language {
      parts.append(language.displayName)
    }
    return parts.joined(separator: " - ")
  }

  private static func narration(for node: WorldNode, index: Int, count: Int) -> String {
    var sentence =
      "Step \(index + 1) of \(count) visits \(node.label), \(article(for: node.kind)) \(label(for: node.kind).lowercased())."
    if let detail = node.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
      sentence += " \(detail)"
    }
    if let location = node.location {
      sentence += " Source anchor: \(location.filePath) \(location.lineLabel)."
    }
    return StringUtils.boundedText(sentence, limit: 260)
  }

  private static func sceneCue(for node: WorldNode) -> SceneCue {
    switch node.kind {
    case .module: return .region
    case .file: return .chamber
    case .type: return .structure
    case .function: return .action
    case .branch, .loop, .switchCase: return .decision
    case .errorPath: return .warning
    case .unresolvedPassage: return .unknown
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

  private static func article(for kind: WorldNodeKind) -> String {
    switch kind {
    case .function, .errorPath, .unresolvedPassage:
      return "an"
    default:
      return "a"
    }
  }
}

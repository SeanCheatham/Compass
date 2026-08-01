import Foundation

/// # Explore Layer
///
/// `ArchitectureGraph` provides architectural import-graph analysis for the Explore layer.
/// It reads every codemap entry from the store, builds a complete file-to-file ``ImportGraph``,
/// and can produce a plain-English architectural description when generated narration is
/// available.
///
/// ## Role in the Explore layer
///
/// ``ArchitectureGraph`` is available independently for import-graph visualization of the
/// codebase structure, and is also called through ``FileExplainer`` when the UI requests an
/// architecture overview. It complements the commit-diff and Q&A components by surfacing
/// module boundaries and cross-module dependency patterns that are otherwise invisible.
///
/// ## Generated narration boundary
///
/// The ``explain(graph:repoURL:)`` method is gated ``@available(macOS 26.0, *)`` and uses
/// the generated narration shim with a structured architectural analysis prompt. Returns
/// `nil` when narration is unavailable or produces no content. The ``buildGraph()``
/// helper is version-agnostic so callers can inspect the raw graph without availability checks.
///
/// ## Components (Explore layer)
///
/// | Component | Role | Generated narration entry point |
/// |---|---|---|
/// | ``FileExplainer`` | Orchestrator — UI entry point for changed-file lists and per-file explanations | Delegates to ``CommitExplainer`` |
/// | ``CommitExplainer`` | Per-commit diff summarization | ``summarize(diff:)`` |
/// | ``CommitTourGenerator`` | Guided code tours | ``generateTour(commits:repoURL:)`` |
/// | ``RepoQnA`` | Repository-scale Q&A | ``answer(question:repoURL:)`` |
/// | ``ArchitectureGraph`` | Architectural import-graph analysis | ``explain(graph:repoURL:)`` |

/// A directed graph of files and their import relationships, built from
/// all ``CodemapEntry`` records in a ``CodemapStore``.
public struct ImportGraph: Sendable {
  /// Node: a file path relative to the repo root.
  public struct Node: Hashable, Sendable {
    public let path: String
  }

  /// A directed edge from one file to another (i.e. `source` imports `target`).
  public struct Edge: Hashable, Sendable {
    public let source: Node
    public let target: Node
    /// The raw import string that produced this edge. Stored so callers
    /// can distinguish local-path imports from system/module imports.
    public let rawImport: String
  }

  /// Every distinct node in the graph.
  private(set) var nodes: [Node] = []
  /// Every directed edge. There may be multiple edges from the same
  /// source to the same target (different raw import forms).
  private(set) var edges: [Edge] = []
  /// Adjacency list: source -> targets (deduplicated per source).
  private(set) var adjacency: [Node: Set<Node>] = [:]

  /// Nodes that have outgoing edges but no incoming edges — likely entry
  /// points or top-level modules.
  public var likelyEntryPoints: [Node] {
    let sinks = Set(edges.map { $0.target })
    return nodes.filter { node in
      !sinks.contains(node) && edges.contains(where: { $0.source == node })
    }
  }

  /// Nodes sorted by their incoming edge count (descending) — files that
  /// many other files depend on are architecturally central.
  public var mostDependedOn: [Node] {
    var counts: [Node: Int] = [:]
    for edge in edges {
      counts[edge.target, default: 0] += 1
    }
    return
      nodes
      .filter { (counts[$0] ?? 0) > 0 }
      .sorted {
        let lhsCount = counts[$0] ?? 0
        let rhsCount = counts[$1] ?? 0
        if lhsCount != rhsCount { return lhsCount > rhsCount }
        return $0.path < $1.path
      }
  }

  public mutating func addEdge(from source: Node, to target: Node, rawImport: String) {
    addNode(source)
    addNode(target)
    let edge = Edge(source: source, target: target, rawImport: rawImport)
    if !edges.contains(edge) {
      edges.append(edge)
    }
    adjacency[source, default: .init()].insert(target)
  }

  public mutating func addNode(_ node: Node) {
    if !nodes.contains(node) {
      nodes.append(node)
    }
  }

  /// Returns a plain-text representation of the graph grouped by top-level
  /// directory (module cluster), with each cluster's internal edges elided
  /// and inter-cluster edges shown with indentation.
  public func textGraph() -> String {
    // Group nodes by top-level directory (module)
    var clusters: [String: [Node]] = [:]
    for node in nodes {
      let topLevel = String(node.path.split(separator: "/").first ?? "")
      clusters[topLevel, default: .init()].append(node)
    }

    var lines: [String] = []
    lines.append("=== Architecture Graph ===")
    lines.append("")

    for (cluster, clusterNodes) in clusters.sorted(by: { $0.key < $1.key }) {
      lines.append("📁 \(cluster)/")
      let localNodes = clusterNodes.filter { node in
        // Only show cross-cluster edges at the cluster level
        adjacency[node]?.contains { target in
          !clusterNodes.contains(target)
        } ?? false
      }
      for node in localNodes.sorted(by: { $0.path < $1.path }) {
        let outgoing = adjacency[node] ?? []
        let crossCluster = outgoing.filter { !clusterNodes.contains($0) }
        if !crossCluster.isEmpty {
          let deps = crossCluster.map { dep -> String in
            // Show the cluster name for cross-cluster, filename for local
            let depCluster = String(dep.path.split(separator: "/").first ?? "")
            if depCluster == cluster {
              return (dep.path.split(separator: "/").last ?? "").description
            } else {
              return "\(depCluster)/\(dep.path.split(separator: "/").last ?? "")"
            }
          }.joined(separator: ", ")
          lines.append("  └─ \(node.path.split(separator: "/").last ?? "") → \(deps)")
        }
      }
      lines.append("")
    }

    lines.append("=== Key Dependencies ===")
    // Show top nodes by incoming edges (most depended-on)
    for node in mostDependedOn.prefix(5) {
      let count = edges.filter { $0.target == node }.count
      lines.append("  • \(node.path) (\(count) incoming)")
    }

    lines.append("")
    lines.append("=== Entry Points ===")
    for node in likelyEntryPoints.sorted(by: { $0.path < $1.path }) {
      lines.append("  • \(node.path)")
    }

    return lines.joined(separator: "\n")
  }
}

/// Loads all ``CodemapEntry`` records from the store at `codemapDirectory`
/// and builds a complete ``ImportGraph`` from the `imports` field on each entry.
///
/// This function is available on all macOS versions so callers can inspect
/// the raw graph without requiring generated narration.
public func buildGraph(codemapDirectory: URL) -> ImportGraph {
  let store = CodemapStore(directory: codemapDirectory)
  let entries = store.loadAllEntries()

  /// Attempts to resolve a raw import string to a repo-relative file path.
  /// Returns `nil` for system imports, absolute paths, or unresolvable refs.
  func resolve(import raw: String, relativeTo sourcePath: String) -> String? {
    // System imports have no file in the repo
    guard !raw.hasPrefix("/"), !raw.hasPrefix("<") else { return nil }

    // Relative imports: "./Foo" or "../Foo"
    if raw.hasPrefix(".") {
      let sourceDir = sourcePath.split(separator: "/").dropLast().map(String.init).joined(
        separator: "/")
      let combined = [sourceDir, raw].filter { !$0.isEmpty }.joined(separator: "/")
      return normaliseRelativePath(combined)
    }

    // Bare identifier like "Foundation" — system module, not a file
    if !raw.contains("/") {
      return nil
    }

    // Multi-component path like "Compass/Explore/CommitExplainer".
    // Keep the raw path as-is so the graph reflects import relationships at the
    // module/package level even without exact file resolution.
    return raw
  }

  func normaliseRelativePath(_ path: String) -> String {
    var components: [String] = []
    for component in path.split(separator: "/").map(String.init) {
      switch component {
      case "", ".":
        continue
      case "..":
        if !components.isEmpty {
          components.removeLast()
        }
      default:
        components.append(component)
      }
    }
    return components.joined(separator: "/")
  }

  var graph = ImportGraph()

  for entry in entries {
    let source = ImportGraph.Node(path: entry.relativePath)
    graph.addNode(source)
    for imp in entry.imports {
      // Try to resolve the raw import string to a file path in the repo.
      // Handles common patterns:
      //   "Module/Submodule"       → looks for Sources/Module/Submodule, Sources/Module/Submodule.swift
      //   "./Foo" or "../Foo"     → relative import
      //   plain "ModuleName"      → system import, no edge in the graph
      let targetPath = resolve(import: imp.raw, relativeTo: entry.relativePath)
      if let tp = targetPath {
        let target = ImportGraph.Node(path: tp)
        graph.addEdge(from: source, to: target, rawImport: imp.raw)
      }
    }
  }

  return graph
}

/// Architecture overview built from a repository's codemap.
///
/// ## Data flow
///
/// `ArchitectureGraph` reads every ``CodemapEntry`` from the store at the
/// provided repo URL, builds a file-to-file import graph from the `imports`
/// field on each entry, and produces two outputs:
///
/// - ``buildGraph()`` — the raw ``ImportGraph`` available on all macOS versions,
///   so callers can inspect graph structure without model availability.
/// - ``explain(graph:repoURL:)`` — a generated plain-English
///   architectural description of what the modules are, what the key
///   cross-module dependencies are, and what seems architecturally significant.
///
/// ## Generated narration boundary
///
/// `explain` streams through the narration shim with a structured architectural
/// analysis prompt. Output is capped at ~1 000 tokens. Returns `nil` when
/// narration is unavailable or produces no content.
@available(macOS 26.0, *)
public enum ArchitectureGraph {
  /// Generates a plain-English architectural description of the given graph.
  ///
  /// The description covers:
  /// - What the top-level modules / packages are
  /// - What the key cross-module dependencies are
  /// - What seems architecturally significant (central files, likely entry
  ///   points, unusual or problematic dependency patterns)
  ///
  /// Returns `nil` when generated narration is unavailable or produces no
  /// content.
  public static func explain(graph: ImportGraph, repoURL: URL) async -> String? {
    guard FoundationModelsAvailability.isAvailable else { return nil }

    let nodeCount = graph.nodes.count
    let edgeCount = graph.edges.count

    let clusterInfo: String = {
      var clusters: [String: Int] = [:]
      for node in graph.nodes {
        let topLevel = String(node.path.split(separator: "/").first ?? "")
        clusters[topLevel, default: 0] += 1
      }
      return clusters.sorted(by: { $0.key < $1.key })
        .map { "\($0.key): \($0.value) files" }
        .joined(separator: ", ")
    }()

    let topFiles = graph.mostDependedOn.prefix(8)
      .map { "\($0.path)" }
      .joined(separator: ", ")

    let entryPoints = graph.nodes.filter { node in
      !(graph.edges.map { $0.target }).contains(node)
    }
    let entryList = entryPoints.prefix(5).map { $0.path }.joined(separator: ", ")

    let crossClusterEdges = graph.edges.filter { edge in
      let srcCluster = String(edge.source.path.split(separator: "/").first ?? "")
      let dstCluster = String(edge.target.path.split(separator: "/").first ?? "")
      return srcCluster != dstCluster
    }
    let keyDeps = crossClusterEdges.prefix(15)
      .map { "\($0.source.path) → \($0.target.path) (imports: \($0.rawImport))" }
      .joined(separator: "\n")

    let prompt = """
      You are a software architect analyzing the import graph of a codebase.

      Overview:
      - Total files: \(nodeCount)
      - Total import relationships: \(edgeCount)
      - Module clusters: \(clusterInfo)
      - Most depended-on files: \(topFiles)
      - Likely entry points (no incoming edges): \(entryList.isEmpty ? "(none detected)" : entryList)

      Key cross-module dependencies:
      \(keyDeps.isEmpty ? "(none)" : keyDeps)

      Based on the above, provide a clear, navigable plain-English description of:
      1. What the top-level modules / packages are and what they contain
      2. What the key cross-module dependencies are and why they exist
      3. What seems architecturally significant — central infrastructure, likely entry points, any unusual or problematic patterns

      Keep the response to about 5-8 sentences and focus on insight rather than enumeration.
      """

    return await FoundationModelsAvailability._streamText(prompt: prompt)
  }

  // MARK: - SVG Export

  /// Renders the complete import graph as an SVG image.
  ///
  /// Nodes are positioned using a simple ranked layout: the longest path
  /// from any source node (node with no incoming edges) determines each
  /// node's vertical rank; nodes within the same rank are spaced
  /// horizontally in topological order.
  ///
  /// Nodes show the short filename (e.g. `AgentExecutor.swift`); edges
  /// show directed import arrows.
  ///
  /// Returns `nil` when the codemap directory is empty (no files indexed).
  public static func exportSVG(from codemapDirectory: URL) -> String? {
    let graph = buildGraph(codemapDirectory: codemapDirectory)
    return exportSVG(from: graph)
  }

  /// Renders the given import graph as an SVG image.
  /// Returns `nil` when the graph has no nodes.
  public static func exportSVG(from graph: ImportGraph) -> String? {
    guard !graph.nodes.isEmpty else { return nil }

    let nodeWidth: CGFloat = 130
    let nodeHeight: CGFloat = 38
    let rankSpacingY: CGFloat = 90
    let nodeSpacingX: CGFloat = 30
    let padding: CGFloat = 40

    // Compute ranks via longest path from source nodes (no incoming edges).
    var ranks: [ImportGraph.Node: Int] = [:]

    let sourceNodes = graph.nodes.filter { node in
      !graph.edges.contains { $0.target == node }
    }

    if sourceNodes.isEmpty {
      // Cycle or fully-connected graph — treat all as rank 0.
      for node in graph.nodes { ranks[node] = 0 }
    } else {
      for source in sourceNodes {
        var visited: [ImportGraph.Node: Int] = [:]
        var queue: [(ImportGraph.Node, Int)] = [(source, 0)]
        while !queue.isEmpty {
          let (node, dist) = queue.removeFirst()
          if let existing = visited[node], existing >= dist { continue }
          visited[node] = dist
          if let existingRank = ranks[node] {
            ranks[node] = max(existingRank, dist)
          } else {
            ranks[node] = dist
          }
          if let outgoing = graph.adjacency[node] {
            for target in outgoing {
              if visited[target] == nil || visited[target]! < dist + 1 {
                queue.append((target, dist + 1))
              }
            }
          }
        }
      }
      // Nodes not reached from any source get rank 0.
      for node in graph.nodes where ranks[node] == nil {
        ranks[node] = 0
      }
    }

    let maxRank = ranks.values.max() ?? 0

    // Group nodes by rank, sort within rank by path for determinism.
    var rankGroups: [[ImportGraph.Node]] = Array(repeating: [], count: maxRank + 1)
    for (node, rank) in ranks {
      rankGroups[rank].append(node)
    }
    for i in 0..<rankGroups.count {
      rankGroups[i].sort { $0.path < $1.path }
    }

    // Position nodes.
    var positions: [ImportGraph.Node: CGPoint] = [:]
    for (rankIdx, nodes) in rankGroups.enumerated() {
      let y = padding + CGFloat(rankIdx) * (nodeHeight + rankSpacingY)
      let totalWidth =
        CGFloat(nodes.count) * nodeWidth
        + CGFloat(max(0, nodes.count - 1)) * nodeSpacingX
      let startX = padding + (max(0, 800 - totalWidth) / 2)
      for (i, node) in nodes.enumerated() {
        let x = startX + CGFloat(i) * (nodeWidth + nodeSpacingX)
        positions[node] = CGPoint(x: x, y: y)
      }
    }

    // SVG bounding box.
    let contentW = positions.values.map(\.x).max() ?? 0
    let svgW = max(800, contentW + padding + nodeWidth)
    let svgH = max(600, CGFloat(maxRank + 1) * (nodeHeight + rankSpacingY) + padding + nodeHeight)

    var svg = """
      <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(svgW))" height="\(Int(svgH))" style="background:#1e1e1e">
        <style>
          .node-rect { fill: #2d2d3d; stroke: #6e6e8a; stroke-width: 1; }
          .node-label { fill: #d0d0e0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 11px; text-anchor: middle; dominant-baseline: middle; }
          .cluster-label { fill: #8888aa; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 10px; text-anchor: start; dominant-baseline: middle; }
          .edge { stroke: #5a5a7e; stroke-width: 1.5; fill: none; marker-end: url(#arrowhead); }
        </style>
        <defs>
          <marker id="arrowhead" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
            <polygon points="0 0, 8 3, 0 6" fill="#5a5a7e"/>
          </marker>
        </defs>

      """

    // Edges drawn behind nodes.
    for edge in graph.edges {
      guard let src = positions[edge.source], let dst = positions[edge.target] else { continue }
      let sx = src.x + nodeWidth / 2
      let sy = src.y + nodeHeight / 2
      let dx = dst.x + nodeWidth / 2
      let dy = dst.y + nodeHeight / 2
      let mid = (sy + dy) / 2
      let d = "M \(sx) \(sy) C \(sx) \(mid), \(dx) \(mid), \(dx) \(dy)"
      svg += "\n  <path d=\"\(d)\" class=\"edge\"/>"
    }

    // Nodes.
    for (node, pos) in positions {
      let label = (node.path as NSString).lastPathComponent
      let escapedLabel = xmlEscaped(label)
      svg += """

          <g>
            <rect x="\(pos.x)" y="\(pos.y)" width="\(nodeWidth)" height="\(nodeHeight)" rx="5" class="node-rect" data-label="\(escapedLabel)"/>
            <text x="\(pos.x + nodeWidth / 2)" y="\(pos.y + nodeHeight / 2)" class="node-label">\(escapedLabel)</text>
          </g>
        """
    }

    svg += "\n</svg>"
    return svg
  }

  private static func xmlEscaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}

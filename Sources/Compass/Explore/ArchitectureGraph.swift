import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// A directed graph of files and their import relationships, built from
/// all ``CodemapEntry`` records in a ``CodemapStore``.
struct ImportGraph: Sendable {
  /// Node: a file path relative to the repo root.
  struct Node: Hashable, Sendable {
    let path: String
  }

  /// A directed edge from one file to another (i.e. `source` imports `target`).
  struct Edge: Hashable, Sendable {
    let source: Node
    let target: Node
    /// The raw import string that produced this edge. Stored so callers
    /// can distinguish local-path imports from system/module imports.
    let rawImport: String
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
  var likelyEntryPoints: [Node] {
    let sinks = Set(edges.map { $0.target })
    return nodes.filter { node in
      !sinks.contains(node) && edges.contains(where: { $0.source == node })
    }
  }

  /// Nodes sorted by their incoming edge count (descending) — files that
  /// many other files depend on are architecturally central.
  var mostDependedOn: [Node] {
    var counts: [Node: Int] = [:]
    for edge in edges {
      counts[edge.target, default: 0] += 1
    }
    return nodes.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
  }

  mutating func addEdge(from source: Node, to target: Node, rawImport: String) {
    addNode(source)
    addNode(target)
    let edge = Edge(source: source, target: target, rawImport: rawImport)
    if !edges.contains(edge) {
      edges.append(edge)
    }
    adjacency[source, default: .init()].insert(target)
  }

  mutating func addNode(_ node: Node) {
    if !nodes.contains(node) {
      nodes.append(node)
    }
  }

  /// Returns a plain-text representation of the graph grouped by top-level
  /// directory (module cluster), with each cluster's internal edges elided
  /// and inter-cluster edges shown with indentation.
  func textGraph() -> String {
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
    let entryPoints = nodes.filter { node in
      !(edges.map { $0.target }).contains(node)
    }
    for node in entryPoints.sorted(by: { $0.path < $1.path }) {
      lines.append("  • \(node.path)")
    }

    return lines.joined(separator: "\n")
  }
}

/// Loads all ``CodemapEntry`` records from the store at `codemapDirectory`
/// and builds a complete ``ImportGraph`` from the `imports` field on each entry.
///
/// This function is available on all macOS versions so callers can inspect
/// the raw graph without requiring Foundation Models.
func buildGraph(codemapDirectory: URL) -> ImportGraph {
  let store = CodemapStore(directory: codemapDirectory)
  let entries = store.loadAllEntries()

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

/// Attempts to resolve a raw import string to a repo-relative file path.
/// Returns `nil` for system imports, absolute paths, or unresolvable refs.
private func resolve(import raw: String, relativeTo sourcePath: String) -> String? {
  // System imports have no file in the repo
  guard !raw.hasPrefix("/"), !raw.hasPrefix("<") else { return nil }

  // Relative imports: "./Foo" or "../Foo"
  if raw.hasPrefix(".") {
    let sourceDir = sourcePath.split(separator: "/").dropLast().map(String.init).joined(separator: "/")
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

private func normaliseRelativePath(_ path: String) -> String {
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
/// - ``explain(graph:repoURL:)`` — a Foundation-Models-powered plain-English
///   architectural description of what the modules are, what the key
///   cross-module dependencies are, and what seems architecturally significant.
///
/// ## Foundation Models boundary
///
/// `explain` streams to Foundation Models with a structured architectural
/// analysis prompt. Output is capped at ~1 000 tokens. Returns `nil` when
/// Foundation Models is unavailable or produces no content.
@available(macOS 26.0, *)
enum ArchitectureGraph {
  /// Generates a plain-English architectural description of the given graph.
  ///
  /// The description covers:
  /// - What the top-level modules / packages are
  /// - What the key cross-module dependencies are
  /// - What seems architecturally significant (central files, likely entry
  ///   points, unusual or problematic dependency patterns)
  ///
  /// Returns `nil` when Foundation Models is unavailable or produces no
  /// content.
  static func explain(graph: ImportGraph, repoURL: URL, commits: [SessionCommit]) async -> String? {
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
}

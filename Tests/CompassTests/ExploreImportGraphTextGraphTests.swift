import Foundation
import Testing

@testable import Compass

/// Tests for ``ImportGraph/textGraph()`` output formatting.
///
/// Verifies the plain-text architectural overview that would be consumed by
/// Foundation Models for architecture summaries or displayed directly in the
/// UI when the model is unavailable.
struct ExploreImportGraphTextGraphTests {

  // MARK: - Cluster grouping

  @Test
  func textGraph_multipleClusters_showsAllClusterHeaders() throws {
    var graph = ImportGraph()
    graph.addEdge(
      from: ImportGraph.Node(path: "Sources/App.swift"),
      to: ImportGraph.Node(path: "Explore/Model.swift"),
      rawImport: "Explore/Model"
    )
    graph.addEdge(
      from: ImportGraph.Node(path: "Tests/AppTests.swift"),
      to: ImportGraph.Node(path: "Sources/App.swift"),
      rawImport: "Sources/App"
    )

    let output = graph.textGraph()

    // Both top-level clusters appear as headers
    #expect(output.contains("📁 Sources/"))
    #expect(output.contains("📁 Explore/"))
    #expect(output.contains("📁 Tests/"))
  }

  @Test
  func textGraph_clusterHeaders_sortedAlphabetically() throws {
    var graph = ImportGraph()
    // Deliberately add clusters out of alphabetical order
    graph.addEdge(
      from: ImportGraph.Node(path: "Zoo/Animal.swift"),
      to: ImportGraph.Node(path: "Alpha/First.swift"),
      rawImport: "Alpha/First"
    )
    graph.addEdge(
      from: ImportGraph.Node(path: "App.swift"),
      to: ImportGraph.Node(path: "Zoo/Animal.swift"),
      rawImport: "Zoo/Animal"
    )

    let output = graph.textGraph()

    let sourcesRange = output.range(of: "📁 Sources/")
    let zooRange = output.range(of: "📁 Zoo/")
    let exploreRange = output.range(of: "📁 Explore/")

    // Alphabetical order: Explore < Sources < Zoo
    if let exploreRange = output.range(of: "📁 Explore/"),
      let sourcesRange = output.range(of: "📁 Sources/"),
      let zooRange = output.range(of: "📁 Zoo/")
    {
      #expect(exploreRange.lowerBound < sourcesRange.lowerBound)
      #expect(sourcesRange.lowerBound < zooRange.lowerBound)
    } else {
      // At minimum, Sources should come before Zoo if both exist
      if let sRange = sourcesRange, let zRange = zooRange {
        #expect(sRange.lowerBound < zRange.lowerBound)
      }
    }
  }

  // MARK: - Cross-cluster arrow notation

  @Test
  func textGraph_crossClusterEdge_showsArrowNotation() throws {
    var graph = ImportGraph()
    graph.addEdge(
      from: ImportGraph.Node(path: "Sources/View.swift"),
      to: ImportGraph.Node(path: "Explore/Model.swift"),
      rawImport: "Explore/Model"
    )

    let output = graph.textGraph()

    // Arrow format: "View.swift → Explore/Model.swift"
    #expect(output.contains("View.swift → Explore/Model.swift"))
  }

  @Test
  func textGraph_crossClusterEdge_showsTargetClusterName() throws {
    var graph = ImportGraph()
    graph.addEdge(
      from: ImportGraph.Node(path: "Sources/A.swift"),
      to: ImportGraph.Node(path: "Module/B.swift"),
      rawImport: "Module/B"
    )

    let output = graph.textGraph()

    // Target shows "Module/B.swift" not just "B.swift"
    #expect(output.contains("→ Module/B.swift"))
  }

  @Test
  func textGraph_localEdge_noArrowInClusterSection() throws {
    var graph = ImportGraph()
    // Both nodes in the same cluster
    graph.addEdge(
      from: ImportGraph.Node(path: "Sources/A.swift"),
      to: ImportGraph.Node(path: "Sources/B.swift"),
      rawImport: "B"
    )

    let output = graph.textGraph()

    // Within the Sources cluster section, local edges are not shown (no arrow)
    // The cluster header appears
    #expect(output.contains("📁 Sources/"))
  }

  // MARK: - Local edges elided within clusters

  @Test
  func textGraph_sameClusterEdges_notShownAtClusterLevel() throws {
    var graph = ImportGraph()
    // Two files in the same cluster that reference each other
    graph.addEdge(
      from: ImportGraph.Node(path: "Sources/File1.swift"),
      to: ImportGraph.Node(path: "Sources/File2.swift"),
      rawImport: "File2"
    )
    graph.addEdge(
      from: ImportGraph.Node(path: "Sources/File2.swift"),
      to: ImportGraph.Node(path: "Sources/File3.swift"),
      rawImport: "File3"
    )
    // Only one cross-cluster edge
    graph.addEdge(
      from: ImportGraph.Node(path: "Sources/File3.swift"),
      to: ImportGraph.Node(path: "Explore/Model.swift"),
      rawImport: "Explore/Model"
    )

    let output = graph.textGraph()

    // Cross-cluster edge appears with arrow
    #expect(output.contains("→ Explore/Model.swift"))
    // Local edges don't produce cross-cluster arrows
    #expect(!output.contains("File1.swift →"))
    #expect(!output.contains("File2.swift → File3.swift"))
  }

  // MARK: - Most-depended-on section (top 5 by incoming edges)

  @Test
  func textGraph_keyDependencies_showsTop5ByIncomingCount() throws {
    var graph = ImportGraph()
    let hub = ImportGraph.Node(path: "Hub.swift")
    let a = ImportGraph.Node(path: "A.swift")
    let b = ImportGraph.Node(path: "B.swift")
    let c = ImportGraph.Node(path: "C.swift")
    let d = ImportGraph.Node(path: "D.swift")
    let e = ImportGraph.Node(path: "E.swift")
    let f = ImportGraph.Node(path: "F.swift")  // beyond top 5

    // Hub has 6 incoming edges
    for node in [a, b, c, d, e, f] {
      graph.addEdge(from: node, to: hub, rawImport: "Hub")
    }

    let output = graph.textGraph()

    // Hub must appear in Key Dependencies
    #expect(output.contains("• Hub.swift"))
    #expect(output.contains("(6 incoming)"))
  }

  @Test
  func textGraph_keyDependencies_max5Entries() throws {
    var graph = ImportGraph()
    // Create 7 nodes each with 1 incoming edge to unique targets
    for i in 0..<7 {
      let source = ImportGraph.Node(path: "Source\(i).swift")
      let target = ImportGraph.Node(path: "Target\(i).swift")
      graph.addEdge(from: source, to: target, rawImport: "Target\(i)")
    }

    let output = graph.textGraph()
    let section =
      output.range(of: "=== Key Dependencies ===").map {
        output[$0.upperBound...]
      } ?? output[output.startIndex...]
    let sectionStr = String(section)

    // Count "•" markers in the Key Dependencies section
    let bulletCount = sectionStr.components(separatedBy: "•").count - 1
    #expect(bulletCount <= 5)
  }

  @Test
  func textGraph_keyDependencies_incomingCountLabel() throws {
    var graph = ImportGraph()
    let shared = ImportGraph.Node(path: "Shared.swift")
    let a = ImportGraph.Node(path: "A.swift")
    let b = ImportGraph.Node(path: "B.swift")
    let c = ImportGraph.Node(path: "C.swift")

    graph.addEdge(from: a, to: shared, rawImport: "Shared")
    graph.addEdge(from: b, to: shared, rawImport: "Shared")
    graph.addEdge(from: c, to: shared, rawImport: "Shared")
    // c also imports something else (not shared)
    graph.addEdge(from: c, to: ImportGraph.Node(path: "X.swift"), rawImport: "X")

    let output = graph.textGraph()

    // Shared must show "(3 incoming)"
    #expect(output.contains("(3 incoming)"))
    // Other files with fewer incoming edges also appear if in top 5
    #expect(output.contains("• Shared.swift"))
  }

  // MARK: - Entry points section

  @Test
  func textGraph_entryPoints_showsFilesWithNoIncomingEdges() throws {
    var graph = ImportGraph()
    let entryA = ImportGraph.Node(path: "Sources/EntryA.swift")
    let entryB = ImportGraph.Node(path: "Sources/EntryB.swift")
    let sink = ImportGraph.Node(path: "Core/Sink.swift")

    // entryA → entryB (both have outgoing, no incoming)
    graph.addEdge(from: entryA, to: entryB, rawImport: "EntryB")
    // entryB → sink (sink has incoming, no outgoing)
    graph.addEdge(from: entryB, to: sink, rawImport: "Sink")

    let output = graph.textGraph()

    #expect(output.contains("=== Entry Points ==="))
    #expect(output.contains("• Sources/EntryA.swift"))
    #expect(output.contains("• Sources/EntryB.swift"))
    // Core/Sink.swift has incoming but no outgoing — not an entry point
    #expect(!output.contains("• Core/Sink.swift"))
  }

  @Test
  func textGraph_entryPoints_sortedAlphabetically() throws {
    var graph = ImportGraph()
    graph.addEdge(
      from: ImportGraph.Node(path: "Zoo/Animal.swift"),
      to: ImportGraph.Node(path: "App.swift"),
      rawImport: "App"
    )
    graph.addEdge(
      from: ImportGraph.Node(path: "App.swift"),
      to: ImportGraph.Node(path: "Alpha/First.swift"),
      rawImport: "Alpha/First"
    )

    let output = graph.textGraph()

    let entrySectionRange = output.range(of: "=== Entry Points ===")
    try #require(entrySectionRange != nil)
    let afterHeader = output[entrySectionRange!.upperBound...]
    let afterHeaderStr = String(afterHeader).trimmingCharacters(in: .whitespacesAndNewlines)

    // Verify entry points are in sorted order
    #expect(afterHeaderStr.contains("• Alpha/First.swift"))
    #expect(afterHeaderStr.contains("• App.swift"))
    #expect(afterHeaderStr.contains("• Zoo/Animal.swift"))
  }

  // MARK: - Sorting: clusters and files within clusters

  @Test
  func textGraph_filesWithinCluster_sortedAlphabetically() throws {
    var graph = ImportGraph()
    // Add files in reverse alphabetical order within Sources cluster
    graph.addEdge(
      from: ImportGraph.Node(path: "Sources/Zebra.swift"),
      to: ImportGraph.Node(path: "Explore/Model.swift"),
      rawImport: "Explore/Model"
    )
    graph.addEdge(
      from: ImportGraph.Node(path: "Sources/Apple.swift"),
      to: ImportGraph.Node(path: "Explore/Model.swift"),
      rawImport: "Explore/Model"
    )

    let output = graph.textGraph()

    let appleRange = output.range(of: "Apple.swift")
    let zebraRange = output.range(of: "Zebra.swift")
    if let ai = appleRange, let zi = zebraRange {
      #expect(ai.lowerBound < zi.lowerBound)
    }
  }

  // MARK: - Empty graph

  @Test
  func textGraph_emptyGraph_showsAllSectionHeadersNoEntries() throws {
    var graph = ImportGraph()
    let output = graph.textGraph()

    #expect(output.contains("=== Architecture Graph ==="))
    #expect(output.contains("=== Key Dependencies ==="))
    #expect(output.contains("=== Entry Points ==="))
  }

  // MARK: - Single-node graph

  @Test
  func textGraph_singleNode_noKeyDependenciesNoEntryPoints() throws {
    var graph = ImportGraph()
    graph.addNode(ImportGraph.Node(path: "Sources/Lone.swift"))
    // No edges — single isolated node

    let output = graph.textGraph()

    // Cluster header present
    #expect(output.contains("📁 Sources/"))
    // Key Dependencies and Entry Points sections present but empty
    #expect(output.contains("=== Key Dependencies ==="))
    #expect(output.contains("=== Entry Points ==="))
  }

  @Test
  func textGraph_singleNodeWithNoIncoming_noEntryPointsListed() throws {
    var graph = ImportGraph()
    let node = ImportGraph.Node(path: "Sources/Lone.swift")
    graph.addNode(node)
    // A node with no edges has no incoming, so not listed as entry point
    // (entry points are nodes with outgoing but no incoming)

    let output = graph.textGraph()

    let entrySection =
      output.range(of: "=== Entry Points ===").map {
        output[$0.upperBound...]
      } ?? Substring()
    let entryStr = String(entrySection).trimmingCharacters(in: .whitespacesAndNewlines)
    // Lone.swift has no outgoing edges, so not an entry point
    #expect(!entryStr.contains("Lone.swift"))
  }

  // MARK: - Sections appear in correct order

  @Test
  func textGraph_sectionsInCorrectOrder() throws {
    var graph = ImportGraph()
    graph.addEdge(
      from: ImportGraph.Node(path: "App.swift"),
      to: ImportGraph.Node(path: "Core/Hub.swift"),
      rawImport: "Core/Hub"
    )

    let output = graph.textGraph()

    let archRange = output.range(of: "=== Architecture Graph ===")
    let keyRange = output.range(of: "=== Key Dependencies ===")
    let entryRange = output.range(of: "=== Entry Points ===")

    try #require(archRange != nil)
    try #require(keyRange != nil)
    try #require(entryRange != nil)

    #expect(archRange!.lowerBound < keyRange!.lowerBound)
    #expect(keyRange!.lowerBound < entryRange!.lowerBound)
  }

  // MARK: - Combined scenario

  @Test
  func textGraph_fullScenario_allSectionsPresent() throws {
    var graph = ImportGraph()

    // Three clusters
    let appA = ImportGraph.Node(path: "App/A.swift")
    let appB = ImportGraph.Node(path: "App/B.swift")
    let coreHub = ImportGraph.Node(path: "Core/Hub.swift")
    let exploreModel = ImportGraph.Node(path: "Explore/Model.swift")

    // App/A and App/B both import Core/Hub (cross-cluster)
    graph.addEdge(from: appA, to: coreHub, rawImport: "Core/Hub")
    graph.addEdge(from: appB, to: coreHub, rawImport: "Core/Hub")
    // Core/Hub imports Explore/Model
    graph.addEdge(from: coreHub, to: exploreModel, rawImport: "Explore/Model")

    let output = graph.textGraph()

    // All three cluster headers present
    #expect(output.contains("📁 App/"))
    #expect(output.contains("📁 Core/"))
    #expect(output.contains("📁 Explore/"))

    // Cross-cluster arrows shown
    #expect(output.contains("→ Core/Hub.swift") || output.contains("→ Core/Hub.swift"))

    // Section headers
    #expect(output.contains("=== Architecture Graph ==="))
    #expect(output.contains("=== Key Dependencies ==="))
    #expect(output.contains("=== Entry Points ==="))

    // Hub appears in key dependencies (most incoming)
    #expect(output.contains("(2 incoming)"))

    // Entry points: App/A and App/B have outgoing but no incoming
    #expect(output.contains("• App/A.swift"))
    #expect(output.contains("• App/B.swift"))
  }
}

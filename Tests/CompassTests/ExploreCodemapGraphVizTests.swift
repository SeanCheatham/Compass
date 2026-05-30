import Foundation
import Testing

@testable import Compass

struct ExploreCodemapGraphVizTests {

  // MARK: - writeOverviewSVG() guard

  @Test
  func writeOverviewSVG_emptyCodemap_returnsNil() throws {
    let dir = try makeTempDir()
    let store = CodemapStore(directory: dir, prettyPrint: true)
    // Store has no entries — buildGraph returns an empty ImportGraph
    _ = store

    let viz = CodemapGraphViz(repoURL: dir, codemapDirectory: dir)
    let result = try viz.writeOverviewSVG()

    #expect(result == nil)
  }

  // MARK: - writeOverviewSVG() single-file

  @Test
  func writeOverviewSVG_singleFile_writesSVGWithNodeAndLabel() throws {
    let repoDir = try makeTempDir()
    let codemapDir = repoDir.appendingPathComponent(".compass/codemap", isDirectory: true)
    try FileManager.default.createDirectory(at: codemapDir, withIntermediateDirectories: true)

    let store = CodemapStore(directory: codemapDir, prettyPrint: true)
    let entry = CodemapEntry(
      relativePath: "Sources/App.swift",
      language: .swift,
      contentHash: "testhash",
      sizeBytes: 0,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entry)

    // Confirm buildGraph can read the store
    let graph = buildGraph(codemapDirectory: codemapDir)
    #expect(!graph.nodes.isEmpty)

    let viz = CodemapGraphViz(repoURL: repoDir, codemapDirectory: codemapDir)
    let result = try viz.writeOverviewSVG()

    try #require(result != nil)
    let svgContents = try String(contentsOf: result!, encoding: .utf8)
    #expect(svgContents.contains("App.swift"))
    #expect(svgContents.contains("<rect"))
  }

  // MARK: - writeOverviewSVG() overwrite

  @Test
  func writeOverviewSVG_twiceOverwritesWithoutError() throws {
    let repoDir = try makeTempDir()
    let codemapDir = repoDir.appendingPathComponent(".compass/codemap", isDirectory: true)
    try FileManager.default.createDirectory(at: codemapDir, withIntermediateDirectories: true)

    let store = CodemapStore(directory: codemapDir, prettyPrint: true)
    let entry = CodemapEntry(
      relativePath: "Sources/App.swift",
      language: .swift,
      contentHash: "testhash",
      sizeBytes: 0,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entry)

    let viz = CodemapGraphViz(repoURL: repoDir, codemapDirectory: codemapDir)

    // First call
    let first = try viz.writeOverviewSVG()
    try #require(first != nil)

    // Second call — should overwrite without throwing
    let second = try viz.writeOverviewSVG()
    try #require(second != nil)

    // Both point to the same file
    #expect(first == second)
  }

  // MARK: - writeOverviewSVG() output filename and location

  @Test
  func writeOverviewSVG_writesTocodemapOverviewSVG_inRepoRoot() throws {
    let repoDir = try makeTempDir()
    let codemapDir = repoDir.appendingPathComponent(".compass/codemap", isDirectory: true)
    try FileManager.default.createDirectory(at: codemapDir, withIntermediateDirectories: true)

    let store = CodemapStore(directory: codemapDir, prettyPrint: true)
    let entry = CodemapEntry(
      relativePath: "Sources/App.swift",
      language: .swift,
      contentHash: "testhash",
      sizeBytes: 0,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entry)

    let viz = CodemapGraphViz(repoURL: repoDir, codemapDirectory: codemapDir)
    let result = try viz.writeOverviewSVG()

    try #require(result != nil)

    // File is named "codemap-overview.svg"
    #expect(result!.lastPathComponent == "codemap-overview.svg")
    // File lives directly in the repo root, not in .compass/codemap/
    #expect(result!.deletingLastPathComponent() == repoDir)
    // File is actually on disk
    let exists = FileManager.default.fileExists(atPath: result!.path)
    #expect(exists)
  }
}

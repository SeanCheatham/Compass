import Foundation
import Testing

@testable import Compass

struct ExploreArchitectureGraphSVGExportTests {

  // MARK: - exportSVG(from:) guard

  @Test
  func exportSVG_emptyGraph_returnsNil() {
    let graph = ImportGraph()
    let result = ArchitectureGraph.exportSVG(from: graph)
    #expect(result == nil)
  }

  // MARK: - exportSVG(from:codemapDirectory:)

  @Test
  func exportSVG_singleNode_rendersLabelAndNodeRect() throws {
    let dir = try makeTempDir()
    let store = CodemapStore(directory: dir, prettyPrint: true)

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

    let graph = buildGraph(codemapDirectory: dir)
    let svg = ArchitectureGraph.exportSVG(from: graph)

    try #require(svg != nil)
    #expect(svg!.contains("App.swift"))
    #expect(svg!.contains("<rect"))
  }

  @Test
  func exportSVG_twoNodesWithEdge_drawnWithArrowMarker() throws {
    let dir = try makeTempDir()
    let store = CodemapStore(directory: dir, prettyPrint: true)

    let entryA = CodemapEntry(
      relativePath: "A.swift",
      language: .swift,
      contentHash: "hasha",
      sizeBytes: 0,
      symbols: [],
      imports: [CodemapImport(raw: "B", line: 1)],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entryA)

    let entryB = CodemapEntry(
      relativePath: "B.swift",
      language: .swift,
      contentHash: "hashb",
      sizeBytes: 0,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entryB)

    let graph = buildGraph(codemapDirectory: dir)
    let svg = ArchitectureGraph.exportSVG(from: graph)

    try #require(svg != nil)
    #expect(svg!.contains("d=\""))
    #expect(svg!.contains("marker-end"))
    #expect(svg!.contains("A.swift"))
    #expect(svg!.contains("B.swift"))
  }

  @Test
  func exportSVG_multipleRanks_stackedVertically() throws {
    let dir = try makeTempDir()
    let store = CodemapStore(directory: dir, prettyPrint: true)

    for (path, imports) in [
      ("source.swift", [CodemapImport(raw: "./middle.swift", line: 1)] as [CodemapImport]),
      ("middle.swift", [CodemapImport(raw: "./sink.swift", line: 1)]),
      ("sink.swift", [] as [CodemapImport]),
    ] {
      let entry = CodemapEntry(
        relativePath: path,
        language: .swift,
        contentHash: "hash",
        sizeBytes: 0,
        symbols: [],
        imports: imports,
        summary: nil,
        summaryModel: nil,
        summaryContentHash: nil,
        isGenerated: false
      )
      try store.saveEntry(entry)
    }

    let graph = buildGraph(codemapDirectory: dir)
    let svg = ArchitectureGraph.exportSVG(from: graph)

    try #require(svg != nil)
    let rectPattern = #"<rect[^>]*x="([^"]+)"[^>]*y="([^"]+)"[^>]*>"#
    let nsString = svg! as NSString
    let range = NSRange(location: 0, length: nsString.length)
    let regex = try NSRegularExpression(pattern: rectPattern, options: [])
    let matches = regex.matches(in: svg!, options: [], range: range)

    var sourceY: CGFloat?
    var sinkY: CGFloat?
    for match in matches {
      let yRange = match.range(at: 2)
      let yStr = nsString.substring(with: yRange)
      let yVal = CGFloat(Double(yStr) ?? 0)
      let rectText = nsString.substring(with: match.range)
      if rectText.contains("source.swift") { sourceY = yVal }
      if rectText.contains("sink.swift") { sinkY = yVal }
    }

    try #require(sourceY != nil)
    try #require(sinkY != nil)
    #expect(sinkY! > sourceY!)
  }

  @Test
  func exportSVG_cycleAllNodesRank0() throws {
    let dir = try makeTempDir()
    let store = CodemapStore(directory: dir, prettyPrint: true)

    let entryA = CodemapEntry(
      relativePath: "A.swift",
      language: .swift,
      contentHash: "hasha",
      sizeBytes: 0,
      symbols: [],
      imports: [CodemapImport(raw: "./B.swift", line: 1)],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entryA)

    let entryB = CodemapEntry(
      relativePath: "B.swift",
      language: .swift,
      contentHash: "hashb",
      sizeBytes: 0,
      symbols: [],
      imports: [CodemapImport(raw: "./A.swift", line: 1)],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entryB)

    let graph = buildGraph(codemapDirectory: dir)
    let svg = ArchitectureGraph.exportSVG(from: graph)

    try #require(svg != nil)
    let rectPattern = #"<rect[^>]*x="([^"]+)"[^>]*y="([^"]+)"[^>]*>"#
    let nsString = svg! as NSString
    let range = NSRange(location: 0, length: nsString.length)
    let regex = try NSRegularExpression(pattern: rectPattern, options: [])
    let matches = regex.matches(in: svg!, options: [], range: range)

    var aY: CGFloat?
    var bY: CGFloat?
    for match in matches {
      let yRange = match.range(at: 2)
      let yStr = nsString.substring(with: yRange)
      let yVal = CGFloat(Double(yStr) ?? 0)
      let rectText = nsString.substring(with: match.range)
      if rectText.contains("A.swift") { aY = yVal }
      if rectText.contains("B.swift") { bY = yVal }
    }

    try #require(aY != nil)
    try #require(bY != nil)
    #expect(aY == bY)
  }

  @Test
  func exportSVG_labelIsShortFilename() throws {
    let dir = try makeTempDir()
    let store = CodemapStore(directory: dir, prettyPrint: true)

    let entry = CodemapEntry(
      relativePath: "Sources/App/ViewModels/Foo.swift",
      language: .swift,
      contentHash: "hash",
      sizeBytes: 0,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entry)

    let graph = buildGraph(codemapDirectory: dir)
    let svg = ArchitectureGraph.exportSVG(from: graph)

    try #require(svg != nil)
    #expect(svg!.contains(">Foo.swift<"))
    #expect(!svg!.contains("Sources/App/ViewModels/Foo.swift"))
  }
}

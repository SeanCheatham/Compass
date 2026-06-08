import Foundation

struct CargoGraphSnapshot: Codable, Equatable, Sendable {
  var contentFingerprint: String
  var generatedAt: Date
  var graph: CargoGraphData
}

struct CargoGraphStore {
  static let filename = "cargo-graph.json"

  func url(for workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: Self.filename)
  }

  func load(from workspace: CompassWorkspace) -> CargoGraphSnapshot? {
    let url = url(for: workspace)
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(CargoGraphSnapshot.self, from: data)
  }

  func save(_ snapshot: CargoGraphSnapshot, workspace: CompassWorkspace) throws {
    try FileManager.default.createDirectory(
      at: workspace.compassURL, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(snapshot)
    try data.write(to: url(for: workspace), options: .atomic)
  }

  func makeSnapshot(
    graph: CargoGraphData,
    workspace: CompassWorkspace,
    generatedAt: Date = Date()
  ) -> CargoGraphSnapshot {
    CargoGraphSnapshot(
      contentFingerprint: Self.contentFingerprint(graph: graph, repoURL: workspace.repoURL),
      generatedAt: generatedAt,
      graph: graph
    )
  }

  static func contentFingerprint(graph: CargoGraphData, repoURL: URL) -> String {
    var data = Data()
    let paths = Set(
      [graph.workspaceRoot] + graph.members.map(\.manifestPath) + ["Cargo.lock"]
    )
    for path in paths.sorted() {
      let url = repoURL.appending(path: path)
      if let contents = try? Data(contentsOf: url) {
        data.append(Data(path.utf8))
        data.append(0)
        data.append(contents)
        data.append(0)
      }
    }
    return CodemapHash.sha256Hex(data)
  }
}

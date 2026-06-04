import Foundation

struct SchemaContractsStore {
  static let filename = "schema-contracts.json"

  func url(for workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: Self.filename)
  }

  func load(from workspace: CompassWorkspace) -> SchemaContractsData? {
    let url = url(for: workspace)
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    return try? JSONDecoder().decode(SchemaContractsData.self, from: data)
  }

  func save(_ data: SchemaContractsData, workspace: CompassWorkspace) throws {
    try FileManager.default.createDirectory(at: workspace.compassURL, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(data).write(to: url(for: workspace), options: .atomic)
  }
}

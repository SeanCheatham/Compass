import Foundation

struct RustCodemapEnricher {
  static let moduleIndexFilename = "rust-module-index.json"
  static let traitIndexFilename = "rust-trait-index.json"

  static func moduleIndexURL(workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: moduleIndexFilename)
  }

  static func traitIndexURL(workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: traitIndexFilename)
  }

  static func loadModuleIndex(workspace: CompassWorkspace) -> RustModuleIndex? {
    decode(RustModuleIndex.self, from: moduleIndexURL(workspace: workspace))
  }

  static func loadTraitIndex(workspace: CompassWorkspace) -> RustTraitIndex? {
    decode(RustTraitIndex.self, from: traitIndexURL(workspace: workspace))
  }

  static func save(_ index: RustIndexData, workspace: CompassWorkspace) throws {
    try FileManager.default.createDirectory(at: workspace.compassURL, withIntermediateDirectories: true)
    try encode(index.moduleIndex, to: moduleIndexURL(workspace: workspace))
    try encode(index.traitIndex, to: traitIndexURL(workspace: workspace))
  }

  static func workspace(from context: AgentToolContext) -> CompassWorkspace {
    CompassWorkspace(
      repoURL: context.workingDirectory,
      storageRootURL: context.codemapStoreDirectory.deletingLastPathComponent()
    )
  }

  private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  private static func encode<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    try data.write(to: url, options: .atomic)
  }
}

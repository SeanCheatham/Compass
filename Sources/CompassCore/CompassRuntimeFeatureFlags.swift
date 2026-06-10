import Foundation

struct CompassRuntimeFeatureFlags: Equatable, Sendable {
  var foundationModelsOnly: Bool
  var generatedOutput: ForgeProfile

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    _ = environment
    foundationModelsOnly = true
    generatedOutput = .generatedProjectDefault
  }

  var copyText: String {
    [
      "foundationModelsOnly=\(foundationModelsOnly)",
      "generatedOutput=\(generatedOutput.rawValue)",
    ].joined(separator: "\n")
  }
}

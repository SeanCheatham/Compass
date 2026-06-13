import Foundation

package struct CompassRuntimeFeatureFlags: Equatable, Sendable {
  package var foundationModelsOnly: Bool
  package var generatedOutput: ForgeProfile

  package init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    _ = environment
    foundationModelsOnly = true
    generatedOutput = .generatedProjectDefault
  }

  package var copyText: String {
    [
      "foundationModelsOnly=\(foundationModelsOnly)",
      "generatedOutput=\(generatedOutput.rawValue)",
    ].joined(separator: "\n")
  }
}

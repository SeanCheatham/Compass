import Foundation

struct CompassRuntimeFeatureFlags: Equatable, Sendable {
  var foundationModelsOnly: Bool

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    _ = environment
    foundationModelsOnly = true
  }

  var copyText: String {
    "foundationModelsOnly=\(foundationModelsOnly)"
  }
}

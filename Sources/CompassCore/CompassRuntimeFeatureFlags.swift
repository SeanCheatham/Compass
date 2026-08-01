import Foundation

public struct CompassRuntimeFeatureFlags: Equatable, Sendable {
  public var foundationModelsOnly: Bool

  public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    _ = environment
    foundationModelsOnly = true
  }

  public var copyText: String {
    "foundationModelsOnly=\(foundationModelsOnly)"
  }
}

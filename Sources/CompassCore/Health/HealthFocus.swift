import Foundation

/// Category that steers one health pass. Mirrors factory `PlanFocus` without `feature`.
public enum HealthFocus: String, Codable, Equatable, Sendable, CaseIterable {
  case bugHunt
  case test
  case cleanup
  case docs

  public var weight: Double {
    switch self {
    case .bugHunt: return 35
    case .test: return 25
    case .cleanup: return 25
    case .docs: return 15
    }
  }

  public var displayName: String {
    switch self {
    case .bugHunt: return "bug hunt"
    case .test: return "tests"
    case .cleanup: return "cleanup"
    case .docs: return "docs"
    }
  }

  public static func weightedRandom<G: RandomNumberGenerator>(
    using generator: inout G
  ) -> HealthFocus {
    let total = allCases.reduce(0.0) { $0 + $1.weight }
    let roll = Double.random(in: 0..<total, using: &generator)
    var cumulative = 0.0
    for focus in allCases {
      cumulative += focus.weight
      if roll < cumulative { return focus }
    }
    return allCases.last ?? .bugHunt
  }

  public static func weightedRandom() -> HealthFocus {
    var generator = SystemRandomNumberGenerator()
    return weightedRandom(using: &generator)
  }
}

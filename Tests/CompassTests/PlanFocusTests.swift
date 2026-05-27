import Foundation
import Testing

@testable import Compass

struct PlanFocusTests {

  /// Weight values matter: feature must still dominate a single
  /// pass in expectation, but not by enough to starve the other
  /// categories. If someone retunes them this test should be
  /// updated deliberately rather than drift silently.
  @Test
  func testWeightsMatchExpectedDistribution() {
    #require(PlanFocus.feature.weight == 30)
    #require(PlanFocus.test.weight == 25)
    #require(PlanFocus.cleanup.weight == 25)
    #require(PlanFocus.docs.weight == 10)
    #require(PlanFocus.bugHunt.weight == 10)

    let total = PlanFocus.allCases.reduce(0.0) { $0 + $1.weight }
    #require(total == 100)
  }

  /// Smoke test the sampler with a seeded generator. We don't pin
  /// the exact sequence (that would lock us to a specific
  /// implementation of `Double.random(in:using:)`) — we just confirm
  /// every category gets picked at least once over a large sample,
  /// which is what "weighted but covers all" actually means in the
  /// product sense.
  @Test
  func testWeightedRandomEventuallyPicksEveryFocus() {
    var generator = SplitMix64(seed: 0xC0FFEE)
    var seen = Set<PlanFocus>()
    for _ in 0..<10_000 {
      seen.insert(PlanFocus.weightedRandom(using: &generator))
      if seen.count == PlanFocus.allCases.count { return }
    }
    #require(false, "weightedRandom did not cover every focus in 10k samples; saw \(seen)")
  }

  /// Over a large sample the empirical distribution should land
  /// close to the configured weights. Use a wide tolerance — the
  /// goal is to catch a wholesale wiring bug (e.g. uniform
  /// sampling, swapped weights), not to validate the RNG.
  @Test
  func testWeightedRandomApproximatesConfiguredWeights() {
    var generator = SplitMix64(seed: 0xDECAFBAD)
    let trials = 20_000
    var counts: [PlanFocus: Int] = [:]
    for _ in 0..<trials {
      let focus = PlanFocus.weightedRandom(using: &generator)
      counts[focus, default: 0] += 1
    }
    for focus in PlanFocus.allCases {
      let observed = Double(counts[focus] ?? 0) / Double(trials)
      let expected = focus.weight / 100.0
      #require(observed == expected, accuracy: 0.03, "focus \(focus.displayName) sampled at \(observed), expected ~\(expected)")
    }
  }
}

/// Deterministic 64-bit PRNG so the distribution tests don't flake
/// across runs. SystemRandomNumberGenerator is not seedable.
private struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z &>> 31)
  }
}

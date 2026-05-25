import Foundation

/// A category that biases what the Plan agent picks as the next
/// increment. Without a focus the planner tends to compound on
/// feature work and lets tests, cleanup, and docs drift; sampling
/// a focus per Plan pass forces the other categories to get airtime
/// over a run.
enum PlanFocus: String, CaseIterable, Equatable {
  case feature
  case test
  case cleanup
  case docs
  case bugHunt

  /// Relative weight used when sampling. The weights are tuned so
  /// feature work still dominates a single pass in expectation but
  /// not by enough to starve the other categories over a session.
  /// Even-er split: feature 30 / test 25 / cleanup 25 / docs 10 / bugHunt 10.
  var weight: Double {
    switch self {
    case .feature: return 30
    case .test: return 25
    case .cleanup: return 25
    case .docs: return 10
    case .bugHunt: return 10
    }
  }

  /// Short label used in logs and session history so the user can
  /// see what was rolled.
  var displayName: String {
    switch self {
    case .feature: return "feature"
    case .test: return "tests"
    case .cleanup: return "cleanup"
    case .docs: return "docs"
    case .bugHunt: return "bug hunt"
    }
  }

  /// Guidance injected into the Plan prompt. Drafts still win over
  /// the focus — the language here mirrors the "Strong steer"
  /// interaction model: when the planner has discretion, it picks a
  /// midTerm item that matches the focus (even if it means skipping
  /// the head of the queue) or originates work in that category.
  var promptGuidance: String {
    let header = "## Focus for this iteration: \(displayName)"
    let interaction = """
      Drafts always win — if the user supplied drafts, honor them and
      ignore the focus. Otherwise let the focus steer your choice:
      pick the midTerm item that best matches the focus (even if it
      means skipping the head of the queue), or originate a new
      increment in this category from the repo state. If absolutely
      nothing in the repo fits this focus right now, pick the most
      useful increment you can and note in the plan body why the
      focus did not apply.
      """
    return "\(header)\n\n\(interaction)\n\n\(detail)"
  }

  private var detail: String {
    switch self {
    case .feature:
      return """
        Focus details — feature:
        - Add a new user-facing capability or extend an existing one
          in a way that delivers visible value.
        - Prefer increments that finish a slice end-to-end over
          scaffolding that future work has to come back and wire up.
        """
    case .test:
      return """
        Focus details — tests:
        - Improve the test suite: add coverage for currently
          untested behavior, replace brittle assertions, repair
          flakes, or convert weak smoke tests into real ones.
        - A pure test-only change is a valid increment. The verify
          command should run the affected tests.
        - Do not write tests that pin implementation details the
          team is likely to refactor; pin behavior instead.
        """
    case .cleanup:
      return """
        Focus details — cleanup:
        - Remove dead code, consolidate duplication, simplify
          abstractions, or pay down a specific piece of tech debt.
        - The increment must leave behavior unchanged. The verify
          command should prove that (existing tests, build, or a
          targeted regression test).
        - Prefer small, surgical consolidations over speculative
          refactors. If a cleanup grows beyond commit-sized, scope
          down to one slice.
        """
    case .docs:
      return """
        Focus details — docs:
        - Improve documentation that a real reader would hit:
          README, in-app help, top-of-file context comments,
          onboarding notes. Fix stale or wrong docs first.
        - Avoid line-by-line comments that just restate code. Aim
          for the kind of context a new contributor would need.
        - The verify command is usually a build or doc-lint; if
          there is no automated check, pick the cheapest command
          that proves nothing else broke.
        """
    case .bugHunt:
      return """
        Focus details — bug hunt:
        - Actively probe for a real bug or rough edge — wrong
          behavior, a crash path, a race, a confusing error
          message, a regression risk — and fix one.
        - Ground the hunt in the repo: read suspect code, run the
          app or tests, reproduce before fixing. Do not invent
          hypothetical bugs.
        - The verify command should be a test that fails before the
          fix and passes after, when feasible.
        """
    }
  }

  /// Samples a focus by weight. Takes a generator so tests can
  /// drive the distribution deterministically.
  static func weightedRandom<G: RandomNumberGenerator>(
    using generator: inout G
  ) -> PlanFocus {
    let total = allCases.reduce(0.0) { $0 + $1.weight }
    let roll = Double.random(in: 0..<total, using: &generator)
    var cumulative = 0.0
    for focus in allCases {
      cumulative += focus.weight
      if roll < cumulative { return focus }
    }
    return allCases.last ?? .feature
  }

  static func weightedRandom() -> PlanFocus {
    var generator = SystemRandomNumberGenerator()
    return weightedRandom(using: &generator)
  }
}

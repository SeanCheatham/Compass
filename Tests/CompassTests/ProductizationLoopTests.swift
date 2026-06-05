import Foundation
import Testing

@testable import Compass

struct ProductizationLoopTests {
  @Test func decisionTransitionValidatorAllowsDocumentedProductizationPath() throws {
    try ProductizationDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .notRun,
      to: .keepGoing,
      summary: ""
    )
    try ProductizationDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .keepGoing,
      to: .narrow,
      summary: ""
    )
    try ProductizationDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .narrow,
      to: .promote,
      summary: "Evidence and Verify support promotion."
    )
    try ProductizationDecisionTransitionValidator.validate(
      experimentID: "experiment-one",
      from: .promote,
      to: .promoted,
      summary: "The promoted experiment has landed."
    )
  }

  @Test func decisionTransitionValidatorRejectsUndocumentedProductizationPath() throws {
    do {
      try ProductizationDecisionTransitionValidator.validate(
        experimentID: "experiment-one",
        from: .pivot,
        to: .promote,
        summary: "Too large a leap."
      )
      Issue.record("Expected pivot -> promote to be rejected.")
    } catch let error as ProductizationDecisionTransitionError {
      try #require(
        error
          == .invalidTransition(
            experimentID: "experiment-one",
            from: .pivot,
            to: .promote
          )
      )
    }
  }

  @Test func decisionTransitionValidatorRequiresSummaryForKillAndPromote() throws {
    do {
      try ProductizationDecisionTransitionValidator.validate(
        experimentID: "experiment-one",
        from: .keepGoing,
        to: .kill,
        summary: "  "
      )
      Issue.record("Expected kill without summary to be rejected.")
    } catch let error as ProductizationDecisionTransitionError {
      try #require(error == .missingSummary(experimentID: "experiment-one", decision: .kill))
    }
  }

  @Test func reflectDecisionApplierUpdatesExperimentAndDecisionTrail() throws {
    let config = ProductizationConfig.seedDefaults(
      projectTitle: "Factory",
      rawPain: "Factory users need better product bet evidence.",
      now: Date(timeIntervalSince1970: 10)
    )
    let experiment = config.experiments[0]
    let update = ProductizationReflectDecisionUpdate(
      experimentID: experiment.id,
      decision: .keepGoing,
      summary: "The deterministic run exposed one clear missing capability.",
      evidenceRunIDs: ["run-one"],
      decidedBy: "Reflect"
    )

    let next = try ProductizationReflectDecisionApplier.applying(
      [update],
      to: config,
      now: Date(timeIntervalSince1970: 20)
    )
    let savedExperiment = try #require(next.experiments.first { $0.id == experiment.id })
    let savedDecision = try #require(next.decisions.last)

    try #require(savedExperiment.decision == .keepGoing)
    try #require(savedExperiment.evidenceSummary.contains("missing capability"))
    try #require(savedExperiment.updatedAt == 20)
    try #require(savedDecision.experimentID == experiment.id)
    try #require(savedDecision.decision == .keepGoing)
    try #require(savedDecision.evidenceRunIDs == ["run-one"])
    try #require(savedDecision.decidedBy == "Reflect")
  }
}

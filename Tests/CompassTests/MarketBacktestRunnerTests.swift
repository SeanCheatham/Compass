import Foundation
import Testing

@testable import Compass

struct MarketBacktestRunnerTests {
  @Test func hidesKnownOutcomeFromCompilerInput() throws {
    let backtestCase = try #require(MarketBacktestFixtures.compactCases.first)
    let runner = MarketBacktestRunner(now: { Date(timeIntervalSince1970: 100) })

    let run = runner.run(backtestCase)

    try #require(!run.compilerInputSummary.contains(backtestCase.knownOutcome.rawValue))
    try #require(!run.compilerInputSummary.contains(backtestCase.outcomeSummary))
    try #require(!run.compilerInputSummary.contains(backtestCase.hiddenOutcomeNotes))
    try #require(run.compilerInputSummary.contains(backtestCase.initialPain))
    try #require(run.compilerInputSummary.contains(backtestCase.initialContender))
  }

  @Test func producesPredictedOutcomeForFiveCompactCases() throws {
    let runner = MarketBacktestRunner(now: { Date(timeIntervalSince1970: 200) })

    let runs = runner.run(MarketBacktestFixtures.compactCases)

    try #require(runs.count == 5)
    try #require(runs.allSatisfy { KnownProductOutcome.allCases.contains($0.predictedOutcome) })
    try #require(runs.allSatisfy { $0.confidence >= 1 && $0.confidence <= 5 })
    try #require(runs.allSatisfy { !$0.strongestReasons.isEmpty })
  }

  @Test func recordsCalibrationDeltaAfterReveal() throws {
    let backtestCase = MarketBacktestCase(
      id: "channel-overfit-case",
      name: "channel overfit case",
      era: "modern saas",
      category: "sales automation",
      initialPain: "Teams want more pipeline without changing workflow.",
      initialContender: "Outbound assistant with broad claims and unclear renewal pull.",
      knownOutcome: .failed,
      outcomeSummary: "The product failed when channel costs outran urgency.",
      hiddenOutcomeNotes: "Channel fit looked better than actual willingness to switch."
    )
    let run = MarketBacktestRun(
      id: "manual-backtest",
      caseID: backtestCase.id,
      predictedOutcome: .breakout,
      actualOutcome: backtestCase.knownOutcome,
      confidence: 5,
      strongestReasons: ["channel fit"],
      missedRisks: ["channel fit"],
      overconfidenceFlags: ["overconfident channel fit"],
      compilerInputSummary: MarketBacktestRunner().compilerInputSummary(for: backtestCase),
      createdAt: 300
    )

    try #require(run.predictedOutcome == .breakout)
    try #require(run.actualOutcome == .failed)
    try #require(run.calibrationDelta == 4)
    try #require(!run.outcomeMatched)
    try #require(run.overconfidenceFlags.contains("overconfident channel fit"))
  }
}

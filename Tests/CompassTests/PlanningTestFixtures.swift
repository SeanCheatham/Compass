import Foundation

@testable import Compass

func testPlanCandidates(_ text: String) -> [PlanCandidate] {
  text.components(separatedBy: .newlines)
    .map { line in
      line.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"^[-*]\s*"#, with: "", options: .regularExpression)
    }
    .filter { !$0.isEmpty }
    .map { PlanCandidate(id: $0, title: $0, outcome: $0) }
}

func testStrategicContext(_ text: String) -> PlanStrategicContext {
  PlanStrategicContext(thesis: text.trimmingCharacters(in: .whitespacesAndNewlines))
}

extension PlanState {
  init(
    completed: [String] = [],
    immediate: PlanNext?,
    candidates: String,
    strategicContext: String
  ) {
    self.init(
      completed: completed,
      immediate: immediate,
      candidates: testPlanCandidates(candidates),
      strategicContext: testStrategicContext(strategicContext)
    )
  }
}

extension PlanProposal {
  init(
    immediate: PlanNext?,
    candidates: String,
    strategicContext: String,
    openQuestions: [PlanQuestion] = []
  ) {
    self.init(
      immediate: immediate,
      candidates: testPlanCandidates(candidates),
      strategicContext: testStrategicContext(strategicContext),
      openQuestions: openQuestions
    )
  }
}

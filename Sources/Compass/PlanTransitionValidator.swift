import Foundation

struct PlanTransitionValidationError: LocalizedError, Equatable {
  var message: String

  var errorDescription: String? {
    message
  }
}

enum PlanTransitionValidator {
  static func validate(from current: PlanState, to next: PlanState) throws {
    if next.completed.count < current.completed.count {
      throw PlanTransitionValidationError(
        message:
          "Plan tried to shrink completed history from \(current.completed.count) entries to \(next.completed.count). Refusing to overwrite state.json."
      )
    }

    if !current.midTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && next.midTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && next.completed.count == current.completed.count
    {
      throw PlanTransitionValidationError(
        message:
          "Plan tried to clear a non-empty midTerm queue without recording a completion. Refusing to overwrite state.json."
      )
    }

    guard let immediate = next.immediate else { return }
    let verify = immediate.verify.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let rejectedVerifyCommands = Set([
      "true",
      "not-running-tests",
      "not running tests",
      "none",
      "n/a",
    ])
    if rejectedVerifyCommands.contains(verify) {
      throw PlanTransitionValidationError(
        message:
          "Plan returned placeholder verify command `\(immediate.verify)`. Refusing to overwrite state.json."
      )
    }
  }
}

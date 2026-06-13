import Foundation

package struct VerifyBypassAutoRepair: Equatable, Sendable {
  package enum Reason: String, Equatable, Sendable {
    case sortedDiffFileList = "sorted-diff-file-list"
  }

  package var command: String
  package var reason: Reason
  package var note: String

  package static func repair(
    plannedCommand: String,
    developSummary: DevelopSummary,
    forgeProfile: ForgeProfile?
  ) -> VerifyBypassAutoRepair? {
    guard developSummary.bypassVerify == true else { return nil }

    let handoff = [developSummary.summary, developSummary.feedback, plannedCommand]
      .map(normalizedText)
      .joined(separator: " ")

    guard describesSortedDiffFileListProblem(handoff) else {
      return nil
    }

    switch forgeProfile {
    case .swiftSPM, .typeScriptPnpmVite, .tesseraApp, nil:
      return nil
    }
  }

  private static func describesSortedDiffFileListProblem(_ text: String) -> Bool {
    containsAny(text, ["expected", "expectation"])
      && containsAny(
        text,
        ["git diff", "diff --name-only", "name-only", "changed file", "file list", "file-list"]
      )
      && containsAny(text, ["sort", "sorted", "order", "ordering", "alphabet"])
  }

  private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
    needles.contains { text.contains($0) }
  }

  private static func normalizedText(_ text: String) -> String {
    text
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

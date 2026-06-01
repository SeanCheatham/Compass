import Foundation

struct DevelopFeedbackValidationError: LocalizedError, Equatable {
  enum Reason: Equatable {
    case empty
    case placeholder
    case tooShort
  }

  var message: String
  var reason: Reason
  var feedback: String?

  var errorDescription: String? { message }
}

enum DevelopFeedbackValidator {
  private static let placeholderKeys: Set<String> = [
    "all done",
    "all good",
    "all set",
    "complete",
    "completed",
    "done",
    "fixed",
    "finished",
    "good",
    "implemented",
    "looks good",
    "n a",
    "na",
    "no feedback",
    "none",
    "nothing",
    "ok",
    "okay",
    "ship it",
    "success",
    "succeeded",
    "works",
  ]

  private static let genericTokens: Set<String> = [
    "all",
    "complete",
    "completed",
    "done",
    "fixed",
    "finished",
    "good",
    "implemented",
    "ok",
    "okay",
    "set",
    "success",
    "succeeded",
    "works",
  ]

  static func validate(_ summary: DevelopSummary) throws {
    let feedback = normalizedWhitespace(summary.feedback)
    guard !feedback.isEmpty else {
      throw DevelopFeedbackValidationError(
        message:
          "Develop feedback is empty. Add a concrete handoff for the next Plan pass.",
        reason: .empty,
        feedback: nil
      )
    }

    let tokens = wordTokens(in: feedback)
    let key = tokens.joined(separator: " ")
    if placeholderKeys.contains(key)
      || (!tokens.isEmpty && tokens.count <= 3 && tokens.allSatisfy(genericTokens.contains))
    {
      throw DevelopFeedbackValidationError(
        message:
          "Develop feedback `\(feedback)` is too generic to guide the next Plan pass.",
        reason: .placeholder,
        feedback: feedback
      )
    }

    guard tokens.count >= 4, feedback.count >= 24 else {
      throw DevelopFeedbackValidationError(
        message:
          "Develop feedback `\(feedback)` is too short. Write one concrete sentence with the result, blocker, or next recovery action.",
        reason: .tooShort,
        feedback: feedback
      )
    }
  }

  private static func normalizedWhitespace(_ text: String) -> String {
    text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private static func wordTokens(in text: String) -> [String] {
    var tokens: [String] = []
    var current = String.UnicodeScalarView()

    for scalar in text.lowercased().unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        current.append(scalar)
      } else if !current.isEmpty {
        tokens.append(String(current))
        current.removeAll(keepingCapacity: true)
      }
    }

    if !current.isEmpty {
      tokens.append(String(current))
    }
    return tokens
  }
}

import Foundation

enum FeedbackHandoffValidationReason: Equatable {
  case empty
  case placeholder
  case tooShort
  case unfinishedSuccess
}

struct DevelopFeedbackValidationError: LocalizedError, Equatable {
  typealias Reason = FeedbackHandoffValidationReason

  var message: String
  var reason: Reason
  var feedback: String?

  var errorDescription: String? { message }
}

struct DevelopVerifyBypassValidationError: LocalizedError, Equatable {
  enum Reason: Equatable {
    case missingReason
    case genericReason
  }

  var message: String
  var reason: Reason

  var errorDescription: String? { message }
}

enum DevelopFeedbackValidator {
  static func validate(_ summary: DevelopSummary) throws {
    if summary.status == .succeeded,
      let unfinished = UnfinishedSuccessFeedback.detect(in: summary.feedback)
    {
      throw DevelopFeedbackValidationError(
        message:
          "Develop reported status=succeeded, but feedback says planned work remains: `\(unfinished)`. If implementation work remains, return status=failed or status=blocked; if the packet is complete, feedback should summarize the verified result with no future implementation step.",
        reason: .unfinishedSuccess,
        feedback: unfinished
      )
    }

    guard let rejection = FeedbackHandoffTextQuality.rejection(for: summary.feedback) else {
      return
    }

    switch rejection.reason {
    case .empty:
      throw DevelopFeedbackValidationError(
        message:
          "Develop feedback is empty. Add a concrete handoff for the next Plan pass.",
        reason: .empty,
        feedback: nil
      )
    case .placeholder:
      throw DevelopFeedbackValidationError(
        message:
          "Develop feedback `\(rejection.feedback ?? "")` is too generic to guide the next Plan pass.",
        reason: .placeholder,
        feedback: rejection.feedback
      )
    case .tooShort:
      throw DevelopFeedbackValidationError(
        message:
          "Develop feedback `\(rejection.feedback ?? "")` is too short. Write one concrete sentence with the result, blocker, or next recovery action.",
        reason: .tooShort,
        feedback: rejection.feedback
      )
    case .unfinishedSuccess:
      throw DevelopFeedbackValidationError(
        message:
          "Develop feedback `\(rejection.feedback ?? "")` says planned work remains despite status=succeeded.",
        reason: .unfinishedSuccess,
        feedback: rejection.feedback
      )
    }
  }
}

enum DevelopVerifyBypassValidator {
  private static let concreteReasonTokens: Set<String> = [
    "cannot",
    "cant",
    "coverage",
    "deleted",
    "disabled",
    "exist",
    "exists",
    "host",
    "invalid",
    "missing",
    "out",
    "removed",
    "renamed",
    "scope",
    "unsupported",
    "wrong",
    "xcode",
    "xcodebuild",
  ]
  private static let concreteProblemDetailTokens: Set<String> = [
    "coverage",
    "deleted",
    "destination",
    "exist",
    "exists",
    "file",
    "filter",
    "flag",
    "host",
    "module",
    "package",
    "path",
    "removed",
    "renamed",
    "scheme",
    "simulator",
    "spm",
    "suite",
    "swiftpm",
    "target",
    "workspace",
    "xcode",
    "xcodebuild",
    "xcodeproj",
  ]

  static func validate(_ summary: DevelopSummary) throws {
    guard summary.bypassVerify == true else { return }

    let combined = [summary.feedback, summary.summary]
      .map(HandoffText.normalizedWhitespace)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    let tokens = Set(HandoffText.wordTokens(in: combined))

    guard tokens.contains("verify") else {
      throw DevelopVerifyBypassValidationError(
        message:
          "Develop set bypassVerify=true without explaining why the verify command itself is wrong or out of scope.",
        reason: .missingReason
      )
    }

    guard !tokens.isDisjoint(with: concreteReasonTokens) else {
      throw DevelopVerifyBypassValidationError(
        message:
          "Develop set bypassVerify=true but did not name a concrete verify-command problem.",
        reason: .genericReason
      )
    }

    guard hasConcreteProblemDetail(in: combined, tokens: tokens) else {
      throw DevelopVerifyBypassValidationError(
        message:
          "Develop set bypassVerify=true but did not name the concrete file, suite, command, or environment detail that makes the verify command wrong.",
        reason: .genericReason
      )
    }
  }

  private static func hasConcreteProblemDetail(in text: String, tokens: Set<String>) -> Bool {
    if text.contains("`") {
      return true
    }
    if !tokens.isDisjoint(with: concreteProblemDetailTokens) {
      return true
    }
    return tokens.contains { token in
      token.count >= 18 || token.contains { $0.isNumber }
    }
  }
}

struct CriticFeedbackValidationError: LocalizedError, Equatable {
  typealias Reason = FeedbackHandoffValidationReason

  var message: String
  var reason: Reason
  var feedback: String?

  var errorDescription: String? { message }
}

enum CriticFeedbackValidator {
  static func validate(_ verdict: CriticVerdict) throws {
    guard verdict.verdict == .requestChanges,
      let rejection = FeedbackHandoffTextQuality.rejection(for: verdict.feedback)
    else {
      return
    }

    switch rejection.reason {
    case .empty:
      throw CriticFeedbackValidationError(
        message:
          "Critic requested changes without feedback. Add a concrete punch list for the next Develop pass.",
        reason: .empty,
        feedback: nil
      )
    case .placeholder:
      throw CriticFeedbackValidationError(
        message:
          "Critic feedback `\(rejection.feedback ?? "")` is too generic to guide the next Develop pass.",
        reason: .placeholder,
        feedback: rejection.feedback
      )
    case .tooShort:
      throw CriticFeedbackValidationError(
        message:
          "Critic feedback `\(rejection.feedback ?? "")` is too short. Name the failing behavior or file and one recovery action.",
        reason: .tooShort,
        feedback: rejection.feedback
      )
    case .unfinishedSuccess:
      throw CriticFeedbackValidationError(
        message:
          "Critic feedback `\(rejection.feedback ?? "")` is too ambiguous. Name the failing behavior or file and one recovery action.",
        reason: .unfinishedSuccess,
        feedback: rejection.feedback
      )
    }
  }
}

private struct FeedbackHandoffRejection: Equatable {
  var reason: FeedbackHandoffValidationReason
  var feedback: String?
}

private enum HandoffText {
  static func normalizedWhitespace(_ text: String) -> String {
    text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  static func wordTokens(in text: String) -> [String] {
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

private enum FeedbackHandoffTextQuality {
  private static let placeholderKeys: Set<String> = [
    "all done",
    "all good",
    "all set",
    "complete",
    "completed",
    "done",
    "fix it",
    "fixed",
    "finished",
    "good",
    "implemented",
    "looks good",
    "n a",
    "na",
    "needs work",
    "no feedback",
    "no follow up",
    "no follow up needed",
    "no further action",
    "no further action needed",
    "none",
    "nothing",
    "nothing else needed",
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
    "fix",
    "fixed",
    "finished",
    "good",
    "implemented",
    "it",
    "needs",
    "ok",
    "okay",
    "set",
    "success",
    "succeeded",
    "work",
    "works",
  ]

  static func rejection(for text: String) -> FeedbackHandoffRejection? {
    let feedback = HandoffText.normalizedWhitespace(text)
    guard !feedback.isEmpty else {
      return FeedbackHandoffRejection(reason: .empty, feedback: nil)
    }

    let tokens = HandoffText.wordTokens(in: feedback)
    let key = tokens.joined(separator: " ")
    if placeholderKeys.contains(key)
      || (!tokens.isEmpty && tokens.count <= 3 && tokens.allSatisfy(genericTokens.contains))
    {
      return FeedbackHandoffRejection(reason: .placeholder, feedback: feedback)
    }

    guard tokens.count >= 4, feedback.count >= 24 else {
      return FeedbackHandoffRejection(reason: .tooShort, feedback: feedback)
    }

    return nil
  }
}

private enum UnfinishedSuccessFeedback {
  private static let unfinishedPhrases = [
    "still needs",
    "still need",
    "needs to",
    "need to",
    "remaining work",
    "work remains",
    "not implemented",
    "not complete",
    "not done",
    "todo",
    "to do",
  ]

  private static let nextStepActions: Set<String> = [
    "add",
    "choose",
    "create",
    "determine",
    "edit",
    "fix",
    "implement",
    "prepare",
    "read",
    "update",
    "use",
    "wire",
  ]

  static func detect(in feedback: String) -> String? {
    let normalized = HandoffText.normalizedWhitespace(feedback)
    guard !normalized.isEmpty else { return nil }
    let lowercased = normalized.lowercased()
    if lowercased.contains("no follow")
      || lowercased.contains("nothing else")
      || lowercased.contains("verified")
      || lowercased.contains("verify passed")
    {
      return nil
    }
    let tokens = HandoffText.wordTokens(in: lowercased)
    if lowercased.contains("next step") || lowercased.contains("next action")
      || lowercased.contains("follow up")
    {
      let tokenSet = Set(tokens)
      if !tokenSet.isDisjoint(with: nextStepActions) {
        return normalized
      }
    }
    if tokens.first == "next",
      tokens.dropFirst().contains(where: nextStepActions.contains)
    {
      return normalized
    }
    if let first = tokens.first, nextStepActions.contains(first) {
      return normalized
    }
    if unfinishedPhrases.contains(where: { lowercased.contains($0) }) {
      return normalized
    }
    if lowercased.hasPrefix("run ") && lowercased.contains("verify") {
      return normalized
    }
    return nil
  }
}

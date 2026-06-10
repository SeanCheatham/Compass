import Foundation

struct DevelopFailureInsight: Equatable {
  enum Kind: Equatable {
    case missingResult
    case malformedToolCall
    case providerFailure
    case generic
  }

  var kind: Kind
  var guideTitle: String
  var inspectTitle: String
  var inspectDetail: String
  var repairTitle: String
  var repairDetail: String
  var retryDetail: String

  init(detail: String) {
    let detail = Self.normalized(detail)
    let searchable = detail.lowercased()
    kind = Self.kind(for: searchable)

    switch kind {
    case .missingResult:
      guideTitle = "Finish the Develop handoff"
      inspectTitle = "Inspect the missing result"
      inspectDetail =
        detail.isEmpty
        ? "Develop ended before Compass received a phase submit envelope."
        : "Develop ended before Compass received a phase submit envelope: \(detail)"
      repairTitle = "Ask for one smaller finish"
      repairDetail =
        "Keep the same plan, but have Develop finish one narrow change and report status through `develop_submit` instead of continuing in prose."
      retryDetail = "Compass will retry Develop with the result handoff requirement preserved."
    case .malformedToolCall:
      guideTitle = "Repair the tool request"
      inspectTitle = "Inspect the malformed tool call"
      inspectDetail =
        detail.isEmpty
        ? "Compass rejected a tool call before trusting its result."
        : "Compass rejected a tool call before trusting its result: \(detail)"
      repairTitle = "Use simpler tool arguments"
      repairDetail =
        "Have Develop retry the same intent with required fields, project-relative paths, and smaller JSON payloads."
      retryDetail =
        "Compass will retry Develop after the model has the concrete tool-shape failure."
    case .providerFailure:
      guideTitle = "Restore the local model"
      inspectTitle = "Inspect the model failure"
      inspectDetail =
        detail.isEmpty
        ? "The local model failed before Develop could finish."
        : "The local model failed before Develop could finish: \(detail)"
      repairTitle = "Check the MLX runtime"
      repairDetail =
        "Confirm the blessed model is downloaded and retry once the MLX runtime is ready."
      retryDetail = "Retry Develop once the local model can produce a complete response."
    case .generic:
      guideTitle = "Retry with the captured failure"
      inspectTitle = "Keep the failure visible"
      inspectDetail = detail.isEmpty ? "Develop failed without captured detail." : detail
      repairTitle = "Ask for a smaller fix"
      repairDetail = "Have Develop address the first concrete error before broadening scope."
      retryDetail = "Compass will preserve the current plan context."
    }
  }

  private static func kind(for text: String) -> Kind {
    if containsAny(
      text,
      [
        "ended without submit_result", "model stopped without calling submit_result",
        "phase submit envelope", "phase submit missing",
        "agent exceeded max iterations", "agent exceeded wall-clock timeout",
      ])
    {
      return .missingResult
    }
    if containsAny(
      text,
      [
        "had undecodable args", "tool call decode", "invalid arguments",
        "args are not valid json", "missing required field",
      ])
    {
      return .malformedToolCall
    }
    if containsAny(
      text,
      ["local model generation failed", "mlx", "model missing", "model provider failed", "provider"]
    ) {
      return .providerFailure
    }
    return .generic
  }

  private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
    needles.contains { text.contains($0) }
  }

  private static func normalized(_ value: String) -> String {
    StringUtils.boundedText(value, limit: 500)
  }
}

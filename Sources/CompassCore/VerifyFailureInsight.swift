import Foundation

package struct VerifyFailureInsight: Equatable {
  package enum Kind: Equatable {
    case testFailure
    case buildFailure
    case missingTool
    case timeout
    case coverage
    case generic
  }

  package var kind: Kind
  package var inspectTitle: String
  package var inspectDetail: String
  package var repairTitle: String
  package var repairDetail: String
  package var retryDetail: String

  package init(detail: String, metadata: String?) {
    let detail = Self.normalized(detail)
    let searchable = [detail, metadata.map(Self.normalized)]
      .compactMap { $0 }
      .joined(separator: " ")
      .lowercased()
    kind = Self.kind(for: searchable)

    switch kind {
    case .testFailure:
      inspectTitle = "Inspect the failing assertion"
      inspectDetail = "Compass found a test failure in the verify output: \(detail)"
      repairTitle = "Fix the behavior under test"
      repairDetail =
        "Have Develop change the code or expectation named by the failing test before broadening scope."
      retryDetail = "Compass will rerun the same test command after Develop patches the failure."
    case .buildFailure:
      inspectTitle = "Inspect the build error"
      inspectDetail = "Compass found a compile or build error in the verify output: \(detail)"
      repairTitle = "Fix the first compiler error"
      repairDetail =
        "Have Develop address the earliest concrete file, symbol, module, or syntax error first."
      retryDetail = "Compass will rerun verification after the build can complete."
    case .missingTool:
      inspectTitle = "Inspect the missing tool"
      inspectDetail = "Compass found that the verify command could not start cleanly: \(detail)"
      repairTitle = "Make the command runnable"
      repairDetail =
        "Install or select the missing tool, or ask Plan to choose a verify command this workspace can run."
      retryDetail = "Retry once the command can start in the selected execution environment."
    case .timeout:
      inspectTitle = "Inspect the timeout"
      inspectDetail =
        "Compass found that verification timed out or stopped making progress: \(detail)"
      repairTitle = "Unblock the hanging check"
      repairDetail =
        "Have Develop reduce the slow path, remove the wait, or split the verify command into a smaller check."
      retryDetail = "Retry after the check has a bounded path to completion."
    case .coverage:
      inspectTitle = "Inspect coverage output"
      inspectDetail = "Compass found a coverage-related verify failure: \(detail)"
      repairTitle = "Restore coverage reporting"
      repairDetail =
        "Keep the coverage-ready command and fix the missing coverage artifact, flag, or threshold."
      retryDetail = "Compass will rerun the coverage check after the reporting path is repaired."
    case .generic:
      inspectTitle = "Inspect verify output"
      inspectDetail = detail.isEmpty ? "Verify failed without captured output." : detail
      repairTitle = "Patch the failing behavior"
      repairDetail = "Have Develop change code or tests only where the failure points."
      retryDetail = "Compass will rerun the planned verification command."
    }
  }

  private static func kind(for text: String) -> Kind {
    if containsAny(text, ["timed out", "timeout", "time limit", "deadline exceeded"]) {
      return .timeout
    }
    if containsAny(
      text,
      ["tessera: command not found", "could not find command tessera"]
    ) {
      return .missingTool
    }
    if containsAny(
      text,
      ["command not found", "no such file or directory", "could not find command"]
    ) {
      return .missingTool
    }
    if containsAny(
      text,
      [
        "tessera test", "expected json",
      ]
    ) {
      return .testFailure
    }
    if containsAny(
      text,
      [
        "typecheck", "syntax error", "compile error", "compiler error",
        "tessera parse", "tessera typecheck", "tessera load", "invalid manifest",
      ]
    ) {
      return .buildFailure
    }
    if containsAny(
      text,
      [
        "xctassert", "assertion failed", "expected", "test case", "tests failed",
        "failing test", "failed test",
      ]
    ) {
      return .testFailure
    }
    if containsAny(
      text,
      [
        "build failed", "compile error", "compiler error", "error:", "cannot find",
        "no such module", "missing package", "syntax error",
      ]
    ) {
      return .buildFailure
    }
    if containsAny(text, ["coverage", "profdata", "lcov", "coverprofile"]) {
      return .coverage
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

import Foundation

struct RustReviewProbe: Equatable, Identifiable, Sendable {
  var id: String { toolName }
  var toolName: String
  var reason: String
}

enum RustReviewProbePlanner {
  static func suggestions(
    forgeProfile: ForgeProfile?,
    gitDiff: String,
    verifyCommand: String = "",
    verifyOutput: String = ""
  ) -> [RustReviewProbe] {
    guard forgeProfile == .rustCargo else { return [] }
    return suggestions(
      changedPaths: changedPaths(fromGitDiff: gitDiff),
      verifyCommand: verifyCommand,
      verifyOutput: verifyOutput
    )
  }

  static func suggestions(
    changedPaths: [String],
    verifyCommand: String = "",
    verifyOutput: String = ""
  ) -> [RustReviewProbe] {
    var probes: [RustReviewProbe] = []

    if changedPaths.contains(where: isCargoWorkspacePath) {
      probes.append(
        RustReviewProbe(
          toolName: AgentWorkspaceOutlineTool.toolName,
          reason: "Cargo workspace or manifest changed"
        ))
    }

    if changedPaths.contains(where: isSchemaPath) || changedPaths.contains(where: isSchemaBackedRustPath) {
      probes.append(
        RustReviewProbe(
          toolName: AgentSchemaContractsTool.toolName,
          reason: "schema or schema-backed Rust source changed"
        ))
    }

    if changedPaths.contains(where: isRustSourcePath) {
      probes.append(
        RustReviewProbe(toolName: AgentCargoCheckTool.toolName, reason: "Rust source changed"))
      probes.append(
        RustReviewProbe(toolName: AgentClippyLintTool.toolName, reason: "Rust source changed"))
    }

    if changedPaths.contains(where: isCargoFeaturePath) {
      appendIfMissing(
        RustReviewProbe(
          toolName: AgentCargoCheckTool.toolName,
          reason: "Cargo workspace or feature wiring changed"
        ),
        to: &probes
      )
      appendIfMissing(
        RustReviewProbe(toolName: AgentClippyLintTool.toolName, reason: "Cargo feature wiring changed"),
        to: &probes
      )
    }

    if coverageEvidence(verifyCommand: verifyCommand, verifyOutput: verifyOutput) {
      probes.append(
        RustReviewProbe(
          toolName: AgentCoverageGapsTool.toolName,
          reason: "coverage evidence is available from verify"
        ))
    }

    if changedPaths.contains(where: isScaffoldContractPath) {
      probes.append(
        RustReviewProbe(
          toolName: AgentScaffoldCheckTool.toolName,
          reason: "generated scaffold contract path changed"
        ))
    }

    return dedupe(probes)
  }

  static func formattedSection(for probes: [RustReviewProbe]) -> String {
    guard !probes.isEmpty else { return "" }
    return (
      ["Suggested Rust review probes:"]
        + probes.prefix(8).map { "- \($0.toolName): \($0.reason)" }
    ).joined(separator: "\n")
  }

  static func changedPaths(fromGitDiff diff: String) -> [String] {
    var paths: [String] = []
    for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.hasPrefix("diff --git ") {
        let parts = line.split(separator: " ")
        if parts.count >= 4 {
          paths.append(stripDiffPrefix(String(parts[2])))
          paths.append(stripDiffPrefix(String(parts[3])))
        }
      } else if line.hasPrefix("+++ ") || line.hasPrefix("--- ") {
        let raw = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
        paths.append(stripDiffPrefix(raw))
      }
    }
    return Array(Set(paths.filter { !$0.isEmpty && $0 != "/dev/null" })).sorted()
  }

  private static func stripDiffPrefix(_ path: String) -> String {
    if path.hasPrefix("a/") || path.hasPrefix("b/") {
      return String(path.dropFirst(2))
    }
    return path
  }

  private static func isCargoWorkspacePath(_ path: String) -> Bool {
    path == "Cargo.toml" || path == "Cargo.lock" || path.hasSuffix("/Cargo.toml")
  }

  private static func isCargoFeaturePath(_ path: String) -> Bool {
    path.hasSuffix("Cargo.toml") || path == "Cargo.lock"
  }

  private static func isRustSourcePath(_ path: String) -> Bool {
    path.hasSuffix(".rs")
  }

  private static func isSchemaPath(_ path: String) -> Bool {
    path.hasPrefix("schemas/") && path.hasSuffix(".json")
  }

  private static func isSchemaBackedRustPath(_ path: String) -> Bool {
    path.hasSuffix(".rs") && (path.contains("state") || path.contains("schema") || path.contains("model"))
  }

  private static func isScaffoldContractPath(_ path: String) -> Bool {
    path == "compass-scaffold.toml"
      || path.hasPrefix("crates/app-core/")
      || path.hasPrefix("crates/app-cli/")
      || path.hasPrefix("crates/app-desktop/")
      || path.hasPrefix("xtask/")
      || path.hasPrefix("schemas/")
      || path == "rust-toolchain.toml"
  }

  private static func coverageEvidence(verifyCommand: String, verifyOutput: String) -> Bool {
    let combined = "\(verifyCommand)\n\(verifyOutput)".lowercased()
    return combined.contains("llvm-cov")
      || combined.contains("coverage")
      || combined.contains("overall line coverage")
  }

  private static func appendIfMissing(_ probe: RustReviewProbe, to probes: inout [RustReviewProbe]) {
    guard !probes.contains(where: { $0.toolName == probe.toolName }) else { return }
    probes.append(probe)
  }

  private static func dedupe(_ probes: [RustReviewProbe]) -> [RustReviewProbe] {
    var seen = Set<String>()
    return probes.filter { seen.insert($0.toolName).inserted }
  }
}

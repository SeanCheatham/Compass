import Foundation

/// Hardcoded quality conventions for Compass-generated Rust Cargo workspaces.
///
/// Mutation testing is prepared here (`mutationTestCommand`) but not yet wired into
/// the factory loop — the intended call site is post-verify / `runPostChecks`.
enum GeneratedProjectQuality {
  static let standardVerifyCommand =
    "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"

  static let coverageCollectCommand = "cargo llvm-cov --workspace --summary-only"

  /// Future post-verify mutation gate. Not invoked by the factory loop yet.
  static let mutationTestCommand = "cargo mutants --no-shuffle -j 1"

  static let coverageRequirementHint =
    "use `\(standardVerifyCommand)` for standard checks, or `cargo llvm-cov --workspace` / `cargo test --workspace` for test-focused slices. Documentation-only README/docs slices may use a simple `grep -q` content check."

  static let planningGuidance = """
    Generated Compass projects are Rust Cargo workspaces:
    - Layout: root `Cargo.toml` workspace plus `crates/app-core` and `crates/app-cli`.
    - No web or desktop UI packages — backend/CLI only.
    - Prefer `cargo fmt`, Clippy (`-D warnings`), and `cargo test` for verification.
    - Standard verify is `\(standardVerifyCommand)`.
    - Coverage is collected after verify with `\(coverageCollectCommand)`.
    - Documentation-only README/docs slices may use a simple `grep -q` content
      check against the edited Markdown/text file instead of cargo.
    """

  static func isCompileOnlyVerify(_ verify: String) -> Bool {
    let normalized = verify.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }
    if normalized.contains(" test") || normalized.hasPrefix("test ")
      || normalized.contains("cargo test")
      || normalized.contains("cargo llvm-cov")
      || normalized.contains("clippy")
    {
      return false
    }
    return normalized.contains("cargo build") || normalized.contains("cargo check")
      || normalized.contains("cargo fmt")
  }

  static func verifyDeclaresCoverage(_ verify: String) -> Bool {
    let normalized = verify.lowercased()
    return normalized.contains("llvm-cov")
      || normalized.contains("cargo test")
      || normalized.contains(standardVerifyCommand.lowercased())
      || (normalized.contains("cargo fmt") && normalized.contains("clippy")
        && normalized.contains("cargo test"))
  }

  static func parseCoverageReport(output: String) -> CoverageSnapshot {
    CoverageSnapshotParser.parseLLVMCovReport(output)
  }
}

struct CoverageSnapshot: Codable, Equatable, Sendable {
  var collectedAt: Date
  var sessionNumber: Int?
  var overallLineCoveragePercent: Double?
  var files: [CoverageFileEntry]
  var rawSummary: String?

  func formattedForPrompt(maxFiles: Int = 12) -> String {
    guard !files.isEmpty || overallLineCoveragePercent != nil else {
      return "_(no coverage data collected yet - ensure verify enables coverage)_"
    }
    var lines: [String] = []
    if let overall = overallLineCoveragePercent {
      lines.append(String(format: "Overall line coverage: %.1f%%", overall))
    }
    let sorted = files.sorted {
      ($0.lineCoveragePercent ?? 100) < ($1.lineCoveragePercent ?? 100)
    }
    for entry in sorted.prefix(maxFiles) {
      if let pct = entry.lineCoveragePercent {
        lines.append(String(format: "- `%@`: %.1f%%", entry.path, pct))
      } else {
        lines.append("- `\(entry.path)`: _(no data)_")
      }
    }
    if sorted.count > maxFiles {
      lines.append("_(+\(sorted.count - maxFiles) more files)_")
    }
    return lines.joined(separator: "\n")
  }
}

struct CoverageFileEntry: Codable, Equatable, Sendable {
  var path: String
  var lineCoveragePercent: Double?
}

enum CoverageSnapshotStore {
  static func coverageSnapshotURL(in workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: "coverage-snapshot.json")
  }

  static func readCoverageSnapshot(from workspace: CompassWorkspace) -> CoverageSnapshot? {
    let url = coverageSnapshotURL(in: workspace)
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(CoverageSnapshot.self, from: data)
  }

  static func writeCoverageSnapshot(_ snapshot: CoverageSnapshot, workspace: CompassWorkspace)
    throws
  {
    let url = coverageSnapshotURL(in: workspace)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(snapshot).write(to: url, options: .atomic)
  }
}

enum CoverageSnapshotParser {
  static func parseLLVMCovReport(_ output: String) -> CoverageSnapshot {
    var files: [CoverageFileEntry] = []
    var totalPercent: Double?
    for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("TOTAL") || trimmed.lowercased().hasPrefix("total") {
        totalPercent = trailingPercent(in: trimmed) ?? totalPercent
        continue
      }
      let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
      guard parts.count >= 2, let last = parts.last, last.hasSuffix("%") else { continue }
      let path = String(parts[0])
      guard path.contains(".") || path.contains("/") else { continue }
      if let pct = Double(last.dropLast()) {
        files.append(CoverageFileEntry(path: path, lineCoveragePercent: pct))
      }
    }
    return CoverageSnapshot(
      collectedAt: Date(),
      sessionNumber: nil,
      overallLineCoveragePercent: totalPercent ?? averagePercent(files),
      files: files,
      rawSummary: String(output.prefix(4000))
    )
  }

  static func readJSONFile(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    return String(decoding: data, as: UTF8.self)
  }

  private static func trailingPercent(in line: String) -> Double? {
    guard let range = line.range(of: #"\d+(\.\d+)?%"#, options: .regularExpression) else {
      return nil
    }
    return Double(line[range].dropLast())
  }

  private static func averagePercent(_ files: [CoverageFileEntry]) -> Double? {
    let values = files.compactMap(\.lineCoveragePercent)
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
  }
}

enum GeneratedVerifyValidator {
  static func coverageViolation(verify: String) -> String? {
    let trimmed = verify.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if GeneratedProjectQuality.isCompileOnlyVerify(trimmed) { return nil }
    if GeneratedProjectQuality.verifyDeclaresCoverage(trimmed) { return nil }
    return """
      Verify command must collect test coverage for generated Rust projects. \
      \(GeneratedProjectQuality.coverageRequirementHint)
      """
  }
}

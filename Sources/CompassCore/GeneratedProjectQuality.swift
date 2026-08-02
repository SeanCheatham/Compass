import Foundation

/// Hardcoded quality conventions for Compass-generated projects.
///
/// Mutation testing (`mutationTestCommand`) runs post-verify, scoped to the Rust
/// files changed in the current iteration; results persist as a `MutationSnapshot`
/// in `.compass/mutation-snapshot.json` and feed the next Plan pass.
public enum GeneratedProjectQuality {
  public static let standardVerifyCommand =
    "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"

  public static let coverageCollectCommand = "cargo llvm-cov --workspace --summary-only"

  /// Post-verify mutation gate, scoped per iteration via `mutationTestCommand(forChangedFiles:)`.
  public static let mutationTestCommand = "cargo mutants --no-shuffle -j 1"

  /// Temporary host-side macOS gate (stand-in for a future macOS VM runner).
  public static let macosVerifyCommand = "bash scripts/verify-macos.sh"

  public static let coverageRequirementHint =
    "use `\(standardVerifyCommand)` for standard checks, or `cargo llvm-cov --workspace` / `cargo test --workspace` for test-focused slices. Documentation-only README/docs slices may use a simple `grep -q` content check."

  public static let planningGuidance = """
    Generated Compass projects require Rust `crates/core` plus at least one product:
    - `cli` → `crates/cli` (Cargo binary over core)
    - `macos` → `crates/ffi` (UniFFI) + `apps/macos` (thin SwiftUI shell)
    - Domain logic lives only in `crates/core`. CLI and macOS are adapters.
    - Prefer `cargo fmt`, Clippy (`-D warnings`), and `cargo test` for Rust verification.
    - Standard Rust verify is `\(standardVerifyCommand)`.
    - When the `macos` product is enabled, also run `\(macosVerifyCommand)` on the Mac host
      (temporary; will move to a macOS VM later). Do not expect Xcode inside the Linux container.
    - Coverage is collected after verify with `\(coverageCollectCommand)`.
    - Mutation testing runs post-verify scoped to changed Rust files; surviving
      mutants indicate weak tests and should drive test-strengthening work.
    - Documentation-only README/docs slices may use a simple `grep -q` content
      check against the edited Markdown/text file instead of cargo.
    """

  public static func planningGuidance(products: [GeneratedProduct]) -> String {
    let normalized = GeneratedProducts.normalize(products)
    let summary = GeneratedProducts.summary(normalized)
    var lines = """
      Generated Compass project products: `\(summary)` (required `crates/core` always present).
      - Domain logic lives only in `crates/core`. Product crates/apps are adapters.
      """
    if GeneratedProducts.contains(normalized, .cli) {
      lines += """
        - CLI product: `crates/cli` (binary + `crates/cli/tests`).
        """
    }
    if GeneratedProducts.contains(normalized, .macos) {
      lines += """
        - macOS product: `crates/ffi` (UniFFI over core) + `apps/macos` (SwiftUI only).
        - macOS verify (host today / VM later): `\(macosVerifyCommand)`.
        """
    }
    lines += """
      - Prefer `cargo fmt`, Clippy (`-D warnings`), and `cargo test` for Rust verification.
      - Standard Rust verify is `\(standardVerifyCommand)`.
      - Coverage is collected after verify with `\(coverageCollectCommand)`.
      - Mutation testing runs post-verify scoped to changed Rust files.
      - Documentation-only README/docs slices may use a simple `grep -q` content check.
      """
    return lines
  }

  public static func isCompileOnlyVerify(_ verify: String) -> Bool {
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

  public static func verifyDeclaresCoverage(_ verify: String) -> Bool {
    let normalized = verify.lowercased()
    return normalized.contains("llvm-cov")
      || normalized.contains("cargo test")
      || normalized.contains(standardVerifyCommand.lowercased())
      || (normalized.contains("cargo fmt") && normalized.contains("clippy")
        && normalized.contains("cargo test"))
  }

  public static func parseCoverageReport(output: String) -> CoverageSnapshot {
    CoverageSnapshotParser.parseLLVMCovReport(output)
  }
}

public struct CoverageSnapshot: Codable, Equatable, Sendable {
  public var collectedAt: Date
  public var sessionNumber: Int?
  public var overallLineCoveragePercent: Double?
  public var files: [CoverageFileEntry]
  public var rawSummary: String?

  public func formattedForPrompt(maxFiles: Int = 12) -> String {
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

public struct CoverageFileEntry: Codable, Equatable, Sendable {
  public var path: String
  public var lineCoveragePercent: Double?
}

public enum CoverageSnapshotStore {
  public static func coverageSnapshotURL(in workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: "coverage-snapshot.json")
  }

  public static func readCoverageSnapshot(from workspace: CompassWorkspace) -> CoverageSnapshot? {
    let url = coverageSnapshotURL(in: workspace)
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(CoverageSnapshot.self, from: data)
  }

  public static func writeCoverageSnapshot(_ snapshot: CoverageSnapshot, workspace: CompassWorkspace)
    throws
  {
    let url = coverageSnapshotURL(in: workspace)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(snapshot).write(to: url, options: .atomic)
  }
}

public enum CoverageSnapshotParser {
  public static func parseLLVMCovReport(_ output: String) -> CoverageSnapshot {
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

  public static func readJSONFile(_ url: URL) -> String? {
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

public enum GeneratedVerifyValidator {
  public static func coverageViolation(verify: String) -> String? {
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

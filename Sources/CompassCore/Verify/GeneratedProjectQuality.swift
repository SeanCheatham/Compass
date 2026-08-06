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

  /// macOS product gate. Runs inside the embedded macOS VM when available,
  /// falling back to the host shell (see `MacOSVerifyGate`).
  public static let macosVerifyCommand = "bash scripts/verify-macos.sh"

  /// Host/guest env var that enables headed launch + screenshot during macOS verify.
  /// Primary UI proof is `crates/ui` simulation under `cargo test` (see `docs/ui-runtime.md`).
  public static let macosUIFidelityEnvironmentKey = "COMPASS_MACOS_UI_FIDELITY"

  public static let coverageRequirementHint =
    "use `\(standardVerifyCommand)` for standard checks, or `cargo llvm-cov --workspace` / `cargo test --workspace` for test-focused slices. Documentation-only README/docs slices may use a simple `grep -q` content check."

  public static let planningGuidance = """
    Generated Compass projects require Rust `crates/core` plus at least one product:
    - `cli` → `crates/cli` (Cargo binary over core)
    - `macos` → `crates/ui` (ViewState/simulation/guardrails) + `crates/ffi` (UniFFI) + `apps/macos` (dumb SwiftUI binder)
    - Domain logic lives only in `crates/core`. UI policy lives in `crates/ui`. CLI and macOS are adapters.
    - Prefer `cargo fmt`, Clippy (`-D warnings`), and `cargo test` for Rust verification (UI simulation included).
    - Standard Rust verify is `\(standardVerifyCommand)`.
    - When the `macos` product is enabled, also run `\(macosVerifyCommand)`; it executes
      inside the embedded macOS VM. Headed launch/screenshot is opt-in via `\(macosUIFidelityEnvironmentKey)=1`.
    - Coverage is collected after verify with `\(coverageCollectCommand)`.
    - Mutation testing runs post-verify scoped to changed Rust files; surviving
      mutants indicate weak tests and should drive test-strengthening work.
      Greeting-scaffold survivors are excluded from Plan pressure until cleanup.
    - macOS adapter verify uses `FFIChecks` (`swift run`), not XCTest/`swift test`.
    - Documentation-only README/docs slices may use a simple `grep -q` content
      check against the edited Markdown/text file instead of cargo.
    """

  public static func planningGuidance(products: [GeneratedProduct]) -> String {
    let normalized = GeneratedProducts.normalize(products)
    let summary = GeneratedProducts.summary(normalized)
    var lines = """
      Generated Compass project products: `\(summary)` (required `crates/core` always present).
      - Domain logic lives only in `crates/core`. UI policy lives in `crates/ui` when macOS is enabled.
      - Product crates/apps are adapters (CLI binary, UniFFI, SwiftUI binder).
      """
    if GeneratedProducts.contains(normalized, .cli) {
      lines += """
        - CLI product: `crates/cli` (binary + `crates/cli/tests`).
        """
    }
    if GeneratedProducts.contains(normalized, .macos) {
      lines += """
        - macOS product: `crates/ui` + `crates/ffi` (UniFFI) + `apps/macos` (SwiftUI binder only).
        - UI proof: simulation/guardrails in `crates/ui` via `cargo test`; macOS adapter verify: `\(macosVerifyCommand)`.
        - Occasional headed fidelity: `\(macosUIFidelityEnvironmentKey)=1` (launch + screenshot).
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

  public static func writeCoverageSnapshot(
    _ snapshot: CoverageSnapshot, workspace: CompassWorkspace
  )
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

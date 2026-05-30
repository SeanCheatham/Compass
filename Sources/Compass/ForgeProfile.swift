import Foundation

/// Opinionated project shapes Compass supports in generated and guided repos.
/// Each profile defines canonical verify/coverage expectations the factory
/// enforces in prompts, plan validation, and post-check collection.
enum ForgeProfile: String, Codable, CaseIterable, Equatable, Sendable {
  case swiftSPM = "swift-spm"
  case goModule = "go-module"
  case rustCargo = "rust-cargo"
  case typeScriptVitest = "ts-vitest"

  var displayName: String {
    switch self {
    case .swiftSPM: return "Swift (SwiftPM)"
    case .goModule: return "Go (module)"
    case .rustCargo: return "Rust (Cargo)"
    case .typeScriptVitest: return "TypeScript (Vitest + pnpm)"
    }
  }

  /// Planning guidance injected into Plan prompts for this profile.
  var planningGuidance: String {
    switch self {
    case .swiftSPM:
      return """
        Forge profile — Swift (SwiftPM):
        - Use SwiftPM only (`Package.swift`, `Sources/`, `Tests/`). Prefer Swift Testing over XCTest for new tests.
        - In the Shared VM, Swift/macOS build and test must run on the host (see execution environment):
          plan `requiresHostXcode: true` with `xcodebuild ... test` (package workspace when needed), use
          `host_xcode` during Develop, and do not plan guest `swift test` verify.
        - When host Xcode is enabled, test verify uses `xcodebuild ... test` with coverage collected host-side;
          compile-only increments may still use guest `swift build` when probing is unnecessary.
        - Compass collects line coverage from the `.profdata` artifact after verify passes.
        """
    case .goModule:
      return """
        Forge profile — Go (module):
        - Standard module layout with `go.mod` at the repo root.
        - Verify for test increments must include coverage collection, e.g. \
        `go test -coverprofile=.compass/coverage.out ./...` (scope `./path/...` when needed).
        - Build-only increments may use `go build ./...` without coverage.
        """
    case .rustCargo:
      return """
        Forge profile — Rust (Cargo):
        - Standard Cargo workspace/crate layout with `Cargo.toml`.
        - Verify for test increments should use `cargo llvm-cov --summary-only` or \
        `cargo llvm-cov test --summary-only` (requires `cargo-llvm-cov` in the project or VM).
        - Check-only increments may use `cargo check` or `cargo build` without coverage.
        """
    case .typeScriptVitest:
      return """
        Forge profile — TypeScript (Vitest + pnpm):
        - Use pnpm as the package manager and Vitest as the sole test runner.
        - Verify for test increments must run Vitest with coverage, e.g. \
        `pnpm test -- --coverage --coverage.reporter=json-summary`.
        - Build-only increments may use `pnpm build` without coverage.
        - TypeScript strict mode is expected; do not add parallel Jest/Mocha setups.
        """
    }
  }

  /// Short hint shown when Plan returns a verify command missing coverage.
  var coverageRequirementHint: String {
    switch self {
    case .swiftSPM:
      return """
        test verify must declare coverage: guest `swift test --enable-code-coverage`, or host \
        `xcodebuild ... test` with `requiresHostXcode: true` (Compass collects coverage host-side after verify).
        """
    case .goModule:
      return
        "test verify commands must include `-coverprofile=.compass/coverage.out` (e.g. `go test -coverprofile=.compass/coverage.out ./...`)."
    case .rustCargo:
      return "test verify commands must use `cargo llvm-cov` with summary or json output."
    case .typeScriptVitest:
      return
        "test verify commands must include Vitest coverage (e.g. `pnpm test -- --coverage --coverage.reporter=json-summary`)."
    }
  }

  /// Shell command Compass runs after a successful verify to collect/refresh
  /// coverage artifacts. May re-run tests when verify was compile-only.
  func coverageCollectCommand() -> String {
    switch self {
    case .swiftSPM:
      return """
        set -e
        PROFDATA="$(find .build -name '*.profdata' -path '*/codecov/*' 2>/dev/null | head -1)"
        if [ -z "$PROFDATA" ]; then
          PROFDATA="$(find .build -name '*.profdata' 2>/dev/null | head -1)"
        fi
        if [ -z "$PROFDATA" ]; then
          echo "compass-coverage: no .profdata found; run verify with --enable-code-coverage"
          exit 0
        fi
        BIN="$(find .build -type f -perm +111 -name '*PackageTests' 2>/dev/null | head -1)"
        if [ -z "$BIN" ]; then
          BIN="$(find .build -type f -perm +111 -path '*xctest/*' 2>/dev/null | head -1)"
        fi
        if [ -n "$BIN" ]; then
          xcrun llvm-cov report "$BIN" -instr-profile="$PROFDATA" 2>/dev/null || llvm-cov report "$BIN" -instr-profile="$PROFDATA"
        else
          xcrun llvm-cov report -instr-profile="$PROFDATA" 2>/dev/null || llvm-cov report -instr-profile="$PROFDATA"
        fi
        """
    case .goModule:
      return """
        if [ -f .compass/coverage.out ]; then
          go tool cover -func=.compass/coverage.out
        else
          go test -coverprofile=.compass/coverage.out ./... && go tool cover -func=.compass/coverage.out
        fi
        """
    case .rustCargo:
      return "cargo llvm-cov --summary-only 2>/dev/null || cargo llvm-cov test --summary-only"
    case .typeScriptVitest:
      return """
        if [ -f coverage/coverage-summary.json ]; then
          cat coverage/coverage-summary.json
        elif [ -f coverage/coverage-final.json ]; then
          cat coverage/coverage-final.json
        else
          pnpm test -- --coverage --coverage.reporter=json-summary --run 2>/dev/null || \
          pnpm exec vitest run --coverage --coverage.reporter=json-summary
        fi
        """
    }
  }

  /// True when the verify command is build/check-only and coverage is not required.
  func isCompileOnlyVerify(_ verify: String) -> Bool {
    let normalized = verify.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }
    if normalized.contains(" test") || normalized.hasPrefix("test ")
      || normalized.contains("pnpm test")
      || normalized.contains("vitest") || normalized.contains("cargo test")
      || normalized.contains("go test")
      || normalized.contains("swift test")
      || normalized.contains("xcodebuild") && normalized.contains(" test")
    {
      return false
    }
    switch self {
    case .swiftSPM:
      return normalized.contains("swift build") || normalized == "swift build"
    case .goModule:
      return normalized.contains("go build") && !normalized.contains("go test")
    case .rustCargo:
      return normalized.contains("cargo check")
        || (normalized.contains("cargo build")
          && !normalized.contains("cargo test"))
    case .typeScriptVitest:
      return normalized.contains("pnpm build") || normalized.contains("tsc ")
    }
  }

  /// True when a test verify command declares coverage collection.
  func verifyDeclaresCoverage(_ verify: String) -> Bool {
    let normalized = verify.lowercased()
    switch self {
    case .swiftSPM:
      return normalized.contains("--enable-code-coverage")
        || normalized.contains("llvm-cov")
        || (normalized.contains("xcodebuild") && normalized.contains(" test"))
    case .goModule:
      return normalized.contains("-coverprofile") || normalized.contains("covermode")
    case .rustCargo:
      return normalized.contains("llvm-cov") || normalized.contains("-Cinstrument-coverage")
    case .typeScriptVitest:
      return normalized.contains("coverage")
    }
  }

  func parseCoverageReport(output: String, workingDirectory: URL) -> CoverageSnapshot {
    switch self {
    case .swiftSPM:
      return CoverageSnapshotParser.parseLLVMCovReport(output, profile: self)
    case .goModule:
      if let fromFile = CoverageSnapshotParser.parseGoCoverFuncFromFile(
        workingDirectory.appending(path: ".compass/coverage.out"),
        profile: self
      ) {
        return fromFile
      }
      return CoverageSnapshotParser.parseGoCoverFunc(output, profile: self)
    case .rustCargo:
      return CoverageSnapshotParser.parseRustLLVMCovSummary(output, profile: self)
    case .typeScriptVitest:
      if let json = CoverageSnapshotParser.readJSONFile(
        workingDirectory.appending(path: "coverage/coverage-summary.json")
      ) {
        return CoverageSnapshotParser.parseVitestSummaryJSON(json, profile: self)
      }
      return CoverageSnapshotParser.parseVitestSummaryJSON(output, profile: self)
    }
  }
}

/// Persisted `.compass/forge-profile.json` shape.
struct ForgeProfileRecord: Codable, Equatable, Sendable {
  var profile: ForgeProfile
  var version: Int

  static let currentVersion = 1
}

/// Per-file and overall coverage Compass collected after verify.
struct CoverageSnapshot: Codable, Equatable, Sendable {
  var profile: ForgeProfile
  var collectedAt: Date
  var sessionNumber: Int?
  var overallLineCoveragePercent: Double?
  var files: [CoverageFileEntry]
  var rawSummary: String?

  func formattedForPrompt(maxFiles: Int = 12) -> String {
    guard !files.isEmpty || overallLineCoveragePercent != nil else {
      return
        "_(no coverage data collected yet — ensure verify enables coverage for this forge profile)_"
    }
    var lines: [String] = []
    if let overall = overallLineCoveragePercent {
      lines.append(String(format: "Overall line coverage: %.1f%%", overall))
    }
    let sorted = files.sorted {
      ($0.lineCoveragePercent ?? 100) < ($1.lineCoveragePercent ?? 100)
    }
    let lowest = sorted.prefix(maxFiles)
    if !lowest.isEmpty {
      lines.append("Lowest-coverage source files:")
      for entry in lowest {
        if let pct = entry.lineCoveragePercent {
          lines.append(String(format: "- `%@`: %.1f%%", entry.path, pct))
        } else {
          lines.append("- `\(entry.path)`: _(no data)_")
        }
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

enum ForgeProfileService {
  static func forgeProfileURL(in workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: "forge-profile.json")
  }

  static func coverageSnapshotURL(in workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: "coverage-snapshot.json")
  }

  /// Resolve the active forge profile: explicit record wins, then auto-detect.
  static func resolve(repoURL: URL, workspace: CompassWorkspace?) -> ForgeProfile? {
    if let workspace,
      let record = readRecord(from: workspace)
    {
      return record.profile
    }
    return detect(in: repoURL)
  }

  static func readRecord(from workspace: CompassWorkspace) -> ForgeProfileRecord? {
    let url = forgeProfileURL(in: workspace)
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    return try? JSONDecoder().decode(ForgeProfileRecord.self, from: data)
  }

  static func writeRecord(_ record: ForgeProfileRecord, workspace: CompassWorkspace) throws {
    let url = forgeProfileURL(in: workspace)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(record)
    try data.write(to: url, options: .atomic)
  }

  /// Auto-detect from repo manifests and persist when a workspace is provided.
  static func detectAndPersist(repoURL: URL, workspace: CompassWorkspace) throws -> ForgeProfile? {
    if let existing = readRecord(from: workspace) {
      return existing.profile
    }
    guard let detected = detect(in: repoURL) else { return nil }
    try writeRecord(
      ForgeProfileRecord(profile: detected, version: ForgeProfileRecord.currentVersion),
      workspace: workspace
    )
    return detected
  }

  /// Repos whose factory loops need full Xcode on the host mirror, not CLT in the guest.
  static func prefersHostXcodeBridge(in repoURL: URL) -> Bool {
    let fm = FileManager.default
    let root = repoURL.standardizedFileURL
    if fm.fileExists(atPath: root.appending(path: "Package.swift").path) {
      return true
    }
    if hasXcodeProjectBundle(in: root, fileManager: fm) {
      return true
    }
    return false
  }

  private static func hasXcodeProjectBundle(
    in root: URL,
    fileManager: FileManager
  ) -> Bool {
    guard
      let children = try? fileManager.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
      )
    else {
      return false
    }
    return children.contains { url in
      let ext = url.pathExtension.lowercased()
      return ext == "xcodeproj" || ext == "xcworkspace"
    }
  }

  static func detect(in repoURL: URL) -> ForgeProfile? {
    let fm = FileManager.default
    let root = repoURL.standardizedFileURL
    if fm.fileExists(atPath: root.appending(path: "Package.swift").path) {
      return .swiftSPM
    }
    if fm.fileExists(atPath: root.appending(path: "go.mod").path) {
      return .goModule
    }
    if fm.fileExists(atPath: root.appending(path: "Cargo.toml").path) {
      return .rustCargo
    }
    if fm.fileExists(atPath: root.appending(path: "package.json").path) {
      return .typeScriptVitest
    }
    return nil
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
    let data = try encoder.encode(snapshot)
    try data.write(to: url, options: .atomic)
  }
}

enum CoverageSnapshotParser {
  static func parseLLVMCovReport(_ output: String, profile: ForgeProfile) -> CoverageSnapshot {
    var files: [CoverageFileEntry] = []
    var totalPercent: Double?
    for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("TOTAL") || trimmed.lowercased().hasPrefix("total") {
        if let pct = trailingPercent(in: trimmed) {
          totalPercent = pct
        }
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
      profile: profile,
      collectedAt: Date(),
      sessionNumber: nil,
      overallLineCoveragePercent: totalPercent ?? averagePercent(files),
      files: files,
      rawSummary: String(output.prefix(4000))
    )
  }

  static func parseGoCoverFunc(_ output: String, profile: ForgeProfile) -> CoverageSnapshot {
    var files: [CoverageFileEntry] = []
    var totalPercent: Double?
    for line in output.split(separator: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("total:") {
        totalPercent = trailingPercent(in: trimmed)
        continue
      }
      guard trimmed.contains(".go:"), let pct = trailingPercent(in: trimmed) else { continue }
      let path =
        trimmed.split(separator: "\t").first.map(String.init)
        ?? trimmed.split(separator: " ").first.map(String.init) ?? trimmed
      let cleanPath = path.split(separator: ":").first.map(String.init) ?? path
      if !files.contains(where: { $0.path == cleanPath }) {
        files.append(CoverageFileEntry(path: cleanPath, lineCoveragePercent: pct))
      }
    }
    return CoverageSnapshot(
      profile: profile,
      collectedAt: Date(),
      sessionNumber: nil,
      overallLineCoveragePercent: totalPercent ?? averagePercent(files),
      files: files,
      rawSummary: String(output.prefix(4000))
    )
  }

  static func parseGoCoverFuncFromFile(_ coverageOut: URL, profile: ForgeProfile)
    -> CoverageSnapshot?
  {
    guard FileManager.default.fileExists(atPath: coverageOut.path) else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["go", "tool", "cover", "-func=\(coverageOut.path)"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return nil }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(decoding: data, as: UTF8.self)
      return parseGoCoverFunc(output, profile: profile)
    } catch {
      return nil
    }
  }

  static func parseRustLLVMCovSummary(_ output: String, profile: ForgeProfile) -> CoverageSnapshot {
    var files: [CoverageFileEntry] = []
    var totalPercent: Double?
    for line in output.split(separator: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.lowercased().contains("total") || trimmed.hasPrefix("TOTAL") {
        totalPercent = trailingPercent(in: trimmed)
        continue
      }
      if trimmed.hasSuffix("%"), trimmed.contains(".rs") {
        let path =
          trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? trimmed
        if let pct = trailingPercent(in: trimmed) {
          files.append(CoverageFileEntry(path: path, lineCoveragePercent: pct))
        }
      }
    }
    return CoverageSnapshot(
      profile: profile,
      collectedAt: Date(),
      sessionNumber: nil,
      overallLineCoveragePercent: totalPercent ?? averagePercent(files),
      files: files,
      rawSummary: String(output.prefix(4000))
    )
  }

  static func parseVitestSummaryJSON(_ input: String, profile: ForgeProfile) -> CoverageSnapshot {
    guard let data = input.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return CoverageSnapshot(
        profile: profile, collectedAt: Date(), sessionNumber: nil,
        overallLineCoveragePercent: nil, files: [], rawSummary: String(input.prefix(2000)))
    }
    return parseVitestSummaryJSONObject(json, profile: profile)
  }

  static func parseVitestSummaryJSONObject(
    _ json: [String: Any], profile: ForgeProfile
  ) -> CoverageSnapshot {
    var files: [CoverageFileEntry] = []
    var totalPercent: Double?
    if let total = json["total"] as? [String: Any],
      let lines = total["lines"] as? [String: Any],
      let pct = lines["pct"] as? Double
    {
      totalPercent = pct
    }
    for (key, value) in json {
      guard key != "total", let entry = value as? [String: Any],
        let lines = entry["lines"] as? [String: Any],
        let pct = lines["pct"] as? Double
      else { continue }
      files.append(CoverageFileEntry(path: key, lineCoveragePercent: pct))
    }
    return CoverageSnapshot(
      profile: profile,
      collectedAt: Date(),
      sessionNumber: nil,
      overallLineCoveragePercent: totalPercent ?? averagePercent(files),
      files: files,
      rawSummary: nil
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
    let match = line[range].dropLast()
    return Double(match)
  }

  private static func averagePercent(_ files: [CoverageFileEntry]) -> Double? {
    let values = files.compactMap(\.lineCoveragePercent)
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
  }
}

enum ForgeVerifyValidator {
  /// Returns an error message when verify violates profile coverage rules.
  static func coverageViolation(verify: String, profile: ForgeProfile?) -> String? {
    guard let profile else { return nil }
    let trimmed = verify.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if profile.isCompileOnlyVerify(trimmed) { return nil }
    if profile.verifyDeclaresCoverage(trimmed) { return nil }
    return """
      Verify command must collect test coverage for \(profile.displayName) projects. \
      \(profile.coverageRequirementHint)
      """
  }
}

import Foundation

enum ForgeProfile: String, Codable, CaseIterable, Equatable, Sendable {
  case swiftSPM = "swift-spm"
  case typeScriptPnpmVite = "typescript-pnpm-vite"
  case tesseraApp = "tessera-app"

  static let generatedProjectDefault: ForgeProfile = .tesseraApp
  static let generatedProjectTargets: [ForgeProfile] = [.tesseraApp]

  var displayName: String {
    switch self {
    case .swiftSPM: return "Imported Swift (SwiftPM)"
    case .typeScriptPnpmVite: return "TypeScript (pnpm + Vite + Vitest)"
    case .tesseraApp: return "Tessera App"
    }
  }

  var isGeneratedProjectTarget: Bool {
    Self.generatedProjectTargets.contains(self)
  }

  var generationStatusDescription: String {
    switch self {
    case .swiftSPM:
      return "imported-repo profile; Compass-generated output is Tessera"
    case .typeScriptPnpmVite:
      return "imported/generated legacy TypeScript profile"
    case .tesseraApp:
      return "default generated-project target"
    }
  }

  var planningGuidance: String {
    switch self {
    case .swiftSPM:
      return """
        Imported Swift profile:
        - This is for maintaining the Compass host or user-owned Swift packages.
        - Do not create new generated output in Swift; generated projects use Tessera.
        - Prefer SwiftPM verification with `swift test` for package work.
        """
    case .typeScriptPnpmVite:
      return """
        Forge profile - TypeScript (pnpm + Vite + Vitest):
        - Compass-generated project code must be TypeScript.
        - Use the pnpm workspace layout: root package scripts plus `packages/core`,
          `packages/cli`, and `packages/web`.
        - Keep TypeScript strict, use Vitest for tests and coverage, `tsx` for CLI/dev scripts,
          and Vite + React for web UI.
        - Standard verify is `pnpm verify`; targeted test work may use
          `pnpm test -- --coverage`.
        - Documentation-only README/docs slices may use a simple `grep -q` content
          check against the edited Markdown/text file instead of pnpm.
        """
    case .tesseraApp:
      return """
        Forge profile - Tessera App:
        - Compass-generated project code must be Tessera source in `src/*.tes`.
        - Use `tessera.json` for named app entrypoints, `contexts/*.json` for host input,
          and `tests/*.json` for deterministic examples.
        - Keep Tessera changes expression-oriented, typed, and small-model friendly.
        - Standard verify is `tessera verify . --json`; focused entrypoint checks may use
          `tessera app <entrypoint> --json`.
        - The `web` entrypoint is `web-json` until Tessera grows a full UI runtime.
        """
    }
  }

  var coverageRequirementHint: String {
    switch self {
    case .swiftSPM:
      return "test verify should declare SwiftPM coverage, e.g. `swift test --enable-code-coverage`."
    case .typeScriptPnpmVite:
      return "use `pnpm verify` for standard checks, include Vitest coverage for test-only checks, e.g. `pnpm test -- --coverage`, or use a simple `grep -q` content check for documentation-only README/docs slices."
    case .tesseraApp:
      return "use `tessera verify . --json` so Compass can read the Tessera trace report for exercised `.tes` sources."
    }
  }

  var standardVerifyCommand: String {
    switch self {
    case .swiftSPM:
      return "swift test --enable-code-coverage"
    case .typeScriptPnpmVite:
      return "pnpm verify"
    case .tesseraApp:
      return "tessera verify . --json"
    }
  }

  func coverageCollectCommand() -> String {
    switch self {
    case .swiftSPM:
      return """
        set -e
        PROFDATA="$(find .build -name '*.profdata' 2>/dev/null | head -1)"
        if [ -z "$PROFDATA" ]; then
          echo "compass-coverage: no .profdata found; run verify with --enable-code-coverage"
          exit 0
        fi
        BIN="$(find .build -type f -perm +111 -name '*PackageTests' 2>/dev/null | head -1)"
        if [ -n "$BIN" ]; then
          xcrun llvm-cov report "$BIN" -instr-profile="$PROFDATA" 2>/dev/null || true
        fi
        """
    case .typeScriptPnpmVite:
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
    case .tesseraApp:
      return "tessera verify . --json"
    }
  }

  func isCompileOnlyVerify(_ verify: String) -> Bool {
    let normalized = verify.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }
    if normalized.contains(" test") || normalized.hasPrefix("test ")
      || normalized.contains("pnpm test")
      || normalized.contains("vitest")
      || normalized.contains("swift test")
      || (normalized.contains("xcodebuild") && normalized.contains(" test"))
    {
      return false
    }
    switch self {
    case .swiftSPM:
      return normalized.contains("swift build") || normalized == "swift build"
    case .typeScriptPnpmVite:
      return normalized.contains("pnpm build") || normalized.contains("pnpm typecheck")
        || normalized.contains("tsc ")
    case .tesseraApp:
      return normalized.contains("tessera validate") || normalized.contains("tessera fmt --check")
    }
  }

  func verifyDeclaresCoverage(_ verify: String) -> Bool {
    let normalized = verify.lowercased()
    switch self {
    case .swiftSPM:
      return normalized.contains("--enable-code-coverage") || normalized.contains("llvm-cov")
    case .typeScriptPnpmVite:
      return normalized.contains("coverage")
        || normalized.contains("pnpm verify")
        || normalized.contains("pnpm run verify")
    case .tesseraApp:
      return normalized.contains("tessera verify") && normalized.contains("--json")
    }
  }

  func parseCoverageReport(output: String, workingDirectory: URL) -> CoverageSnapshot {
    switch self {
    case .swiftSPM:
      return CoverageSnapshotParser.parseLLVMCovReport(output, profile: self)
    case .typeScriptPnpmVite:
      if let json = CoverageSnapshotParser.readJSONFile(
        workingDirectory.appending(path: "coverage/coverage-summary.json")
      ) {
        return CoverageSnapshotParser.parseVitestSummaryJSON(json, profile: self)
      }
      return CoverageSnapshotParser.parseVitestSummaryJSON(output, profile: self)
    case .tesseraApp:
      return CoverageSnapshotParser.parseTesseraTraceJSON(output, profile: self)
    }
  }
}

struct ForgeProfileRecord: Codable, Equatable, Sendable {
  var profile: ForgeProfile
  var version: Int

  static let currentVersion = 1
}

struct CoverageSnapshot: Codable, Equatable, Sendable {
  var profile: ForgeProfile
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

enum ForgeProfileService {
  static func forgeProfileURL(in workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: "forge-profile.json")
  }

  static func coverageSnapshotURL(in workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: "coverage-snapshot.json")
  }

  static func resolve(repoURL: URL, workspace: CompassWorkspace?) -> ForgeProfile? {
    if let workspace, let record = readRecord(from: workspace) {
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
    try encoder.encode(record).write(to: url, options: .atomic)
  }

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

  static func detect(in repoURL: URL) -> ForgeProfile? {
    let root = repoURL.standardizedFileURL
    let fm = FileManager.default
    if TesseraProjectScaffold.isGeneratedWorkspace(at: root)
      || fm.fileExists(atPath: root.appending(path: "tessera.json").path)
    {
      return .tesseraApp
    }
    if TypeScriptProjectScaffold.isGeneratedWorkspace(at: root) {
      return .typeScriptPnpmVite
    }
    if fm.fileExists(atPath: root.appending(path: "package.json").path) {
      return .typeScriptPnpmVite
    }
    if fm.fileExists(atPath: root.appending(path: "Package.swift").path) {
      return .swiftSPM
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
    try encoder.encode(snapshot).write(to: url, options: .atomic)
  }
}

enum CoverageSnapshotParser {
  static func parseLLVMCovReport(_ output: String, profile: ForgeProfile) -> CoverageSnapshot {
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
        profile: profile,
        collectedAt: Date(),
        sessionNumber: nil,
        overallLineCoveragePercent: nil,
        files: [],
        rawSummary: String(input.prefix(2000))
      )
    }
    return parseVitestSummaryJSONObject(json, profile: profile)
  }

  static func parseVitestSummaryJSONObject(
    _ json: [String: Any],
    profile: ForgeProfile
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
      guard key != "total",
        let entry = value as? [String: Any],
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

  static func parseTesseraTraceJSON(_ input: String, profile: ForgeProfile) -> CoverageSnapshot {
    guard let data = input.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let trace = json["trace"] as? [String: Any]
    else {
      return CoverageSnapshot(
        profile: profile,
        collectedAt: Date(),
        sessionNumber: nil,
        overallLineCoveragePercent: nil,
        files: [],
        rawSummary: String(input.prefix(2000))
      )
    }
    let sourceCount = trace["source_count"] as? Double
      ?? (trace["source_count"] as? Int).map(Double.init)
      ?? 0
    let coveredCount = trace["covered_source_count"] as? Double
      ?? (trace["covered_source_count"] as? Int).map(Double.init)
      ?? 0
    let covered = trace["covered_sources"] as? [String] ?? []
    let uncovered = trace["uncovered_sources"] as? [String] ?? []
    let files =
      covered.map { CoverageFileEntry(path: $0, lineCoveragePercent: 100) }
      + uncovered.map { CoverageFileEntry(path: $0, lineCoveragePercent: 0) }
    let percent = sourceCount > 0 ? (coveredCount / sourceCount) * 100 : nil
    return CoverageSnapshot(
      profile: profile,
      collectedAt: Date(),
      sessionNumber: nil,
      overallLineCoveragePercent: percent,
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
    return Double(line[range].dropLast())
  }

  private static func averagePercent(_ files: [CoverageFileEntry]) -> Double? {
    let values = files.compactMap(\.lineCoveragePercent)
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
  }
}

enum ForgeVerifyValidator {
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

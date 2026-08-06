import Foundation

public enum SuccessfulVerifyGates {
  public struct Finding: Equatable, Sendable {
    public var issue: String
    public var retryKind: String

    public init(issue: String, retryKind: String) {
      self.issue = issue
      self.retryKind = retryKind
    }
  }

  private struct CoverageTableRow {
    let path: String
    let statements: Double?
    let functions: Double?
    let lines: Double?
  }

  private struct CoverageGap {
    let changedPath: String
    let coverageLine: String
    let testTargetLines: [String]
  }

  private struct PackageEntryPointIssue {
    let manifestPath: String
    let field: String
    let declaredPath: String
    let targetPath: String
  }

  /// Evaluates gates in the same order as Headless today. Returns first finding or nil.
  public static func firstFinding(
    immediate: PlanNext,
    brief: PlanStrategicContext,
    command: String,
    verifyOutput: String,
    changedPaths: [String]?,
    repoURL: URL
  ) -> Finding? {
    guard let changedPaths else { return nil }
    if let issue = coverageIssue(
      command: command, output: verifyOutput, changedPaths: changedPaths, repoURL: repoURL
    ) {
      return Finding(issue: issue, retryKind: "coverage_gap")
    }
    if let issue = missingRequiredTestIssue(
      immediate: immediate, brief: brief, command: command, changedPaths: changedPaths
    ) {
      return Finding(issue: issue, retryKind: "missing_required_tests")
    }
    if let issue = weakCLIFlagTestIssue(
      immediate: immediate, brief: brief, command: command, changedPaths: changedPaths,
      repoURL: repoURL
    ) {
      return Finding(issue: issue, retryKind: "weak_cli_flag_tests")
    }
    if let issue = weakCLIBinaryInvocationIssue(
      command: command, changedPaths: changedPaths, repoURL: repoURL
    ) {
      return Finding(issue: issue, retryKind: "weak_cli_acceptance_tests")
    }
    if let issue = weakServerEndpointTestIssue(
      command: command, changedPaths: changedPaths, repoURL: repoURL
    ) {
      return Finding(issue: issue, retryKind: "weak_server_endpoint_tests")
    }
    if let issue = missingPackageEntryIssue(
      command: command, changedPaths: changedPaths, repoURL: repoURL
    ) {
      return Finding(issue: issue, retryKind: "missing_package_entry")
    }
    if let issue = manifestOnlyImplementationIssue(
      immediate: immediate, brief: brief, command: command, changedPaths: changedPaths
    ) {
      return Finding(issue: issue, retryKind: "metadata_only_implementation")
    }
    return nil
  }

  private static func coverageIssue(
    command: String, output: String, changedPaths: [String], repoURL: URL
  ) -> String? {
    let rows = vitestCoverageRows(in: output)
    guard !rows.isEmpty else { return nil }
    let changedSourcePaths = changedPaths.filter(isCoverageGatedSourcePath)
    guard !changedSourcePaths.isEmpty else { return nil }
    let gaps = changedSourcePaths.compactMap { changedPath -> CoverageGap? in
      guard let row = rows.first(where: { coveragePath($0.path, matchesChangedPath: changedPath) }),
        row.statements == 0 || row.functions == 0 || row.lines == 0
      else { return nil }
      let coverageDisplayPath =
        row.path == changedPath ? row.path : "\(changedPath) (reported as \(row.path))"
      return CoverageGap(
        changedPath: changedPath,
        coverageLine:
          "- \(coverageDisplayPath): statements \(percentLabel(row.statements)), functions \(percentLabel(row.functions)), lines \(percentLabel(row.lines))",
        testTargetLines: coverageRepairTestTargetLines(for: changedPath, repoURL: repoURL)
      )
    }
    guard !gaps.isEmpty else { return nil }
    let targetLines = gaps.flatMap(\.testTargetLines)
    let testTargetSection =
      targetLines.isEmpty
      ? ""
      : """

      Suggested test targets:
      \(targetLines.joined(separator: "\n"))
      """
    let sourceList = gaps.map { "`\($0.changedPath)`" }.joined(separator: ", ")
    return """
      Verify passed for `\(command)`, but coverage shows changed source files were not exercised:
      \(gaps.map(\.coverageLine).joined(separator: "\n"))

      Coverage repair instructions:
      - Your next Develop action should be test-focused, not another source-only inspection.
      - Add or update a test that imports and executes \(sourceList).
      - Do not edit those source files merely to say no changes were needed; the problem is
        missing execution evidence, not a source formatting issue.
      - If an existing sibling or package test file is listed below, read it and edit it.
        Otherwise create a `tests/*.rs` integration test or a `#[cfg(test)]` module.
      \(testTargetSection)

      A green verify is not enough when new or changed source has 0% coverage. Add or update tests that import and execute these changed files, wire the new code into the planned behavior when needed, then rerun `\(command)`.
      """
  }

  private static func missingRequiredTestIssue(
    immediate: PlanNext, brief: PlanStrategicContext, command: String, changedPaths: [String]
  ) -> String? {
    let changedSourcePaths = changedPaths.filter(isCoverageGatedSourcePath)
    guard !changedSourcePaths.isEmpty, !changedPaths.contains(where: isTestPath) else { return nil }
    let requestedTestPaths = mentionedTestPaths(in: handoffText(immediate: immediate, brief: brief))
    guard !requestedTestPaths.isEmpty else { return nil }
    return """
      Verify passed for `\(command)`, but the accepted plan or brief explicitly requires test changes and no test/spec file changed.

      Requested test file(s):
      \(requestedTestPaths.map { "- `\($0)`" }.joined(separator: "\n"))

      Changed source file(s) without a matching test edit:
      \(changedSourcePaths.map { "- `\($0)`" }.joined(separator: "\n"))

      Missing required test instructions:
      - Your next Develop action should update one of the requested test files before submitting success.
      - Add assertions for the new behavior named in the plan or brief, then rerun `\(command)`.
      - Do not rely on a green verify from the old tests when the acceptance checks explicitly call for new or updated tests.
      """
  }

  private static func weakCLIFlagTestIssue(
    immediate: PlanNext, brief: PlanStrategicContext, command: String, changedPaths: [String],
    repoURL: URL
  ) -> String? {
    let text = handoffText(immediate: immediate, brief: brief).lowercased()
    guard text.contains("--format json"), text.contains("cli") else { return nil }
    let changedCLIPaths = changedPaths.filter {
      $0.hasPrefix("crates/cli/src/") && isCoverageGatedSourcePath($0)
    }
    guard !changedCLIPaths.isEmpty else { return nil }
    let changedTestPaths = changedPaths.filter { $0.hasPrefix("crates/cli/") && isTestPath($0) }
    guard !changedTestPaths.isEmpty else { return nil }
    let changedTestFiles: [(path: String, contents: String)] = changedTestPaths.compactMap { path in
      guard let contents = try? String(contentsOf: repoURL.appending(path: path), encoding: .utf8)
      else { return nil }
      return (path, contents)
    }
    guard !changedTestFiles.contains(where: { containsSplitFormatJSONAssertion($0.contents) })
    else { return nil }
    let weakTestPaths = changedTestFiles.map(\.path)
    guard !weakTestPaths.isEmpty else { return nil }
    return """
      Verify passed for `\(command)`, but the CLI `--format json` tests do not exercise real argv splitting.

      In `process.argv`, `--format json` arrives as separate `--format` and `json` arguments. A test like `["--format json", "Ship", "it"]` can pass while the real CLI command fails.

      Weak or missing split-argv test file(s):
      \(weakTestPaths.map { "- `\($0)`" }.joined(separator: "\n"))

      Changed CLI source file(s):
      \(changedCLIPaths.map { "- `\($0)`" }.joined(separator: "\n"))

      Required repair:
      - Update the CLI test to call the exported CLI function with split arguments, for example `main(["--format", "json", "Ship", "it"])`.
      - Assert the JSON title is `Ship it`, with `open` and `total` fields present.
      - Rerun `\(command)` after the test and implementation agree on real argv behavior.
      """
  }

  /// Flags CLI source changes whose tests never invoke the built binary.
  private static func weakCLIBinaryInvocationIssue(
    command: String, changedPaths: [String], repoURL: URL
  ) -> String? {
    // Only gate binary-entry changes; helper modules may use library unit tests.
    let changedCLIPaths = changedPaths.filter {
      $0 == "crates/cli/src/main.rs" || $0.hasPrefix("crates/cli/src/bin/")
    }
    guard !changedCLIPaths.isEmpty else { return nil }
    let changedTestPaths = changedPaths.filter { $0.hasPrefix("crates/cli/") && isTestPath($0) }
    guard !changedTestPaths.isEmpty else { return nil }
    let changedTestFiles: [(path: String, contents: String)] = changedTestPaths.compactMap { path in
      guard let contents = try? String(contentsOf: repoURL.appending(path: path), encoding: .utf8)
      else { return nil }
      return (path, contents)
    }
    let invokesBinary = changedTestFiles.contains {
      $0.contents.contains("CARGO_BIN_EXE") || $0.contents.contains("assert_cmd")
        || $0.contents.contains("Command::new")
    }
    guard !invokesBinary else { return nil }
    return """
      Verify passed for `\(command)`, but CLI acceptance tests do not invoke the built binary.

      Changed CLI source file(s):
      \(changedCLIPaths.map { "- `\($0)`" }.joined(separator: "\n"))

      Changed CLI test file(s):
      \(changedTestFiles.map { "- `\($0.path)`" }.joined(separator: "\n"))

      Required repair:
      - Run `env!("CARGO_BIN_EXE_app-cli")` (or `assert_cmd`) and assert stdout/stderr/exit codes for the user flows named in requirements.
      - Prefer golden-output assertions over library-only unit tests for CLI adapters.
      - Rerun `\(command)` after the binary harness covers the changed behavior.
      """
  }

  /// Flags server source changes whose tests never exercise HTTP endpoints.
  private static func weakServerEndpointTestIssue(
    command: String, changedPaths: [String], repoURL: URL
  ) -> String? {
    let changedServerPaths = changedPaths.filter {
      $0.hasPrefix("crates/server/src/") && isCoverageGatedSourcePath($0)
    }
    guard !changedServerPaths.isEmpty else { return nil }
    let changedTestPaths = changedPaths.filter { $0.hasPrefix("crates/server/") && isTestPath($0) }
    guard !changedTestPaths.isEmpty else { return nil }
    let changedTestFiles: [(path: String, contents: String)] = changedTestPaths.compactMap { path in
      guard let contents = try? String(contentsOf: repoURL.appending(path: path), encoding: .utf8)
      else { return nil }
      return (path, contents)
    }
    let exercisesEndpoint = changedTestFiles.contains {
      let body = $0.contents
      return body.contains("oneshot") || body.contains(".uri(") || body.contains("reqwest")
        || body.contains("/status") || body.contains("Router")
    }
    guard !exercisesEndpoint else { return nil }
    return """
      Verify passed for `\(command)`, but server tests do not exercise HTTP endpoints.

      Changed server source file(s):
      \(changedServerPaths.map { "- `\($0)`" }.joined(separator: "\n"))

      Changed server test file(s):
      \(changedTestFiles.map { "- `\($0.path)`" }.joined(separator: "\n"))

      Required repair:
      - Call the shared router via `tower::ServiceExt::oneshot` (or an ephemeral bind) and assert status + body for the changed routes.
      - Keep domain logic in `crates/core`; server tests prove adapter behavior.
      - Rerun `\(command)` after endpoint proofs cover the changed routes.
      """
  }

  private static func missingPackageEntryIssue(
    command: String, changedPaths: [String], repoURL: URL
  ) -> String? {
    guard !changedPaths.isEmpty else { return nil }
    let reviewPaths = changedPaths.filter { !isHeadlessFixtureArtifactPath($0) }
    let issues = missingPackageEntryPointIssues(repoURL: repoURL).filter {
      reviewPaths.contains($0.manifestPath) || reviewPaths.contains($0.targetPath)
    }
    guard !issues.isEmpty else { return nil }
    return """
      Verify passed for `\(command)`, but package entry points now reference files that do not exist:
      \(issues.map { "- `\($0.manifestPath)` \($0.field) = `\($0.declaredPath)` -> missing `\($0.targetPath)`" }.joined(separator: "\n"))

      Package-entry repair instructions:
      - If this is a real replacement entry point, create the missing target file with the implementation and add or update tests that execute it.
      - If the replacement was accidental, restore the manifest entry to the existing source file and edit that existing file instead.
      - Rerun `\(command)` after the manifest and files agree.

      A green Cargo build can miss a binary target when only library crates are checked. Do not submit success while a manifest entry points at a missing file.
      """
  }

  private static func manifestOnlyImplementationIssue(
    immediate: PlanNext, brief: PlanStrategicContext, command: String, changedPaths: [String]
  ) -> String? {
    guard !changedPaths.isEmpty else { return nil }
    let reviewPaths = changedPaths.filter { !isHeadlessFixtureArtifactPath($0) }
    guard !reviewPaths.isEmpty,
      !reviewPaths.contains(where: isCoverageGatedSourcePath),
      !reviewPaths.contains(where: isTestPath),
      reviewPaths.allSatisfy(isPackageMetadataPath),
      handoffRequiresSourceOrTestWork(handoffText(immediate: immediate, brief: brief))
    else { return nil }
    return """
      Verify passed for `\(command)`, but this Develop attempt changed only package metadata or lockfiles:
      \(reviewPaths.map { "- `\($0)`" }.joined(separator: "\n"))

      The accepted handoff asks for source behavior or tests, so metadata-only changes are not enough.

      Required repair:
      - Edit or create the source file that implements the requested behavior.
      - Add or update a test/spec file that executes that behavior.
      - Keep package metadata changes only if they are still needed after the source and test edits.
      - Rerun `\(command)` after source and test files changed.
      """
  }

  private static func handoffText(immediate: PlanNext, brief: PlanStrategicContext) -> String {
    [
      immediate.plan, immediate.selectedBecause ?? "", brief.summary,
      brief.desiredOutcomes.joined(separator: "\n"), brief.constraints.joined(separator: "\n"),
      brief.acceptanceSignals.joined(separator: "\n"),
    ].joined(separator: "\n")
  }

  private static func coverageRepairTestTargetLines(for changedPath: String, repoURL: URL)
    -> [String]
  {
    var candidates = coverageRepairTestTargets(for: changedPath)
    for candidate in existingCoveragePackageTestTargets(for: changedPath, repoURL: repoURL)
    where !candidates.contains(candidate) { candidates.append(candidate) }
    return candidates.map { candidate in
      let action =
        FileManager.default.fileExists(atPath: repoURL.appending(path: candidate).path)
        ? "read_file then edit_file" : "write_file"
      return "- `\(candidate)` (\(action)) should import and execute `\(changedPath)`."
    }
  }

  private static func coverageRepairTestTargets(for changedPath: String) -> [String] {
    let url = URL(fileURLWithPath: changedPath)
    let ext = url.pathExtension.lowercased()
    guard !ext.isEmpty else { return [] }
    if ext == "rs" {
      let basename = url.deletingPathExtension().lastPathComponent
      guard changedPath.contains("/src/") else { return [] }
      let crateRoot =
        changedPath.split(separator: "/src/", maxSplits: 1).first.map(String.init) ?? ""
      return ["\(crateRoot)/tests/\(basename).rs", "\(crateRoot)/tests/cli.rs"]
    }
    let basename = url.deletingPathExtension().lastPathComponent
    return [url.deletingLastPathComponent().appending(path: "\(basename).test.\(ext)").relativePath]
  }

  private static func containsSplitFormatJSONAssertion(_ contents: String) -> Bool {
    let normalized = contents.replacingOccurrences(of: "'", with: "\"").unicodeScalars
      .filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(String.init).joined()
    return normalized.contains("[\"--format\",\"json\"")
      || normalized.contains("([\"--format\",\"json\"")
      || normalized.contains("\"--formatjson\"")
  }

  private static func mentionedTestPaths(in text: String) -> [String] {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/-"))
    let normalized = String(text.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
    var seen: Set<String> = []
    var paths: [String] = []
    for rawToken in normalized.split(whereSeparator: \.isWhitespace) {
      let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "./"))
      guard !token.isEmpty, isTestPath(token), seen.insert(token).inserted else { continue }
      paths.append(token)
    }
    return paths.sorted()
  }

  private static func existingCoveragePackageTestTargets(for changedPath: String, repoURL: URL)
    -> [String]
  {
    let sourceDirectory = URL(fileURLWithPath: changedPath).deletingLastPathComponent()
    let directoryURL = repoURL.appending(path: sourceDirectory.relativePath)
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }
    return entries.compactMap { entry in
      let filename = entry.lastPathComponent.lowercased()
      let relative = sourceDirectory.appending(path: entry.lastPathComponent).relativePath
      if filename.hasSuffix(".rs") {
        guard relative.contains("/tests/") else { return nil }
      } else {
        guard filename.contains(".test.") || filename.contains(".spec.") else { return nil }
      }
      guard (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
        return nil
      }
      return relative
    }.sorted()
  }

  private static func missingPackageEntryPointIssues(repoURL: URL) -> [PackageEntryPointIssue] {
    packageManifestURLs(in: repoURL).flatMap {
      missingPackageEntryPointIssues(manifestURL: $0, repoURL: repoURL)
    }
    .sorted {
      [$0.manifestPath, $0.field, $0.targetPath].joined(separator: "\u{0}")
        < [$1.manifestPath, $1.field, $1.targetPath].joined(separator: "\u{0}")
    }
  }

  private static func packageManifestURLs(in repoURL: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: repoURL, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }
    var manifests: [URL] = []
    for case let url as URL in enumerator {
      if shouldSkipPackageManifestScanDescendants(url) {
        enumerator.skipDescendants()
        continue
      }
      guard url.lastPathComponent == "Cargo.toml",
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      else { continue }
      manifests.append(url)
    }
    return manifests
  }

  private static func shouldSkipPackageManifestScanDescendants(_ url: URL) -> Bool {
    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
      return false
    }
    return [".compass", ".git", "dist", "node_modules", "target"].contains(url.lastPathComponent)
  }

  private static func missingPackageEntryPointIssues(manifestURL: URL, repoURL: URL)
    -> [PackageEntryPointIssue]
  {
    guard let contents = try? String(contentsOf: manifestURL, encoding: .utf8) else { return [] }
    let manifestPath = relativePath(manifestURL, repoURL: repoURL)
    let packageDirectory = manifestURL.deletingLastPathComponent()
    let pattern = #/\bpath\s*=\s*["']([^"']+)["']/#
    return contents.matches(of: pattern).compactMap { match in
      let declared = String(match.1)
      guard let cleanedPath = cleanedLocalPackageEntryPath(declared) else { return nil }
      let targetURL = packageDirectory.appending(path: cleanedPath).standardizedFileURL
      guard !FileManager.default.fileExists(atPath: targetURL.path) else { return nil }
      return PackageEntryPointIssue(
        manifestPath: manifestPath, field: "path", declaredPath: declared,
        targetPath: relativePath(targetURL, repoURL: repoURL)
      )
    }
  }

  private static func cleanedLocalPackageEntryPath(_ rawPath: String) -> String? {
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.contains("://") else { return nil }
    let withoutFragment =
      trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? trimmed
    let withoutQuery =
      withoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? withoutFragment
    let cleaned = withoutQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : cleaned
  }

  private static func isPackageMetadataPath(_ path: String) -> Bool {
    ["cargo.toml", "cargo.lock", "rust-toolchain.toml", "rust-toolchain"].contains(
      URL(fileURLWithPath: path).lastPathComponent.lowercased()
    )
  }

  private static func isHeadlessFixtureArtifactPath(_ path: String) -> Bool {
    let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
    return filename == "fixture.jsonl" || filename.hasSuffix("-fixture.jsonl")
  }

  private static func handoffRequiresSourceOrTestWork(_ text: String) -> Bool {
    [
      "acceptance checks", "add core", "cli", "command", "component", "cover", "function",
      "implement", "logic", "source", "test", "crate",
    ].contains { text.lowercased().contains($0) }
  }

  private static func relativePath(_ url: URL, repoURL: URL) -> String {
    let repoPath = repoURL.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path == repoPath || path.hasPrefix(repoPath + "/") else { return url.path }
    return path == repoPath ? "." : String(path.dropFirst(repoPath.count + 1))
  }

  private static func vitestCoverageRows(in output: String) -> [CoverageTableRow] {
    var rows: [CoverageTableRow] = []
    var currentDirectory: String?
    for line in output.components(separatedBy: "\n") {
      guard line.contains("|") else { continue }
      let columns = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
      guard columns.count >= 5 else { continue }
      let displayPath = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !displayPath.isEmpty, displayPath != "File", displayPath != "All files",
        !displayPath.allSatisfy({ $0 == "-" })
      else { continue }
      if !hasSourceExtension(displayPath), displayPath.contains("/") {
        currentDirectory = displayPath
        continue
      }
      guard hasSourceExtension(displayPath) else { continue }
      let coveragePath: String
      if displayPath.contains("/") {
        coveragePath = displayPath
      } else if let currentDirectory {
        coveragePath = [currentDirectory, displayPath].joined(separator: "/")
      } else {
        coveragePath = displayPath
      }
      rows.append(
        CoverageTableRow(
          path: coveragePath, statements: coveragePercent(columns[1]),
          functions: coveragePercent(columns[3]),
          lines: coveragePercent(columns[4])
        ))
    }
    return rows
  }

  private static func coveragePath(_ coveragePath: String, matchesChangedPath changedPath: String)
    -> Bool
  {
    changedPath == coveragePath || changedPath.hasSuffix("/\(coveragePath)")
      || changedPath.hasSuffix(coveragePath)
  }

  private static func isCoverageGatedSourcePath(_ path: String) -> Bool {
    let lowercased = path.lowercased()
    guard hasSourceExtension(lowercased), !lowercased.contains("/target/"),
      !lowercased.contains("/tests/")
    else { return false }
    return lowercased.contains("/src/")
  }

  private static func isTestPath(_ path: String) -> Bool {
    let lowercased = path.lowercased()
    guard hasSourceExtension(lowercased) else { return false }
    if lowercased.hasSuffix(".rs") { return lowercased.contains("/tests/") }
    let filename = URL(fileURLWithPath: lowercased).lastPathComponent
    return filename.contains(".test.") || filename.contains(".spec.")
  }

  private static func hasSourceExtension(_ path: String) -> Bool {
    ["rs"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
  }

  private static func coveragePercent(_ value: String) -> Double? {
    Double(
      value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func percentLabel(_ value: Double?) -> String {
    guard let value else { return "unknown" }
    return value.rounded() == value ? "\(Int(value))%" : String(format: "%.2f%%", value)
  }
}

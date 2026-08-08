import Foundation

/// Deterministic chamber recon: package list + baseline `cargo test` via VM bash.
public enum ChamberRecon {
  public static func run(
    repoURL: URL,
    bashRunner: AgentBashRunner,
    timeout: TimeInterval = 600
  ) async -> ChamberReconResult {
    var notes: [String] = []
    var packageNames: [String] = []

    let meta = try? await bashRunner.run(
      command: "cargo metadata --no-deps --format-version 1 2>/dev/null | head -c 200000",
      workingDirectory: repoURL,
      timeout: min(timeout, 120)
    )
    if let meta, meta.exitCode == 0 {
      packageNames = parsePackageNames(from: meta.stdout)
    } else {
      notes.append("cargo metadata failed or unavailable")
    }

    let testResult = try? await bashRunner.run(
      command: "cargo test --workspace -- --nocapture 2>&1 | tee /tmp/compass-chamber-baseline.log | tail -c 80000",
      workingDirectory: repoURL,
      timeout: timeout
    )
    let baseline: ChamberTestRunSummary
    if let testResult {
      let combined = testResult.stdout + testResult.stderr
      baseline = ChamberTestRunSummary(
        success: testResult.exitCode == 0,
        passed: countMatches(#"(\d+) passed"#, in: combined),
        failed: countMatches(#"(\d+) failed"#, in: combined),
        ignored: countMatches(#"(\d+) ignored"#, in: combined),
        stdout: String(testResult.stdout.suffix(20_000)),
        stderr: String(testResult.stderr.suffix(8_000))
      )
      if !baseline.success {
        notes.append("baseline cargo test failed — treat as chamber signal")
      }
    } else {
      baseline = ChamberTestRunSummary(success: false, stderr: "baseline cargo test did not run")
      notes.append("baseline cargo test did not run")
    }

    var targets: [ChamberRankedTarget] = []
    for name in packageNames.prefix(12) {
      targets.append(
        ChamberRankedTarget(
          path: "crates/\(name)/src",
          functionHint: nil,
          reason: "package \(name)",
          priority: 1
        ))
    }
    if targets.isEmpty {
      targets.append(
        ChamberRankedTarget(path: "src", reason: "default crate root", priority: 1))
    }

    return ChamberReconResult(
      packageNames: packageNames,
      baselineTests: baseline,
      rankedTargets: targets,
      notes: notes
    )
  }

  private static func parsePackageNames(from metadataJSON: String) -> [String] {
    guard let data = metadataJSON.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let packages = obj["packages"] as? [[String: Any]
      ]
    else { return [] }
    return packages.compactMap { $0["name"] as? String }.sorted()
  }

  private static func countMatches(_ pattern: String, in text: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
      let r = Range(match.range(at: 1), in: text)
    else { return 0 }
    return Int(text[r]) ?? 0
  }
}

import Foundation

public enum HealthFindingKind: String, Codable, Equatable, Sendable {
  case failingGeneratedTest
  case baselineFailure
  case survivingMutant
  case staleDoc
  case orphanedSurface
  case testGap
  case deadCode
}

public struct HealthTriageResult: Codable, Equatable, Sendable {
  public var isRealBug: Bool
  public var rationale: String

  public init(isRealBug: Bool, rationale: String) {
    self.isRealBug = isRealBug
    self.rationale = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public struct HealthFinding: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var kind: HealthFindingKind
  public var title: String
  public var description: String
  public var file: String?
  public var testPath: String?
  public var confidence: Double
  public var triage: HealthTriageResult?
  public var evidence: String
  public var commitSHA: String?
  public var focus: HealthFocus?

  public enum CodingKeys: String, CodingKey {
    case id, kind, title, description, file, testPath, confidence, triage, evidence, commitSHA,
      focus
  }

  public init(
    id: String = UUID().uuidString,
    kind: HealthFindingKind,
    title: String,
    description: String,
    file: String? = nil,
    testPath: String? = nil,
    confidence: Double = 0.5,
    triage: HealthTriageResult? = nil,
    evidence: String = "",
    commitSHA: String? = nil,
    focus: HealthFocus? = nil
  ) {
    self.id = id
    self.kind = kind
    self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
    self.file = {
      let t = file?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return t.isEmpty ? nil : t
    }()
    self.testPath = {
      let t = testPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return t.isEmpty ? nil : t
    }()
    self.confidence = min(1, max(0, confidence))
    self.triage = triage
    self.evidence = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
    self.commitSHA = {
      let t = commitSHA?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return t.isEmpty ? nil : t
    }()
    self.focus = focus
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
    kind = try container.decode(HealthFindingKind.self, forKey: .kind)
    title = (try container.decodeIfPresent(String.self, forKey: .title) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    description = (try container.decodeIfPresent(String.self, forKey: .description) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let rawFile = try container.decodeIfPresent(String.self, forKey: .file)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    file = rawFile.isEmpty ? nil : rawFile
    let rawTest = try container.decodeIfPresent(String.self, forKey: .testPath)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    testPath = rawTest.isEmpty ? nil : rawTest
    confidence = min(1, max(0, try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5))
    triage = try container.decodeIfPresent(HealthTriageResult.self, forKey: .triage)
    evidence = (try container.decodeIfPresent(String.self, forKey: .evidence) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let rawSHA = try container.decodeIfPresent(String.self, forKey: .commitSHA)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    commitSHA = rawSHA.isEmpty ? nil : rawSHA
    focus = try container.decodeIfPresent(HealthFocus.self, forKey: .focus)
  }

  /// Confirmed product bugs (triaged real), excluding mutant coverage gaps and doc/sprawl debt.
  public var isConfirmedRealBug: Bool {
    switch kind {
    case .survivingMutant, .staleDoc, .orphanedSurface, .testGap, .deadCode:
      return false
    case .baselineFailure:
      return true
    case .failingGeneratedTest:
      return triage?.isRealBug == true
    }
  }

  /// Stable key for Run Loop novelty — ignores volatile `id` / evidence.
  public var noveltyKey: String {
    let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let file = self.file?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let testPath = self.testPath?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return "\(kind.rawValue)|\(title)|\(file)|\(testPath)"
  }

  /// Whether this finding counts toward Run Loop diminishing-returns novelty.
  /// Baseline failures are excluded — recon re-emits them every pass while red.
  public var countsTowardNovelty: Bool {
    kind != .baselineFailure
  }
}

/// Pure helpers for Health Run Loop idle-stop decisions.
public enum HealthLoopNovelty {
  public static func noveltyKeys(in findings: [HealthFinding]) -> Set<String> {
    Set(findings.filter(\.countsTowardNovelty).map(\.noveltyKey))
  }

  /// Returns how many keys in `current` are absent from `seen`, then the updated seen set.
  public static func incorporate(
    current findings: [HealthFinding],
    seen: Set<String>
  ) -> (newCount: Int, seen: Set<String>) {
    let keys = noveltyKeys(in: findings)
    let novel = keys.subtracting(seen)
    return (novel.count, seen.union(keys))
  }
}

public struct HealthGeneratedTest: Codable, Equatable, Sendable {
  public var path: String
  public var targetHint: String
  public var compiled: Bool
  public var passed: Bool?
  public var compileErrors: String?

  public init(
    path: String,
    targetHint: String = "",
    compiled: Bool,
    passed: Bool? = nil,
    compileErrors: String? = nil
  ) {
    self.path = path
    self.targetHint = targetHint
    self.compiled = compiled
    self.passed = passed
    self.compileErrors = compileErrors
  }
}

public struct HealthTestRunSummary: Codable, Equatable, Sendable {
  public var success: Bool
  public var passed: Int
  public var failed: Int
  public var ignored: Int
  public var stdout: String
  public var stderr: String

  public init(
    success: Bool,
    passed: Int = 0,
    failed: Int = 0,
    ignored: Int = 0,
    stdout: String = "",
    stderr: String = ""
  ) {
    self.success = success
    self.passed = max(0, passed)
    self.failed = max(0, failed)
    self.ignored = max(0, ignored)
    self.stdout = stdout
    self.stderr = stderr
  }
}

public struct HealthRankedTarget: Codable, Equatable, Sendable {
  public var path: String
  public var functionHint: String?
  public var reason: String
  public var priority: Int

  public init(path: String, functionHint: String? = nil, reason: String, priority: Int = 0) {
    self.path = path
    self.functionHint = functionHint
    self.reason = reason
    self.priority = priority
  }
}

public struct HealthSurfaceInventory: Codable, Equatable, Sendable {
  public var binaries: [String]
  public var libraries: [String]
  public var docPaths: [String]

  public init(binaries: [String] = [], libraries: [String] = [], docPaths: [String] = []) {
    self.binaries = binaries
    self.libraries = libraries
    self.docPaths = docPaths
  }
}

public struct HealthReconResult: Codable, Equatable, Sendable {
  public var packageNames: [String]
  public var baselineTests: HealthTestRunSummary
  public var rankedTargets: [HealthRankedTarget]
  public var surfaces: HealthSurfaceInventory
  public var notes: [String]

  public init(
    packageNames: [String] = [],
    baselineTests: HealthTestRunSummary = HealthTestRunSummary(success: true),
    rankedTargets: [HealthRankedTarget] = [],
    surfaces: HealthSurfaceInventory = HealthSurfaceInventory(),
    notes: [String] = []
  ) {
    self.packageNames = packageNames
    self.baselineTests = baselineTests
    self.rankedTargets = rankedTargets
    self.surfaces = surfaces
    self.notes = notes
  }
}

public struct HealthBudget: Equatable, Sendable {
  public var maxIterations: Int
  public var wallClockSecs: Int
  /// Consecutive Health Run Loop passes with no new findings before auto-play stops.
  public var idleStopPasses: Int

  /// Post-ship health inside a factory loop (fail-open, shorter leash).
  public static let factoryShipDefault = HealthBudget(
    maxIterations: 48,
    wallClockSecs: 30 * 60,
    idleStopPasses: 3
  )

  /// Pure health project passes (UI / CLI default; editable at runtime).
  public static let healthLoopDefault = HealthBudget(
    maxIterations: 128,
    wallClockSecs: 2 * 60 * 60,
    idleStopPasses: 3
  )

  public init(
    maxIterations: Int = 128,
    wallClockSecs: Int = 2 * 60 * 60,
    idleStopPasses: Int = 3
  ) {
    self.maxIterations = max(1, maxIterations)
    self.wallClockSecs = max(30, wallClockSecs)
    self.idleStopPasses = max(1, idleStopPasses)
  }
}

public struct HealthHuntSubmit: Codable, Equatable, Sendable {
  public var plan: String
  public var generatedTests: [HealthGeneratedTest]
  public var findings: [HealthFinding]
  public var notes: [String]
  public var focus: HealthFocus?

  public enum CodingKeys: String, CodingKey {
    case plan
    case generatedTests
    case findings
    case notes
    case focus
  }

  public init(
    plan: String = "",
    generatedTests: [HealthGeneratedTest] = [],
    findings: [HealthFinding] = [],
    notes: [String] = [],
    focus: HealthFocus? = nil
  ) {
    self.plan = plan
    self.generatedTests = generatedTests
    self.findings = findings
    self.notes = notes
    self.focus = focus
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    plan = try container.decodeIfPresent(String.self, forKey: .plan) ?? ""
    generatedTests =
      try container.decodeIfPresent([HealthGeneratedTest].self, forKey: .generatedTests) ?? []
    findings = try container.decodeIfPresent([HealthFinding].self, forKey: .findings) ?? []
    notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    focus = try container.decodeIfPresent(HealthFocus.self, forKey: .focus)
  }
}

public struct HealthCommitSummary: Codable, Equatable, Sendable, Identifiable {
  public var sha: String
  public var subject: String

  public var id: String { sha }

  public init(sha: String, subject: String) {
    self.sha = sha
    self.subject = subject
  }
}

public struct HealthSnapshot: Codable, Equatable, Sendable {
  public var collectedAt: Date
  public var sessionNumber: Int?
  public var plan: String
  public var recon: HealthReconResult
  public var generatedTests: [HealthGeneratedTest]
  public var findings: [HealthFinding]
  public var notes: [String]
  public var partial: Bool
  public var focus: HealthFocus?
  public var healthBranch: String?
  public var baseSHA: String?
  public var tipSHA: String?
  public var commits: [HealthCommitSummary]

  public init(
    collectedAt: Date = Date(),
    sessionNumber: Int? = nil,
    plan: String = "",
    recon: HealthReconResult = HealthReconResult(),
    generatedTests: [HealthGeneratedTest] = [],
    findings: [HealthFinding] = [],
    notes: [String] = [],
    partial: Bool = false,
    focus: HealthFocus? = nil,
    healthBranch: String? = nil,
    baseSHA: String? = nil,
    tipSHA: String? = nil,
    commits: [HealthCommitSummary] = []
  ) {
    self.collectedAt = collectedAt
    self.sessionNumber = sessionNumber
    self.plan = plan
    self.recon = recon
    self.generatedTests = generatedTests
    self.findings = findings
    self.notes = notes
    self.partial = partial
    self.focus = focus
    self.healthBranch = healthBranch
    self.baseSHA = baseSHA
    self.tipSHA = tipSHA
    self.commits = commits
  }

  public func formattedForPrompt(maxFindings: Int = 8) -> String {
    var lines: [String] = []
    if partial {
      lines.append("_(health pass partial / fail-open)_")
    }
    if let focus {
      lines.append("Focus: \(focus.displayName)")
    }
    if let branch = healthBranch, let base = baseSHA, let tip = tipSHA {
      lines.append("Branch \(branch): \(base.prefix(8))..\(tip.prefix(8))")
    }
    let realBugs = findings.filter(\.isConfirmedRealBug)
    let mutants = findings.filter { $0.kind == .survivingMutant }
    let debt = findings.filter {
      switch $0.kind {
      case .staleDoc, .orphanedSurface, .testGap, .deadCode: return true
      default: return false
      }
    }
    let other = findings.filter {
      !$0.isConfirmedRealBug && $0.kind != .survivingMutant
        && $0.kind != .staleDoc && $0.kind != .orphanedSurface && $0.kind != .testGap
        && $0.kind != .deadCode
    }

    if realBugs.isEmpty && mutants.isEmpty && debt.isEmpty && other.isEmpty {
      lines.append("_(no health findings)_")
      return lines.joined(separator: "\n")
    }

    if !realBugs.isEmpty {
      lines.append("Confirmed bugs (prefer fix packets):")
      for finding in realBugs.prefix(maxFindings) {
        lines.append("- \(finding.title): \(finding.description)")
      }
    }
    if !debt.isEmpty {
      lines.append("Docs / sprawl / test debt:")
      for finding in debt.prefix(maxFindings) {
        lines.append("- [\(finding.kind.rawValue)] \(finding.title)")
      }
    }
    if !other.isEmpty {
      lines.append("Other findings (triage uncertain / not confirmed):")
      for finding in other.prefix(maxFindings) {
        let tag = finding.triage.map { $0.isRealBug ? "real?" : "fp?" } ?? "untriaged"
        lines.append("- [\(tag)] \(finding.title)")
      }
    }
    if !mutants.isEmpty {
      lines.append("Surviving mutants (coverage gaps, not product bugs):")
      for finding in mutants.prefix(maxFindings) {
        lines.append("- \(finding.title)")
      }
    }
    return lines.joined(separator: "\n")
  }
}

public enum HealthPaths {
  public static let generatedTestsDirectory = "tests"
  public static let generatedTestPrefix = "compass_gen_"
  public static let snapshotFileName = "health-snapshot.json"
  public static let findingsFileName = "findings.json"

  public static func isGeneratedTestFileName(_ name: String) -> Bool {
    let base = (name as NSString).lastPathComponent
    return base.hasPrefix(generatedTestPrefix) && base.hasSuffix(".rs")
  }

  public static func normalizeGeneratedTestFileName(_ raw: String) -> String {
    var name = (raw as NSString).lastPathComponent
    if name.contains("/") || name.contains("\\") || name.contains("..") {
      name = name.replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "\\", with: "_")
        .replacingOccurrences(of: "..", with: "_")
    }
    if !name.hasSuffix(".rs") {
      name += ".rs"
    }
    if !name.hasPrefix(generatedTestPrefix) {
      name = generatedTestPrefix + name
    }
    return name
  }
}

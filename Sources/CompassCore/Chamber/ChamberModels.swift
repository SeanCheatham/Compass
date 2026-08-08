import Foundation

public enum ChamberFindingKind: String, Codable, Equatable, Sendable {
  case failingGeneratedTest
  case baselineFailure
  case survivingMutant
}

public struct ChamberTriageResult: Codable, Equatable, Sendable {
  public var isRealBug: Bool
  public var rationale: String

  public init(isRealBug: Bool, rationale: String) {
    self.isRealBug = isRealBug
    self.rationale = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public struct ChamberFinding: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var kind: ChamberFindingKind
  public var title: String
  public var description: String
  public var file: String?
  public var testPath: String?
  public var confidence: Double
  public var triage: ChamberTriageResult?
  public var evidence: String

  public enum CodingKeys: String, CodingKey {
    case id, kind, title, description, file, testPath, confidence, triage, evidence
  }

  public init(
    id: String = UUID().uuidString,
    kind: ChamberFindingKind,
    title: String,
    description: String,
    file: String? = nil,
    testPath: String? = nil,
    confidence: Double = 0.5,
    triage: ChamberTriageResult? = nil,
    evidence: String = ""
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
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
    kind = try container.decode(ChamberFindingKind.self, forKey: .kind)
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
    triage = try container.decodeIfPresent(ChamberTriageResult.self, forKey: .triage)
    evidence = (try container.decodeIfPresent(String.self, forKey: .evidence) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Confirmed product bugs (triaged real), excluding mutant coverage gaps.
  public var isConfirmedRealBug: Bool {
    guard kind != .survivingMutant else { return false }
    if kind == .baselineFailure { return true }
    return triage?.isRealBug == true
  }
}

public struct ChamberGeneratedTest: Codable, Equatable, Sendable {
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

public struct ChamberTestRunSummary: Codable, Equatable, Sendable {
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

public struct ChamberRankedTarget: Codable, Equatable, Sendable {
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

public struct ChamberReconResult: Codable, Equatable, Sendable {
  public var packageNames: [String]
  public var baselineTests: ChamberTestRunSummary
  public var rankedTargets: [ChamberRankedTarget]
  public var notes: [String]

  public init(
    packageNames: [String] = [],
    baselineTests: ChamberTestRunSummary = ChamberTestRunSummary(success: true),
    rankedTargets: [ChamberRankedTarget] = [],
    notes: [String] = []
  ) {
    self.packageNames = packageNames
    self.baselineTests = baselineTests
    self.rankedTargets = rankedTargets
    self.notes = notes
  }
}

public struct ChamberBudget: Equatable, Sendable {
  public var maxIterations: Int
  public var wallClockSecs: Int

  /// Post-ship chamber inside a factory loop (fail-open, shorter leash).
  public static let factoryShipDefault = ChamberBudget(
    maxIterations: 48,
    wallClockSecs: 30 * 60
  )

  /// Pure chamber project hunts (UI / CLI default; editable at runtime).
  public static let chamberLoopDefault = ChamberBudget(
    maxIterations: 128,
    wallClockSecs: 2 * 60 * 60
  )

  public init(
    maxIterations: Int = 128,
    wallClockSecs: Int = 2 * 60 * 60
  ) {
    self.maxIterations = max(1, maxIterations)
    self.wallClockSecs = max(30, wallClockSecs)
  }
}

public struct ChamberHuntSubmit: Codable, Equatable, Sendable {
  public var plan: String
  public var generatedTests: [ChamberGeneratedTest]
  public var findings: [ChamberFinding]
  public var notes: [String]

  public enum CodingKeys: String, CodingKey {
    case plan
    case generatedTests
    case findings
    case notes
  }

  public init(
    plan: String = "",
    generatedTests: [ChamberGeneratedTest] = [],
    findings: [ChamberFinding] = [],
    notes: [String] = []
  ) {
    self.plan = plan
    self.generatedTests = generatedTests
    self.findings = findings
    self.notes = notes
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    plan = try container.decodeIfPresent(String.self, forKey: .plan) ?? ""
    generatedTests =
      try container.decodeIfPresent([ChamberGeneratedTest].self, forKey: .generatedTests) ?? []
    findings = try container.decodeIfPresent([ChamberFinding].self, forKey: .findings) ?? []
    notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
  }
}

public struct ChamberSnapshot: Codable, Equatable, Sendable {
  public var collectedAt: Date
  public var sessionNumber: Int?
  public var plan: String
  public var recon: ChamberReconResult
  public var generatedTests: [ChamberGeneratedTest]
  public var findings: [ChamberFinding]
  public var notes: [String]
  public var partial: Bool

  public init(
    collectedAt: Date = Date(),
    sessionNumber: Int? = nil,
    plan: String = "",
    recon: ChamberReconResult = ChamberReconResult(),
    generatedTests: [ChamberGeneratedTest] = [],
    findings: [ChamberFinding] = [],
    notes: [String] = [],
    partial: Bool = false
  ) {
    self.collectedAt = collectedAt
    self.sessionNumber = sessionNumber
    self.plan = plan
    self.recon = recon
    self.generatedTests = generatedTests
    self.findings = findings
    self.notes = notes
    self.partial = partial
  }

  public func formattedForPrompt(maxFindings: Int = 8) -> String {
    var lines: [String] = []
    if partial {
      lines.append("_(chamber pass partial / fail-open)_")
    }
    let realBugs = findings.filter(\.isConfirmedRealBug)
    let mutants = findings.filter { $0.kind == .survivingMutant }
    let other = findings.filter { !$0.isConfirmedRealBug && $0.kind != .survivingMutant }

    if realBugs.isEmpty && mutants.isEmpty && other.isEmpty {
      lines.append("_(no chamber findings)_")
      return lines.joined(separator: "\n")
    }

    if !realBugs.isEmpty {
      lines.append("Confirmed bugs (prefer fix packets):")
      for finding in realBugs.prefix(maxFindings) {
        lines.append("- \(finding.title): \(finding.description)")
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

public enum ChamberPaths {
  public static let generatedTestsDirectory = "tests"
  public static let generatedTestPrefix = "compass_gen_"
  public static let snapshotFileName = "chamber-snapshot.json"
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

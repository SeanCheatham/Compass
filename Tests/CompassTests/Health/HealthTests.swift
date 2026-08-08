import CompassCore
import Foundation
import Testing

@Suite("Health")
struct HealthTests {
  @Test("normalizeGeneratedTestFileName forces prefix and .rs")
  func normalizeName() {
    #expect(HealthPaths.normalizeGeneratedTestFileName("foo") == "compass_gen_foo.rs")
    #expect(HealthPaths.normalizeGeneratedTestFileName("compass_gen_bar.rs") == "compass_gen_bar.rs")
    #expect(HealthPaths.isGeneratedTestFileName("compass_gen_x.rs"))
    #expect(!HealthPaths.isGeneratedTestFileName("lib.rs"))
  }

  @Test("FP guard demotes invented numeric assert without docs")
  func fpGuard() {
    let finding = HealthFinding(
      kind: .failingGeneratedTest,
      title: "weird",
      description: "assert_eq!(bump(1), 1) failed",
      confidence: 0.8,
      triage: HealthTriageResult(isRealBug: true, rationale: "I guessed"),
      evidence: "assert_eq!(bump(1), 99)"
    )
    let guarded = HealthFPGuards.apply(to: [finding])
    #expect(guarded.first?.triage?.isRealBug == false)
  }

  @Test("eval scores recall and control false positives")
  func evalScore() throws {
    let bugsTOML = """
      [[bugs]]
      id = "bump_identity"
      function = "bump"
      control = false
      match = ["bump"]

      [[bugs]]
      id = "clamp_control"
      function = "clamp"
      control = true
      match = ["clamp"]
      """
    let bugs = HealthEval.parseBugsTOML(bugsTOML)
    #expect(bugs.count == 2)

    let hit = HealthSnapshot(
      findings: [
        HealthFinding(
          kind: .failingGeneratedTest,
          title: "bump wrong",
          description: "bump should be identity",
          testPath: "tests/compass_gen_bump.rs",
          confidence: 0.9,
          triage: HealthTriageResult(isRealBug: true, rationale: "documented identity"),
          evidence: "bump failed"
        ),
        HealthFinding(
          kind: .failingGeneratedTest,
          title: "clamp false positive",
          description: "clamp",
          confidence: 0.5,
          triage: HealthTriageResult(isRealBug: true, rationale: "wrong"),
          evidence: "clamp"
        ),
      ]
    )
    let score = HealthEval.score(bugs: bugs, snapshot: hit)
    #expect(score.hits == ["bump_identity"])
    #expect(score.missed.isEmpty)
    #expect(score.controlFalsePositives == 1)
    #expect(score.recall == 1.0)
  }

  @Test("PlanState defaults projectKind to factory and round-trips health")
  func planStateKind() throws {
    let empty = PlanState.empty
    #expect(empty.projectKind == .factory)

    var state = PlanState.empty
    state.projectKind = .health
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(PlanState.self, from: data)
    #expect(decoded.projectKind == .health)
  }

  @Test("health snapshot formats Plan pressure")
  func snapshotPrompt() {
    let snap = HealthSnapshot(
      findings: [
        HealthFinding(
          kind: .failingGeneratedTest,
          title: "real bug",
          description: "contract broken",
          triage: HealthTriageResult(isRealBug: true, rationale: "docs"),
          evidence: "fail"
        ),
        HealthFinding(
          kind: .survivingMutant,
          title: "mutant X",
          description: "unkilled",
          triage: HealthTriageResult(isRealBug: false, rationale: "coverage gap")
        ),
        HealthFinding(
          kind: .staleDoc,
          title: "README lag",
          description: "mentions removed CLI"
        ),
      ]
    )
    let text = snap.formattedForPrompt()
    #expect(text.contains("Confirmed bugs"))
    #expect(text.contains("real bug"))
    #expect(text.contains("Surviving mutants"))
    #expect(text.contains("Docs / sprawl"))
  }

  @Test("write policy gates paths by focus")
  func writePolicy() {
    #expect(HealthWritePolicy.allows(relativePath: "tests/compass_gen_x.rs", focus: .bugHunt))
    #expect(!HealthWritePolicy.allows(relativePath: "tests/other.rs", focus: .bugHunt))
    #expect(HealthWritePolicy.allows(relativePath: "tests/foo.rs", focus: .test))
    #expect(HealthWritePolicy.allows(relativePath: "README.md", focus: .docs))
    #expect(HealthWritePolicy.allows(relativePath: "docs/arch.md", focus: .docs))
    #expect(!HealthWritePolicy.allows(relativePath: "src/lib.rs", focus: .docs))
    #expect(HealthWritePolicy.allows(relativePath: "src/lib.rs", focus: .cleanup))
    #expect(!HealthWritePolicy.allows(relativePath: ".compass/state.json", focus: .cleanup))
  }

  @Test("HealthBranch create commit restore")
  func healthBranchRoundTrip() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("compass-health-branch-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    func git(_ args: [String]) throws {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      process.arguments = ["-C", root.path] + args
      process.standardOutput = Pipe()
      process.standardError = Pipe()
      try process.run()
      process.waitUntilExit()
      #expect(process.terminationStatus == 0)
    }

    try git(["init"])
    try git(["config", "user.email", "compass@example.com"])
    try git(["config", "user.name", "Compass"])
    try "hello\n".write(to: root.appending(path: "README.md"), atomically: true, encoding: .utf8)
    try git(["add", "README.md"])
    try git(["commit", "-m", "init"])
    try git(["branch", "-M", "main"])

    let session = try HealthBranch.begin(repoURL: root, projectId: "test-project")
    #expect(session.healthBranch.contains("compass/health/"))
    try "patch\n".write(to: root.appending(path: "NOTE.md"), atomically: true, encoding: .utf8)
    let tip = try HealthBranch.commitIfDirty(repoURL: root, message: "health(docs): note")
    #expect(tip != nil)
    try HealthBranch.end(repoURL: root, session: session)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", root.path, "symbolic-ref", "--short", "HEAD"]
    let out = Pipe()
    process.standardOutput = out
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    let branch = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(branch == "main")
    #expect(!fm.fileExists(atPath: root.appending(path: "NOTE.md").path))

    // Retry while still on the health branch (crashed pass) must succeed.
    _ = try HealthBranch.begin(repoURL: root, projectId: "test-project")
    let recovered = try HealthBranch.begin(repoURL: root, projectId: "test-project")
    #expect(recovered.previousRef == "main")
    try HealthBranch.end(repoURL: root, session: recovered)

    let dirtyRoot = fm.temporaryDirectory.appendingPathComponent(
      "compass-health-dirty-\(UUID().uuidString)")
    try fm.createDirectory(at: dirtyRoot, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dirtyRoot) }
    func gitDirty(_ args: [String]) throws {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      process.arguments = ["-C", dirtyRoot.path] + args
      process.standardOutput = Pipe()
      process.standardError = Pipe()
      try process.run()
      process.waitUntilExit()
      #expect(process.terminationStatus == 0)
    }
    try gitDirty(["init"])
    try gitDirty(["config", "user.email", "compass@example.com"])
    try gitDirty(["config", "user.name", "Compass"])
    try "x\n".write(to: dirtyRoot.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    try gitDirty(["add", "a.txt"])
    try gitDirty(["commit", "-m", "init"])
    try "dirty\n".write(to: dirtyRoot.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    #expect(throws: HealthBranchError.self) {
      try HealthBranch.begin(repoURL: dirtyRoot, projectId: "dirty")
    }
  }

  @Test("initialize commits .gitignore when adding .compass/")
  func initializeCommitsGitignore() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(
      "compass-gitignore-commit-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    func git(_ args: [String]) throws {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      process.arguments = ["-C", root.path] + args
      process.standardOutput = Pipe()
      process.standardError = Pipe()
      try process.run()
      process.waitUntilExit()
      #expect(process.terminationStatus == 0)
    }

    try git(["init"])
    try git(["config", "user.email", "compass@example.com"])
    try git(["config", "user.name", "Compass"])
    try "keep\n".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    try git(["add", "a.txt"])
    try git(["commit", "-m", "init"])
    try git(["branch", "-M", "main"])

    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()

    let status = Process()
    status.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    status.arguments = ["-C", root.path, "status", "--porcelain"]
    let statusOut = Pipe()
    status.standardOutput = statusOut
    status.standardError = Pipe()
    try status.run()
    status.waitUntilExit()
    let porcelain = String(data: statusOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unset"
    #expect(porcelain.isEmpty)

    let gitignore = try String(
      contentsOf: root.appending(path: ".gitignore"), encoding: .utf8)
    #expect(gitignore.contains(".compass/"))

    let log = Process()
    log.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    log.arguments = ["-C", root.path, "log", "-1", "--format=%s"]
    let logOut = Pipe()
    log.standardOutput = logOut
    log.standardError = Pipe()
    try log.run()
    log.waitUntilExit()
    let subject = String(data: logOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(subject == "Ignore Compass workspace (.compass/)")

    let session = try HealthBranch.begin(repoURL: root, projectId: "after-init")
    try HealthBranch.end(repoURL: root, session: session)
  }

  @Test("CLI parses health run budget and focus args")
  func cliHealth() throws {
    let run = try CompassCLICommand.parse([
      "health", "run", "--repo", "/tmp/repo", "--recon-only",
      "--focus", "docs",
      "--max-iterations", "64", "--wall-clock-secs", "3600", "--format", "text",
    ])
    if case .healthRun(let repo, _, _, let skipHunt, let budget, let focus, let format) = run {
      #expect(repo.path == "/tmp/repo")
      #expect(skipHunt)
      #expect(budget.maxIterations == 64)
      #expect(budget.wallClockSecs == 3600)
      #expect(focus == .docs)
      #expect(format == .text)
    } else {
      Issue.record("Expected healthRun")
    }

    let eval = try CompassCLICommand.parse([
      "health", "eval", "--repo", "/tmp/repo", "--bugs", "/tmp/bugs.toml",
    ])
    if case .healthEval(let repo, let bugs, _) = eval {
      #expect(repo.path == "/tmp/repo")
      #expect(bugs.path == "/tmp/bugs.toml")
    } else {
      Issue.record("Expected healthEval")
    }
  }

  @Test("novelty keys ignore baseline failures and drive idle streak")
  func noveltyIdle() {
    let dead = HealthFinding(
      kind: .deadCode,
      title: "Unused helper",
      description: "commented out",
      file: "src/lib.rs",
      confidence: 0.9,
      evidence: "block"
    )
    let baseline = HealthFinding(
      kind: .baselineFailure,
      title: "Baseline tests failing",
      description: "red",
      confidence: 0.9,
      evidence: "fail"
    )
    let sameDeadDifferentEvidence = HealthFinding(
      kind: .deadCode,
      title: "Unused helper",
      description: "still there",
      file: "src/lib.rs",
      confidence: 0.8,
      evidence: "other citation"
    )
    let docs = HealthFinding(
      kind: .staleDoc,
      title: "README drift",
      description: "missing crate",
      file: "README.md",
      confidence: 0.7,
      evidence: "listing"
    )

    #expect(dead.countsTowardNovelty)
    #expect(!baseline.countsTowardNovelty)
    #expect(dead.noveltyKey == sameDeadDifferentEvidence.noveltyKey)

    var seen = HealthLoopNovelty.noveltyKeys(in: [dead, baseline])
    #expect(seen.count == 1)

    let idle1 = HealthLoopNovelty.incorporate(
      current: [dead, baseline, sameDeadDifferentEvidence],
      seen: seen
    )
    #expect(idle1.newCount == 0)
    seen = idle1.seen

    let novel = HealthLoopNovelty.incorporate(current: [docs, baseline], seen: seen)
    #expect(novel.newCount == 1)
    #expect(novel.seen.count == 2)

    #expect(HealthBudget.healthLoopDefault.idleStopPasses == 3)
    #expect(HealthBudget(idleStopPasses: 0).idleStopPasses == 1)
  }
}

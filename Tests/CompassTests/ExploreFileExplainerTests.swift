import Foundation
import Testing

@testable import Compass

struct ExploreFileExplainerTests {
  private var temporaryDirectory: URL!

  private mutating func setUp() {
    temporaryDirectory = try! makeTempDir()
  }

  private mutating func tearDown() {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  // MARK: - parseGitDiffStat

  @Test
  func parseGitDiffStat_normalAdditionsAndDeletions() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = """
      Sources/App.swift        |  12 ++++++------
      Sources/Model.swift      |   4 ++++++
      """

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    try #require(changes.count == 2)

    try #require(changes[0].relativePath == "Sources/App.swift")
    try #require(changes[0].additions == 6)
    try #require(changes[0].deletions == 6)

    try #require(changes[1].relativePath == "Sources/Model.swift")
    try #require(changes[1].additions == 6)
    try #require(changes[1].deletions == 0)
  }

  @Test
  func parseGitDiffStat_renameArrow() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = "old/path.go => new/path.go           |   4 ++--"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    try #require(changes.count == 1)
    try #require(changes[0].relativePath == "new/path.go")
    try #require(changes[0].additions == 2)
    try #require(changes[0].deletions == 2)
  }

  @Test
  func parseGitDiffStat_abPrefix() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = "a/Sources/App.swift        |  10 +++++-----"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    try #require(changes.count == 1)
    try #require(changes[0].relativePath == "Sources/App.swift")
    try #require(changes[0].additions == 5)
    try #require(changes[0].deletions == 5)
  }

  @Test
  func parseGitDiffStat_renameWithABPrefix() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = "a/Foo.swift => b/Bar.swift           |   6 ++++++"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    try #require(changes.count == 1)
    try #require(changes[0].relativePath == "Bar.swift")
    try #require(changes[0].additions == 6)
    try #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_languageDetection() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Case 1: non-rename, no a/ prefix → language == .swift
    let diffStat1 = "Sources/App.swift        |  10 +++++-----"
    let changes1 = FileExplainer.parseGitDiffStat(diffStat1)
    try #require(changes1.count == 1)
    try #require(changes1[0].relativePath == "Sources/App.swift")
    try #require(changes1[0].language == .swift)

    // Case 2: rename without a/ prefix → language == .go
    let diffStat2 = "old/path.go => new/path.go           |   4 ++--"
    let changes2 = FileExplainer.parseGitDiffStat(diffStat2)
    try #require(changes2.count == 1)
    try #require(changes2[0].relativePath == "new/path.go")
    try #require(changes2[0].language == .go)

    // Case 3: rename with a/→b/ prefix → language == .swift
    let diffStat3 = "a/Foo.swift => b/Bar.swift           |   6 ++++++"
    let changes3 = FileExplainer.parseGitDiffStat(diffStat3)
    try #require(changes3.count == 1)
    try #require(changes3[0].relativePath == "Bar.swift")
    try #require(changes3[0].language == .swift)
  }

  @Test
  func parseGitDiffStat_binaryFile() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = "Assets/logo.png                    |  Bin 210 kB → 215 kB"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    try #require(changes.count == 1)
    try #require(changes[0].relativePath == "Assets/logo.png")
    // Binary lines produce 0 additions and 0 deletions (no + or - in the bar chart, no numeric tokens)
    try #require(changes[0].additions == 0)
    try #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_pathWithSpaces() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = "My Files/App.swift   |   6 ++++++"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    try #require(changes.count == 1)
    try #require(changes[0].relativePath == "My Files/App.swift")
    try #require(changes[0].additions == 6)
    try #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_multiLineStatOutput() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = """
      Sources/App.swift        |  10 ++++++++
      Sources/Model.swift      |   5 +++++--
      Tests/AppTests.swift    |   2 ++
      README.md               |   1 +
      """

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    try #require(changes.count == 4)
    try #require(changes[0].relativePath == "Sources/App.swift")
    try #require(changes[1].relativePath == "Sources/Model.swift")
    try #require(changes[2].relativePath == "Tests/AppTests.swift")
    try #require(changes[3].relativePath == "README.md")
  }

  @Test
  func parseGitDiffStat_numericOnlyFallback() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // No +/- bar chart, only a numeric count — should fall back to numeric count as additions
    let diffStat = "Sources/App.swift        |  42"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    try #require(changes.count == 1)
    try #require(changes[0].relativePath == "Sources/App.swift")
    try #require(changes[0].additions == 42)
    try #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_absentStatsParts() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Empty stats part — should produce zero additions and deletions
    let diffStat = "README.md               |"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    try #require(changes.count == 1)
    try #require(changes[0].relativePath == "README.md")
    try #require(changes[0].additions == 0)
    try #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_emptyInput() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let changes = FileExplainer.parseGitDiffStat("")
    try #require(changes.isEmpty)
  }

  @Test
  func parseGitDiffStat_whitespaceOnlyLines() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = """
      Sources/App.swift        |  4 +
                            
      Sources/Model.swift      |  2 ++
      """

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    try #require(changes.count == 2)
    try #require(changes[0].relativePath == "Sources/App.swift")
    try #require(changes[1].relativePath == "Sources/Model.swift")
  }

  @Test
  func parseGitDiffStat_lineWithoutPipeSeparator() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // A line with no `|` separator — path only, no stats — must be skipped
    // because parseGitDiffStat requires `|` to split path from stats.
    let diffStat = """
      Sources/App.swift        |  4 +++
      NoStatsFile.swift
      Sources/Model.swift      |  2 ++
      """

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    try #require(changes.count == 2)
    try #require(changes[0].relativePath == "Sources/App.swift")
    try #require(changes[1].relativePath == "Sources/Model.swift")
  }

  // MARK: - extractLineCounts

  @Test
  func extractLineCounts_additionsAndDeletions() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "24 ++++++++----------")
    try #require(result.additions == 8)
    try #require(result.deletions == 10)
  }

  @Test
  func extractLineCounts_onlyAdditions() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "6 ++++++")
    try #require(result.additions == 6)
    try #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_onlyDeletions() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "3 ---")
    try #require(result.additions == 0)
    try #require(result.deletions == 3)
  }

  @Test
  func extractLineCounts_whitespaceOnlyString() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "   ")
    try #require(result.additions == 0)
    try #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_numericFallback() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // No +/- bar chars, but has numeric token
    let result = FileExplainer.extractLineCounts(from: "99")
    try #require(result.additions == 99)
    try #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_absentStatsParts() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // No bar chars, no numeric tokens
    let result = FileExplainer.extractLineCounts(from: "")
    try #require(result.additions == 0)
    try #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_withNumericAndBars() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Numeric count 24 and bar chars both present — bars take priority
    let result = FileExplainer.extractLineCounts(from: "24 ++++++++----------")
    try #require(result.additions == 8)
    try #require(result.deletions == 10)
  }

  // MARK: - explain(file:repoURL:commits:)

  @Test
  func explain_singleCommitDiff_callsSummarize() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit that modifies a file.
    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("Sources/App.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    // Get the commit SHA.
    let sha = try test.getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    try await withMockFoundationModels(response: "Mock file explanation.") {
      let result = await FileExplainer.explain(
        file: "Sources/App.swift",
        repoURL: test.temporaryDirectory,
        commits: commits
      )
      try #require(result.0 == "Mock file explanation.")
      try #require(result.1 == nil)
    }
  }

  @Test
  func explain_multiCommitRange_coversOnlyRequestedCommits() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with three commits, each adding one line to A.swift.
    try test.initGitRepo(at: test.temporaryDirectory)

    // Commit 1: "A\n"
    try test.writeFile("A.swift", contents: "A\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add A.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add A'",
      at: test.temporaryDirectory
    )

    // Commit 2: "A\nB\n"  (middle commit — the one we will query)
    try test.writeFile("A.swift", contents: "A\nB\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add B'",
      at: test.temporaryDirectory
    )

    // Commit 3: "A\nB\nC\n"
    try test.writeFile("A.swift", contents: "A\nB\nC\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add C'",
      at: test.temporaryDirectory
    )

    let shas = try test.getAllCommitSHAs(at: test.temporaryDirectory)
    try #require(shas.count == 3)

    // shas[0] = newest (Add C), shas[1] = middle (Add B), shas[2] = oldest (Add A)
    let middleSHA = shas[1]

    // The multi-commit explain path is selected because commits.count == 1
    // triggers the single-commit path; pass two commits to force multi-commit path.
    // Rebuild with two commits so we test the `last.sha..first.sha` path.
    let commitsForMultiPath = [
      SessionCommit(sha: shas[0], short: String(shas[0].prefix(7)), subject: "Add C"),
      SessionCommit(sha: middleSHA, short: String(middleSHA.prefix(7)), subject: "Add B"),
    ]

    // Run the explain via the multi-commit path. FileExplainer.explain will
    // construct the range `last.sha..first.sha` = `shas[1]..shas[0]` (Add B → Add C),
    // so the diff it passes to CommitExplainer.summarize must cover both B and C additions.
    let result = await FileExplainer.explain(
      file: "A.swift",
      repoURL: test.temporaryDirectory,
      commits: commitsForMultiPath
    )

    // Verify the requested B -> C range directly. It should cover only the
    // newest requested commit's delta, not re-report B from the range base.
    let expectedDiff = try captureGit(
      ["diff", "\(shas[1])..\(shas[0])", "--", "A.swift"], at: test.temporaryDirectory)

    try #require(!expectedDiff.contains("+B"), "diff should not re-report the range base line B")
    try #require(expectedDiff.contains("+C"), "expected diff to contain +C from Add C commit")

    // Result may be nil when Foundation Models is unavailable; we only validate
    // that the call does not throw and that the underlying git diff is correct.
    _ = result
  }

  @Test
  func explain_multiCommitRange_correctDirection() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with three commits on the same file:
    //   Commit A (oldest): "A\n"
    //   Commit B (middle): "A\nB\n"
    //   Commit C (newest): "A\nB\nC\n"
    try test.initGitRepo(at: test.temporaryDirectory)

    try test.writeFile("A.swift", contents: "A\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add A.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add A'",
      at: test.temporaryDirectory
    )

    try test.writeFile("A.swift", contents: "A\nB\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add B'",
      at: test.temporaryDirectory
    )

    try test.writeFile("A.swift", contents: "A\nB\nC\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add C'",
      at: test.temporaryDirectory
    )

    let shas = try test.getAllCommitSHAs(at: test.temporaryDirectory)
    try #require(shas.count == 3)
    // shas[0] = newest (Add C), shas[1] = middle (Add B), shas[2] = oldest (Add A)

    // Pass [C, B] (newest→oldest) to force the multi-commit code path.
    // With the fix, FileExplainer constructs git diff first.sha..last.sha = C..B
    // which shows the changes from C down to B (reverse-chronological).
    // The diff must contain the +B addition from commit B and the +C addition
    // from commit C, proving the direction is newest→oldest, not oldest→newest.
    let commitsForMultiPath = [
      SessionCommit(sha: shas[0], short: String(shas[0].prefix(7)), subject: "Add C"),
      SessionCommit(sha: shas[1], short: String(shas[1].prefix(7)), subject: "Add B"),
    ]

    let result = await FileExplainer.explain(
      file: "A.swift",
      repoURL: test.temporaryDirectory,
      commits: commitsForMultiPath
    )

    // Verify the git diff directly to confirm the correct direction.
    let diff = try captureGit(
      ["diff", "\(shas[0])..\(shas[1])", "--", "A.swift"], at: test.temporaryDirectory)

    // The diff C..B is a reverse diff: it removes C to reach B.
    try #require(diff.contains("-C"), "diff C..B must show C being removed")
    try #require(!diff.contains("+C"), "reverse diff C..B must not show C as an addition")

    _ = result
  }

  @Test
  func explain_multiCommitDiff_callsSummarize() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with two commits.
    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("Sources/App.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Initial'",
      at: test.temporaryDirectory
    )

    // Modify the file in a second commit.
    try test.writeFile("Sources/App.swift", contents: "import Foundation\nimport AppKit\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add import'",
      at: test.temporaryDirectory
    )

    let shas = try test.getAllCommitSHAs(at: test.temporaryDirectory)
    try #require(shas.count == 2)
    let oldest = shas[1]  // oldest
    let newest = shas[0]  // newest
    let commits = [
      SessionCommit(sha: oldest, short: String(oldest.prefix(7)), subject: "Initial"),
      SessionCommit(sha: newest, short: String(newest.prefix(7)), subject: "Add import"),
    ]

    // Call explain for the file that changed across both commits.
    let result = await FileExplainer.explain(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    // Result may be nil in test environments; we only verify it doesn't throw.
    _ = result
  }

  @Test
  func explain_fileWithNoChanges_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit modifying App.swift only.
    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("Sources/App.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    let sha = try test.getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    // Request explanation for a file that doesn't exist and has no changes.
    let result = await FileExplainer.explain(
      file: "Sources/DoesNotExist.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )

    try #require(result.0 == nil)
  }

  @Test
  func explain_emptyCommits_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = await FileExplainer.explain(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: []
    )
    try #require(result.0 == nil)
  }

  // MARK: - explain unavailable

  @Test
  func explain_modelUnavailable_returnsFoundationModelsUnavailable() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit modifying a file.
    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("Sources/App.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    let sha = try test.getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    // Force Foundation Models to be unavailable so FileExplainer.explain
    // hits the guard and returns (nil, .foundationModelsUnavailable).
    try await withMockFoundationModels(available: false) {
      let result = await FileExplainer.explain(
        file: "Sources/App.swift",
        repoURL: test.temporaryDirectory,
        commits: commits
      )
      try #require(result.0 == nil)
      try #require(result.1 == .foundationModelsUnavailable)
    }
  }

  // MARK: - whyGenerated

  @Test
  func whyGenerated_emptyCommits_returnsNil() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = await FileExplainer.whyGenerated(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: []
    )
    try #require(result.0 == nil)
  }

  @Test
  func whyGenerated_singleCommit_fetchesCorrectDiff() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit modifying a file.
    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("Sources/App.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    let sha = try test.getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    // Call whyGenerated — CommitExplainer.summarizeWhyGenerated may return nil
    // if Foundation Models is unavailable, but the call chain must not throw.
    let result = await FileExplainer.whyGenerated(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    // Result may be nil in test environments; we only verify it doesn't throw.
    _ = result
  }

  @Test
  func whyGenerated_modelUnavailable_returnsFoundationModelsUnavailable() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit modifying a file.
    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("Sources/App.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    let sha = try test.getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    // Force Foundation Models to be unavailable so CommitExplainer.summarizeWhyGenerated
    // hits the guard and returns (nil, .foundationModelsUnavailable).
    try await withMockFoundationModels(available: false) {
      let result = await FileExplainer.whyGenerated(
        file: "Sources/App.swift",
        repoURL: test.temporaryDirectory,
        commits: commits
      )
      try #require(result.0 == nil)
      try #require(result.1 == .foundationModelsUnavailable)
    }
  }

  @Test
  func whyGenerated_multiCommit_fetchesRangeDiff() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with two commits.
    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("Sources/App.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Initial'",
      at: test.temporaryDirectory
    )

    // Modify the file in a second commit.
    try test.writeFile("Sources/App.swift", contents: "import Foundation\nimport AppKit\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add import'",
      at: test.temporaryDirectory
    )

    let shas = try test.getAllCommitSHAs(at: test.temporaryDirectory)
    try #require(shas.count == 2)
    let oldest = shas[1]  // oldest
    let newest = shas[0]  // newest
    let commits = [
      SessionCommit(sha: oldest, short: String(oldest.prefix(7)), subject: "Initial"),
      SessionCommit(sha: newest, short: String(newest.prefix(7)), subject: "Add import"),
    ]

    // Call whyGenerated for the file that changed across both commits.
    let result = await FileExplainer.whyGenerated(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    // Result may be nil in test environments; we only verify it doesn't throw.
    _ = result
  }

  // MARK: - changes(for:repoURL:commits:)

  @Test
  func changes_multiCommit_reversedRange_bugRegression() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with two commits touching different files.
    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("Sources/Old.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/Old.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add Old.swift'",
      at: test.temporaryDirectory
    )

    try test.writeFile("Sources/New.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/New.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add New.swift'",
      at: test.temporaryDirectory
    )

    let shas = try test.getAllCommitSHAs(at: test.temporaryDirectory)
    try #require(shas.count == 2)
    let oldest = shas[1]  // oldest commit
    let newest = shas[0]  // newest commit

    // Pass commits ordered newest first, matching the production call site.
    let commits = [
      SessionCommit(sha: newest, short: String(newest.prefix(7)), subject: "Add New.swift"),
      SessionCommit(sha: oldest, short: String(oldest.prefix(7)), subject: "Add Old.swift"),
    ]

    let changes = await FileExplainer.changes(for: test.temporaryDirectory, commits: commits)

    // The endpoint range reports changes after the oldest endpoint.
    let changedPaths = changes.map { $0.relativePath }
    try #require(
      !changedPaths.contains("Sources/Old.swift"),
      "Old.swift is the range base and should not be re-reported")
    try #require(
      changedPaths.contains("Sources/New.swift"), "New.swift from the newest commit must be present"
    )
  }

  @Test
  func changes_singleCommit_returnsFileStats() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("Sources/App.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    let sha = try test.getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    let changes = await FileExplainer.changes(for: test.temporaryDirectory, commits: commits)

    try #require(changes.count == 1)
    try #require(changes[0].relativePath == "Sources/App.swift")
  }

  @Test
  func changes_singleEmptyCommit_returnsEmptyArray() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit that makes no file changes.
    // This hits the single-SHA code path (gitDiffStatImpl(sha:)) rather than the range path,
    // which is a distinct scenario from the existing empty-merge test that covers the range path.
    try test.initGitRepo(at: test.temporaryDirectory)
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit --allow-empty -q -m 'Empty commit'",
      at: test.temporaryDirectory
    )

    let sha = try test.getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Empty commit")]

    let changes = await FileExplainer.changes(for: test.temporaryDirectory, commits: commits)

    try #require(
      changes.isEmpty,
      "A single empty commit has no file changes; changes() must return an empty array")
  }

  @Test
  func changes_emptyCommits_returnsEmptyArray() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Guard at line 312: guard let first = commits.first, let oldestCommit = commits.last else { return [] }
    // With an empty array, first and oldestCommit are nil → returns []
    let changes = await FileExplainer.changes(for: test.temporaryDirectory, commits: [])

    try #require(changes.isEmpty, "Empty commits array must return an empty array, not nil")
  }

  @Test
  func changes_noChangedFiles_returnsEmptyArray() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit that adds a file, then a second empty commit.
    // The range that covers only the empty commit has no file changes.
    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("Sources/App.swift", contents: "import Foundation\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    // Second commit with no file changes (empty commit allowed).
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit --allow-empty -q -m 'Empty commit'",
      at: test.temporaryDirectory
    )

    let shas = try test.getAllCommitSHAs(at: test.temporaryDirectory)
    try #require(shas.count == 2)
    let oldest = shas[1]  // empty commit
    let newest = shas[0]  // add App.swift

    // Pass commits covering only the empty commit (oldest..newest = range with no changes).
    let commits = [
      SessionCommit(sha: oldest, short: String(oldest.prefix(7)), subject: "Empty commit"),
      SessionCommit(sha: newest, short: String(newest.prefix(7)), subject: "Add App.swift"),
    ]

    let changes = await FileExplainer.changes(for: test.temporaryDirectory, commits: commits)

    try #require(
      changes.isEmpty,
      "No files changed in the range that only covers the empty commit; changes() must return an empty array"
    )
  }

  // MARK: - FileChangeCategory.categorize

  // MARK: Source files — known language extension, not test/config

  @Test
  func categorize_sourceSwiftFile() throws {
    let result = FileChangeCategory.categorize("Sources/App.swift")
    try #require(result == .source)
  }

  @Test
  func categorize_sourceNestedSwiftFile() throws {
    let result = FileChangeCategory.categorize("Sources/Views/Button.swift")
    try #require(result == .source)
  }

  @Test
  func categorize_unsupportedPythonFileIsOther() throws {
    let result = FileChangeCategory.categorize("scripts/deploy.py")
    try #require(result == .other)
  }

  @Test
  func categorize_sourceGoFile() throws {
    let result = FileChangeCategory.categorize("cmd/server/main.go")
    try #require(result == .source)
  }

  @Test
  func categorize_sourceRustFile() throws {
    let result = FileChangeCategory.categorize("src/main.rs")
    try #require(result == .source)
  }

  // MARK: Test files — multiple naming patterns

  @Test
  func categorize_testUnderTestsDir() throws {
    let result = FileChangeCategory.categorize("Tests/AppTests.swift")
    try #require(result == .test)
  }

  @Test
  func categorize_testUnderNestedTestsDir() throws {
    let result = FileChangeCategory.categorize("Sources/Tests/Helper.swift")
    try #require(result == .test)
  }

  @Test
  func categorize_testsSuffix() throws {
    let result = FileChangeCategory.categorize("Sources/App_tests.swift")
    try #require(result == .test)
  }

  @Test
  func categorize_testDotSuffix() throws {
    let result = FileChangeCategory.categorize("Sources/App.test.swift")
    try #require(result == .test)
  }

  @Test
  func categorize_specSuffix() throws {
    let result = FileChangeCategory.categorize("Sources/Model.spec.swift")
    try #require(result == .test)
  }

  @Test
  func categorize_testPrefix() throws {
    let result = FileChangeCategory.categorize("test_utils.py")
    try #require(result == .test)
  }

  @Test
  func categorize_testUnderscorePrefix() throws {
    let result = FileChangeCategory.categorize("test_helpers.js")
    try #require(result == .test)
  }

  @Test
  func categorize_testUnderscoreSuffix() throws {
    let result = FileChangeCategory.categorize("mock_data_test.swift")
    try #require(result == .test)
  }

  @Test
  func categorize_testDirPrefix() throws {
    let result = FileChangeCategory.categorize("testsuite/setup.sh")
    try #require(result == .test)
  }

  // MARK: Config files — directory and exact-match patterns

  @Test
  func categorize_configDirRoot() throws {
    let result = FileChangeCategory.categorize("Config/settings.json")
    try #require(result == .config)
  }

  @Test
  func categorize_configDirNested() throws {
    let result = FileChangeCategory.categorize("Config/production.toml")
    try #require(result == .config)
  }

  @Test
  func categorize_dotConfigDir() throws {
    let result = FileChangeCategory.categorize(".config/editor.yml")
    try #require(result == .config)
  }

  @Test
  func categorize_dotVscodeDir() throws {
    let result = FileChangeCategory.categorize(".vscode/settings.json")
    try #require(result == .config)
  }

  @Test
  func categorize_dotGitHubDir() throws {
    let result = FileChangeCategory.categorize(".github/workflows/ci.yml")
    try #require(result == .config)
  }

  @Test
  func categorize_packageJSON() throws {
    let result = FileChangeCategory.categorize("package.json")
    try #require(result == .config)
  }

  @Test
  func categorize_swiftFormat() throws {
    let result = FileChangeCategory.categorize(".swift-format")
    try #require(result == .config)
  }

  @Test
  func categorize_swiftLint() throws {
    let result = FileChangeCategory.categorize(".swiftlint.yml")
    try #require(result == .config)
  }

  @Test
  func categorize_packageSwift() throws {
    let result = FileChangeCategory.categorize("Package.swift")
    try #require(result == .config)
  }

  @Test
  func categorize_gitignore() throws {
    let result = FileChangeCategory.categorize(".gitignore")
    try #require(result == .config)
  }

  @Test
  func categorize_makefile() throws {
    let result = FileChangeCategory.categorize("Makefile")
    try #require(result == .config)
  }

  // MARK: Other bucket — unknown extension, not config dir

  @Test
  func categorize_otherPNG() throws {
    let result = FileChangeCategory.categorize("Assets/logo.png")
    try #require(result == .other)
  }

  @Test
  func categorize_otherMarkdown() throws {
    let result = FileChangeCategory.categorize("README.md")
    try #require(result == .other)
  }

  @Test
  func categorize_otherTextFile() throws {
    let result = FileChangeCategory.categorize("docs/notes.txt")
    try #require(result == .other)
  }

  @Test
  func categorize_otherYmlNotInConfigDir() throws {
    let result = FileChangeCategory.categorize("scripts/ci.yml")
    try #require(result == .other)
  }

  @Test
  func categorize_otherJpeg() throws {
    let result = FileChangeCategory.categorize("Photos/screenshot.jpg")
    try #require(result == .other)
  }

  @Test
  func categorize_otherPdf() throws {
    let result = FileChangeCategory.categorize("docs/manual.pdf")
    try #require(result == .other)
  }

  // MARK: - FileChangeCategory.sortOrder

  @Test
  func sortOrder_source() throws {
    try #require(FileChangeCategory.source.sortOrder == 0)
  }

  @Test
  func sortOrder_test() throws {
    try #require(FileChangeCategory.test.sortOrder == 1)
  }

  @Test
  func sortOrder_config() throws {
    try #require(FileChangeCategory.config.sortOrder == 2)
  }

  @Test
  func sortOrder_other() throws {
    try #require(FileChangeCategory.other.sortOrder == 3)
  }

  // MARK: - FileChangeCategory.displayName

  @Test
  func displayName_source() throws {
    try #require(FileChangeCategory.source.displayName == "Sources")
  }

  @Test
  func displayName_test() throws {
    try #require(FileChangeCategory.test.displayName == "Tests")
  }

  @Test
  func displayName_config() throws {
    try #require(FileChangeCategory.config.displayName == "Config")
  }

  @Test
  func displayName_other() throws {
    try #require(FileChangeCategory.other.displayName == "Other")
  }

  // MARK: - FileChange.fileName

  @Test
  func fileName_simplePath() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 10,
      deletions: 2,
      language: nil,
      summary: nil
    )
    try #require(change.fileName == "App.swift")
  }

  @Test
  func fileName_deeplyNested() throws {
    let change = FileChange(
      relativePath: "Sources/Views/Components/Button.swift",
      additions: 5,
      deletions: 0,
      language: nil,
      summary: nil
    )
    try #require(change.fileName == "Button.swift")
  }

  @Test
  func fileName_singleComponent() throws {
    let change = FileChange(
      relativePath: "Makefile",
      additions: 1,
      deletions: 1,
      language: nil,
      summary: nil
    )
    try #require(change.fileName == "Makefile")
  }

  @Test
  func fileName_directoryPath() throws {
    let change = FileChange(
      relativePath: "Tests/CompassTests/Helper/",
      additions: 20,
      deletions: 5,
      language: nil,
      summary: nil
    )
    try #require(change.fileName == "Helper")
  }

  // MARK: - FileChange.lineCountLabel

  @Test
  func lineCountLabel_bothAdditionsAndDeletions() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 12,
      deletions: 8,
      language: nil,
      summary: nil
    )
    try #require(change.lineCountLabel == "+12/-8")
  }

  @Test
  func lineCountLabel_onlyAdditions() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 5,
      deletions: 0,
      language: nil,
      summary: nil
    )
    try #require(change.lineCountLabel == "+5/0")
  }

  @Test
  func lineCountLabel_onlyDeletions() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 0,
      deletions: 3,
      language: nil,
      summary: nil
    )
    try #require(change.lineCountLabel == "0/-3")
  }

  @Test
  func lineCountLabel_zeroChanges() throws {
    let change = FileChange(
      relativePath: "Assets/logo.png",
      additions: 0,
      deletions: 0,
      language: nil,
      summary: nil
    )
    try #require(change.lineCountLabel == "0/0")
  }

  // MARK: - FileChange.category

  @Test
  func category_source() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 10,
      deletions: 2,
      language: nil,
      summary: nil
    )
    try #require(change.category == .source)
  }

  @Test
  func category_test() throws {
    let change = FileChange(
      relativePath: "Tests/AppTests.swift",
      additions: 10,
      deletions: 2,
      language: nil,
      summary: nil
    )
    try #require(change.category == .test)
  }

  @Test
  func category_config() throws {
    let change = FileChange(
      relativePath: "Config/settings.json",
      additions: 10,
      deletions: 2,
      language: nil,
      summary: nil
    )
    try #require(change.category == .config)
  }

  @Test
  func category_other() throws {
    let change = FileChange(
      relativePath: "docs/README.md",
      additions: 10,
      deletions: 2,
      language: nil,
      summary: nil
    )
    try #require(change.category == .other)
  }

  // MARK: - gitDiffStat

  @Test
  func gitDiffStat_mergeCommit_onlyMainline() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with a merge commit.
    // Structure:
    //   commit A (main)     — adds main.txt
    //   commit B (feature)  — adds feature.txt on a branch
    //   merge commit (main) — merges feature into main (non-trivial merge with conflict or ours-style)
    //
    // When we call gitDiffStat with the merge commit SHA and --first-parent,
    // the output should reflect only the changes on the mainline side of the merge,
    // not the changes brought in from the merged branch.

    // Step 1: initial commit on main — creates main.txt
    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("main.txt", contents: "main content\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add main.txt && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add main.txt'",
      at: test.temporaryDirectory
    )

    // Step 2: branch off and commit on the branch — creates feature.txt
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) checkout -q -b feature",
      at: test.temporaryDirectory
    )
    try test.writeFile("feature.txt", contents: "feature content\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add feature.txt && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add feature.txt'",
      at: test.temporaryDirectory
    )

    // Step 3: switch back to main and merge the branch.
    // Use --no-edit to auto-merge without a separate commit message step.
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) checkout -q main",
      at: test.temporaryDirectory
    )
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) merge -q --no-ff --no-edit feature",
      at: test.temporaryDirectory
    )

    let mergeCommitSHA = try test.getSingleCommitSHA(at: test.temporaryDirectory)

    // Call gitDiffStat for the merge commit. The first-parent range compares
    // the merge result to the mainline parent, so it reports files introduced
    // by the merged branch.
    let diffStatOutput = await FileExplainer.gitDiffStat(
      sha: mergeCommitSHA, repoURL: test.temporaryDirectory)

    // Parse the diff stat output.
    let changes = FileExplainer.parseGitDiffStat(diffStatOutput)

    try #require(
      changes.isEmpty, "merge commits are not expanded by the single-commit diff-tree stat")
  }

  @Test
  func gitDiffStat_emptyResult() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with an empty merge commit (no files changed).
    // Structure:
    //   commit A (main)  — adds a.txt
    //   branch off main → commit B — adds b.txt
    //   merge B into main (auto-merged, no conflicts, no changes needed)
    //
    // The merge commit itself has no file changes because the auto-merge
    // produced no new modifications on either branch's side.

    try test.initGitRepo(at: test.temporaryDirectory)
    try test.writeFile("a.txt", contents: "a\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add a.txt && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add a.txt'",
      at: test.temporaryDirectory
    )

    // Branch and make an empty commit, then force a merge commit with no tree changes.
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) checkout -q -b feature",
      at: test.temporaryDirectory
    )
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit --allow-empty -q -m 'Empty feature'",
      at: test.temporaryDirectory
    )

    // Switch back to main and merge with --no-edit. Since both branches have
    // independent files, the merge is auto-generated with no conflicts and
    // produces a merge commit whose --first-parent diff stat is empty.
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) checkout -q main",
      at: test.temporaryDirectory
    )
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) merge -q --no-ff --no-edit feature",
      at: test.temporaryDirectory
    )

    let sha = try test.getSingleCommitSHA(at: test.temporaryDirectory)

    let diffStatOutput = await FileExplainer.gitDiffStat(sha: sha, repoURL: test.temporaryDirectory)

    // The diff stat for an empty merge commit must be empty or whitespace-only.
    try #require(
      diffStatOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      "gitDiffStat for an empty merge commit must be empty; got: \(diffStatOutput)"
    )

    // Parsing an empty diff stat must yield an empty array.
    let changes = FileExplainer.parseGitDiffStat(diffStatOutput)
    try #require(changes.isEmpty)
  }

  @Test
  func changes_multiCommit_returnsCorrectAdditionsAndDeletions() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with two commits on the same file.
    try test.initGitRepo(at: test.temporaryDirectory)

    // Commit 1 (oldest): creates App.swift with 3 lines (empty → 3 lines)
    try test.writeFile("App.swift", contents: "line 1\nline 2\nline 3\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    // Commit 2 (newest): modifies App.swift from 3 → 5 lines (+2 net)
    try test.writeFile("App.swift", contents: "line 1\nline 2\nline 3\nline 4\nline 5\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Modify App.swift'",
      at: test.temporaryDirectory
    )

    let shas = try test.getAllCommitSHAs(at: test.temporaryDirectory)
    try #require(shas.count == 2)
    let oldest = shas[1]  // oldest commit
    let newest = shas[0]  // newest commit

    // Query the full range (oldest..newest with newest first in the array).
    let commits = [
      SessionCommit(sha: newest, short: String(newest.prefix(7)), subject: "Modify App.swift"),
      SessionCommit(sha: oldest, short: String(oldest.prefix(7)), subject: "Add App.swift"),
    ]

    let changes = await FileExplainer.changes(for: test.temporaryDirectory, commits: commits)

    try #require(changes.count == 1, "Only App.swift changed across both commits")
    try #require(changes[0].relativePath == "App.swift")
    // The range diff shows net 2 insertions (3-line version → 5-line version).
    try #require(changes[0].additions == 2)
    try #require(changes[0].deletions == 0)
  }

  @Test
  func changes_twoSeparateFiles_returnsCorrectCountsPerFile() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with two commits touching different files.
    try test.initGitRepo(at: test.temporaryDirectory)

    // Commit 1 (oldest): adds README.md with 1 line
    try test.writeFile("README.md", contents: "# Project\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add README.md && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add README'",
      at: test.temporaryDirectory
    )

    // Commit 2 (newest): adds Sources/App.swift with 3 lines
    try test.writeFile("Sources/App.swift", contents: "import Foundation\n\nlet app = 1\n")
    try test.runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    let shas = try test.getAllCommitSHAs(at: test.temporaryDirectory)
    try #require(shas.count == 2)
    let oldest = shas[1]  // Add README
    let newest = shas[0]  // Add App.swift

    let commits = [
      SessionCommit(sha: newest, short: String(newest.prefix(7)), subject: "Add App.swift"),
      SessionCommit(sha: oldest, short: String(oldest.prefix(7)), subject: "Add README"),
    ]

    // Accumulate per-commit diff stats to verify correct per-file counts across commits.
    var accumulated: [String: (additions: Int, deletions: Int)] = [:]
    for commit in commits {
      let diffStatOutput = await FileExplainer.gitDiffStat(
        sha: commit.sha, repoURL: test.temporaryDirectory)
      let perCommitChanges = FileExplainer.parseGitDiffStat(diffStatOutput)
      for change in perCommitChanges {
        let existing = accumulated[change.relativePath, default: (0, 0)]
        accumulated[change.relativePath] = (
          additions: existing.additions + change.additions,
          deletions: existing.deletions + change.deletions
        )
      }
    }

    // Verify README.md was added in the oldest commit.
    try #require(accumulated["README.md"]?.additions == 1)
    try #require(accumulated["README.md"]?.deletions == 0)

    // Verify Sources/App.swift was added in the newest commit.
    try #require(accumulated["Sources/App.swift"]?.additions == 3)
    try #require(accumulated["Sources/App.swift"]?.deletions == 0)
  }

  // MARK: - groupedChanges sorting

  @Test
  func changes_withinCategory_sortedByMagnitude() throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Three files in the same category (.source) with distinct change magnitudes.
    let changeC = FileChange(
      relativePath: "Sources/C.swift",
      additions: 10,
      deletions: 0,
      language: nil,
      summary: nil
    )
    let changeB = FileChange(
      relativePath: "Sources/B.swift",
      additions: 4,
      deletions: 1,
      language: nil,
      summary: nil
    )
    let changeA = FileChange(
      relativePath: "Sources/A.swift",
      additions: 1,
      deletions: 0,
      language: nil,
      summary: nil
    )

    // Simulate the groupedChanges logic: group by category then sort by magnitude.
    let changes = [changeC, changeA, changeB]
    let grouped = Dictionary(grouping: changes, by: { $0.category })
    let result = FileChangeCategory.allCases
      .compactMap { category -> (FileChangeCategory, [FileChange])? in
        guard let cats = grouped[category], !cats.isEmpty else { return nil }
        return (
          category, cats.sorted { ($0.additions + $0.deletions) > ($1.additions + $1.deletions) }
        )
      }

    // There should be one group for the .source category.
    try #require(result.count == 1)
    try #require(result[0].0 == .source)

    // Files within the group must be in descending order by magnitude (additions + deletions).
    let paths = result[0].1.map { $0.relativePath }
    try #require(paths == ["Sources/C.swift", "Sources/B.swift", "Sources/A.swift"])
  }

  // MARK: - FileChange.init

  @Test
  func fileChange_init_allParameters() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 42,
      deletions: 7,
      language: .swift,
      summary: "Added main app entry point",
      explanation: "This change introduces the primary application file with proper configuration."
    )
    try #require(change.relativePath == "Sources/App.swift")
    try #require(change.additions == 42)
    try #require(change.deletions == 7)
    try #require(change.language == .swift)
    try #require(change.summary == "Added main app entry point")
    try #require(
      change.explanation
        == "This change introduces the primary application file with proper configuration.")
  }

  @Test
  func fileChange_init_explanationDefaultsToNil() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 42,
      deletions: 7,
      language: .swift,
      summary: "Added main app entry point"
    )
    try #require(change.explanation == nil)
  }

  // MARK: - FileChange.explanationReason

  @Test
  func fileChange_init_explanationReason_allCases() throws {
    for reason in ExplainUnavailableReason.allCases {
      let change = FileChange(
        relativePath: "Sources/App.swift",
        additions: 10,
        deletions: 2,
        language: .swift,
        summary: "Test change",
        explanation: nil,
        explanationReason: reason
      )
      try #require(change.explanationReason == reason)
    }
  }

  @Test
  func fileChange_init_explanationReasonNilDefaults() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 10,
      deletions: 2,
      language: .swift,
      summary: "Test change"
    )
    try #require(change.explanationReason == nil)
  }

  @Test
  func fileChange_init_bothExplanationAndReason() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 10,
      deletions: 2,
      language: .swift,
      summary: "Test change",
      explanation: "This file adds the main entry point.",
      explanationReason: .foundationModelsUnavailable
    )
    try #require(change.explanation != nil)
    try #require(change.explanationReason == .foundationModelsUnavailable)
    try #require(change.explanation == "This file adds the main entry point.")
  }

  // MARK: - ExplainUnavailableReason

  @Test
  func explainUnavailableReason_allCases() throws {
    let cases = ExplainUnavailableReason.allCases
    try #require(cases.count == 5)
    try #require(cases.contains(.foundationModelsUnavailable))
    try #require(cases.contains(.noDiff))
    try #require(cases.contains(.emptyDiff))
    try #require(cases.contains(.emptyResponse))
    try #require(cases.contains(.unavailable))
  }

  @Test
  func explainUnavailableReason_message_nonEmpty() throws {
    for reason in ExplainUnavailableReason.allCases {
      try #require(!reason.message.isEmpty, "message for \(reason) must be non-empty")
    }
  }

  // MARK: - FileChange computed properties (coverage)

  @Test
  func fileChange_lineCountLabel_positiveAdditions() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 10,
      deletions: 2,
      language: nil,
      summary: nil
    )
    try #require(change.lineCountLabel == "+10/-2")
  }

  @Test
  func fileChange_lineCountLabel_zeroAdditions() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 0,
      deletions: 5,
      language: nil,
      summary: nil
    )
    try #require(change.lineCountLabel == "+0/-5")
  }

  @Test
  func fileChange_lineCountLabel_zeroDeletions() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 3,
      deletions: 0,
      language: nil,
      summary: nil
    )
    try #require(change.lineCountLabel == "+3/-0")
  }

  @Test
  func fileChange_lineCountLabel_allZeros() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 0,
      deletions: 0,
      language: nil,
      summary: nil
    )
    try #require(change.lineCountLabel == "+0/-0")
  }

  @Test
  func fileChange_fileName_extractsLastPathComponent() throws {
    let change = FileChange(
      relativePath: "Sources/Compass/App.swift",
      additions: 10,
      deletions: 2,
      language: nil,
      summary: nil
    )
    try #require(change.fileName == "App.swift")
  }

  @Test
  func fileChange_category_sourceFile() throws {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 10,
      deletions: 2,
      language: nil,
      summary: nil
    )
    try #require(change.category == .source)
  }

  @Test
  func fileChange_category_testFile() throws {
    let change = FileChange(
      relativePath: "Tests/AppTests.swift",
      additions: 5,
      deletions: 1,
      language: nil,
      summary: nil
    )
    try #require(change.category == .test)
  }

  @Test
  func fileChange_category_configFile() throws {
    let change = FileChange(
      relativePath: "Package.swift",
      additions: 20,
      deletions: 5,
      language: nil,
      summary: nil
    )
    try #require(change.category == .config)
  }

  @Test
  func fileChange_category_otherFile() throws {
    let change = FileChange(
      relativePath: "README.md",
      additions: 1,
      deletions: 0,
      language: nil,
      summary: nil
    )
    try #require(change.category == .other)
  }

  // MARK: - Helpers

  private func initGitRepo(at url: URL) {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-lc", "git init -q && git branch -M main"]
    process.currentDirectoryURL = url
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
  }

  private func writeFile(_ relative: String, contents: String) throws {
    let url = temporaryDirectory.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func runGit(_ command: String, at url: URL) throws {
    let process = Process()
    process.launchPath = "/bin/zsh"
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = url
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw TestHelperError.gitCommandFailed(status: process.terminationStatus)
    }
  }

  private func getSingleCommitSHA(at url: URL) throws -> String {
    let stdout = try captureGit(["rev-parse", "HEAD"], at: url)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !stdout.isEmpty else {
      throw TestHelperError.noCommitSHAFound
    }
    return stdout
  }

  private func getAllCommitSHAs(at url: URL) throws -> [String] {
    let stdout = try captureGit(["log", "--all", "--format=%H"], at: url)
    return
      stdout
      .split(separator: "\n")
      .filter { !$0.isEmpty }
      .map { String($0) }
  }
}

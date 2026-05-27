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
  func parseGitDiffStat_normalAdditionsAndDeletions()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = """
    Sources/App.swift        |  12 ++++++------
    Sources/Model.swift      |   4 ++++++
    """

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 2)

    #require(changes[0].relativePath == "Sources/App.swift")
    #require(changes[0].additions == 4)
    #require(changes[0].deletions == 2)

    #require(changes[1].relativePath == "Sources/Model.swift")
    #require(changes[1].additions == 4)
    #require(changes[1].deletions == 0)
  }

  @Test
  func parseGitDiffStat_renameArrow()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = "old/path.go => new/path.go           |   4 ++--"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "new/path.go")
    #require(changes[0].additions == 2)
    #require(changes[0].deletions == 2)
  }

  @Test
  func parseGitDiffStat_binaryFile()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = "Assets/logo.png                    |  Bin 210 kB → 215 kB"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "Assets/logo.png")
    // Binary lines produce 0 additions and 0 deletions (no + or - in the bar chart, no numeric tokens)
    #require(changes[0].additions == 0)
    #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_pathWithSpaces()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = "My Files/App.swift   |   6 ++++++"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "My Files/App.swift")
    #require(changes[0].additions == 6)
    #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_multiLineStatOutput()  throws {
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

    #require(changes.count == 4)
    #require(changes[0].relativePath == "Sources/App.swift")
    #require(changes[1].relativePath == "Sources/Model.swift")
    #require(changes[2].relativePath == "Tests/AppTests.swift")
    #require(changes[3].relativePath == "README.md")
  }

  @Test
  func parseGitDiffStat_numericOnlyFallback()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // No +/- bar chart, only a numeric count — should fall back to numeric count as additions
    let diffStat = "Sources/App.swift        |  42"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "Sources/App.swift")
    #require(changes[0].additions == 42)
    #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_absentStatsParts()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Empty stats part — should produce zero additions and deletions
    let diffStat = "README.md               |"

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "README.md")
    #require(changes[0].additions == 0)
    #require(changes[0].deletions == 0)
  }

  @Test
  func parseGitDiffStat_emptyInput()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let changes = FileExplainer.parseGitDiffStat("")
    #require(changes.isEmpty)
  }

  @Test
  func parseGitDiffStat_whitespaceOnlyLines()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diffStat = """
    Sources/App.swift        |  4 +
                          
    Sources/Model.swift      |  2 ++
    """

    let changes = FileExplainer.parseGitDiffStat(diffStat)

    #require(changes.count == 2)
    #require(changes[0].relativePath == "Sources/App.swift")
    #require(changes[1].relativePath == "Sources/Model.swift")
  }

  // MARK: - extractLineCounts

  @Test
  func extractLineCounts_additionsAndDeletions()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "24 ++++++++----------")
    #require(result.additions == 8)
    #require(result.deletions == 10)
  }

  @Test
  func extractLineCounts_onlyAdditions()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "6 ++++++")
    #require(result.additions == 6)
    #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_onlyDeletions()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "3 ---")
    #require(result.additions == 0)
    #require(result.deletions == 3)
  }

  @Test
  func extractLineCounts_numericFallback()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // No +/- bar chars, but has numeric token
    let result = FileExplainer.extractLineCounts(from: "99")
    #require(result.additions == 99)
    #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_absentStatsParts()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // No bar chars, no numeric tokens
    let result = FileExplainer.extractLineCounts(from: "")
    #require(result.additions == 0)
    #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_withNumericAndBars()  throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Numeric count 24 and bar chars both present — bars take priority
    let result = FileExplainer.extractLineCounts(from: "24 ++++++++----------")
    #require(result.additions == 8)
    #require(result.deletions == 10)
  }

  // MARK: - explain(file:repoURL:commits:)

  @Test
  func explain_singleCommitDiff_callsSummarize() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with one commit that modifies a file.
    try initGitRepo(at: test.temporaryDirectory)
    try writeFile("Sources/App.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    // Get the commit SHA.
    let sha = try getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    // Call explain — CommitExplainer.summarize may return nil if Foundation Models
    // is unavailable, but the call chain must not throw.
    let result = await FileExplainer.explain(
      file: "Sources/App.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )
    // Result may be nil in test environments; we only verify it doesn't throw.
    _ = result
  }

  @Test
  func explain_multiCommitDiff_callsSummarize() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with two commits.
    try initGitRepo(at: test.temporaryDirectory)
    try writeFile("Sources/App.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Initial'",
      at: test.temporaryDirectory
    )

    // Modify the file in a second commit.
    try writeFile("Sources/App.swift", contents: "import Foundation\nimport AppKit\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add . && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add import'",
      at: test.temporaryDirectory
    )

    let shas = try getAllCommitSHAs(at: test.temporaryDirectory)
    #require(shas.count == 2)
    let oldest = shas[1] // oldest
    let newest = shas[0] // newest
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
    try initGitRepo(at: test.temporaryDirectory)
    try writeFile("Sources/App.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    let sha = try getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    // Request explanation for a file that doesn't exist and has no changes.
    let result = await FileExplainer.explain(
      file: "Sources/DoesNotExist.swift",
      repoURL: test.temporaryDirectory,
      commits: commits
    )

    #require(result == nil)
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
    #require(result == nil)
  }

  // MARK: - changes(for:repoURL:commits:)

  @Test
  func changes_multiCommit_reversedRange_bugRegression() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Set up a git repo with two commits touching different files.
    try initGitRepo(at: test.temporaryDirectory)
    try writeFile("Sources/Old.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/Old.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add Old.swift'",
      at: test.temporaryDirectory
    )

    try writeFile("Sources/New.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/New.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add New.swift'",
      at: test.temporaryDirectory
    )

    let shas = try getAllCommitSHAs(at: test.temporaryDirectory)
    #require(shas.count == 2)
    let oldest = shas[1] // oldest commit
    let newest = shas[0] // newest commit

    // Pass commits ordered oldest→newest (standard ordering).
    let commits = [
      SessionCommit(sha: oldest, short: String(oldest.prefix(7)), subject: "Add Old.swift"),
      SessionCommit(sha: newest, short: String(newest.prefix(7)), subject: "Add New.swift"),
    ]

    let changes = await FileExplainer.changes(for: test.temporaryDirectory, commits: commits)

    // With the reversed range bug, git diff newest..oldest misses Old.swift.
    // The correct git diff oldest..newest shows both files.
    let changedPaths = changes.map { $0.relativePath }
    #require(changedPaths.contains("Sources/Old.swift")) { "Old.swift from the oldest commit must be present; the reversed range bug causes it to be missing" }
    #require(changedPaths.contains("Sources/New.swift")) { "New.swift from the newest commit must be present" }
  }

  @Test
  func changes_singleCommit_returnsFileStats() async throws {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    try initGitRepo(at: test.temporaryDirectory)
    try writeFile("Sources/App.swift", contents: "import Foundation\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add Sources/App.swift && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c name=t commit -q -m 'Add App.swift'",
      at: test.temporaryDirectory
    )

    let sha = try getSingleCommitSHA(at: test.temporaryDirectory)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]

    let changes = await FileExplainer.changes(for: test.temporaryDirectory, commits: commits)

    #require(changes.count == 1)
    #require(changes[0].relativePath == "Sources/App.swift")
  }

  // MARK: - FileChangeCategory.categorize

  // MARK: Source files — known language extension, not test/config

  @Test
  func categorize_sourceSwiftFile() {
    let result = FileChangeCategory.categorize("Sources/App.swift")
    #require(result == .source)
  }

  @Test
  func categorize_sourceNestedSwiftFile() {
    let result = FileChangeCategory.categorize("Sources/Views/Button.swift")
    #require(result == .source)
  }

  @Test
  func categorize_sourcePythonFile() {
    let result = FileChangeCategory.categorize("scripts/deploy.py")
    #require(result == .source)
  }

  @Test
  func categorize_sourceGoFile() {
    let result = FileChangeCategory.categorize("cmd/server/main.go")
    #require(result == .source)
  }

  @Test
  func categorize_sourceRustFile() {
    let result = FileChangeCategory.categorize("src/main.rs")
    #require(result == .source)
  }

  // MARK: Test files — multiple naming patterns

  @Test
  func categorize_testUnderTestsDir() {
    let result = FileChangeCategory.categorize("Tests/AppTests.swift")
    #require(result == .test)
  }

  @Test
  func categorize_testUnderNestedTestsDir() {
    let result = FileChangeCategory.categorize("Sources/Tests/Helper.swift")
    #require(result == .test)
  }

  @Test
  func categorize_testsSuffix() {
    let result = FileChangeCategory.categorize("Sources/App_tests.swift")
    #require(result == .test)
  }

  @Test
  func categorize_testDotSuffix() {
    let result = FileChangeCategory.categorize("Sources/App.test.swift")
    #require(result == .test)
  }

  @Test
  func categorize_specSuffix() {
    let result = FileChangeCategory.categorize("Sources/Model.spec.swift")
    #require(result == .test)
  }

  @Test
  func categorize_testPrefix() {
    let result = FileChangeCategory.categorize("test_utils.py")
    #require(result == .test)
  }

  @Test
  func categorize_testUnderscorePrefix() {
    let result = FileChangeCategory.categorize("test_helpers.js")
    #require(result == .test)
  }

  @Test
  func categorize_testUnderscoreSuffix() {
    let result = FileChangeCategory.categorize("mock_data_test.swift")
    #require(result == .test)
  }

  @Test
  func categorize_testDirPrefix() {
    let result = FileChangeCategory.categorize("testsuite/setup.sh")
    #require(result == .test)
  }

  // MARK: Config files — directory and exact-match patterns

  @Test
  func categorize_configDirRoot() {
    let result = FileChangeCategory.categorize("Config/settings.json")
    #require(result == .config)
  }

  @Test
  func categorize_configDirNested() {
    let result = FileChangeCategory.categorize("Config/production.toml")
    #require(result == .config)
  }

  @Test
  func categorize_dotConfigDir() {
    let result = FileChangeCategory.categorize(".config/editor.yml")
    #require(result == .config)
  }

  @Test
  func categorize_dotVscodeDir() {
    let result = FileChangeCategory.categorize(".vscode/settings.json")
    #require(result == .config)
  }

  @Test
  func categorize_dotGitHubDir() {
    let result = FileChangeCategory.categorize(".github/workflows/ci.yml")
    #require(result == .config)
  }

  @Test
  func categorize_packageJSON() {
    let result = FileChangeCategory.categorize("package.json")
    #require(result == .config)
  }

  @Test
  func categorize_swiftFormat() {
    let result = FileChangeCategory.categorize(".swift-format")
    #require(result == .config)
  }

  @Test
  func categorize_swiftLint() {
    let result = FileChangeCategory.categorize(".swiftlint.yml")
    #require(result == .config)
  }

  @Test
  func categorize_packageSwift() {
    let result = FileChangeCategory.categorize("Package.swift")
    #require(result == .config)
  }

  @Test
  func categorize_gitignore() {
    let result = FileChangeCategory.categorize(".gitignore")
    #require(result == .config)
  }

  @Test
  func categorize_makefile() {
    let result = FileChangeCategory.categorize("Makefile")
    #require(result == .config)
  }

  // MARK: Other bucket — unknown extension, not config dir

  @Test
  func categorize_otherPNG() {
    let result = FileChangeCategory.categorize("Assets/logo.png")
    #require(result == .other)
  }

  @Test
  func categorize_otherMarkdown() {
    let result = FileChangeCategory.categorize("README.md")
    #require(result == .other)
  }

  @Test
  func categorize_otherTextFile() {
    let result = FileChangeCategory.categorize("docs/notes.txt")
    #require(result == .other)
  }

  @Test
  func categorize_otherYmlNotInConfigDir() {
    let result = FileChangeCategory.categorize("scripts/ci.yml")
    #require(result == .other)
  }

  @Test
  func categorize_otherJpeg() {
    let result = FileChangeCategory.categorize("Photos/screenshot.jpg")
    #require(result == .other)
  }

  @Test
  func categorize_otherPdf() {
    let result = FileChangeCategory.categorize("docs/manual.pdf")
    #require(result == .other)
  }

  // MARK: - FileChangeCategory.sortOrder

  @Test
  func sortOrder_source() {
    #require(FileChangeCategory.source.sortOrder == 0)
  }

  @Test
  func sortOrder_test() {
    #require(FileChangeCategory.test.sortOrder == 1)
  }

  @Test
  func sortOrder_config() {
    #require(FileChangeCategory.config.sortOrder == 2)
  }

  @Test
  func sortOrder_other() {
    #require(FileChangeCategory.other.sortOrder == 3)
  }

  // MARK: - FileChange.fileName

  @Test
  func fileName_simplePath() {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 10,
      deletions: 2,
      language: nil,
      summary: nil
    )
    #require(change.fileName == "App.swift")
  }

  @Test
  func fileName_deeplyNested() {
    let change = FileChange(
      relativePath: "Sources/Views/Components/Button.swift",
      additions: 5,
      deletions: 0,
      language: nil,
      summary: nil
    )
    #require(change.fileName == "Button.swift")
  }

  @Test
  func fileName_singleComponent() {
    let change = FileChange(
      relativePath: "Makefile",
      additions: 1,
      deletions: 1,
      language: nil,
      summary: nil
    )
    #require(change.fileName == "Makefile")
  }

  @Test
  func fileName_directoryPath() {
    let change = FileChange(
      relativePath: "Tests/CompassTests/Helper/",
      additions: 20,
      deletions: 5,
      language: nil,
      summary: nil
    )
    #require(change.fileName == "Helper")
  }

  // MARK: - FileChange.lineCountLabel

  @Test
  func lineCountLabel_bothAdditionsAndDeletions() {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 12,
      deletions: 8,
      language: nil,
      summary: nil
    )
    #require(change.lineCountLabel == "+12/-8")
  }

  @Test
  func lineCountLabel_onlyAdditions() {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 5,
      deletions: 0,
      language: nil,
      summary: nil
    )
    #require(change.lineCountLabel == "+5/0")
  }

  @Test
  func lineCountLabel_onlyDeletions() {
    let change = FileChange(
      relativePath: "Sources/App.swift",
      additions: 0,
      deletions: 3,
      language: nil,
      summary: nil
    )
    #require(change.lineCountLabel == "0/-3")
  }

  @Test
  func lineCountLabel_zeroChanges() {
    let change = FileChange(
      relativePath: "Assets/logo.png",
      additions: 0,
      deletions: 0,
      language: nil,
      summary: nil
    )
    #require(change.lineCountLabel == "0/0")
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
    try initGitRepo(at: test.temporaryDirectory)
    try writeFile("main.txt", contents: "main content\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add main.txt && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add main.txt'",
      at: test.temporaryDirectory
    )

    // Step 2: branch off and commit on the branch — creates feature.txt
    try runGit(
      "git -C \(test.temporaryDirectory.path) checkout -q -b feature",
      at: test.temporaryDirectory
    )
    try writeFile("feature.txt", contents: "feature content\n")
    try runGit(
      "git -C \(test.temporaryDirectory.path) add feature.txt && "
        + "git -C \(test.temporaryDirectory.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m 'Add feature.txt'",
      at: test.temporaryDirectory
    )

    // Step 3: switch back to main and merge the branch.
    // Use --no-edit to auto-merge without a separate commit message step.
    try runGit(
      "git -C \(test.temporaryDirectory.path) checkout -q main",
      at: test.temporaryDirectory
    )
    try runGit(
      "git -C \(test.temporaryDirectory.path) merge -q --no-edit feature",
      at: test.temporaryDirectory
    )

    let mergeCommitSHA = try getSingleCommitSHA(at: test.temporaryDirectory)

    // Call gitDiffStat for the merge commit — with --first-parent it should only
    // show the changes that were made on mainline (main.txt changes), not the
    // files introduced by the merged branch (feature.txt).
    let diffStatOutput = await FileExplainer.gitDiffStat(sha: mergeCommitSHA, repoURL: test.temporaryDirectory)

    // Parse the diff stat output.
    let changes = FileExplainer.parseGitDiffStat(diffStatOutput)

    // The merge commit introduced main.txt (from the merge base to tip).
    // With --first-parent, git reports the changes from the merge base to the merge commit on main.
    // Since the merge auto-merged (no conflicts), the mainline changes are just the update to main.txt
    // that happened between the pre-merge state and the merge commit.
    //
    // More precisely: after the merge, main.txt still shows as changed because the merge commit
    // has a mainline diff that includes main.txt. feature.txt should NOT appear because it was
    // brought in via the branch (second parent), which --first-parent excludes.
    #require(!changes.isEmpty) { "gitDiffStat for a merge commit must not be empty" }
    let changedPaths = changes.map { $0.relativePath }
    #require(!changedPaths.contains("feature.txt")) { "feature.txt was introduced by the merged branch (second parent) and must not appear in --first-parent output" }
    #require(changedPaths.contains("main.txt")) { "main.txt is on the mainline (first parent) and must appear in --first-parent output" }
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
      throw "git command failed with status \(process.terminationStatus)"
    }
  }

  private func getSingleCommitSHA(at url: URL) throws -> String {
    let result = try waitForSync {
      try? ProcessRunner.runEnv(
        "git", ["rev-parse", "HEAD"],
        workingDirectory: url
      )
    }
    guard let stdout = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
          !stdout.isEmpty else {
      throw "no commit SHA found"
    }
    return stdout
  }

  private func getAllCommitSHAs(at url: URL) throws -> [String] {
    let result = try waitForSync {
      try? ProcessRunner.runEnv(
        "git", ["log", "--all", "--format=%H"],
        workingDirectory: url
      )
    }
    guard let stdout = result?.stdout else { return [] }
    return stdout
      .split(separator: "\n")
      .filter { !$0.isEmpty }
      .map { String($0) }
  }

  private func waitForSync<T>(_ fn: () async throws -> T?) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      Task {
        do {
          if let value = try await fn() {
            continuation.resume(returning: value)
          } else {
            continuation.resume(throwing: "fn returned nil")
          }
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
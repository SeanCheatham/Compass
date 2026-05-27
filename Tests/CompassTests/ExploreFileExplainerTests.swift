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
  func parseGitDiffStat_normalAdditionsAndDeletions() {
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
  func parseGitDiffStat_renameArrow() {
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
  func parseGitDiffStat_binaryFile() {
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
  func parseGitDiffStat_pathWithSpaces() {
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
  func parseGitDiffStat_multiLineStatOutput() {
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
  func parseGitDiffStat_numericOnlyFallback() {
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
  func parseGitDiffStat_absentStatsParts() {
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
  func parseGitDiffStat_emptyInput() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let changes = FileExplainer.parseGitDiffStat("")
    #require(changes.isEmpty)
  }

  @Test
  func parseGitDiffStat_whitespaceOnlyLines() {
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
  func extractLineCounts_additionsAndDeletions() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "24 ++++++++----------")
    #require(result.additions == 8)
    #require(result.deletions == 10)
  }

  @Test
  func extractLineCounts_onlyAdditions() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "6 ++++++")
    #require(result.additions == 6)
    #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_onlyDeletions() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = FileExplainer.extractLineCounts(from: "3 ---")
    #require(result.additions == 0)
    #require(result.deletions == 3)
  }

  @Test
  func extractLineCounts_numericFallback() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // No +/- bar chars, but has numeric token
    let result = FileExplainer.extractLineCounts(from: "99")
    #require(result.additions == 99)
    #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_absentStatsParts() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // No bar chars, no numeric tokens
    let result = FileExplainer.extractLineCounts(from: "")
    #require(result.additions == 0)
    #require(result.deletions == 0)
  }

  @Test
  func extractLineCounts_withNumericAndBars() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // Numeric count 24 and bar chars both present — bars take priority
    let result = FileExplainer.extractLineCounts(from: "24 ++++++++----------")
    #require(result.additions == 8)
    #require(result.deletions == 10)
  }
}
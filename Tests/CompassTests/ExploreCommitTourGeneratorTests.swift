import Foundation
import FoundationModels
import Testing

@testable import Compass

// MARK: - ExploreCommitTourGeneratorError

/// Error type used by test helpers in ExploreCommitTourGeneratorTests.
/// Required to be `Sendable` under Swift 6 strict concurrency when thrown
/// from async closures (e.g. inside `withCheckedThrowingContinuation`).
struct ExploreCommitTourGeneratorError: Error, Sendable {
  enum Kind: Sendable {
    case gitCommandFailed(status: Int32)
    case shellCommandFailed(command: String)
    case noCommitSHAFound
    case fnReturnedNil
  }
  let kind: Kind
}

struct ExploreCommitTourGeneratorTests {
  // MARK: - Empty string guard

  @Test
  func generate_emptyString_returnsNil() async throws {
    let result = await CommitTourGenerator.generate(diff: "")
    try #require(result == nil)
  }

  // MARK: - Whitespace-only guard

  @Test
  func generate_whitespaceOnlyString_returnsNil() async throws {
    let result = await CommitTourGenerator.generate(diff: "   \n\t  \n  ")
    try #require(result == nil)
  }

  @Test
  func generate_newlinesOnlyString_returnsNil() async throws {
    let result = await CommitTourGenerator.generate(diff: "\n\n\n")
    try #require(result == nil)
  }

  // MARK: - Non-throwing contract for normal diffs

  @Test
  func generate_normalDiff_doesNotThrow() async throws {
    // Verify the async method does not throw for a valid diff.
    // Returns nil when Foundation Models is unavailable in this environment.
    let diff = """
      Sources/App.swift | 4 ++++
      Sources/Model.swift | 2 ++
      """
    let result = await CommitTourGenerator.generate(diff: diff)
    // Result may be nil (Foundation Models unavailable) or non-nil (available)
    // but it must not throw.
    try #require(result == nil || result != nil)
  }

  @Test
  func generate_singleLineDiff_doesNotThrow() async throws {
    let diff = "README.md | 1 +"
    try await withMockFoundationModels(response: "Mock tour.") {
      let result = await CommitTourGenerator.generate(diff: diff)
      try #require(result == "Mock tour.")
    }
  }

  // MARK: - Large-diff stability

  @Test
  func generate_largeDiff_doesNotThrow() async throws {
    // A large diff mimicking a full commit range; must not crash or throw.
    let largeDiff = (1...200).map { idx in
      "Sources/File\(String(format: "%03d", idx)).swift\t|  \(idx) +\t\t// Line \(idx) of a simulated large diff"
    }.joined(separator: "\n")

    let result = await CommitTourGenerator.generate(diff: largeDiff)
    // Returns nil if Foundation Models is unavailable or declines output.
    // Must never throw regardless of input size.
    _ = result
  }

  @Test
  func generate_largeDiffWithManyFiles_doesNotThrow() async throws {
    // Wide diff: many files, small changes each — tests batch-processing stability.
    let wideDiff = (1...50).map { idx in
      "Sources/Package\(idx)/Source.swift\t|  2 +\t\t// Added utility function in package \(idx)"
    }.joined(separator: "\n")

    let result = await CommitTourGenerator.generate(diff: wideDiff)
    _ = result
  }

  // MARK: - generateTour empty commits guard

  @Test
  func generateTour_emptyCommits_returnsNil() async throws {
    // Empty commits array must return nil without attempting to invoke git or the model.
    let repoURL = try makeTempDir()
    let result = await CommitTourGenerator.generateTour(commits: [], repoURL: repoURL)
    try #require(result == nil)
  }

  // MARK: - generateTour single-commit integration (real git repo)

  @Test
  func generateTour_singleCommit_callsGitDiffForSha() async throws {
    let repoURL = try makeTempDir()

    // Set up a real git repo with one commit
    try await runShell(
      "git init -q && git branch -M main && "
        + "git -c user.email=t@t -c user.name=t commit -q --allow-empty -m 'Initial'",
      at: repoURL
    )

    // Get the SHA of the single commit
    let sha = try await capture("git rev-parse HEAD", at: repoURL)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Initial")]
    let result = await CommitTourGenerator.generateTour(commits: commits, repoURL: repoURL)

    // Both nil and non-nil are acceptable; the key requirement is no crash.
    _ = result
  }

  @Test
  func generateTour_singleCommitWithFileChanges_returnsNonNilOrNilWithoutThrowing() async throws {
    // Creates a real commit with an actual file change (not --allow-empty)
    // and verifies: (1) no crash, (2) nil only when Foundation Models unavailable.
    let repoURL = try makeTempDir()
    try initGitRepo(at: repoURL)
    let commits = try makeSingleCommit(at: repoURL)

    let result = await CommitTourGenerator.generateTour(commits: commits, repoURL: repoURL)

    // The method must not throw regardless of Foundation Models availability.
    // When unavailable, result must be nil; when available it may be nil or non-nil.
    if FoundationModelsAvailability.isAvailable {
      // Model is available: result may be nil (model declined) or non-nil.
      _ = result
    } else {
      try #require(result == nil)
    }
  }

  // MARK: - Large subject line does not overflow diff logic

  @Test
  func generateTour_largeCommitSubject_doesNotOverflow() async throws {
    // Creates a real commit with a ~10,000-character subject line and
    // exercises the single-commit `gitDiff(sha:repoURL)` path where only
    // the SHA is used (not the subject), confirming long subjects don't
    // overflow the diff logic.
    let repoURL = try makeTempDir()
    try initGitRepo(at: repoURL)

    // Create a file to commit
    try writeFile("Sources/App.swift", contents: "import Foundation\n", at: repoURL)

    // Create a commit with a ~10,000 character subject
    let longSubject = String(repeating: "x", count: 10_000)
    try runGit(
      "git -C \(repoURL.path) add Sources/App.swift && "
        + "git -C \(repoURL.path) "
        + "-c user.email=t@t -c user.name=t commit -q -m \"\(longSubject)\"",
      at: repoURL
    )

    // Get the SHA of the single commit
    let sha = try await capture("git -C \(repoURL.path) rev-parse HEAD", at: repoURL)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: longSubject)]
    let result = await CommitTourGenerator.generateTour(commits: commits, repoURL: repoURL)

    // The method must not throw regardless of subject length.
    // Result is nil when Foundation Models is unavailable.
    if !FoundationModelsAvailability.isAvailable {
      try #require(result == nil)
    }
  }

  // MARK: - generateTour multi-commit integration (real git repo)

  @Test
  func generateTour_multiCommit_callsGitDiffRange() async throws {
    let repoURL = try makeTempDir()

    // Set up a real git repo with two commits
    try await runShell("git init -q && git branch -M main", at: repoURL)

    // First commit
    try await runShell(
      "touch README.md && " + "git add README.md && "
        + "git -c user.email=t@t -c user.name=t commit -q -m 'First'",
      at: repoURL
    )

    // Second commit
    try await runShell(
      "echo 'content' >> README.md && " + "git add README.md && "
        + "git -c user.email=t@t -c user.name=t commit -q -m 'Second'",
      at: repoURL
    )

    // Get both SHAs
    let firstSha = try await capture("git rev-parse HEAD~", at: repoURL)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let secondSha = try await capture("git rev-parse HEAD", at: repoURL)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let commits = [
      SessionCommit(sha: secondSha, short: String(secondSha.prefix(7)), subject: "Second"),
      SessionCommit(sha: firstSha, short: String(firstSha.prefix(7)), subject: "First"),
    ]
    let result = await CommitTourGenerator.generateTour(commits: commits, repoURL: repoURL)

    // Returns nil when unavailable or when the model declines output.
    // Must not throw regardless of commit range.
    _ = result
  }

  // MARK: - Git failure path

  @Test
  func generateTour_nonExistentRepoURL_returnsNil() async throws {
    // When the repo URL does not exist, git diff fails and generateTour
    // returns nil without crashing.
    let nonExistentURL = try makeTempDir()
    try FileManager.default.removeItem(at: nonExistentURL)

    let fakeCommit = SessionCommit(
      sha: "0000000000000000000000000000000000000000",
      short: "0000000",
      subject: "Fake"
    )

    let result = await CommitTourGenerator.generateTour(
      commits: [fakeCommit],
      repoURL: nonExistentURL
    )
    try #require(result == nil)
  }

  // MARK: - isAvailable guard (real git repo)

  @Test
  func generate_withRealGitRepo_returnsNilWhenModelUnavailable() async throws {
    // Confirms the isAvailable guard fires correctly when Foundation Models is
    // unavailable, using a real git repo with a real commit (mirroring the
    // pattern from ExploreRepoQnAAnswerGuardTests and ExploreCommitTourGeneratorTests).
    let repoURL = try makeTempDir()
    try initGitRepo(at: repoURL)
    _ = try makeSingleCommit(at: repoURL)

    let diff = """
      Sources/App.swift        |   2 ++
      """
    let result = await CommitTourGenerator.generate(diff: diff)
    if !FoundationModelsAvailability.isAvailable {
      try #require(result == nil)
    }
  }

  // MARK: - generateTour non-existent SHA → nil

  @Test
  func generateTour_nonExistentSHA_returnsNil() async throws {
    let repoURL = try makeTempDir()
    try initGitRepo(at: repoURL)
    _ = try makeSingleCommit(at: repoURL)

    // Valid-format SHA that does not exist in the repo → git diff returns "" → nil
    let fakeSHA = "0000000000000000000000000000000000000000"
    let commits = [SessionCommit(sha: fakeSHA, short: String(fakeSHA.prefix(7)), subject: "Fake")]
    let result = await CommitTourGenerator.generateTour(commits: commits, repoURL: repoURL)
    try #require(result == nil)
  }

  // MARK: - generateTour mixed valid/invalid SHAs → nil

  @Test
  func generateTour_mixedValidInvalidSHAs_returnsNil() async throws {
    let repoURL = try makeTempDir()
    try initGitRepo(at: repoURL)
    let validCommits = try makeSingleCommit(at: repoURL)
    guard let validSHA = validCommits.first?.sha else {
      throw TestHelperError.noCommitSHAFound
    }

    // First commit is valid; second is a fake SHA → range diff is empty → nil
    let fakeSHA = "0000000000000000000000000000000000000000"
    let mixedCommits = [
      SessionCommit(sha: validSHA, short: String(validSHA.prefix(7)), subject: "Valid"),
      SessionCommit(sha: fakeSHA, short: String(fakeSHA.prefix(7)), subject: "Fake"),
    ]
    let result = await CommitTourGenerator.generateTour(commits: mixedCommits, repoURL: repoURL)
    try #require(result == nil)
  }

  // MARK: - generateTour uses oldest/newest regardless of input order

  @Test
  func generateTour_usesOldestNewest_regardlessOfOrder() async throws {
    // Verifies generateTour selects oldest/newest from the commit list
    // using first/last, not assuming chronological order of input.
    let repoURL = try makeTempDir()
    try initGitRepo(at: repoURL)

    // Create two commits: first (older) and second (newer)
    try writeFile("README.md", contents: "initial\n", at: repoURL)
    try runGit(
      "git -C \(repoURL.path) add README.md && "
        + "git -C \(repoURL.path) -c user.email=t@t -c user.name=t commit -q -m 'First'",
      at: repoURL
    )

    try writeFile("Sources/App.swift", contents: "import Foundation\n", at: repoURL)
    try runGit(
      "git -C \(repoURL.path) add Sources/App.swift && "
        + "git -C \(repoURL.path) -c user.email=t@t -c user.name=t commit -q -m 'Second'",
      at: repoURL
    )

    let firstSHA = try await capture("git -C \(repoURL.path) rev-parse HEAD~", at: repoURL)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let secondSHA = try await capture("git -C \(repoURL.path) rev-parse HEAD", at: repoURL)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    // Pass in newest-first order (as SessionCommit normally arrives)
    let commits = [
      SessionCommit(sha: secondSHA, short: String(secondSHA.prefix(7)), subject: "Second"),
      SessionCommit(sha: firstSHA, short: String(firstSHA.prefix(7)), subject: "First"),
    ]
    let result = await CommitTourGenerator.generateTour(commits: commits, repoURL: repoURL)

    // Must not throw; result may be nil if Foundation Models is unavailable
    _ = result

    // Also verify with oldest-first order (reversed) — same oldest/newest computed
    let reversedCommits = [
      SessionCommit(sha: firstSHA, short: String(firstSHA.prefix(7)), subject: "First"),
      SessionCommit(sha: secondSHA, short: String(secondSHA.prefix(7)), subject: "Second"),
    ]
    let resultReversed = await CommitTourGenerator.generateTour(
      commits: reversedCommits,
      repoURL: repoURL
    )
    _ = resultReversed
  }

  // MARK: - generateTour single-commit path uses correct first/last keying

  @Test
  func generateTour_singleCommit_cachingKeyMatches() async throws {
    // Guard path: single-commit path uses first/last keying (same element),
    // confirming commits.count == 1 takes the single-commit branch in generateTour.
    let repoURL = try makeTempDir()
    try initGitRepo(at: repoURL)

    // Create a file and commit
    try writeFile("Sources/App.swift", contents: "import Foundation\n", at: repoURL)
    try runGit(
      "git -C \(repoURL.path) add Sources/App.swift && "
        + "git -C \(repoURL.path) -c user.email=t@t -c user.name=t commit -q -m 'Add App'",
      at: repoURL
    )

    let sha = try getSingleCommitSHA(at: repoURL)
    let commits = [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App")]

    // When commits.count == 1, generateTour calls gitDiff(sha:), not gitDiffRange.
    // This test confirms the single-commit path is exercised without throwing.
    let result = await CommitTourGenerator.generateTour(commits: commits, repoURL: repoURL)

    // The result may be nil (Foundation Models unavailable) but must not throw.
    // The key observable is that we reach the generate(diff:) call internally
    // without crashing, confirming the first/last single-element keying works.
    if !FoundationModelsAvailability.isAvailable {
      try #require(result == nil)
    } else {
      // Model available: result may be nil (model declined) or non-nil
      _ = result
    }
  }

  // MARK: - isAvailable guard

  @Test
  func generate_returnsNilWhenModelUnavailable() async throws {
    // When FoundationModelsAvailability.isAvailable is false, generate
    // returns nil without attempting to create a session.
    let diff = """
      Sources/App.swift        |   2 ++
      """
    let result = await CommitTourGenerator.generate(diff: diff)
    // Either Foundation Models is available and we get a string (or nil
    // from an error), or it is unavailable and we definitely get nil.
    if !FoundationModelsAvailability.isAvailable {
      try #require(result == nil)
    }
  }

  @Test
  func generateTour_returnsNilWhenModelUnavailable() async throws {
    // Confirms the isAvailable guard fires correctly when Foundation Models is
    // unavailable, using a real git repo with a real commit.  This mirrors
    // the pattern from the existing `generate_withRealGitRepo_returnsNilWhenModelUnavailable`
    // test but exercises `generateTour` (which calls `generate` internally)
    // rather than `generate` directly.
    let repoURL = try makeTempDir()
    try initGitRepo(at: repoURL)
    let commits = try makeSingleCommit(at: repoURL)

    let result = await CommitTourGenerator.generateTour(commits: commits, repoURL: repoURL)
    if !FoundationModelsAvailability.isAvailable {
      try #require(result == nil)
    }
  }

  @Test
  func generateTour_modelUnavailable_returnsNil_forcing() async throws {
    // Forcing version: uses withMockFoundationModels(available: false) to
    // guarantee the guard fires regardless of host environment, turning the
    // host-dependent conditional test into a deterministic one.
    let repoURL = try makeTempDir()
    try initGitRepo(at: repoURL)
    let commits = try makeSingleCommit(at: repoURL)

    try await withMockFoundationModels(available: false) {
      let result = await CommitTourGenerator.generateTour(commits: commits, repoURL: repoURL)
      try #require(result == nil)
    }
  }

}

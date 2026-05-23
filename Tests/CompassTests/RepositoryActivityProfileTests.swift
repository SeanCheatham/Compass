import Foundation
import XCTest

@testable import Compass

final class RepositoryActivityProfilePorcelainTests: XCTestCase {
  func testPorcelainStatusParsingCoversKnownAndFallbackCodes() {
    let clean = RepositoryActivityProfileDeriver.worktreeChanges(fromPorcelainStatus: "")
    XCTAssertEqual(clean, RepositoryWorktreeChangeCounts())
    XCTAssertEqual(clean.pressureLevel, .clean)
    XCTAssertEqual(clean.hudSummary, "Clean worktree")

    let counts = RepositoryActivityProfileDeriver.worktreeChanges(
      fromPorcelainStatus: """
        A  staged-added
         M modified
         D deleted
        R  old -> new
         C copied
        ?? untracked
        UU conflict
        !! ignored
        X  unknown
        Z
        """
    )

    XCTAssertEqual(counts.added, 1)
    XCTAssertEqual(counts.modified, 1)
    XCTAssertEqual(counts.deleted, 1)
    XCTAssertEqual(counts.renamed, 2)
    XCTAssertEqual(counts.untracked, 1)
    XCTAssertEqual(counts.conflicted, 1)
    XCTAssertEqual(counts.other, 3)
    XCTAssertEqual(counts.total, 10)
    XCTAssertEqual(counts.pressureLevel, .heavy)
    XCTAssertEqual(counts.hudSummary, "10 pending changes: 1 added, 1 modified")
  }

  func testPressureThresholdsAndWorktreeHudSummaries() {
    let clean = makeWorktreeChanges()
    XCTAssertEqual(clean.pressureLevel, .clean)
    XCTAssertEqual(clean.hudSummary, "Clean worktree")

    let light = makeWorktreeChanges(added: 5)
    XCTAssertEqual(light.pressureLevel, .light)
    XCTAssertEqual(light.hudSummary, "5 pending changes: 5 added")

    let moderate = makeWorktreeChanges(modified: 6)
    XCTAssertEqual(moderate.pressureLevel, .moderate)
    XCTAssertEqual(moderate.hudSummary, "6 pending changes: 6 modified")

    let heavyByVolume = makeWorktreeChanges(deleted: 16)
    XCTAssertEqual(heavyByVolume.pressureLevel, .heavy)
    XCTAssertEqual(heavyByVolume.hudSummary, "16 pending changes: 16 deleted")

    let heavyByConflict = makeWorktreeChanges(conflicted: 1)
    XCTAssertEqual(heavyByConflict.pressureLevel, .heavy)
    XCTAssertEqual(heavyByConflict.hudSummary, "1 pending change: 1 conflicted")
  }

  func testPressureScoreIncludesWorktreeAndFailureInputs() {
    let profile = RepositoryActivityProfileDeriver.profile(
      from: [
        makeSession(1, status: .failed, endedAt: 100),
        makeSession(2, status: .failed, endedAt: 200),
      ],
      worktreeChanges: makeWorktreeChanges(
        added: 1,
        untracked: 2,
        conflicted: 1
      )
    )

    XCTAssertEqual(profile.pressureLevel, .heavy)
    XCTAssertEqual(profile.pressureScore, 20)
  }
}

final class RepositoryActivityProfileDerivationTests: XCTestCase {
  func testDerivesRecentCountsCommitsLastTerminalStatusAndFailureStreak() {
    let profile = RepositoryActivityProfileDeriver.profile(
      from: [
        makeSession(1, status: .succeeded, endedAt: 100, commits: 1),
        makeSession(2, status: .failed, endedAt: 200, commits: 1),
        makeSession(3, status: .failed, endedAt: 300, commits: 2),
        makeSession(4, status: .developing, endedAt: nil, commits: 5),
      ],
      worktreeChanges: makeWorktreeChanges()
    )

    XCTAssertTrue(profile.isAvailable)
    XCTAssertFalse(profile.isEmpty)
    XCTAssertEqual(profile.recentSessionCount, 3)
    XCTAssertEqual(profile.recentSucceededCount, 1)
    XCTAssertEqual(profile.recentFailedCount, 2)
    XCTAssertEqual(profile.recentCommitCount, 4)
    XCTAssertEqual(profile.lastTerminalStatus, .failed)
    XCTAssertEqual(profile.lastSuccessfulSession, 1)
    XCTAssertEqual(profile.lastFailedSession, 3)
    XCTAssertEqual(profile.successStreak, 0)
    XCTAssertEqual(profile.failureStreak, 2)
    XCTAssertFalse(profile.recoveredFromFailure)
    XCTAssertEqual(profile.pressureScore, 10)
    XCTAssertEqual(
      profile.hudSummary,
      "Clean worktree - 4 recent commits - 2 failed runs in a row."
    )
  }

  func testDerivesSuccessStreakAndRecoveredFromFailure() {
    let profile = RepositoryActivityProfileDeriver.profile(
      from: [
        makeSession(8, status: .failed, endedAt: 800),
        makeSession(9, status: .succeeded, endedAt: 900),
        makeSession(10, status: .succeeded, endedAt: 1_000),
      ],
      worktreeChanges: makeWorktreeChanges(added: 2, untracked: 1)
    )

    XCTAssertEqual(profile.lastTerminalStatus, .succeeded)
    XCTAssertEqual(profile.lastSuccessfulSession, 10)
    XCTAssertEqual(profile.lastFailedSession, 8)
    XCTAssertEqual(profile.successStreak, 2)
    XCTAssertEqual(profile.failureStreak, 0)
    XCTAssertTrue(profile.recoveredFromFailure)
    XCTAssertEqual(
      profile.hudSummary,
      "3 pending changes: 2 added, 1 untracked - 2-run recovery streak."
    )
  }

  func testEmptyAndNoTerminalSessionsStayAvailableWithNoRecentSessionHud() {
    let empty = RepositoryActivityProfileDeriver.profile(
      from: [],
      worktreeChanges: makeWorktreeChanges()
    )
    XCTAssertTrue(empty.isAvailable)
    XCTAssertEqual(empty.recentSessionCount, 0)
    XCTAssertNil(empty.lastTerminalStatus)
    XCTAssertEqual(empty.successStreak, 0)
    XCTAssertEqual(empty.failureStreak, 0)
    XCTAssertEqual(empty.hudSummary, "Clean worktree - no recent sessions.")

    let noTerminal = RepositoryActivityProfileDeriver.profile(
      from: [
        makeSession(1, status: .planning, endedAt: nil),
        makeSession(2, status: .developing, endedAt: nil),
      ],
      worktreeChanges: makeWorktreeChanges()
    )
    XCTAssertEqual(noTerminal, empty)
  }

  func testRecentSessionLimitAppliesToCountsAndCommitsOnly() {
    let sessions = (1...10).map {
      makeSession($0, status: .succeeded, endedAt: Double($0), commits: 1)
    }

    let profile = RepositoryActivityProfileDeriver.profile(
      from: sessions,
      worktreeChanges: makeWorktreeChanges()
    )

    XCTAssertEqual(profile.recentSessionCount, 8)
    XCTAssertEqual(profile.recentSucceededCount, 8)
    XCTAssertEqual(profile.recentFailedCount, 0)
    XCTAssertEqual(profile.recentCommitCount, 8)
    XCTAssertEqual(profile.lastTerminalStatus, .succeeded)
    XCTAssertEqual(profile.lastSuccessfulSession, 10)
    XCTAssertNil(profile.lastFailedSession)
    XCTAssertEqual(profile.successStreak, 10)
    XCTAssertEqual(profile.failureStreak, 0)
    XCTAssertEqual(
      profile.hudSummary,
      "Clean worktree - 8 recent commits - 10-run success streak."
    )
  }
}

final class RepositoryActivityProfileScanInputTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  func testScanReturnsEmptyWhenSessionsFileIsMissing() async throws {
    let repoURL = try makeTemporaryDirectory()

    let profile = await RepositoryActivityProfileService.scan(repoURL: repoURL)

    XCTAssertEqual(profile, .empty)
  }

  func testScanReturnsEmptyWhenSessionsFileIsMalformed() async throws {
    let repoURL = try makeTemporaryDirectory()
    try write("{", to: sessionsURL(for: repoURL))

    let profile = await RepositoryActivityProfileService.scan(repoURL: repoURL)

    XCTAssertEqual(profile, .empty)
  }

  func testScanReturnsEmptyWhenSessionsFileIsOversized() async throws {
    let repoURL = try makeTemporaryDirectory()
    let sessionsURL = sessionsURL(for: repoURL)
    try createDirectory(sessionsURL.deletingLastPathComponent())
    let oversized = Data(repeating: 0, count: (2 * 1024 * 1024) + 1)
    try oversized.write(to: sessionsURL, options: .atomic)

    let profile = await RepositoryActivityProfileService.scan(repoURL: repoURL)

    XCTAssertEqual(profile, .empty)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(
        path: "RepositoryActivityProfileTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try createDirectory(url)
    temporaryDirectories.append(url)
    return url
  }

  private func sessionsURL(for repoURL: URL) -> URL {
    repoURL
      .appending(path: ".compass", directoryHint: .isDirectory)
      .appending(path: "sessions.json")
  }

  private func write(_ string: String, to url: URL) throws {
    let data = try XCTUnwrap(string.data(using: .utf8))
    try createDirectory(url.deletingLastPathComponent())
    try data.write(to: url, options: .atomic)
  }

  private func createDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
}

private func makeWorktreeChanges(
  added: Int = 0,
  modified: Int = 0,
  deleted: Int = 0,
  renamed: Int = 0,
  untracked: Int = 0,
  conflicted: Int = 0,
  other: Int = 0
) -> RepositoryWorktreeChangeCounts {
  var changes = RepositoryWorktreeChangeCounts()
  changes.added = added
  changes.modified = modified
  changes.deleted = deleted
  changes.renamed = renamed
  changes.untracked = untracked
  changes.conflicted = conflicted
  changes.other = other
  return changes
}

private func makeSession(
  _ number: Int,
  status: SessionStatus,
  endedAt: Double?,
  commits: Int = 0
) -> SessionRecord {
  SessionRecord(
    session: number,
    startedAt: endedAt.map { $0 - 10 } ?? Double(number),
    endedAt: endedAt,
    plan: nil,
    verify: nil,
    beforeSha: nil,
    afterSha: nil,
    commits: (0..<commits).map {
      SessionCommit(
        sha: "sha-\(number)-\($0)",
        short: "s\(number)-\($0)",
        subject: "Commit \(number)-\($0)"
      )
    },
    status: status,
    notes: [],
    verifyOutput: nil,
    feedback: nil
  )
}

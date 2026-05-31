import Foundation
import Testing

@testable import Compass

final class SharedCompassVMGitExchangeTests {
  private var temporaryDirectories: [URL] = []

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
  }

  @Test func prepareInitializesExchangeAndFetchesHostBranch() async throws {
    let repo = try makeGitRepo()
    let repoID = UUID().uuidString.lowercased()

    let context = try await SharedCompassVMGitExchange.prepare(
      hostRepoURL: repo,
      repoID: repoID
    )

    try #require(context.repoID == repoID)
    try #require(context.branchName == "main")
    try #require(FileManager.default.fileExists(atPath: context.exchangeRepoURL.path))
    let exchangeHead = try await git(
      ["--git-dir", context.exchangeRepoURL.path, "rev-parse", "refs/heads/main"])
    let hostHead = try await git(["-C", repo.path, "rev-parse", "HEAD"])
    try #require(exchangeHead.trimmed == hostHead.trimmed)
  }

  @Test func prepareBlocksDirtyHostCheckout() async throws {
    let repo = try makeGitRepo()
    try write("dirty\n", to: repo.appending(path: "dirty.txt"))

    await #expect(throws: SharedCompassVMGitExchange.ExchangeError.self) {
      _ = try await SharedCompassVMGitExchange.prepare(
        hostRepoURL: repo,
        repoID: UUID().uuidString.lowercased()
      )
    }
  }

  @Test func promoteFastForwardsHostToStagedGuestCommit() async throws {
    let repo = try makeGitRepo()
    let repoID = UUID().uuidString.lowercased()
    let context = try await SharedCompassVMGitExchange.prepare(hostRepoURL: repo, repoID: repoID)
    let guest = try makeTemporaryDirectory(prefix: "GuestClone")
    try await git(["clone", context.exchangeRepoURL.path, guest.path])
    try await git(["-C", guest.path, "checkout", "main"])
    try await git(["-C", guest.path, "config", "user.email", "agent@example.test"])
    try await git(["-C", guest.path, "config", "user.name", "Agent"])
    try write("agent\n", to: guest.appending(path: "agent.txt"))
    try await git(["-C", guest.path, "add", "agent.txt"])
    try await git(["-C", guest.path, "commit", "-m", "agent commit"])
    let stagingRef = try SharedCompassVMGitExchange.stagingRef(
      repoID: repoID,
      sessionNumber: 7,
      branchName: "main"
    )
    try await git(["-C", guest.path, "push", "origin", "HEAD:\(stagingRef)"])
    let guestHead = try await git(["-C", guest.path, "rev-parse", "HEAD"])

    try await SharedCompassVMGitExchange.promote(
      stagingRef: stagingRef,
      context: context,
      hostRepoURL: repo
    )

    let hostHead = try await git(["-C", repo.path, "rev-parse", "HEAD"])
    try #require(hostHead.trimmed == guestHead.trimmed)
    let file = try String(contentsOf: repo.appending(path: "agent.txt"), encoding: .utf8)
    try #require(file == "agent\n")
  }

  @Test func promotePreservesMultipleGuestCommitsInOrder() async throws {
    let repo = try makeGitRepo()
    let repoID = UUID().uuidString.lowercased()
    let context = try await SharedCompassVMGitExchange.prepare(hostRepoURL: repo, repoID: repoID)
    let guest = try makeTemporaryDirectory(prefix: "GuestCloneMultiple")
    try await git(["clone", context.exchangeRepoURL.path, guest.path])
    try await git(["-C", guest.path, "checkout", "main"])
    try await git(["-C", guest.path, "config", "user.email", "agent@example.test"])
    try await git(["-C", guest.path, "config", "user.name", "Agent"])

    try write("one\n", to: guest.appending(path: "one.txt"))
    try await git(["-C", guest.path, "add", "one.txt"])
    try await git(["-C", guest.path, "commit", "-m", "agent commit one"])
    try write("two\n", to: guest.appending(path: "two.txt"))
    try await git(["-C", guest.path, "add", "two.txt"])
    try await git(["-C", guest.path, "commit", "-m", "agent commit two"])

    let stagingRef = try SharedCompassVMGitExchange.stagingRef(
      repoID: repoID,
      sessionNumber: 9,
      branchName: "main"
    )
    try await git(["-C", guest.path, "push", "origin", "HEAD:\(stagingRef)"])
    let guestHead = try await git(["-C", guest.path, "rev-parse", "HEAD"])

    try await SharedCompassVMGitExchange.promote(
      stagingRef: stagingRef,
      context: context,
      hostRepoURL: repo
    )

    let hostHead = try await git(["-C", repo.path, "rev-parse", "HEAD"])
    try #require(hostHead.trimmed == guestHead.trimmed)
    let recentSubjects = try await git(["-C", repo.path, "log", "--format=%s", "-2"])
    try #require(recentSubjects.split(separator: "\n").map(String.init) == [
      "agent commit two",
      "agent commit one",
    ])
  }

  @Test func exchangeRejectsDirectGuestPushToBranchHead() async throws {
    let repo = try makeGitRepo()
    let repoID = UUID().uuidString.lowercased()
    let context = try await SharedCompassVMGitExchange.prepare(hostRepoURL: repo, repoID: repoID)
    let guest = try makeTemporaryDirectory(prefix: "GuestCloneRejectedHead")
    try await git(["clone", context.exchangeRepoURL.path, guest.path])
    try await git(["-C", guest.path, "checkout", "main"])
    try await git(["-C", guest.path, "config", "user.email", "agent@example.test"])
    try await git(["-C", guest.path, "config", "user.name", "Agent"])
    try write("bad\n", to: guest.appending(path: "bad.txt"))
    try await git(["-C", guest.path, "add", "bad.txt"])
    try await git(["-C", guest.path, "commit", "-m", "direct branch push"])

    let result = try await runGit(["-C", guest.path, "push", "origin", "HEAD:refs/heads/main"])

    #expect(result.exitCode != 0)
    #expect((result.stderr + result.stdout).contains("rejects direct guest updates"))
  }

  @Test func exchangeRejectsStagingPushForDifferentRepoID() async throws {
    let repo = try makeGitRepo()
    let repoID = UUID().uuidString.lowercased()
    let context = try await SharedCompassVMGitExchange.prepare(hostRepoURL: repo, repoID: repoID)
    let guest = try makeTemporaryDirectory(prefix: "GuestCloneWrongStagingID")
    try await git(["clone", context.exchangeRepoURL.path, guest.path])
    try await git(["-C", guest.path, "checkout", "main"])
    try await git(["-C", guest.path, "config", "user.email", "agent@example.test"])
    try await git(["-C", guest.path, "config", "user.name", "Agent"])
    try write("wrong\n", to: guest.appending(path: "wrong.txt"))
    try await git(["-C", guest.path, "add", "wrong.txt"])
    try await git(["-C", guest.path, "commit", "-m", "wrong staging id"])
    let wrongStagingRef = try SharedCompassVMGitExchange.stagingRef(
      repoID: UUID().uuidString.lowercased(),
      sessionNumber: 10,
      branchName: "main"
    )

    let result = try await runGit(["-C", guest.path, "push", "origin", "HEAD:\(wrongStagingRef)"])

    #expect(result.exitCode != 0)
    #expect((result.stderr + result.stdout).contains("rejects direct guest updates"))
  }

  @Test func promoteRejectsWhenHostBranchAdvanced() async throws {
    let repo = try makeGitRepo()
    let repoID = UUID().uuidString.lowercased()
    let context = try await SharedCompassVMGitExchange.prepare(hostRepoURL: repo, repoID: repoID)
    let guest = try makeTemporaryDirectory(prefix: "GuestCloneAdvanced")
    try await git(["clone", context.exchangeRepoURL.path, guest.path])
    try await git(["-C", guest.path, "checkout", "main"])
    try await git(["-C", guest.path, "config", "user.email", "agent@example.test"])
    try await git(["-C", guest.path, "config", "user.name", "Agent"])
    try write("agent\n", to: guest.appending(path: "agent.txt"))
    try await git(["-C", guest.path, "add", "agent.txt"])
    try await git(["-C", guest.path, "commit", "-m", "agent commit"])
    let stagingRef = try SharedCompassVMGitExchange.stagingRef(
      repoID: repoID,
      sessionNumber: 8,
      branchName: "main"
    )
    try await git(["-C", guest.path, "push", "origin", "HEAD:\(stagingRef)"])

    try write("human\n", to: repo.appending(path: "human.txt"))
    try await git(["-C", repo.path, "add", "human.txt"])
    try await git(["-C", repo.path, "commit", "-m", "human commit"])

    await #expect(throws: SharedCompassVMGitExchange.ExchangeError.self) {
      try await SharedCompassVMGitExchange.promote(
        stagingRef: stagingRef,
        context: context,
        hostRepoURL: repo
      )
    }
  }

  private func makeGitRepo() throws -> URL {
    let repo = try makeTemporaryDirectory(prefix: "GitExchangeRepo")
    try write(".compass/\n", to: repo.appending(path: ".gitignore"))
    try write("hello\n", to: repo.appending(path: "README.md"))
    try awaitShell("git init -q && git branch -M main", in: repo)
    try awaitShell("git config user.email test@example.test", in: repo)
    try awaitShell("git config user.name Test", in: repo)
    try awaitShell("git add . && git commit -q -m init", in: repo)
    return repo
  }

  private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    temporaryDirectories.append(url)
    return url
  }

  private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  @discardableResult
  private func git(_ arguments: [String]) async throws -> String {
    let result = try await runGit(arguments)
    guard result.exitCode == 0 else {
      throw TestError.gitFailed(result.stderr + result.stdout)
    }
    return result.stdout
  }

  private func runGit(_ arguments: [String]) async throws -> ProcessResult {
    try await ProcessRunner.runEnv("git", arguments, timeout: 60)
  }

  private func awaitShell(_ command: String, in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = directory
    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let detail = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
      throw TestError.gitFailed(detail)
    }
  }

  private enum TestError: Error, CustomStringConvertible {
    case gitFailed(String)

    var description: String {
      switch self {
      case .gitFailed(let detail):
        return detail
      }
    }
  }
}

private extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

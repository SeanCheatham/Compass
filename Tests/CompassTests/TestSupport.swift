import Foundation
import Testing

@testable import Compass

// MARK: - TestHelperError

enum TestHelperError: Error {
  case gitCommandFailed(status: Int32)
  case noCommitSHAFound
  case fnReturnedNil
  case shellFailed(command: String)
  case message(String)
}

func makeTempDir(file: StaticString = #file, line: UInt = #line) throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("CompassTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}

// MARK: - Shared Explore Test Helpers

/// Runs a git command in the given directory, throwing on non-zero exit.
func runGit(_ command: String, at directory: URL) throws {
  let process = Process()
  process.launchPath = "/bin/zsh"
  process.arguments = ["-lc", command]
  process.currentDirectoryURL = directory
  process.standardOutput = Pipe()
  process.standardError = Pipe()
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw TestHelperError.gitCommandFailed(status: process.terminationStatus)
  }
}

/// Initialises a new git repo in the given directory.
func initGitRepo(at directory: URL) throws {
  try runGit("git init -q && git branch -M main", at: directory)
}

/// Creates or overwrites a file at `relative` inside `directory` with the given contents.
func writeFile(_ relative: String, contents: String, at directory: URL) throws {
  let url = directory.appendingPathComponent(relative)
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try contents.write(to: url, atomically: true, encoding: .utf8)
}

/// Creates a single commit with `Sources/App.swift` and returns its SessionCommit.
func makeSingleCommit(at directory: URL) throws -> [SessionCommit] {
  try writeFile("Sources/App.swift", contents: "import Foundation\n", at: directory)
  try runGit(
    "git -C \(directory.path) add Sources/App.swift && "
      + "git -C \(directory.path) "
      + "-c user.email=t@t -c user.name=t commit -q -m 'Add App.swift'",
    at: directory
  )
  let sha = try getSingleCommitSHA(at: directory)
  return [SessionCommit(sha: sha, short: String(sha.prefix(7)), subject: "Add App.swift")]
}

/// Returns the full SHA of the current HEAD commit.
func getSingleCommitSHA(at directory: URL) throws -> String {
  let stdout = try captureGit(["rev-parse", "HEAD"], at: directory)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  guard !stdout.isEmpty else {
    throw TestHelperError.noCommitSHAFound
  }
  return stdout
}

func captureGit(_ arguments: [String], at directory: URL) throws -> String {
  let process = Process()
  process.launchPath = "/usr/bin/git"
  process.arguments = arguments
  process.currentDirectoryURL = directory
  let outputPipe = Pipe()
  process.standardOutput = outputPipe
  process.standardError = Pipe()
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw TestHelperError.gitCommandFailed(status: process.terminationStatus)
  }
  let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
  return String(data: data, encoding: .utf8) ?? ""
}

/// Runs a shell command asynchronously at the given URL, throwing on non-zero exit.
func runShell(_ command: String, at url: URL) async throws {
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    Task {
      let process = Process()
      process.launchPath = "/bin/zsh"
      process.arguments = ["-lc", command]
      process.currentDirectoryURL = url
      process.standardOutput = Pipe()
      process.standardError = Pipe()
      do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
          continuation.resume()
        } else {
          continuation.resume(throwing: TestHelperError.shellFailed(command: command))
        }
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}

/// Captures the stdout of a shell command run at the given URL.
func capture(_ command: String, at url: URL) async throws -> String {
  try await withCheckedThrowingContinuation { continuation in
    Task {
      let process = Process()
      process.launchPath = "/bin/zsh"
      process.arguments = ["-lc", command]
      process.currentDirectoryURL = url
      let outputPipe = Pipe()
      process.standardOutput = outputPipe
      process.standardError = Pipe()
      do {
        try process.run()
        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        continuation.resume(returning: output)
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}

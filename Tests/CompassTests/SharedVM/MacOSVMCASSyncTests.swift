import CompassCore
import Foundation
import Testing

struct MacOSVMCASSyncTests {

  @Test
  func guestPathsPlaceObjectsAndManifestBesideWorktree() {
    let paths = SharedCompassVMCASSync.guestPaths(workspaceID: "abc-123")
    #expect(paths.workspaceRoot == "/Users/compass/Compass/Repos/abc-123")
    #expect(paths.worktreePath == "/Users/compass/Compass/Repos/abc-123/worktree")
    #expect(paths.objectsPath == "/Users/compass/Compass/Repos/abc-123/objects")
    #expect(paths.manifestPath == "/Users/compass/Compass/Repos/abc-123/manifest.json")
  }

  @Test
  func objectRelativePathUsesHashPrefixSharding() {
    let hash = "abcdef0123456789"
    #expect(SharedCompassVMCASSync.objectRelativePath(forHash: hash) == "objects/ab/cdef0123456789")
  }

  @Test
  func buildHostManifestCapturesFilesSkipsIgnoredAndIsStable() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }

    let first = try SharedCompassVMCASSync.buildHostManifest(at: repo)
    #expect(first.entries.contains { $0.path == "file.txt" && $0.kind == "file" })
    #expect(first.entries.contains { $0.path == "link" && $0.kind == "symlink" })
    #expect(!first.entries.contains { $0.path == "ignored.bin" })
    #expect(first.id == SharedCompassVMCASSync.manifestID(for: first.entries))

    let second = try SharedCompassVMCASSync.buildHostManifest(at: repo)
    #expect(first == second)

    try "edited".write(
      to: repo.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    let third = try SharedCompassVMCASSync.buildHostManifest(at: repo)
    #expect(third.id != first.id)
    #expect(
      third.entries.first { $0.path == "file.txt" }?.hash
        != first.entries.first { $0.path == "file.txt" }?.hash)
  }

  @Test
  func manifestIDChangesWhenSymlinkTargetChanges() throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }
    let before = try SharedCompassVMCASSync.buildHostManifest(at: repo)
    let link = repo.appendingPathComponent("link")
    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "other.txt")
    let after = try SharedCompassVMCASSync.buildHostManifest(at: repo)
    #expect(before.id != after.id)
  }

  // MARK: - Helpers

  private func makeTempRepo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("compass-cas-sync-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    _ = try git(url, "init")
    try "ignored.bin\n".write(
      to: url.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    try "initial".write(
      to: url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    try "other".write(
      to: url.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
      atPath: url.appendingPathComponent("link").path,
      withDestinationPath: "file.txt"
    )
    try "build artifact".write(
      to: url.appendingPathComponent("ignored.bin"), atomically: true, encoding: .utf8)
    _ = try git(url, "add", "-A")
    _ = try git(
      url, "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "init")
    return url
  }

  @discardableResult
  private func git(_ repo: URL, _ args: String...) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = repo
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let out =
      String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard process.terminationStatus == 0 else {
      let err =
        String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      throw NSError(
        domain: "MacOSVMCASSyncTests", code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed: \(err)"])
    }
    return out
  }
}

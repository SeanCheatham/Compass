import Foundation
import Testing

@testable import CompassCore

struct SharedCompassVMWorktreeSyncStagingTests {

  @Test
  func guestSyncStagingPathStaysUnderReposJail() {
    let worktree = "/Users/compass/Compass/Repos/abc-123/worktree"
    let staged = SharedCompassVMWorktreeSync.guestSyncStagingPath(
      nearGuestWorktreePath: worktree,
      name: "compass-sync-in-deadbeef.tar"
    )
    #expect(staged == "/Users/compass/Compass/Repos/abc-123/compass-sync-in-deadbeef.tar")
    #expect(staged.hasPrefix(SharedCompassVMGuestWorkspaceCatalog.guestReposRoot + "/"))
    #expect(!staged.hasPrefix("/tmp/"))
  }

  @Test
  func guestWorkspaceRootIsParentOfWorktree() {
    #expect(
      SharedCompassVMWorktreeSync.guestWorkspaceRoot(
        for: "/Users/compass/Compass/Repos/abc-123/worktree"
      ) == "/Users/compass/Compass/Repos/abc-123"
    )
  }

  /// Regression: sequential stdin-write then stdout-read deadlocks once
  /// tar fills the ~64 KiB pipe. Enough small files to exceed that.
  @Test
  func buildHostTarDrainsStdoutWhileFeedingPathList() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "compass-tar-pipe-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let gitInit = Process()
    gitInit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    gitInit.arguments = ["-C", root.path, "init"]
    gitInit.standardOutput = Pipe()
    gitInit.standardError = Pipe()
    try gitInit.run()
    gitInit.waitUntilExit()
    #expect(gitInit.terminationStatus == 0)

    let payload = Data(repeating: 0x61, count: 4096)
    for i in 0..<80 {
      let file = root.appending(path: String(format: "f-%03d.txt", i))
      try payload.write(to: file)
    }
    let gitAdd = Process()
    gitAdd.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    gitAdd.arguments = ["-C", root.path, "add", "."]
    gitAdd.standardOutput = Pipe()
    gitAdd.standardError = Pipe()
    try gitAdd.run()
    gitAdd.waitUntilExit()
    #expect(gitAdd.terminationStatus == 0)

    let tarData = try SharedCompassVMWorktreeSync.buildHostTar(at: root)
    #expect(tarData.count > 64 * 1024)

    let tarFile = root.appending(path: "out.tar")
    try tarData.write(to: tarFile)
    let list = Process()
    list.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    list.arguments = ["-tf", tarFile.path]
    let stdout = Pipe()
    list.standardOutput = stdout
    list.standardError = Pipe()
    try list.run()
    let listed = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
    list.waitUntilExit()
    #expect(list.terminationStatus == 0)
    let names = String(decoding: listed, as: UTF8.self)
      .split(whereSeparator: \.isNewline)
      .map(String.init)
    #expect(names.count == 80)
  }
}

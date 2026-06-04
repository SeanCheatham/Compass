import Foundation
import Testing

@testable import Compass

struct RustEngineLocatorTests {
  @Test func devPathCandidateFindsReleaseBinaryFromRepoRoot() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "RustEngineLocatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let binary = root
      .appending(path: "target", directoryHint: .isDirectory)
      .appending(path: "release", directoryHint: .isDirectory)
      .appending(path: "compass-engine")
    try FileManager.default.createDirectory(
      at: binary.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "#!/bin/sh\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

    let original = FileManager.default.currentDirectoryPath
    FileManager.default.changeCurrentDirectoryPath(root.path)
    defer { FileManager.default.changeCurrentDirectoryPath(original) }

    #expect(RustEngineLocator.locateEngineBinary()?.path == binary.path)
  }
}

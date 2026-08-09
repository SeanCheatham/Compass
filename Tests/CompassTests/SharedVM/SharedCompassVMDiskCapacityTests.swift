import Foundation
import Testing

@testable import CompassCore

@Suite("SharedCompassVM disk capacity")
struct SharedCompassVMDiskCapacityTests {
  @Test
  func allocateThenExtendGrowsSparseImage() throws {
    let dir = FileManager.default.temporaryDirectory
      .appending(path: "compass-disk-extend-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let image = dir.appending(path: "Disk.img")

    let oneMiB: UInt64 = 1 * 1024 * 1024
    let twoMiB: UInt64 = 2 * 1024 * 1024
    try SharedCompassVMImageInstaller.allocateDiskImageIfNeeded(
      at: image,
      sizeInBytes: oneMiB
    )
    #expect(try SharedCompassVMImageInstaller.diskImageSizeInBytes(at: image) == oneMiB)

    try SharedCompassVMImageInstaller.extendDiskImage(at: image, toSizeInBytes: twoMiB)
    #expect(try SharedCompassVMImageInstaller.diskImageSizeInBytes(at: image) == twoMiB)

    // Equal size is a no-op.
    try SharedCompassVMImageInstaller.extendDiskImage(at: image, toSizeInBytes: twoMiB)
    #expect(try SharedCompassVMImageInstaller.diskImageSizeInBytes(at: image) == twoMiB)
  }

  @Test
  func extendRejectsMissingAndShrink() throws {
    let missing = FileManager.default.temporaryDirectory
      .appending(path: "compass-disk-missing-\(UUID().uuidString).img")
    #expect(throws: SharedCompassVMImageInstaller.DiskCapacityError.self) {
      try SharedCompassVMImageInstaller.extendDiskImage(at: missing, toSizeInBytes: 1024)
    }

    let dir = FileManager.default.temporaryDirectory
      .appending(path: "compass-disk-shrink-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let image = dir.appending(path: "Disk.img")
    let twoMiB: UInt64 = 2 * 1024 * 1024
    try SharedCompassVMImageInstaller.allocateDiskImageIfNeeded(at: image, sizeInBytes: twoMiB)

    #expect(throws: SharedCompassVMImageInstaller.DiskCapacityError.self) {
      try SharedCompassVMImageInstaller.extendDiskImage(at: image, toSizeInBytes: 1024)
    }
  }

  @Test
  func allocateLeavesExistingImageAlone() throws {
    let dir = FileManager.default.temporaryDirectory
      .appending(path: "compass-disk-noop-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let image = dir.appending(path: "Disk.img")
    let oneMiB: UInt64 = 1 * 1024 * 1024
    try SharedCompassVMImageInstaller.allocateDiskImageIfNeeded(at: image, sizeInBytes: oneMiB)
    try SharedCompassVMImageInstaller.allocateDiskImageIfNeeded(
      at: image,
      sizeInBytes: 8 * 1024 * 1024
    )
    #expect(try SharedCompassVMImageInstaller.diskImageSizeInBytes(at: image) == oneMiB)
  }

  @Test
  func resetInstalledArtifactsPreservesLastBundleSize() throws {
    let dir = FileManager.default.temporaryDirectory
      .appending(path: "compass-bundle-reset-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let bundle = SharedCompassVMBundle(rootURL: dir)
    try bundle.ensureExists()
    _ = FileManager.default.createFile(atPath: bundle.diskImageURL.path, contents: Data())
    _ = FileManager.default.createFile(atPath: bundle.auxiliaryStorageURL.path, contents: Data())
    let preferred: UInt64 = 128 * 1024 * 1024 * 1024
    try bundle.saveState(
      SharedCompassVMBundle.State(
        provisionStep: .ready,
        lastBundleSize: preferred,
        guestMACAddress: "02:00:00:00:00:01"
      )
    )

    try bundle.resetInstalledArtifacts()
    let state = try bundle.loadState()
    #expect(state.provisionStep == .notProvisioned)
    #expect(state.lastBundleSize == preferred)
    #expect(state.guestMACAddress == "02:00:00:00:00:01")
    #expect(!FileManager.default.fileExists(atPath: bundle.diskImageURL.path))
  }

  @Test
  func formatGiBRoundsWholeNumbers() {
    #expect(SharedCompassVM.formatGiB(64 * 1024 * 1024 * 1024) == "64 GiB")
    #expect(SharedCompassVM.formatGiB(512 * 1024 * 1024 * 1024) == "512 GiB")
  }
}

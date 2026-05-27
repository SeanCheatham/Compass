import Foundation
import Testing

@testable import Compass

/// Coverage for `SharedCompassVMBundle`'s file-layout helpers and State Codable contract.
/// The bundle's `ensureExists()` creates plain directories on disk, so we exercise it
/// against a temporary directory instead of `~/Library/Application Support`.
struct SharedCompassVMBundleTests {
  private var temporaryDirectories: [URL] = []

  func cleanup() {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  // MARK: - State Codable

  @Test
  func testStateRoundTripsThroughJSONEncodeDecode() throws {
    let original = SharedCompassVMBundle.State(
      provisionStep: .ready,
      lastKnownGoodIP: "10.0.0.42",
      guestUserName: "compass",
      guestOSVersion: "26.0.1",
      bootAttemptCounter: 7,
      lastBundleSize: 12_345_678
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(SharedCompassVMBundle.State.self, from: data)

    #require(decoded == original)
  }

  @Test
  func testStateDefaultsAreSensible() {
    let state = SharedCompassVMBundle.State()
    #require(state.provisionStep == .notProvisioned)
    #require(state.lastKnownGoodIP == nil)
    #require(state.guestUserName == SharedCompassVMBundle.State.defaultGuestUserName)
    #require(state.guestOSVersion == nil)
    #require(state.bootAttemptCounter == 0)
    #require(state.lastBundleSize == nil)
  }

  @Test
  func testProvisionStepEnumRoundTripsEachCaseThroughCodable() throws {
    let allSteps: [SharedCompassVMBundle.State.ProvisionStep] = [
      .notProvisioned,
      .downloadingIPSW,
      .installing,
      .guestPrepping,
      .ready,
    ]
    for step in allSteps {
      let encoded = try JSONEncoder().encode(step)
      let decoded = try JSONDecoder().decode(
        SharedCompassVMBundle.State.ProvisionStep.self,
        from: encoded
      )
      #require(decoded == step)
    }
  }

  // MARK: - Path helpers

  @Test
  func testRestoreImageURLLivesUnderCacheDirectory() {
    let bundle = makeBundle()
    let url = bundle.restoreImageURL(forVersion: "26.0.1.23A123")
    #require(
      url.path.hasPrefix(bundle.cacheDirectoryURL.path + "/"),
      "Expected \(url.path) to be under \(bundle.cacheDirectoryURL.path)"
    )
    #require(url.lastPathComponent.hasSuffix(".ipsw"))
    #require(url.lastPathComponent.contains("26.0.1.23A123"))
  }

  @Test
  func testBundleFilePathsAreUnderBundleRoot() {
    let bundle = makeBundle()
    let root = bundle.rootURL.path
    let mustBeUnderRoot: [URL] = [
      bundle.diskImageURL,
      bundle.auxiliaryStorageURL,
      bundle.hardwareModelURL,
      bundle.machineIdentifierURL,
      bundle.stateURL,
      bundle.knownHostsURL,
      bundle.privateKeyURL,
      bundle.publicKeyURL,
      bundle.cacheDirectoryURL,
    ]
    for url in mustBeUnderRoot {
      #require(
        url.path == root || url.path.hasPrefix(root + "/"),
        "\(url.path) is not under bundle root \(root)"
      )
    }
  }

  // MARK: - ensureExists

  @Test
  func testEnsureExistsCreatesBundleAndCacheDirectories() throws {
    let bundle = makeBundle()
    #require(!FileManager.default.fileExists(atPath: bundle.rootURL.path))

    try bundle.ensureExists()

    var isDir: ObjCBool = false
    #require(FileManager.default.fileExists(atPath: bundle.rootURL.path, isDirectory: &isDir))
    #require(isDir.boolValue)

    var cacheIsDir: ObjCBool = false
    #require(
      FileManager.default.fileExists(
        atPath: bundle.cacheDirectoryURL.path, isDirectory: &cacheIsDir)
    )
    #require(cacheIsDir.boolValue)
  }

  @Test
  func testEnsureExistsIsIdempotent() throws {
    let bundle = makeBundle()
    try bundle.ensureExists()
    // Second call must not throw and must leave the directories in place.
    try bundle.ensureExists()
    #require(FileManager.default.fileExists(atPath: bundle.rootURL.path))
    #require(FileManager.default.fileExists(atPath: bundle.cacheDirectoryURL.path))
  }

  @Test
  func testExistsOnDiskFalseUntilDiskAndAuxiliaryStorageArePresent() throws {
    let bundle = makeBundle()
    try bundle.ensureExists()
    #require(!bundle.existsOnDisk())

    try Data("disk".utf8).write(to: bundle.diskImageURL)
    #require(!bundle.existsOnDisk(), "Still missing AuxiliaryStorage")

    try Data("aux".utf8).write(to: bundle.auxiliaryStorageURL)
    #require(bundle.existsOnDisk())
  }

  @Test
  func testResetInstalledArtifactsRemovesInstallStateButPreservesCacheAndSSHKeys() throws {
    let bundle = makeBundle()
    try bundle.ensureExists()
    let cachedRestoreImage = bundle.restoreImageURL(forVersion: "26.0.1")

    let filesToCreate = [
      bundle.diskImageURL,
      bundle.auxiliaryStorageURL,
      bundle.hardwareModelURL,
      bundle.machineIdentifierURL,
      bundle.knownHostsURL,
      bundle.privateKeyURL,
      bundle.publicKeyURL,
      cachedRestoreImage,
    ]
    for url in filesToCreate {
      try Data(url.lastPathComponent.utf8).write(to: url)
    }
    try bundle.saveState(
      SharedCompassVMBundle.State(
        provisionStep: .installing,
        lastKnownGoodIP: "192.168.64.9",
        guestUserName: "compass",
        guestOSVersion: "26.0",
        bootAttemptCounter: 3,
        lastBundleSize: 12_345,
        guestMACAddress: "02:11:22:33:44:55"
      ))

    try bundle.resetInstalledArtifacts()

    #require(!FileManager.default.fileExists(atPath: bundle.diskImageURL.path))
    #require(!FileManager.default.fileExists(atPath: bundle.auxiliaryStorageURL.path))
    #require(!FileManager.default.fileExists(atPath: bundle.hardwareModelURL.path))
    #require(!FileManager.default.fileExists(atPath: bundle.machineIdentifierURL.path))
    #require(!FileManager.default.fileExists(atPath: bundle.knownHostsURL.path))

    #require(FileManager.default.fileExists(atPath: bundle.privateKeyURL.path))
    #require(FileManager.default.fileExists(atPath: bundle.publicKeyURL.path))
    #require(FileManager.default.fileExists(atPath: cachedRestoreImage.path))

    let state = try bundle.loadState()
    #require(state.provisionStep == .notProvisioned)
    #require(state.lastKnownGoodIP == nil)
    #require(state.guestOSVersion == nil)
    #require(state.bootAttemptCounter == 0)
    #require(state.lastBundleSize == nil)
    #require(state.guestMACAddress == "02:11:22:33:44:55")
  }

  // MARK: - State persistence

  @Test
  func testLoadStateReturnsDefaultWhenFileMissing() throws {
    let bundle = makeBundle()
    try bundle.ensureExists()
    let loaded = try bundle.loadState()
    #require(loaded == SharedCompassVMBundle.State())
  }

  @Test
  func testSaveStateAndReloadRoundTripsValue() throws {
    let bundle = makeBundle()
    let state = SharedCompassVMBundle.State(
      provisionStep: .guestPrepping,
      lastKnownGoodIP: "192.168.64.7",
      guestUserName: "compass",
      guestOSVersion: "26.0.0",
      bootAttemptCounter: 2,
      lastBundleSize: 42
    )
    try bundle.saveState(state)

    let reloaded = try bundle.loadState()
    #require(reloaded == state)
  }

  @Test
  func testMutateStateApplyClosureAndPersistsResult() throws {
    let bundle = makeBundle()
    try bundle.saveState(SharedCompassVMBundle.State())
    let result = try bundle.mutateState { state in
      state.provisionStep = .ready
      state.bootAttemptCounter += 3
    }
    #require(result.provisionStep == .ready)
    #require(result.bootAttemptCounter == 3)

    let reloaded = try bundle.loadState()
    #require(reloaded == result)
  }

  // MARK: - Helpers

  private func makeBundle() -> SharedCompassVMBundle {
    let base = FileManager.default.temporaryDirectory
      .appending(
        path: "SharedCompassVMBundleTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    temporaryDirectories.append(base)
    let bundleRoot = base.appending(path: "bundle.vmbundle", directoryHint: .isDirectory)
    return SharedCompassVMBundle(rootURL: bundleRoot)
  }
}

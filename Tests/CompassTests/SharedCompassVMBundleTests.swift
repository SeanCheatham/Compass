import Foundation
@testable import Compass
import XCTest

/// Coverage for `SharedCompassVMBundle`'s file-layout helpers and State Codable contract.
/// The bundle's `ensureExists()` creates plain directories on disk, so we exercise it
/// against a temporary directory instead of `~/Library/Application Support`.
final class SharedCompassVMBundleTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    // MARK: - State Codable

    func testStateRoundTripsThroughJSONEncodeDecode() throws {
        let original = SharedCompassVMBundle.State(
            provisionStep: .ready,
            lastKnownGoodIP: "10.0.0.42",
            guestUserName: "compass",
            guestOSVersion: "26.0.1",
            codexLoginCompleted: true,
            bootAttemptCounter: 7,
            lastBundleSize: 12_345_678
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(SharedCompassVMBundle.State.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testStateDefaultsAreSensible() {
        let state = SharedCompassVMBundle.State()
        XCTAssertEqual(state.provisionStep, .notProvisioned)
        XCTAssertNil(state.lastKnownGoodIP)
        XCTAssertEqual(state.guestUserName, SharedCompassVMBundle.State.defaultGuestUserName)
        XCTAssertNil(state.guestOSVersion)
        XCTAssertFalse(state.codexLoginCompleted)
        XCTAssertEqual(state.bootAttemptCounter, 0)
        XCTAssertNil(state.lastBundleSize)
    }

    func testProvisionStepEnumRoundTripsEachCaseThroughCodable() throws {
        let allSteps: [SharedCompassVMBundle.State.ProvisionStep] = [
            .notProvisioned,
            .downloadingIPSW,
            .installing,
            .firstBootPending,
            .guestPrepping,
            .ready
        ]
        for step in allSteps {
            let encoded = try JSONEncoder().encode(step)
            let decoded = try JSONDecoder().decode(
                SharedCompassVMBundle.State.ProvisionStep.self,
                from: encoded
            )
            XCTAssertEqual(decoded, step)
        }
    }

    // MARK: - Path helpers

    func testRestoreImageURLLivesUnderCacheDirectory() {
        let bundle = makeBundle()
        let url = bundle.restoreImageURL(forVersion: "26.0.1.23A123")
        XCTAssertTrue(
            url.path.hasPrefix(bundle.cacheDirectoryURL.path + "/"),
            "Expected \(url.path) to be under \(bundle.cacheDirectoryURL.path)"
        )
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".ipsw"))
        XCTAssertTrue(url.lastPathComponent.contains("26.0.1.23A123"))
    }

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
            bundle.codexCredentialsStashURL
        ]
        for url in mustBeUnderRoot {
            XCTAssertTrue(
                url.path == root || url.path.hasPrefix(root + "/"),
                "\(url.path) is not under bundle root \(root)"
            )
        }
    }

    // MARK: - ensureExists

    func testEnsureExistsCreatesBundleAndCacheDirectories() throws {
        let bundle = makeBundle()
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.rootURL.path))

        try bundle.ensureExists()

        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.rootURL.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        var cacheIsDir: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: bundle.cacheDirectoryURL.path, isDirectory: &cacheIsDir)
        )
        XCTAssertTrue(cacheIsDir.boolValue)
    }

    func testEnsureExistsIsIdempotent() throws {
        let bundle = makeBundle()
        try bundle.ensureExists()
        // Second call must not throw and must leave the directories in place.
        try bundle.ensureExists()
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.rootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.cacheDirectoryURL.path))
    }

    func testExistsOnDiskFalseUntilDiskAndAuxiliaryStorageArePresent() throws {
        let bundle = makeBundle()
        try bundle.ensureExists()
        XCTAssertFalse(bundle.existsOnDisk())

        try Data("disk".utf8).write(to: bundle.diskImageURL)
        XCTAssertFalse(bundle.existsOnDisk(), "Still missing AuxiliaryStorage")

        try Data("aux".utf8).write(to: bundle.auxiliaryStorageURL)
        XCTAssertTrue(bundle.existsOnDisk())
    }

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
            cachedRestoreImage
        ]
        for url in filesToCreate {
            try Data(url.lastPathComponent.utf8).write(to: url)
        }
        try FileManager.default.createDirectory(at: bundle.codexCredentialsStashURL, withIntermediateDirectories: true)
        try Data("creds".utf8).write(to: bundle.codexCredentialsStashURL.appendingPathComponent("auth.json"))

        try bundle.saveState(SharedCompassVMBundle.State(
            provisionStep: .installing,
            lastKnownGoodIP: "192.168.64.9",
            guestUserName: "compass",
            guestOSVersion: "26.0",
            codexLoginCompleted: true,
            bootAttemptCounter: 3,
            lastBundleSize: 12_345,
            guestMACAddress: "02:11:22:33:44:55"
        ))

        try bundle.resetInstalledArtifacts()

        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.diskImageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.auxiliaryStorageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.hardwareModelURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.machineIdentifierURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.knownHostsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.codexCredentialsStashURL.path))

        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.privateKeyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.publicKeyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedRestoreImage.path))

        let state = try bundle.loadState()
        XCTAssertEqual(state.provisionStep, .notProvisioned)
        XCTAssertNil(state.lastKnownGoodIP)
        XCTAssertNil(state.guestOSVersion)
        XCTAssertFalse(state.codexLoginCompleted)
        XCTAssertEqual(state.bootAttemptCounter, 0)
        XCTAssertNil(state.lastBundleSize)
        XCTAssertEqual(state.guestMACAddress, "02:11:22:33:44:55")
    }

    // MARK: - State persistence

    func testLoadStateReturnsDefaultWhenFileMissing() throws {
        let bundle = makeBundle()
        try bundle.ensureExists()
        let loaded = try bundle.loadState()
        XCTAssertEqual(loaded, SharedCompassVMBundle.State())
    }

    func testSaveStateAndReloadRoundTripsValue() throws {
        let bundle = makeBundle()
        let state = SharedCompassVMBundle.State(
            provisionStep: .firstBootPending,
            lastKnownGoodIP: "192.168.64.7",
            guestUserName: "compass",
            guestOSVersion: "26.0.0",
            codexLoginCompleted: false,
            bootAttemptCounter: 2,
            lastBundleSize: 42
        )
        try bundle.saveState(state)

        let reloaded = try bundle.loadState()
        XCTAssertEqual(reloaded, state)
    }

    func testMutateStateApplyClosureAndPersistsResult() throws {
        let bundle = makeBundle()
        try bundle.saveState(SharedCompassVMBundle.State())
        let result = try bundle.mutateState { state in
            state.provisionStep = .ready
            state.bootAttemptCounter += 3
            state.codexLoginCompleted = true
        }
        XCTAssertEqual(result.provisionStep, .ready)
        XCTAssertEqual(result.bootAttemptCounter, 3)
        XCTAssertTrue(result.codexLoginCompleted)

        let reloaded = try bundle.loadState()
        XCTAssertEqual(reloaded, result)
    }

    // MARK: - Helpers

    private func makeBundle() -> SharedCompassVMBundle {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "SharedCompassVMBundleTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(base)
        let bundleRoot = base.appending(path: "bundle.vmbundle", directoryHint: .isDirectory)
        return SharedCompassVMBundle(rootURL: bundleRoot)
    }
}

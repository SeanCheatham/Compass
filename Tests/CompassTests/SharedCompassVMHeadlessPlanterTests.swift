import XCTest
@testable import Compass

final class SharedCompassVMHeadlessPlanterTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    // MARK: - hdiutil attach plist parsing

    func testParseContainerDevnodeFromAttachPlistPicksTheWholeDiskNode() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>system-entities</key>
            <array>
                <dict>
                    <key>dev-entry</key>
                    <string>/dev/disk7</string>
                    <key>content-hint</key>
                    <string>GUID_partition_scheme</string>
                </dict>
                <dict>
                    <key>dev-entry</key>
                    <string>/dev/disk7s1</string>
                    <key>content-hint</key>
                    <string>Apple_APFS</string>
                </dict>
                <dict>
                    <key>dev-entry</key>
                    <string>/dev/disk7s2</string>
                    <key>content-hint</key>
                    <string>Apple_APFS_ISC</string>
                </dict>
            </array>
        </dict>
        </plist>
        """
        let devnode = try HDIUtilDiskAttacher.parseContainerDeviceNode(fromPlist: plist)
        XCTAssertEqual(devnode, "/dev/disk7")
    }

    func testParseContainerDevnodeFallsBackToFirstEntryWhenNoWholeDiskMatch() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
            <key>system-entities</key>
            <array>
                <dict>
                    <key>dev-entry</key>
                    <string>/dev/disk9s1</string>
                </dict>
            </array>
        </dict>
        </plist>
        """
        let devnode = try HDIUtilDiskAttacher.parseContainerDeviceNode(fromPlist: plist)
        XCTAssertEqual(devnode, "/dev/disk9s1")
    }

    func testParseContainerDevnodeRejectsEmptySystemEntities() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
            <key>system-entities</key>
            <array/>
        </dict>
        </plist>
        """
        XCTAssertThrowsError(try HDIUtilDiskAttacher.parseContainerDeviceNode(fromPlist: plist))
    }

    func testParseContainerDevnodeRejectsNonPlistInput() {
        XCTAssertThrowsError(try HDIUtilDiskAttacher.parseContainerDeviceNode(fromPlist: "garbage"))
    }

    // MARK: - diskutil apfs list plist parsing

    func testParseDataVolumeDevnodeReturnsDataRoleVolume() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
            <key>Containers</key>
            <array>
                <dict>
                    <key>Volumes</key>
                    <array>
                        <dict>
                            <key>DeviceIdentifier</key>
                            <string>disk7s1s1</string>
                            <key>Roles</key>
                            <array>
                                <string>System</string>
                            </array>
                        </dict>
                        <dict>
                            <key>DeviceIdentifier</key>
                            <string>disk7s1s2</string>
                            <key>Roles</key>
                            <array>
                                <string>Data</string>
                            </array>
                        </dict>
                        <dict>
                            <key>DeviceIdentifier</key>
                            <string>disk7s1s3</string>
                            <key>Roles</key>
                            <array>
                                <string>VM</string>
                            </array>
                        </dict>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
        let devnode = try DiskUtilDataVolumeLocator.parseDataVolumeDeviceNode(fromPlist: plist)
        XCTAssertEqual(devnode, "/dev/disk7s1s2")
    }

    func testParseDataVolumeDevnodeThrowsWhenNoDataRolePresent() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
            <key>Containers</key>
            <array>
                <dict>
                    <key>Volumes</key>
                    <array>
                        <dict>
                            <key>DeviceIdentifier</key>
                            <string>disk7s1s1</string>
                            <key>Roles</key>
                            <array>
                                <string>System</string>
                            </array>
                        </dict>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
        XCTAssertThrowsError(try DiskUtilDataVolumeLocator.parseDataVolumeDeviceNode(fromPlist: plist))
    }

    // MARK: - Elevated script rendering

    func testElevatedScriptInstallsLaunchDaemonAsRootWheel0644() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("install -o root -g wheel -m 0644"))
        XCTAssertTrue(script.contains("$MOUNT_POINT/Library/LaunchDaemons/com.seancheatham.Compass.firstboot.plist"))
    }

    func testElevatedScriptInstallsBootstrapScriptAsRootWheel0755() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("install -o root -g wheel -m 0755"))
        XCTAssertTrue(script.contains("$STAGING_DIR/bootstrap.sh"))
        XCTAssertTrue(script.contains("$MOUNT_POINT/usr/local/libexec/compass-firstboot.sh"))
    }

    func testElevatedScriptInstallsSudoersAsRootWheel0440() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("install -o root -g wheel -m 0440"))
        XCTAssertTrue(script.contains("$MOUNT_POINT/private/etc/sudoers.d/compass"))
    }

    func testElevatedScriptInstallsAppleSetupDoneMarker() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("$MOUNT_POINT/private/var/db/.AppleSetupDone"))
    }

    func testElevatedScriptStagesPublicKeyAndPasswordAndOptionalCodex() {
        let scriptWithCodex = renderStandardScript(includeCodex: true)
        let scriptNoCodex = renderStandardScript(includeCodex: false)
        for script in [scriptWithCodex, scriptNoCodex] {
            XCTAssertTrue(script.contains("$MOUNT_POINT/Users/Shared/compass-firstboot/id_ed25519.pub"))
            XCTAssertTrue(script.contains("$MOUNT_POINT/Users/Shared/compass-firstboot/user.password"))
            XCTAssertTrue(script.contains("install -o root -g wheel -m 0600"))
        }
        // The codex install line is wrapped in a `[ -f ... ]` guard regardless.
        XCTAssertTrue(scriptWithCodex.contains("if [ -f \"$STAGING_DIR/codex\" ]"))
        XCTAssertTrue(scriptNoCodex.contains("if [ -f \"$STAGING_DIR/codex\" ]"))
    }

    func testElevatedScriptUnmountsViaTrapOnExit() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("trap cleanup EXIT"))
        XCTAssertTrue(script.contains("diskutil unmount \"$MOUNT_POINT\""))
    }

    func testElevatedScriptUsesDiskutilMountWithExplicitMountPoint() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("diskutil mount -mountPoint \"$MOUNT_POINT\" -nobrowse \"$DATA_DEV\""))
    }

    // MARK: - Staging

    func testStagePayloadWritesAllArtifactsByWellKnownName() throws {
        let stagingDir = makeTempDir()
        let payload = makePayload(includeCodex: true)
        try SharedCompassVMHeadlessPlanter.stagePayload(payload, into: stagingDir)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: stagingDir.appendingPathComponent("launchd.plist").path))
        XCTAssertTrue(fm.fileExists(atPath: stagingDir.appendingPathComponent("bootstrap.sh").path))
        XCTAssertTrue(fm.fileExists(atPath: stagingDir.appendingPathComponent("sudoers").path))
        XCTAssertTrue(fm.fileExists(atPath: stagingDir.appendingPathComponent("apple-setup-done").path))
        XCTAssertTrue(fm.fileExists(atPath: stagingDir.appendingPathComponent("id_ed25519.pub").path))
        XCTAssertTrue(fm.fileExists(atPath: stagingDir.appendingPathComponent("user.password").path))
        XCTAssertTrue(fm.fileExists(atPath: stagingDir.appendingPathComponent("codex").path))
    }

    func testStagePayloadOmitsCodexFileWhenAbsent() throws {
        let stagingDir = makeTempDir()
        let payload = makePayload(includeCodex: false)
        try SharedCompassVMHeadlessPlanter.stagePayload(payload, into: stagingDir)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: stagingDir.appendingPathComponent("codex").path)
        )
    }

    func testStagePayloadTightensPasswordFilePermissionsTo0600() throws {
        let stagingDir = makeTempDir()
        let payload = makePayload(includeCodex: false)
        try SharedCompassVMHeadlessPlanter.stagePayload(payload, into: stagingDir)
        let attrs = try FileManager.default.attributesOfItem(
            atPath: stagingDir.appendingPathComponent("user.password").path
        )
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o600)
    }

    func testMakeStagingDirectoryReturnsFreshUUIDPath() throws {
        let first = try SharedCompassVMHeadlessPlanter.makeStagingDirectory()
        temporaryDirectories.append(first)
        let second = try SharedCompassVMHeadlessPlanter.makeStagingDirectory()
        temporaryDirectories.append(second)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.lastPathComponent.hasPrefix("Compass-HeadlessFirstBoot-"))
    }

    // MARK: - plant(...) integration with mocked deps

    func testPlantOrchestrationStagesPayloadInvokesElevatorAndDetachesContainer() async throws {
        // Fakes capture every call so the test can assert order + arguments
        // without spawning hdiutil / osascript.
        let attacher = FakeAttacher()
        attacher.deviceNode = "/dev/disk7"
        let locator = FakeLocator()
        locator.dataVolume = "/dev/disk7s1s2"
        let elevator = FakeElevator()
        elevator.output = "[compass-planter] done.\n"

        let dependencies = SharedCompassVMHeadlessPlanter.Dependencies(
            diskAttacher: attacher,
            dataVolumeLocator: locator,
            elevator: elevator
        )

        let diskImageURL = makeTempDir().appendingPathComponent("Disk.img", isDirectory: false)
        FileManager.default.createFile(atPath: diskImageURL.path, contents: Data())

        let payload = makePayload(includeCodex: true)
        let report = try await SharedCompassVMHeadlessPlanter.plant(
            payload: payload,
            diskImageURL: diskImageURL,
            dependencies: dependencies
        )

        // Mock invocation accounting
        XCTAssertEqual(attacher.attachedURLs, [diskImageURL])
        XCTAssertEqual(locator.queriedContainers, ["/dev/disk7"])
        XCTAssertEqual(elevator.invokedScriptURLs.count, 1)
        XCTAssertTrue(report.dataVolumeDeviceNode == "/dev/disk7s1s2")
        XCTAssertEqual(report.elevatedScriptOutput, "[compass-planter] done.\n")

        // The elevated script the planter wrote must reference both the
        // staging dir it created and the data volume devnode it discovered.
        let writtenScript = elevator.invokedScriptContents.first ?? ""
        XCTAssertTrue(writtenScript.contains("/dev/disk7s1s2"))
        XCTAssertTrue(writtenScript.contains("$STAGING_DIR/launchd.plist"))
        XCTAssertTrue(writtenScript.contains("$STAGING_DIR/bootstrap.sh"))
        XCTAssertTrue(writtenScript.contains("$STAGING_DIR/sudoers"))
        XCTAssertTrue(writtenScript.contains("$STAGING_DIR/user.password"))
        XCTAssertTrue(writtenScript.contains("$STAGING_DIR/id_ed25519.pub"))

        // After completion, the planter must detach the container so VZ can
        // grab the disk back for boot. (The detach call is deferred inside
        // plant; allow the runtime a tick to drain it.)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(attacher.detachedDeviceNodes, ["/dev/disk7"])

        // Staging dir must be cleaned up so subsequent runs start fresh.
        XCTAssertFalse(FileManager.default.fileExists(atPath: report.stagingDirectoryURL.path))
    }

    func testPlantCleansUpStagingDirectoryEvenWhenElevatedScriptThrows() async throws {
        let attacher = FakeAttacher()
        attacher.deviceNode = "/dev/disk9"
        let locator = FakeLocator()
        locator.dataVolume = "/dev/disk9s1s2"
        let elevator = FakeElevator()
        elevator.errorToThrow = SharedCompassVMHeadlessPlanter.Error.userCancelledElevation

        let dependencies = SharedCompassVMHeadlessPlanter.Dependencies(
            diskAttacher: attacher,
            dataVolumeLocator: locator,
            elevator: elevator
        )
        let diskImageURL = makeTempDir().appendingPathComponent("Disk.img", isDirectory: false)
        FileManager.default.createFile(atPath: diskImageURL.path, contents: Data())

        let payload = makePayload(includeCodex: false)
        do {
            _ = try await SharedCompassVMHeadlessPlanter.plant(
                payload: payload,
                diskImageURL: diskImageURL,
                dependencies: dependencies
            )
            XCTFail("plant should rethrow elevator failures")
        } catch SharedCompassVMHeadlessPlanter.Error.userCancelledElevation {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }

        // Even on failure, the staging dir must be removed so the next
        // provisioning attempt is not left with stale files on disk.
        let leftoverDirs = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            includingPropertiesForKeys: nil
        )) ?? []
        let leakedPlanterDirs = leftoverDirs.filter {
            $0.lastPathComponent.hasPrefix("Compass-HeadlessFirstBoot-")
        }
        XCTAssertTrue(leakedPlanterDirs.isEmpty, "plant leaked staging directories: \(leakedPlanterDirs)")
    }

    // MARK: - Test doubles

    private final class FakeAttacher: HostDiskAttaching, @unchecked Sendable {
        var deviceNode: String = "/dev/disk0"
        var attachedURLs: [URL] = []
        var detachedDeviceNodes: [String] = []

        func attachWithoutMount(diskImageURL: URL) async throws -> HostDiskAttachment {
            attachedURLs.append(diskImageURL)
            return HostDiskAttachment(containerDeviceNode: deviceNode, rawPlist: "")
        }

        func detach(deviceNode: String) async throws {
            detachedDeviceNodes.append(deviceNode)
        }
    }

    private final class FakeLocator: DataVolumeLocating, @unchecked Sendable {
        var dataVolume: String = "/dev/disk0s1s2"
        var queriedContainers: [String] = []

        func locateDataVolume(insideContainer container: String) async throws -> String {
            queriedContainers.append(container)
            return dataVolume
        }
    }

    private final class FakeElevator: AdminElevating, @unchecked Sendable {
        var output: String = ""
        var errorToThrow: Error?
        var invokedScriptURLs: [URL] = []
        var invokedScriptContents: [String] = []

        func runElevatedScript(at scriptURL: URL) async throws -> String {
            invokedScriptURLs.append(scriptURL)
            if let contents = try? String(contentsOf: scriptURL, encoding: .utf8) {
                invokedScriptContents.append(contents)
            }
            if let errorToThrow {
                throw errorToThrow
            }
            return output
        }
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompassHeadlessPlanterTest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func makePayload(includeCodex: Bool) -> SharedCompassVMHeadlessFirstBoot.Payload {
        let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
        let inputs = SharedCompassVMHeadlessFirstBoot.RenderInputs.makeStandard(
            profile: profile,
            publicKeyData: Data("ssh-ed25519 AAAA fake".utf8),
            codexBinaryData: includeCodex ? Data("#!/bin/sh\necho fake\n".utf8) : nil,
            generatedPassword: "passwordforsure"
        )
        return SharedCompassVMHeadlessFirstBoot.renderPayload(from: inputs)
    }

    private func renderStandardScript(includeCodex: Bool = false) -> String {
        let payload = makePayload(includeCodex: includeCodex)
        return SharedCompassVMHeadlessPlanter.renderElevatedScript(
            payload: payload,
            stagingDirectoryHostPath: "/tmp/Compass-HeadlessFirstBoot-xyz",
            dataVolumeDeviceNode: "/dev/disk7s1s2"
        )
    }
}

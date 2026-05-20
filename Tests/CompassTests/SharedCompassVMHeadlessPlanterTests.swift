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

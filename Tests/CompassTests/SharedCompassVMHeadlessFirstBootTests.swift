import XCTest
@testable import Compass

final class SharedCompassVMHeadlessFirstBootTests: XCTestCase {
    // MARK: - Profile registry

    func testProfileRegistryReturnsStandardProfileForKnownMajor() {
        let profile = SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 16)
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.macOSMajor, 16)
        XCTAssertEqual(profile?.appleSetupDoneGuestPath, "/private/var/db/.AppleSetupDone")
        XCTAssertEqual(profile?.launchDaemonGuestPath, "/Library/LaunchDaemons/com.seancheatham.Compass.firstboot.plist")
        XCTAssertEqual(profile?.bootstrapScriptGuestPath, "/usr/local/libexec/compass-firstboot.sh")
        XCTAssertEqual(profile?.sudoersFragmentGuestPath, "/etc/sudoers.d/compass")
        XCTAssertEqual(profile?.stagingDirectoryGuestPath, "/Users/Shared/compass-firstboot")
    }

    func testProfileRegistryRefusesMacOSBelowSupportedFloor() {
        XCTAssertNil(SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 14))
        XCTAssertNil(SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 0))
    }

    func testProfileRegistryClampsFutureMajorToLatestKnown() {
        let future = SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 99)
        XCTAssertEqual(
            future?.macOSMajor,
            SharedCompassVMHeadlessFirstBoot.Registry.latestKnownMajor
        )
    }

    func testMacOSMajorParsingFromBuildVersion() {
        // Darwin major 24 -> macOS 15 (Sequoia: e.g. 24A335)
        XCTAssertEqual(
            SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "24A335"),
            15
        )
        // Darwin major 25 -> macOS 16
        XCTAssertEqual(
            SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "25B71"),
            16
        )
        // Two-digit prefix with surrounding whitespace
        XCTAssertEqual(
            SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "  26C12  "),
            17
        )
    }

    func testMacOSMajorParsingRejectsUnparseableBuilds() {
        XCTAssertNil(SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: ""))
        XCTAssertNil(SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "A24335"))
        // Darwin 22 -> macOS 13, which is below our supported floor (15).
        XCTAssertNil(SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "22A123"))
    }

    func testProfileForBuildVersionConvenience() {
        let profile = SharedCompassVMHeadlessFirstBoot.Registry.profile(forBuildVersion: "25C12")
        XCTAssertEqual(profile?.macOSMajor, 16)
    }

    // MARK: - LaunchDaemon plist

    func testLaunchDaemonPlistIncludesLabelAndProgramArguments() {
        let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
        let plist = SharedCompassVMHeadlessFirstBoot.renderLaunchDaemonPlist(profile: profile)
        XCTAssertTrue(plist.hasPrefix("<?xml"))
        XCTAssertTrue(plist.contains("<string>com.seancheatham.Compass.firstboot</string>"))
        XCTAssertTrue(plist.contains("<string>/bin/bash</string>"))
        XCTAssertTrue(plist.contains("<string>/usr/local/libexec/compass-firstboot.sh</string>"))
        XCTAssertTrue(plist.contains("<key>RunAtLoad</key>\n    <true/>"))
        XCTAssertTrue(plist.contains("<key>LaunchOnlyOnce</key>\n    <true/>"))
    }

    func testLaunchDaemonPlistIsParseableByPropertyListSerialization() throws {
        let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
        let plist = SharedCompassVMHeadlessFirstBoot.renderLaunchDaemonPlist(profile: profile)
        let data = Data(plist.utf8)
        let parsed = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let dict = parsed as? [String: Any] else {
            XCTFail("rendered plist did not decode to a dictionary")
            return
        }
        XCTAssertEqual(dict["Label"] as? String, "com.seancheatham.Compass.firstboot")
        XCTAssertEqual(dict["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(dict["LaunchOnlyOnce"] as? Bool, true)
        XCTAssertEqual(dict["KeepAlive"] as? Bool, false)
        let args = dict["ProgramArguments"] as? [String]
        XCTAssertEqual(args?.count, 2)
        XCTAssertEqual(args?.first, "/bin/bash")
    }

    // MARK: - Bootstrap script

    func testBootstrapScriptStartsWithBashShebangAndStrictMode() {
        let script = renderStandardScript()
        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(script.contains("set -euo pipefail"))
    }

    func testBootstrapScriptUsesSysadminctlForUserCreation() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("/usr/sbin/sysadminctl \\"))
        XCTAssertTrue(script.contains("-addUser \"$GUEST_USER\""))
        XCTAssertTrue(script.contains("-admin"))
    }

    func testBootstrapScriptShortCircuitsWhenUserAlreadyExists() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("/usr/bin/dscl . -read \"/Users/$GUEST_USER\""))
        XCTAssertTrue(script.contains("user already exists; skipping create"))
    }

    func testBootstrapScriptEnablesRemoteLoginAndAuthorisesSSHKey() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("/usr/sbin/systemsetup -setremotelogin on"))
        XCTAssertTrue(script.contains("cat \"$PUBKEY\" >> \"$GUEST_HOME/.ssh/authorized_keys\""))
        XCTAssertTrue(script.contains("chmod 600 \"$GUEST_HOME/.ssh/authorized_keys\""))
        XCTAssertTrue(script.contains("chmod 700 \"$GUEST_HOME/.ssh\""))
    }

    func testBootstrapScriptCreatesWorkspacesSymlinkAfterShareMount() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("ln -s \"$SHARE_ROOT\" /opt/compass/workspaces"))
        XCTAssertTrue(script.contains("/Volumes/My Shared Files/compass-workspaces"))
    }

    func testBootstrapScriptInstallsCodexWhenStaged() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("install -m 755 \"$CODEX\" /usr/local/bin/codex"))
        XCTAssertTrue(script.contains("install one inside the guest manually"))
    }

    func testBootstrapScriptSelfRemovesLaunchDaemonAndPasswordOnSuccess() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("rm -f \"$LAUNCH_DAEMON\""))
        XCTAssertTrue(script.contains("rm -f \"$PASSWORD_FILE\""))
        XCTAssertTrue(script.contains("touch \"$MARKER\""))
    }

    func testBootstrapScriptSealsSudoersFragmentPermissions() {
        let script = renderStandardScript()
        XCTAssertTrue(script.contains("chmod 0440 \"$SUDOERS_FRAGMENT\""))
        XCTAssertTrue(script.contains("chown root:wheel \"$SUDOERS_FRAGMENT\""))
    }

    // MARK: - Sudoers fragment

    func testSudoersFragmentGrantsPasswordlessSudoToGuestUser() {
        let fragment = SharedCompassVMHeadlessFirstBoot.renderSudoersFragment(guestUserName: "compass")
        XCTAssertTrue(fragment.contains("compass ALL=(ALL) NOPASSWD: ALL"))
    }

    // MARK: - Payload composition

    func testRenderPayloadCarriesEveryArtifactNeededByThePlanter() {
        let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
        let inputs = SharedCompassVMHeadlessFirstBoot.RenderInputs.makeStandard(
            profile: profile,
            publicKeyData: Data("ssh-ed25519 AAAA fake".utf8),
            codexBinaryData: Data("#!/bin/sh\necho fake\n".utf8),
            generatedPassword: "hunter2-not-really"
        )
        let payload = SharedCompassVMHeadlessFirstBoot.renderPayload(from: inputs)

        XCTAssertEqual(payload.profile, profile)
        XCTAssertEqual(payload.guestUserName, "compass")
        XCTAssertEqual(payload.guestFullName, "Compass")
        XCTAssertFalse(payload.launchDaemonPlist.isEmpty)
        XCTAssertTrue(payload.bootstrapScript.contains("set -euo pipefail"))
        XCTAssertTrue(payload.sudoersFragment.contains("NOPASSWD"))
        XCTAssertEqual(payload.stagedPublicKey, inputs.publicKeyData)
        XCTAssertEqual(payload.stagedCodexBinary, inputs.codexBinaryData)
        XCTAssertEqual(payload.stagedPassword, "hunter2-not-really")
    }

    func testRenderPayloadOmitsCodexWhenNotProvided() {
        let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
        let inputs = SharedCompassVMHeadlessFirstBoot.RenderInputs.makeStandard(
            profile: profile,
            publicKeyData: Data("ssh-ed25519 AAAA fake".utf8),
            codexBinaryData: nil,
            generatedPassword: "x"
        )
        let payload = SharedCompassVMHeadlessFirstBoot.renderPayload(from: inputs)
        XCTAssertNil(payload.stagedCodexBinary)
    }

    // MARK: - Helpers

    private func renderStandardScript() -> String {
        let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
        let inputs = SharedCompassVMHeadlessFirstBoot.RenderInputs.makeStandard(
            profile: profile,
            publicKeyData: Data(),
            codexBinaryData: nil,
            generatedPassword: "ignored"
        )
        return SharedCompassVMHeadlessFirstBoot.renderBootstrapScript(inputs: inputs)
    }
}

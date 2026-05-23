import XCTest

@testable import Compass

final class SharedCompassVMHeadlessFirstBootTests: XCTestCase {
  // MARK: - Profile registry

  func testProfileRegistryReturnsStandardProfileForKnownMajor() {
    let profile = SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 16)
    XCTAssertNotNil(profile)
    XCTAssertEqual(profile?.macOSMajor, 16)
    XCTAssertEqual(profile?.appleSetupDoneGuestPath, "/private/var/db/.AppleSetupDone")
    XCTAssertEqual(
      profile?.launchDaemonGuestPath,
      "/Library/LaunchDaemons/com.seancheatham.Compass.firstboot.plist")
    XCTAssertEqual(profile?.bootstrapScriptGuestPath, "/usr/local/libexec/compass-firstboot.sh")
    XCTAssertEqual(profile?.sudoersFragmentGuestPath, "/private/etc/sudoers.d/compass")
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

  func testBootstrapScriptCreatesUserViaDsclNotSysadminctl() {
    // sysadminctl fails with eDSReceiveFailed (-14120) when called
    // from a LaunchDaemon at first boot on Apple Silicon because it
    // cannot reach Keybag for Secure Token provisioning. We bypass
    // it entirely and plant the dslocal record directly via dscl;
    // SSH + sudo work fine without a Secure Token, and we
    // don't enable FileVault.
    let script = renderStandardScript()
    XCTAssertFalse(
      script.contains("/usr/sbin/sysadminctl"),
      "sysadminctl is broken on Apple Silicon first-boot LaunchDaemons; use dscl"
    )
    XCTAssertTrue(script.contains("/usr/bin/dscl . -create \"/Users/$GUEST_USER\""))
    XCTAssertTrue(script.contains("/usr/bin/dscl . -passwd \"/Users/$GUEST_USER\""))
    XCTAssertTrue(script.contains("/usr/sbin/dseditgroup -o edit -a \"$GUEST_USER\" -t user admin"))
  }

  func testBootstrapScriptShortCircuitsWhenUserAlreadyExists() {
    let script = renderStandardScript()
    XCTAssertTrue(script.contains("/usr/bin/dscl . -read \"/Users/$GUEST_USER\" UniqueID"))
    XCTAssertTrue(script.contains("user already exists; skipping create"))
  }

  func testBootstrapScriptWaitsForOpendirectorydBeforeDsclWrites() {
    // On a `.AppleSetupDone`-bypassed first boot, opendirectoryd
    // may not have initialized the local Default node when our
    // LaunchDaemon fires. dscl writes issued before then return 0
    // but never persist — earlier the guest booted with the
    // bootstrap log claiming success yet no users on disk. The
    // readiness wait + explicit bootstrap-fallback keeps that
    // from regressing.
    let script = renderStandardScript()
    XCTAssertTrue(
      script.contains("Waiting for opendirectoryd readiness"),
      "must wait for opendirectoryd before dscl writes"
    )
    XCTAssertTrue(
      script.contains(
        "/bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.opendirectoryd.plist"
      ),
      "fallback path must explicitly bootstrap opendirectoryd"
    )
  }

  func testBootstrapScriptVerifiesDsclUserPersistedToDisk() {
    // dscl returning 0 is not enough — opendirectoryd can accept
    // the write into a confused in-memory state and never flush
    // the plist to /var/db/dslocal. We must check the on-disk
    // file exists, and force a flush via kickstart -k if it is
    // missing, and fail loudly otherwise (so we don't leave the
    // guest in a stuck state with the completion marker set).
    let script = renderStandardScript()
    XCTAssertTrue(
      script.contains("DSLOCAL_PLIST=\"/var/db/dslocal/nodes/Default/users/$GUEST_USER.plist\""),
      "must check the dslocal plist on disk after dscl"
    )
    XCTAssertTrue(
      script.contains("/bin/launchctl kickstart -k system/com.apple.opendirectoryd"),
      "force-flush opendirectoryd if the plist is missing"
    )
    XCTAssertTrue(
      script.contains("FATAL: dslocal plist never appeared on disk"),
      "must hard-fail rather than declare success when persistence fails"
    )
  }

  func testBootstrapScriptGrantsGuestUserSSHAccessGroupMembership() {
    // Ventura+ macOS gates SSH on com.apple.access_ssh group
    // membership. Without this, sshd accepts connections but
    // rejects auth even for admins, even though
    // `systemsetup -getremotelogin` says "On". Earlier first-boot
    // run got here: dscl user created, sshd listening, host probe
    // still failed. Belt-and-suspenders: ensure the group exists
    // before adding the guest user (it isn't always pre-created
    // on a fresh `.AppleSetupDone`-bypassed install).
    let script = renderStandardScript()
    XCTAssertTrue(
      script.contains("/usr/sbin/dseditgroup -o create -q com.apple.access_ssh"),
      "must ensure the SSH access group exists"
    )
    XCTAssertTrue(
      script.contains(
        "/usr/sbin/dseditgroup -o edit -a \"$GUEST_USER\" -t user com.apple.access_ssh"),
      "guest user must be granted com.apple.access_ssh membership"
    )
  }

  func testBootstrapScriptEmitsDiagnosticSnapshotForFutureDumps() {
    // When SSH still fails despite everything looking right, the
    // next dump should give us enough state to diagnose without
    // shelling into the VM. Log systemsetup remotelogin status,
    // group memberships, authorized_keys layout, sshd config auth
    // lines, listener interfaces, and primary IP.
    let script = renderStandardScript()
    XCTAssertTrue(script.contains("sshd diagnostic snapshot"))
    XCTAssertTrue(script.contains("systemsetup -getremotelogin"))
    XCTAssertTrue(script.contains("checkmember -m \"$GUEST_USER\" com.apple.access_ssh"))
    XCTAssertTrue(script.contains("netstat -an -p tcp"))
  }

  func testBootstrapScriptEnablesRemoteLoginNoninteractivelyAndVerifies() {
    // Multi-strategy enablement + verification. `systemsetup
    // -setremotelogin on` would hang on yes/no without piped input;
    // `launchctl load -w` is deprecated on Sonoma+ and may silently
    // no-op; `launchctl enable` + `bootstrap` is the modern path
    // but only enables — `kickstart -k` is what actually starts
    // the service. After all that, verify sshd is listening before
    // moving on, otherwise the host SSH probe will time out.
    let script = renderStandardScript()
    XCTAssertTrue(
      script.contains("echo \"yes\" | /usr/sbin/systemsetup -setremotelogin on"),
      "systemsetup needs piped 'yes' or it hangs forever in a LaunchDaemon"
    )
    XCTAssertTrue(
      script.contains("/bin/launchctl enable system/com.openssh.sshd"),
      "modern enable path required for Sonoma+"
    )
    XCTAssertTrue(
      script.contains("/bin/launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist"),
      "modern bootstrap path required for Sonoma+"
    )
    XCTAssertTrue(
      script.contains("/bin/launchctl kickstart -k system/com.openssh.sshd"),
      "kickstart is what actually starts the enabled service"
    )
    XCTAssertTrue(
      script.contains("/usr/bin/nc -z -G 1 127.0.0.1 22"),
      "must verify sshd is listening before declaring success"
    )
    XCTAssertTrue(script.contains("cat \"$PUBKEY\" >> \"$GUEST_HOME/.ssh/authorized_keys\""))
    XCTAssertTrue(script.contains("chmod 600 \"$GUEST_HOME/.ssh/authorized_keys\""))
    XCTAssertTrue(script.contains("chmod 700 \"$GUEST_HOME/.ssh\""))
  }

  func testBootstrapScriptCreatesGuestLocalWorktreesRoot() {
    // Compass dropped the VirtioFS share + /opt/compass/workspaces
    // symlink after confirming macOS guests TCC-block AppleVirtIOFS
    // reads from every process (including LaunchAgents in gui/501
    // and root via LaunchDaemon). Worktrees now live under the
    // compass user's home and are vsock-synced from the host — the
    // first-boot script just needs to materialize the empty parent
    // dir with the right ownership.
    let script = renderStandardScript()
    XCTAssertTrue(script.contains("WORKTREES_ROOT=\"$GUEST_HOME/Compass/Worktrees\""))
    XCTAssertTrue(script.contains("mkdir -p \"$WORKTREES_ROOT\""))
    XCTAssertTrue(script.contains("chown -R \"$GUEST_USER\":staff \"$GUEST_HOME/Compass\""))
    XCTAssertFalse(
      script.contains("/opt/compass/workspaces"),
      "the VirtioFS-mount symlink must be gone — AppleVirtIOFS is TCC-blocked"
    )
    XCTAssertFalse(
      script.contains("/Volumes/My Shared Files"),
      "the VirtioFS share is no longer attached to the VM"
    )
  }

  func testBootstrapScriptPlantsAutoLoginSoVMBootsStraightToDesktop() {
    // The graphical login window stays at the username/password
    // prompt by default — Compass drives the guest entirely
    // through SSH, but the empty login prompt is a confusing first
    // impression and would block any future VNC-style takeover.
    // Plant /etc/kcpassword (XOR-obfuscated password with Apple's
    // well-known 11-byte key) and set autoLoginUser in
    // /Library/Preferences/com.apple.loginwindow so the VM boots
    // straight to a desktop. killall loginwindow forces the change
    // to take effect on the current boot, not just the next one.
    let script = renderStandardScript()
    XCTAssertTrue(
      script.contains("/etc/kcpassword"),
      "must plant /etc/kcpassword for the auto-login subsystem"
    )
    XCTAssertTrue(
      script.contains("7D895223D2BCDDEAA3B91F"),
      "kcpassword XOR key must be the documented Apple constant"
    )
    XCTAssertTrue(
      script.contains(
        "/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser"),
      "must set autoLoginUser in com.apple.loginwindow preferences"
    )
    XCTAssertTrue(
      script.contains("/bin/chmod 600 /etc/kcpassword"),
      "kcpassword must be root-readable only (XOR obfuscation, not encryption)"
    )
    XCTAssertTrue(
      script.contains("/usr/bin/killall loginwindow"),
      "must restart loginwindow so auto-login takes effect on this boot"
    )
  }

  func testGuestAgentLaunchDaemonLandsInSystemLaunchDaemonsDir() {
    // The guest agent ran as a LaunchAgent in Phase 7/8 because we
    // thought a GUI-session TCC profile was required to read the
    // VirtioFS share. Phase 10 dropped VirtioFS (it's TCC-blocked from
    // every process anyway), so there's no GUI-session prerequisite
    // left — and live testing on macOS 26 showed auto-login is
    // unreliable enough that SecurityAgent often refuses to start a
    // GUI session at all. Switching to a LaunchDaemon (which loads at
    // boot in the system context, then drops to UID 501 via UserName)
    // sidesteps the regression. Pin the directory so a future refactor
    // doesn't accidentally roll back to LaunchAgents.
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    XCTAssertTrue(
      profile.guestAgentLaunchDaemonGuestPath.hasPrefix("/Library/LaunchDaemons/"),
      "guest agent must be a LaunchDaemon (system context, no GUI session) on macOS 26+"
    )
    XCTAssertTrue(profile.guestAgentLaunchDaemonGuestPath.hasSuffix(".plist"))
  }

  func testGuestAgentPlistReferencesItsBinaryAndUsesKeepAlive() {
    // The wire-down failure mode for vsock is "no listener on the
    // guest" → the host gets ECONNREFUSED and can't tell apart
    // "agent crashed" from "agent never started". KeepAlive=true
    // lets launchd restart the agent within seconds of any crash,
    // so a transient crash doesn't wedge subsequent agent runs.
    // UserName drops the daemon to the compass user so worktree
    // ownership stays correct.
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let plist = SharedCompassVMHeadlessFirstBoot.renderGuestAgentLaunchDaemonPlist(profile: profile)
    XCTAssertTrue(plist.contains("<key>KeepAlive</key>\n    <true/>"))
    XCTAssertTrue(plist.contains("<key>RunAtLoad</key>\n    <true/>"))
    XCTAssertTrue(plist.contains("<key>UserName</key>\n    <string>compass</string>"))
    XCTAssertTrue(
      plist.contains("<string>\(profile.guestAgentBinaryGuestPath)</string>"),
      "ProgramArguments must point at the planted binary path"
    )
  }

  func testBootstrapScriptPlantsZshenvSoSSHFindsBinariesOnPATH() {
    // macOS sshd runs `ssh user@host command` as a non-interactive,
    // non-login zsh, which skips /etc/zprofile and therefore
    // path_helper — leaving PATH=/usr/bin:/bin:/usr/sbin:/sbin and
    // /usr/local/bin off PATH. Plant ~/.zshenv (sourced for EVERY zsh,
    // including non-interactive SSH) so PATH includes /usr/local/bin.
    let script = renderStandardScript()
    XCTAssertTrue(
      script.contains("$GUEST_HOME/.zshenv"),
      "must plant ~/.zshenv for the guest user"
    )
    XCTAssertTrue(
      script.contains("compass:path_helper"),
      "uses a sentinel string to make planting idempotent across reboots"
    )
    XCTAssertTrue(
      script.contains("/usr/libexec/path_helper"),
      "must call path_helper so /etc/paths and /etc/paths.d apply"
    )
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
    let agentBytes = Data("not-really-a-mach-o".utf8)
    let inputs = SharedCompassVMHeadlessFirstBoot.RenderInputs.makeStandard(
      profile: profile,
      publicKeyData: Data("ssh-ed25519 AAAA fake".utf8),
      generatedPassword: "hunter2-not-really",
      guestAgentBinary: agentBytes
    )
    let payload = SharedCompassVMHeadlessFirstBoot.renderPayload(from: inputs)

    XCTAssertEqual(payload.profile, profile)
    XCTAssertEqual(payload.guestUserName, "compass")
    XCTAssertEqual(payload.guestFullName, "Compass")
    XCTAssertFalse(payload.launchDaemonPlist.isEmpty)
    XCTAssertTrue(payload.bootstrapScript.contains("set -euo pipefail"))
    XCTAssertTrue(payload.sudoersFragment.contains("NOPASSWD"))
    XCTAssertEqual(payload.stagedPublicKey, inputs.publicKeyData)
    XCTAssertEqual(payload.stagedPassword, "hunter2-not-really")
    XCTAssertEqual(payload.guestAgentBinary, agentBytes)
    let plistString = String(decoding: payload.guestAgentLaunchDaemonPlist, as: UTF8.self)
    XCTAssertTrue(
      plistString.contains(profile.guestAgentBinaryGuestPath),
      "LaunchDaemon plist must reference the planted binary path: \(plistString)"
    )
    XCTAssertTrue(
      plistString.contains(SharedCompassVMHeadlessFirstBoot.guestAgentLaunchDaemonLabel))
  }

  // MARK: - Helpers

  private func renderStandardScript() -> String {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let inputs = SharedCompassVMHeadlessFirstBoot.RenderInputs.makeStandard(
      profile: profile,
      publicKeyData: Data(),
      generatedPassword: "ignored",
      guestAgentBinary: Data()
    )
    return SharedCompassVMHeadlessFirstBoot.renderBootstrapScript(inputs: inputs)
  }
}

import Foundation
import Testing

@testable import Compass

struct SharedCompassVMHeadlessFirstBootTests {
  // MARK: - Profile registry

  @Test
  func testProfileRegistryReturnsStandardProfileForKnownMajor() throws {
    let profile = SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 16)
    try #require(profile != nil)
    try #require(profile?.macOSMajor == 16)
    try #require(profile?.appleSetupDoneGuestPath == "/private/var/db/.AppleSetupDone")
    try #require(
      profile?.launchDaemonGuestPath
        == "/Library/LaunchDaemons/com.seancheatham.Compass.firstboot.plist")
    try #require(profile?.bootstrapScriptGuestPath == "/usr/local/libexec/compass-firstboot.sh")
    try #require(profile?.sudoersFragmentGuestPath == "/private/etc/sudoers.d/compass")
    try #require(profile?.stagingDirectoryGuestPath == "/Users/Shared/compass-firstboot")
  }

  @Test
  func testProfileRegistryRefusesMacOSBelowSupportedFloor() throws {
    try #require(SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 14) == nil)
    try #require(SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 0) == nil)
  }

  @Test
  func testProfileRegistryClampsFutureMajorToLatestKnown() throws {
    let future = SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 99)
    try #require(
      future?.macOSMajor == SharedCompassVMHeadlessFirstBoot.Registry.latestKnownMajor
    )
  }

  @Test
  func testMacOSMajorParsingFromBuildVersion() throws {
    // Darwin major 24 -> macOS 15 (Sequoia: e.g. 24A335)
    try #require(
      SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "24A335") == 15
    )
    // Darwin major 25 -> macOS 16
    try #require(
      SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "25B71") == 16
    )
    // Two-digit prefix with surrounding whitespace
    try #require(
      SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "  26C12  ") == 17
    )
  }

  @Test
  func testMacOSMajorParsingRejectsUnparseableBuilds() throws {
    try #require(SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "") == nil)
    try #require(
      SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "A24335") == nil)
    // Darwin 22 -> macOS 13, which is below our supported floor (15).
    try #require(
      SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "22A123") == nil)
  }

  @Test
  func testProfileForBuildVersionConvenience() throws {
    let profile = SharedCompassVMHeadlessFirstBoot.Registry.profile(forBuildVersion: "25C12")
    try #require(profile?.macOSMajor == 16)
  }

  // MARK: - LaunchDaemon plist

  @Test
  func testLaunchDaemonPlistIncludesLabelAndProgramArguments() throws {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let plist = SharedCompassVMHeadlessFirstBoot.renderLaunchDaemonPlist(profile: profile)
    try #require(plist.hasPrefix("<?xml"))
    try #require(plist.contains("<string>com.seancheatham.Compass.firstboot</string>"))
    try #require(plist.contains("<string>/bin/bash</string>"))
    try #require(plist.contains("<string>/usr/local/libexec/compass-firstboot.sh</string>"))
    try #require(plist.contains("<key>RunAtLoad</key>\n    <true/>"))
    try #require(plist.contains("<key>LaunchOnlyOnce</key>\n    <true/>"))
  }

  @Test
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
      #expect(Bool(false), "rendered plist did not decode to a dictionary")
      return
    }
    try #require(dict["Label"] as? String == "com.seancheatham.Compass.firstboot")
    try #require(dict["RunAtLoad"] as? Bool == true)
    try #require(dict["LaunchOnlyOnce"] as? Bool == true)
    try #require(dict["KeepAlive"] as? Bool == false)
    let args = dict["ProgramArguments"] as? [String]
    try #require(args?.count == 2)
    try #require(args?.first == "/bin/bash")
  }

  // MARK: - Bootstrap script

  @Test
  func testBootstrapScriptStartsWithBashShebangAndStrictMode() throws {
    let script = renderStandardScript()
    try #require(script.hasPrefix("#!/bin/bash"))
    try #require(script.contains("set -euo pipefail"))
  }

  @Test
  func testBootstrapScriptCreatesUserViaDsclNotSysadminctl() throws {
    // sysadminctl fails with eDSReceiveFailed (-14120) when called
    // from a LaunchDaemon at first boot on Apple Silicon because it
    // cannot reach Keybag for Secure Token provisioning. We bypass
    // it entirely and plant the dslocal record directly via dscl;
    // SSH + sudo work fine without a Secure Token, and we
    // don't enable FileVault.
    let script = renderStandardScript()
    try #require(
      !script.contains("/usr/sbin/sysadminctl"),
      "sysadminctl is broken on Apple Silicon first-boot LaunchDaemons; use dscl"
    )
    try #require(script.contains("/usr/bin/dscl . -create \"/Users/$GUEST_USER\""))
    try #require(script.contains("/usr/bin/dscl . -passwd \"/Users/$GUEST_USER\""))
    try #require(script.contains("/usr/sbin/dseditgroup -o edit -a \"$GUEST_USER\" -t user admin"))
  }

  @Test
  func testBootstrapScriptShortCircuitsWhenUserAlreadyExists() throws {
    let script = renderStandardScript()
    try #require(script.contains("/usr/bin/dscl . -read \"/Users/$GUEST_USER\" UniqueID"))
    try #require(script.contains("user already exists; skipping create"))
  }

  @Test
  func testBootstrapScriptWaitsForOpendirectorydBeforeDsclWrites() throws {
    // On a `.AppleSetupDone`-bypassed first boot, opendirectoryd
    // may not have initialized the local Default node when our
    // LaunchDaemon fires. dscl writes issued before then return 0
    // but never persist — earlier the guest booted with the
    // bootstrap log claiming success yet no users on disk. The
    // readiness wait + explicit bootstrap-fallback keeps that
    // from regressing.
    let script = renderStandardScript()
    try #require(
      script.contains("Waiting for opendirectoryd readiness"),
      "must wait for opendirectoryd before dscl writes"
    )
    try #require(
      script.contains(
        "/bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.opendirectoryd.plist"
      ),
      "fallback path must explicitly bootstrap opendirectoryd"
    )
  }

  @Test
  func testBootstrapScriptVerifiesDsclUserPersistedToDisk() throws {
    // dscl returning 0 is not enough — opendirectoryd can accept
    // the write into a confused in-memory state and never flush
    // the plist to /var/db/dslocal. We must check the on-disk
    // file exists, and force a flush via kickstart -k if it is
    // missing, and fail loudly otherwise (so we don't leave the
    // guest in a stuck state with the completion marker set).
    let script = renderStandardScript()
    try #require(
      script.contains("DSLOCAL_PLIST=\"/var/db/dslocal/nodes/Default/users/$GUEST_USER.plist\""),
      "must check the dslocal plist on disk after dscl"
    )
    try #require(
      script.contains("/bin/launchctl kickstart -k system/com.apple.opendirectoryd"),
      "force-flush opendirectoryd if the plist is missing"
    )
    try #require(
      script.contains("FATAL: dslocal plist never appeared on disk"),
      "must hard-fail rather than declare success when persistence fails"
    )
  }

  @Test
  func testBootstrapScriptGrantsGuestUserSSHAccessGroupMembership() throws {
    // Ventura+ macOS gates SSH on com.apple.access_ssh group
    // membership. Without this, sshd accepts connections but
    // rejects auth even for admins, even though
    // `systemsetup -getremotelogin` says "On". Earlier first-boot
    // run got here: dscl user created, sshd listening, host probe
    // still failed. Belt-and-suspenders: ensure the group exists
    // before adding the guest user (it isn't always pre-created
    // on a fresh `.AppleSetupDone`-bypassed install).
    let script = renderStandardScript()
    try #require(
      script.contains("/usr/sbin/dseditgroup -o create -q com.apple.access_ssh"),
      "must ensure the SSH access group exists"
    )
    try #require(
      script.contains(
        "/usr/sbin/dseditgroup -o edit -a \"$GUEST_USER\" -t user com.apple.access_ssh"),
      "guest user must be granted com.apple.access_ssh membership"
    )
  }

  @Test
  func testBootstrapScriptEmitsDiagnosticSnapshotForFutureDumps() throws {
    // When SSH still fails despite everything looking right, the
    // next dump should give us enough state to diagnose without
    // shelling into the VM. Log systemsetup remotelogin status,
    // group memberships, authorized_keys layout, sshd config auth
    // lines, listener interfaces, and primary IP.
    let script = renderStandardScript()
    try #require(script.contains("sshd diagnostic snapshot"))
    try #require(script.contains("systemsetup -getremotelogin"))
    try #require(script.contains("checkmember -m \"$GUEST_USER\" com.apple.access_ssh"))
    try #require(script.contains("netstat -an -p tcp"))
  }

  @Test
  func testBootstrapScriptEnablesRemoteLoginNoninteractivelyAndVerifies() throws {
    // Multi-strategy enablement + verification. `systemsetup
    // -setremotelogin on` would hang on yes/no without piped input;
    // `launchctl enable` + `bootstrap` is the modern path but only
    // enables — `kickstart -k` is what actually starts the service.
    // After all that, verify sshd is listening before moving on,
    // otherwise the host SSH probe will time out.
    let script = renderStandardScript()
    try #require(
      script.contains("echo \"yes\" | /usr/sbin/systemsetup -setremotelogin on"),
      "systemsetup needs piped 'yes' or it hangs forever in a LaunchDaemon"
    )
    try #require(
      script.contains("/bin/launchctl enable system/com.openssh.sshd"),
      "modern enable path required for Sonoma+"
    )
    try #require(
      script.contains("/bin/launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist"),
      "modern bootstrap path required for Sonoma+"
    )
    try #require(
      script.contains("/bin/launchctl kickstart -k system/com.openssh.sshd"),
      "kickstart is what actually starts the enabled service"
    )
    try #require(
      script.contains("/usr/bin/nc -z -G 1 127.0.0.1 22"),
      "must verify sshd is listening before declaring success"
    )
    try #require(script.contains("cat \"$PUBKEY\" >> \"$GUEST_HOME/.ssh/authorized_keys\""))
    try #require(script.contains("chmod 600 \"$GUEST_HOME/.ssh/authorized_keys\""))
    try #require(script.contains("chmod 700 \"$GUEST_HOME/.ssh\""))
  }

  @Test
  func testBootstrapScriptCreatesGuestLocalRepoRoots() throws {
    // Compass dropped the VirtioFS share + /opt/compass/workspaces
    // symlink after confirming macOS guests TCC-block AppleVirtIOFS
    // reads from every process (including LaunchAgents in gui/501
    // and root via LaunchDaemon). Git-backed worktrees now live under
    // the compass user's home and are synced via the vsock Git exchange.
    // The legacy Worktrees root remains for tar-sync fallback state.
    let script = renderStandardScript()
    try #require(script.contains("REPOS_ROOT=\"$GUEST_HOME/Compass/Repos\""))
    try #require(script.contains("mkdir -p \"$REPOS_ROOT\""))
    try #require(script.contains("WORKTREES_ROOT=\"$GUEST_HOME/Compass/Worktrees\""))
    try #require(script.contains("mkdir -p \"$WORKTREES_ROOT\""))
    try #require(script.contains("chown -R \"$GUEST_USER\":staff \"$GUEST_HOME/Compass\""))
    try #require(
      !script.contains("/opt/compass/workspaces"),
      "the VirtioFS-mount symlink must be gone — AppleVirtIOFS is TCC-blocked"
    )
    try #require(
      !script.contains("/Volumes/My Shared Files"),
      "the VirtioFS share is no longer attached to the VM"
    )
  }

  @Test
  func testBootstrapScriptPlantsAutoLoginSoVMBootsStraightToDesktop() throws {
    // The graphical login window stays at the username/password
    // prompt by default — Compass drives the guest entirely
    // through SSH, but the empty login prompt would block any future VNC-style takeover.
    // Plant /etc/kcpassword (XOR-obfuscated password with Apple's
    // well-known 11-byte key) and set autoLoginUser in
    // /Library/Preferences/com.apple.loginwindow so the VM boots
    // straight to a desktop.
    let script = renderStandardScript()
    try #require(
      script.contains("/etc/kcpassword"),
      "must plant /etc/kcpassword for the auto-login subsystem"
    )
    try #require(
      script.contains("7D895223D2BCDDEAA3B91F"),
      "kcpassword XOR key must be the documented Apple constant"
    )
  }

  @Test
  func testAutoLoginHelperScriptWaitsForConsolePasswordAndReappliesKcpassword() throws {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let script = SharedCompassVMHeadlessFirstBoot.renderAutoLoginScript(
      profile: profile,
      guestUserName: "compass"
    )
    try #require(script.hasPrefix("#!/bin/bash"))
    try #require(script.contains("com.seancheatham.Compass.autologin"))
    try #require(script.contains("/var/root/.compass-console-password"))
    try #require(script.contains("/usr/bin/dscl . -authonly \"$GUEST_USER\" \"$PASSWORD\""))
    try #require(script.contains("/etc/kcpassword"))
    try #require(script.contains("autoLoginUser -string"))
    try #require(script.contains("/usr/bin/stat -f '%Su' /dev/console"))
    try #require(script.contains("/usr/bin/killall loginwindow"))
  }

  @Test
  func testAutoLoginLaunchDaemonPlistReferencesHelperScript() throws {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let plist = SharedCompassVMHeadlessFirstBoot.renderAutoLoginLaunchDaemonPlist(profile: profile)
    try #require(plist.contains("<string>com.seancheatham.Compass.autologin</string>"))
    try #require(plist.contains("<string>/usr/local/libexec/compass-autologin.sh</string>"))
    try #require(plist.contains("<key>RunAtLoad</key>\n    <true/>"))
  }

  @Test
  func testGuestAgentLaunchDaemonLandsInSystemLaunchDaemonsDir() throws {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    try #require(
      profile.guestAgentLaunchDaemonGuestPath.hasPrefix("/Library/LaunchDaemons/"),
      "guest agent must be a LaunchDaemon (system context, no GUI session) on macOS 26+"
    )
    try #require(profile.guestAgentLaunchDaemonGuestPath.hasSuffix(".plist"))
  }

  @Test
  func testGuestAgentPlistReferencesItsBinaryAndUsesKeepAlive() throws {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let plist = SharedCompassVMHeadlessFirstBoot.renderGuestAgentLaunchDaemonPlist(profile: profile)
    try #require(plist.contains("<key>KeepAlive</key>\n    <true/>"))
    try #require(plist.contains("<key>RunAtLoad</key>\n    <true/>"))
    try #require(plist.contains("<key>UserName</key>\n    <string>compass</string>"))
    try #require(
      plist.contains("<string>\(profile.guestAgentBinaryGuestPath)</string>"),
      "ProgramArguments must point at the planted binary path"
    )
  }

  @Test
  func testBootstrapScriptPlantsZshenvSoSSHFindsBinariesOnPATH() throws {
    // macOS sshd runs `ssh user@host command` as a non-interactive,
    // non-login zsh, which skips /etc/zprofile and therefore
    // path_helper — leaving PATH=/usr/bin:/bin:/usr/sbin:/sbin and
    // /usr/local/bin off PATH. Plant ~/.zshenv (sourced for EVERY zsh,
    // including non-interactive SSH) so PATH includes /usr/local/bin.
    let script = renderStandardScript()
    try #require(
      script.contains("$GUEST_HOME/.zshenv"),
      "must plant ~/.zshenv for the guest user"
    )
    try #require(
      script.contains("compass:path_helper"),
      "uses a sentinel string to make planting idempotent across reboots"
    )
    try #require(
      script.contains("/usr/libexec/path_helper"),
      "must call path_helper so /etc/paths and /etc/paths.d apply"
    )
  }

  @Test
  func testBootstrapScriptSelfRemovesLaunchDaemonAndPasswordOnSuccess() throws {
    let script = renderStandardScript()
    try #require(script.contains("rm -f \"$LAUNCH_DAEMON\""))
    try #require(script.contains("rm -f \"$PASSWORD_FILE\""))
    try #require(script.contains("touch \"$MARKER\""))
  }

  @Test
  func testBootstrapScriptSealsSudoersFragmentPermissions() throws {
    let script = renderStandardScript()
    try #require(script.contains("chmod 0440 \"$SUDOERS_FRAGMENT\""))
    try #require(script.contains("chown root:wheel \"$SUDOERS_FRAGMENT\""))
  }

  // MARK: - Sudoers fragment

  @Test
  func testSudoersFragmentGrantsPasswordlessSudoToGuestUser() throws {
    let fragment = SharedCompassVMHeadlessFirstBoot.renderSudoersFragment(guestUserName: "compass")
    try #require(fragment.contains("compass ALL=(ALL) NOPASSWD: ALL"))
  }

  // MARK: - Payload composition

  @Test
  func testRenderPayloadCarriesEveryArtifactNeededByThePlanter() throws {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let agentBytes = Data("not-really-a-mach-o".utf8)
    let inputs = SharedCompassVMHeadlessFirstBoot.RenderInputs.makeStandard(
      profile: profile,
      publicKeyData: Data("ssh-ed25519 AAAA fake".utf8),
      generatedPassword: "hunter2-not-really",
      guestAgentBinary: agentBytes
    )
    let payload = SharedCompassVMHeadlessFirstBoot.renderPayload(from: inputs)

    try #require(payload.profile == profile)
    try #require(payload.guestUserName == "compass")
    try #require(payload.guestFullName == "Compass")
    try #require(!payload.launchDaemonPlist.isEmpty)
    try #require(payload.bootstrapScript.contains("set -euo pipefail"))
    try #require(payload.sudoersFragment.contains("NOPASSWD"))
    try #require(payload.stagedPublicKey == inputs.publicKeyData)
    try #require(payload.stagedPassword == "hunter2-not-really")
    try #require(payload.guestAgentBinary == agentBytes)
    let plistString = String(decoding: payload.guestAgentLaunchDaemonPlist, as: UTF8.self)
    try #require(
      plistString.contains(profile.guestAgentBinaryGuestPath),
      "LaunchDaemon plist must reference the planted binary path: \(plistString)"
    )
    try #require(
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

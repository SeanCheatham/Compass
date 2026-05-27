import Foundation
import Testing

@testable import Compass

struct SharedCompassVMHeadlessFirstBootTests {
  // MARK: - Profile registry

  @Test
  func testProfileRegistryReturnsStandardProfileForKnownMajor() {
    let profile = SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 16)
    #require(profile != nil)
    #require(profile?.macOSMajor == 16)
    #require(profile?.appleSetupDoneGuestPath == "/private/var/db/.AppleSetupDone")
    #require(
      profile?.launchDaemonGuestPath ==
      "/Library/LaunchDaemons/com.seancheatham.Compass.firstboot.plist")
    #require(profile?.bootstrapScriptGuestPath == "/usr/local/libexec/compass-firstboot.sh")
    #require(profile?.sudoersFragmentGuestPath == "/private/etc/sudoers.d/compass")
    #require(profile?.stagingDirectoryGuestPath == "/Users/Shared/compass-firstboot")
  }

  @Test
  func testProfileRegistryRefusesMacOSBelowSupportedFloor() {
    #require(SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 14) == nil)
    #require(SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 0) == nil)
  }

  @Test
  func testProfileRegistryClampsFutureMajorToLatestKnown() {
    let future = SharedCompassVMHeadlessFirstBoot.Registry.profile(forMacOSMajor: 99)
    #require(
      future?.macOSMajor ==
      SharedCompassVMHeadlessFirstBoot.Registry.latestKnownMajor
    )
  }

  @Test
  func testMacOSMajorParsingFromBuildVersion() {
    // Darwin major 24 -> macOS 15 (Sequoia: e.g. 24A335)
    #require(
 SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "24A335") ==
      15
    )
    // Darwin major 25 -> macOS 16
    #require(
      SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "25B71") ==
      16
    )
    // Two-digit prefix with surrounding whitespace
    #require(
      SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "  26C12  ") ==
      17
    )
  }

  @Test
  func testMacOSMajorParsingRejectsUnparseableBuilds() {
    #require(SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "") == nil)
    #require(SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBlock: "A24335") == nil)
    // Darwin 22 -> macOS 13, which is below our supported floor (15).
    #require(SharedCompassVMHeadlessFirstBoot.Registry.macOSMajor(forBuildVersion: "22A123") == nil)
  }

  @Test
  func testProfileForBuildVersionConvenience() {
    let profile = SharedCompassVMHeadlessFirstBoot.Registry.profile(forBuildVersion: "25C12")
    #require(profile?.macOSMajor == 16)
  }

  // MARK: - LaunchDaemon plist

  @Test
  func testLaunchDaemonPlistIncludesLabelAndProgramArguments() {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let plist = SharedCompassVMHeadlessFirstBoot.renderLaunchDaemonPlist(profile: profile)
    #require(plist.hasPrefix("<?xml"))
    #require(plist.contains("<string>com.seancheatham.Compass.firstboot</string>"))
    #require(plist.contains("<string>/bin/bash</string>"))
    #require(plist.contains("<string>/usr/local/libexec/compass-firstboot.sh</string>"))
    #require(plist.contains("<key>RunAtLoad</key>\n    <true/>"))
    #require(plist.contains("<key>LaunchOnlyOnce</key>\n    <true/>"))
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
      #require(false, "rendered plist did not decode to a dictionary")
      return
    }
    #require(dict["Label"] as? String == "com.seancheatham.Compass.firstboot")
    #require(dict["RunAtLoad"] as? Bool == true)
    #require(dict["LaunchOnlyOnce"] as? Bool == true)
    #require(dict["KeepAlive"] as? Bool == false)
    let args = dict["ProgramArguments"] as? [String]
    #require(args?.count == 2)
    #require(args?.first == "/bin/bash")
  }

  // MARK: - Bootstrap script

  @Test
  func testBootstrapScriptStartsWithBashShebangAndStrictMode() {
    let script = renderStandardScript()
    #require(script.hasPrefix("#!/bin/bash"))
    #require(script.contains("set -euo pipefail"))
  }

  @Test
  func testBootstrapScriptCreatesUserViaDsclNotSysadminctl() {
    // sysadminctl fails with eDSReceiveFailed (-14120) when called
    // from a LaunchDaemon at first boot on Apple Silicon because it
    // cannot reach Keybag for Secure Token provisioning. We bypass
    // it entirely and plant the dslocal record directly via dscl;
    // SSH + sudo work fine without a Secure Token, and we
    // don't enable FileVault.
    let script = renderStandardScript()
    #require(
      !script.contains("/usr/sbin/sysadminctl"),
      "sysadminctl is broken on Apple Silicon first-boot LaunchDaemons; use dscl"
    )
    #require(script.contains("/usr/bin/dscl . -create \"/Users/$GUEST_USER\""))
    #require(script.contains("/usr/bin/dscl . -passwd \"/Users/$GUEST_USER\""))
    #require(script.contains("/usr/sbin/dseditgroup -o edit -a \"$GUEST_USER\" -t user admin"))
  }

  @Test
  func testBootstrapScriptShortCircuitsWhenUserAlreadyExists() {
    let script = renderStandardScript()
    #require(script.contains("/usr/bin/dscl . -read \"/Users/$GUEST_USER\" UniqueID"))
    #require(script.contains("user already exists; skipping create"))
  }

  @Test
  func testBootstrapScriptWaitsForOpendirectorydBeforeDsclWrites() {
    // On a `.AppleSetupDone`-bypassed first boot, opendirectoryd
    // may not have initialized the local Default node when our
    // LaunchDaemon fires. dscl writes issued before then return 0
    // but never persist — earlier the guest booted with the
    // bootstrap log claiming success yet no users on disk. The
    // readiness wait + explicit bootstrap-fallback keeps that
    // from regressing.
    let script = renderStandardScript()
    #require(
      script.contains("Waiting for opendirectoryd readiness"),
      "must wait for opendirectoryd before dscl writes"
    )
    #require(
      script.contains(
        "/bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.opendirectoryd.plist"
      ),
      "fallback path must explicitly bootstrap opendirectoryd"
    )
  }

  @Test
  func testBootstrapScriptVerifiesDsclUserPersistedToDisk() {
    // dscl returning 0 is not enough — opendirectoryd can accept
    // the write into a confused in-memory state and never flush
    // the plist to /var/db/dslocal. We must check the on-disk
    // file exists, and force a flush via kickstart -k if it is
    // missing, and fail loudly otherwise (so we don't leave the
    // guest in a stuck state with the completion marker set).
    let script = renderStandardScript()
    #require(
      script.contains("DSLOCAL_PLIST=\"/var/db/dslocal/nodes/Default/users/$GUEST_USER.plist\""),
      "must check the dslocal plist on disk after dscl"
    )
    #require(
      script.contains("/bin/launchctl kickstart -k system/com.apple.opendirectoryd"),
      "force-flush opendirectoryd if the plist is missing"
    )
    #require(
      script.contains("FATAL: dslocal plist never appeared on disk"),
      "must hard-fail rather than declare success when persistence fails"
    )
  }

  @Test
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
    #require(
      script.contains("/usr/sbin/dseditgroup -o create -q com.apple.access_ssh"),
      "must ensure the SSH access group exists"
    )
    #require(
      script.contains(
        "/usr/sbin/dseditgroup -o edit -a \"$GUEST_USER\" -t user com.apple.access_ssh"),
      "guest user must be granted com.apple.access_ssh membership"
    )
  }

  @Test
  func testBootstrapScriptEmitsDiagnosticSnapshotForFutureDumps() {
    // When SSH still fails despite everything looking right, the
    // next dump should give us enough state to diagnose without
    // shelling into the VM. Log systemsetup remotelogin status,
    // group memberships, authorized_keys layout, sshd config auth
    // lines, listener interfaces, and primary IP.
    let script = renderStandardScript()
    #require(script.contains("sshd diagnostic snapshot"))
    #require(script.contains("systemsetup -getremotelogin"))
    #require(script.contains("checkmember -m \"$GUEST_USER\" com.apple.access_ssh"))
    #require(script.contains("netstat -an -p tcp"))
  }

  @Test
  func testBootstrapScriptEnablesRemoteLoginNoninteractivelyAndVerifies() {
    // Multi-strategy enablement + verification. `systemsetup
    // -setremotelogin on` would hang on yes/no without piped input;
    // `launchctl enable` + `bootstrap` is the modern path but only
    // enables — `kickstart -k` is what actually starts the service.
    // After all that, verify sshd is listening before moving on,
    // otherwise the host SSH probe will time out.
    let script = renderStandardScript()
    #require(
      script.contains("echo \"yes\" | /usr/sbin/systemsetup -setremotelogin on"),
      "systemsetup needs piped 'yes' or it hangs forever in a LaunchDaemon"
    )
    #require(
      script.contains("/bin/launchctl enable system/com.openssh.sshd"),
      "modern enable path required for Sonoma+"
    )
    #require(
      script.contains("/bin/launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist"),
      "modern bootstrap path required for Sonoma+"
    )
    #require(
      script.contains("/bin/launchctl kickstart -k system/com.openssh.sshd"),
      "kickstart is what actually starts the enabled service"
    )
    #require(
      script.contains("/usr/bin/nc -z -G 1 127.0.0.1 22"),
      "must verify sshd is listening before declaring success"
    )
    #require(script.contains("cat \"$PUBKEY\" >> \"$GUEST_HOME/.ssh/authorized_keys\""))
    #require(script.contains("chmod 600 \"$GUEST_HOME/.ssh/authorized_keys\""))
    #require(script.contains("chmod 700 \"$GUEST_HOME/.ssh\""))
  }

  @Test
  func testBootstrapScriptCreatesGuestLocalWorktreesRoot() {
    // Compass dropped the VirtioFS share + /opt/compass/workspaces
    // symlink after confirming macOS guests TCC-block AppleVirtIOFS
    // reads from every process (including LaunchAgents in gui/501
    // and root via LaunchDaemon). Worktrees now live under the
    // compass user's home and are vsock-synced from the host — the
    // first-boot script just needs to materialize the empty parent
    // dir with the right ownership.
    let script = renderStandardScript()
    #require(script.contains("WORKTREES_ROOT=\"$GUEST_HOME/Compass/Worktrees\""))
    #require(script.contains("mkdir -p \"$WORKTREES_ROOT\""))
    #require(script.contains("chown -R \"$GUEST_USER\":staff \"$GUEST_HOME/Compass\""))
    #require(
      !script.contains("/opt/compass/workspaces"),
      "the VirtioFS-mount symlink must be gone — AppleVirtIOFS is TCC-blocked"
    )
    #require(
      !script.contains("/Volumes/My Shared Files"),
      "the VirtioFS share is no longer attached to the VM"
    )
  }

  @Test
  func testBootstrapScriptPlantsAutoLoginSoVMBootsStraightToDesktop() {
    // The graphical login window stays at the username/password
    // prompt by default — Compass drives the guest entirely
    // through SSH, but the empty login prompt would block any future VNC-style takeover.
    // Plant /etc/kcpassword (XOR-obfuscated password with Apple's
    // well-known 11-byte key) and set autoLoginUser in
    // /Library/Preferences/com.apple.loginwindow so the VM boots
    // straight to a desktop.
    let script = renderStandardScript()
    #require(
      script.contains("/etc/kcpassword"),
      "must plant /etc/kcpassword for the auto-login subsystem"
    )
    #require(
      script.contains("7D895223D2BCDDEAA3B91F"),
      "kcpassword XOR key must be the documented Apple constant"
    )
  }

  @Test
  func testAutoLoginHelperScriptWaitsForConsolePasswordAndReappliesKcpassword() {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let script = SharedCompassVMHeadlessFirstBoot.renderAutoLoginScript(
      profile: profile,
      guestUserName: "compass"
    )
    #require(script.hasPrefix("#!/bin/bash"))
    #require(script.contains("com.seancheatham.Compass.autologin"))
    #require(script.contains("/var/root/.compass-console-password"))
    #require(script.contains("/usr/bin/dscl . -authonly \"$GUEST_USER\" \"$PASSWORD\""))
    #require(script.contains("/etc/kcpassword"))
    #require(script.contains("autoLoginUser -string"))
    #require(script.contains("/usr/bin/stat -f '%Su' /dev/console"))
    #require(script.contains("/usr/bin/killall loginwindow"))
  }

  @Test
  func testAutoLoginLaunchDaemonPlistReferencesHelperScript() {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let plist = SharedCompassVMHeadlessFirstBoot.renderAutoLoginLaunchDaemonPlist(profile: profile)
    #require(plist.contains("<string>com.seancheatham.Compass.autologin</string>"))
    #require(plist.contains("<string>/usr/local/libexec/compass-autologin.sh</string>"))
    #require(plist.contains("<key>RunAtLoad</key>\n    <true/>"))
  }

  @Test
  func testGuestAgentLaunchDaemonLandsInSystemLaunchDaemonsDir() {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    #require(
      profile.guestAgentLaunchDaemonGuestPath.hasPrefix("/Library/LaunchDaemons/"),
      "guest agent must be a LaunchDaemon (system context, no GUI session) on macOS 26+"
    )
    #require(profile.guestAgentLaunchDaemonGuestPath.hasSuffix(".plist"))
  }

  @Test
  func testGuestAgentPlistReferencesItsBinaryAndUsesKeepAlive() {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let plist = SharedCompassVMHeadlessFirstBoot.renderGuestAgentLaunchDaemonPlist(profile: profile)
    #require(plist.contains("<key>KeepAlive</key>\n    <true/>"))
    #require(plist.contains("<key>RunAtLoad</key>\n    <true/>"))
    #require(plist.contains("<key>UserName</key>\n    <string>compass</string>"))
    #require(
      plist.contains("<string>\(profile.guestAgentBinaryGuestPath)</string>"),
      "ProgramArguments must point at the planted binary path"
    )
  }

  @Test
  func testBootstrapScriptPlantsZshenvSoSSHFindsBinariesOnPATH() {
    // macOS sshd runs `ssh user@host command` as a non-interactive,
    // non-login zsh, which skips /etc/zprofile and therefore
    // path_helper — leaving PATH=/usr/bin:/bin:/usr/sbin:/sbin and
    // /usr/local/bin off PATH. Plant ~/.zshenv (sourced for EVERY zsh,
    // including non-interactive SSH) so PATH includes /usr/local/bin.
    let script = renderStandardScript()
    #require(
      script.contains("$GUEST_HOME/.zshenv"),
      "must plant ~/.zshenv for the guest user"
    )
    #require(
      script.contains("compass:path_helper"),
      "uses a sentinel string to make planting idempotent across reboots"
    )
    #require(
      script.contains("/usr/libexec/path_helper"),
      "must call path_helper so /etc/paths and /etc/paths.d apply"
    )
  }

  @Test
  func testBootstrapScriptSelfRemovesLaunchDaemonAndPasswordOnSuccess() {
    let script = renderStandardScript()
    #require(script.contains("rm -f \"$LAUNCH_DAEMON\""))
    #require(script.contains("rm -f \"$PASSWORD_FILE\""))
    #require(script.contains("touch \"$MARKER\""))
  }

  @Test
  func testBootstrapScriptSealsSudoersFragmentPermissions() {
    let script = renderStandardScript()
    #require(script.contains("chmod 0440 \"$SUDOERS_FRAGMENT\""))
    #require(script.contains("chown root:wheel \"$SUDOERS_FRAGMENT\""))
  }

  // MARK: - Sudoers fragment

  @Test
  func testSudoersFragmentGrantsPasswordlessSudoToGuestUser() {
    let fragment = SharedCompassVMHeadlessFirstBoot.renderSudoersFragment(guestUserName: "compass")
    #require(fragment.contains("compass ALL=(ALL) NOPASSWD: ALL"))
  }

  // MARK: - Payload composition

  @Test
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

    #require(payload.profile == profile)
    #require(payload.guestUserName == "compass")
    #require(payload.guestFullName == "Compass")
    #require(!payload.launchDaemonPlist.isEmpty)
    #require(payload.bootstrapScript.contains("set -euo pipefail"))
    #require(payload.sudoersFragment.contains("NOPASSWD"))
    #require(payload.stagedPublicKey == inputs.publicKeyData)
    #require(payload.stagedPassword == "hunter2-not-really")
    #require(payload.guestAgentBinary == agentBytes)
    let plistString = String(decoding: payload.guestAgentLaunchDaemonPlist, as: UTF8.self)
    #require(
      plistString.contains(profile.guestAgentBinaryGuestPath),
      "LaunchDaemon plist must reference the planted binary path: \(plistString)"
    )
    #require(
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

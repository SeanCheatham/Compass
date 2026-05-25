import Foundation

/// Headless first-boot bootstrap for the Compass shared VM.
///
/// Replaces the interactive Setup Assistant click-through by planting four
/// classes of files into the freshly-installed guest disk **before** the VM
/// boots for the first time:
///
///   1. `/private/var/db/.AppleSetupDone` — marker that skips Setup
///      Assistant entirely.
///   2. `/Library/LaunchDaemons/com.seancheatham.Compass.firstboot.plist` —
///      one-shot LaunchDaemon (root) that fires at boot and runs the
///      bootstrap script.
///   3. `/usr/local/libexec/compass-firstboot.sh` — the bootstrap script.
///      Creates the `compass` admin user (with the host-generated password),
///      authorises the Compass SSH key, enables Remote Login, creates the
///      guest-local worktrees root, then removes itself.
///   4. `/etc/sudoers.d/compass` — `compass ALL=(ALL) NOPASSWD: ALL` so agents
///      can run privileged steps without prompting.
///
/// One supporting payload file travels alongside under `/Users/Shared/compass-firstboot/`:
/// the SSH public key copied from the host. It lands in a world-readable
/// location because the planter cannot easily chown into root-only
/// directories before first boot; the bootstrap script re-permissions it as
/// it runs.
///
/// Because Setup Assistant internals are an Apple implementation detail that
/// can shift across major macOS releases, the per-version specifics
/// (filesystem paths, dscl semantics, plist key set) live in
/// `Profile` values registered against macOS major versions in
/// `Registry.profiles`. `Registry.profile(forBuildVersion:)` parses the build
/// string returned by `VZMacOSRestoreImage.buildVersion` and returns the
/// matching profile, or `nil` if Compass has not been taught about that major.
enum SharedCompassVMHeadlessFirstBoot {
  /// LaunchDaemon plist label. Must match the plist filename minus the extension.
  static let launchDaemonLabel = "com.seancheatham.Compass.firstboot"

  /// LaunchDaemon plist label for the in-guest Compass agent.
  ///
  /// Earlier prototypes ran this as a LaunchAgent under the auto-logged-in
  /// `compass` user, betting that the GUI session's TCC profile would
  /// grant access to the VirtioFS share. Live testing on macOS 26.x
  /// disproved that bet (AppleVirtIOFS is TCC-blocked from every process,
  /// LaunchAgent included), so Phase 10 dropped VirtioFS entirely and
  /// the agent now operates on a guest-local copy of the worktree — no
  /// TCC-protected resources involved. With no GUI-session prerequisite
  /// left, switching to a LaunchDaemon (which loads at boot, no user
  /// session required) sidesteps the macOS-26 auto-login regression
  /// where `SecurityAgent` logs `no autologin because no conditions for
  /// autologin were met` even with kcpassword + autoLoginUser planted.
  /// `UserName=compass` keeps the daemon process running as the compass
  /// user so the worktree files it writes have the expected ownership.
  static let guestAgentLaunchDaemonLabel = "com.seancheatham.Compass.guest-agent"

  /// LaunchDaemon label for the persistent auto-login helper. Runs at
  /// every boot (not one-shot) to re-apply `/etc/kcpassword` and nudge
  /// `loginwindow` once SecurityAgent is ready — macOS 26 often logs
  /// `no autologin because no conditions for autologin were met` when
  /// auto-login is planted only during the first-boot race.
  static let autoLoginLaunchDaemonLabel = "com.seancheatham.Compass.autologin"

  /// Sentinel the bootstrap script writes to the host-readable status file
  /// once it has completed all idempotent steps. Mostly informational —
  /// host-side readiness keys off the SSH probe, not the status file.
  static let bootstrapCompletionMarker = "compass-firstboot-complete"

  // MARK: - Profile

  /// Per-macOS-version configuration for the headless first-boot planting.
  /// Currently all known macOS majors share the same layout, but the
  /// `Profile` struct exists so that a future macOS that moves
  /// `.AppleSetupDone` or changes the `sysadminctl` flag set can ship a
  /// version-specific profile without touching the planter.
  struct Profile: Equatable {
    /// macOS major (e.g. `15` for Sequoia, `16` for the next major).
    var macOSMajor: Int

    /// Absolute guest path of the Setup Assistant marker. Empty file,
    /// root:wheel, mode 0644.
    var appleSetupDoneGuestPath: String

    /// Absolute guest path of the LaunchDaemon plist. Must live inside
    /// `/Library/LaunchDaemons/` and be owned root:wheel mode 0644.
    var launchDaemonGuestPath: String

    /// Absolute guest path of the bootstrap shell script. root:wheel 0755.
    var bootstrapScriptGuestPath: String

    /// Absolute guest path of the sudoers fragment. root:wheel 0440 (sudo
    /// refuses to load fragments that are group- or world-writable).
    var sudoersFragmentGuestPath: String

    /// Absolute guest path of the staging directory that holds the SSH
    /// public key and password file. The planter writes here without
    /// elevation (host user can chown into `/Users/Shared/` without
    /// root); the bootstrap script re-permissions to root:wheel 0700 as
    /// it runs.
    var stagingDirectoryGuestPath: String

    /// Filename (not path) of the SSH public key inside the staging directory.
    var stagedPublicKeyName: String

    /// Filename (not path) of the password file used to seed
    /// `sysadminctl -password`. Removed by the script on first boot.
    var stagedPasswordFileName: String

    /// Bootstrap completion marker filename inside the staging directory.
    /// The script touches this once it has finished; useful for
    /// post-mortem diagnostics from the host side.
    var completionMarkerName: String

    /// Where the planted CompassGuestAgent binary lives on the guest.
    /// `/usr/local/libexec` is the conventional macOS location for
    /// service-helper executables. root:wheel mode 0755.
    var guestAgentBinaryGuestPath: String

    /// Where the LaunchDaemon plist for the guest agent lives on the
    /// guest. `/Library/LaunchDaemons` is loaded by launchd at boot in
    /// the system context — no user session required, which dodges the
    /// macOS-26 auto-login regression observed live. The daemon process
    /// drops to UID 501 (the compass user) via `UserName` in the plist
    /// so the worktree files it writes have the right ownership.
    /// root:wheel mode 0644.
    var guestAgentLaunchDaemonGuestPath: String

    /// Where the persistent auto-login helper script lives on the guest.
    /// root:wheel mode 0755.
    var autoLoginScriptGuestPath: String

    /// LaunchDaemon plist for the auto-login helper. Loaded at every
    /// boot until the console reaches a logged-in desktop session.
    /// root:wheel mode 0644.
    var autoLoginLaunchDaemonGuestPath: String

    /// Root-only file holding the guest console password so the
    /// auto-login helper can re-apply `/etc/kcpassword` on every boot
    /// after first-boot deletes the staging copy. root:wheel mode 0600.
    var consolePasswordGuestPath: String

    /// Default profile shared across recent macOS majors. Override fields
    /// per-version in the registry when Apple moves things around.
    static func standard(macOSMajor: Int) -> Profile {
      Profile(
        macOSMajor: macOSMajor,
        appleSetupDoneGuestPath: "/private/var/db/.AppleSetupDone",
        launchDaemonGuestPath: "/Library/LaunchDaemons/\(launchDaemonLabel).plist",
        bootstrapScriptGuestPath: "/usr/local/libexec/compass-firstboot.sh",
        // Uses /private/etc form because that path string works as
        // both the host-mount-relative destination (the Data volume
        // exposes /private/etc, not /etc — the /etc symlink lives on
        // the read-only System volume) and the guest-runtime
        // reference (sudo follows /etc -> /private/etc at runtime).
        sudoersFragmentGuestPath: "/private/etc/sudoers.d/compass",
        stagingDirectoryGuestPath: "/Users/Shared/compass-firstboot",
        stagedPublicKeyName: "id_ed25519.pub",
        stagedPasswordFileName: "user.password",
        completionMarkerName: bootstrapCompletionMarker,
        guestAgentBinaryGuestPath: "/usr/local/libexec/compass-guest-agent",
        guestAgentLaunchDaemonGuestPath:
          "/Library/LaunchDaemons/\(guestAgentLaunchDaemonLabel).plist",
        autoLoginScriptGuestPath: "/usr/local/libexec/compass-autologin.sh",
        autoLoginLaunchDaemonGuestPath:
          "/Library/LaunchDaemons/\(autoLoginLaunchDaemonLabel).plist",
        consolePasswordGuestPath: "/var/root/.compass-console-password"
      )
    }
  }

  // MARK: - Registry

  /// Per-major-version profile catalogue. Add a row here whenever Compass
  /// is extended to support a new macOS major; if Apple changes one of the
  /// paths above for that release, override only the affected field.
  enum Registry {
    /// Lowest macOS major Compass's headless first-boot will attempt.
    /// Below this we have no validation and refuse to plant.
    static let minimumSupportedMajor = 15

    /// Highest macOS major Compass has been tested against. Newer guests
    /// fall through to the latest known profile with a logged warning —
    /// updating this constant after testing a new major is the
    /// per-release maintenance step the README's decision log calls out.
    static let latestKnownMajor = 26

    /// Static catalogue. Currently every supported major uses the
    /// standard profile; the registry exists so that diverging a single
    /// version is a one-line change rather than a refactor.
    static func profile(forMacOSMajor major: Int) -> Profile? {
      guard major >= minimumSupportedMajor else { return nil }
      let clamped = min(major, latestKnownMajor)
      return .standard(macOSMajor: clamped)
    }

    /// Parses the build string supplied by `VZMacOSRestoreImage.buildVersion`
    /// (e.g. `24A335`, `26B71`) into a macOS major. Apple's build numbering
    /// uses a two-digit Darwin-major prefix; macOS major is Darwin-major
    /// minus 9 (Darwin 24 -> macOS 15, Darwin 25 -> macOS 16, ...).
    /// Returns nil if the prefix cannot be parsed.
    static func macOSMajor(forBuildVersion buildVersion: String) -> Int? {
      let trimmed = buildVersion.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      var digits = ""
      for character in trimmed {
        if character.isNumber {
          digits.append(character)
        } else {
          break
        }
      }
      guard let darwinMajor = Int(digits) else { return nil }
      let macOSMajor = darwinMajor - 9
      guard macOSMajor >= minimumSupportedMajor else { return nil }
      return macOSMajor
    }

    /// Convenience: build version -> profile in one call. Returns nil if
    /// the build cannot be parsed or the major is below the supported floor.
    static func profile(forBuildVersion buildVersion: String) -> Profile? {
      guard let major = macOSMajor(forBuildVersion: buildVersion) else {
        return nil
      }
      return profile(forMacOSMajor: major)
    }
  }

  // MARK: - Rendered content

  /// Captures the rendered first-boot payload for a (profile, guest-user,
  /// public-key) tuple. The planter writes these byte blobs verbatim into
  /// the mounted guest volume.
  struct Payload: Equatable {
    var profile: Profile
    var guestUserName: String
    var guestFullName: String
    var launchDaemonPlist: Data
    var bootstrapScript: String
    var sudoersFragment: String
    var stagedPublicKey: Data
    var stagedPassword: String
    /// Raw bytes of the CompassGuestAgent executable. Planter copies
    /// these verbatim to `profile.guestAgentBinaryGuestPath`.
    var guestAgentBinary: Data
    /// LaunchDaemon plist loaded by launchd at boot — starts the guest
    /// agent under the compass user via `UserName`, no GUI session
    /// required.
    var guestAgentLaunchDaemonPlist: Data
    /// Persistent auto-login helper script + LaunchDaemon. Re-applies
    /// `/etc/kcpassword` on every boot so the headed Sandbox console
    /// reaches a desktop even when macOS 26 rejects the first-boot
    /// timing.
    var autoLoginScript: String
    var autoLoginLaunchDaemonPlist: Data
  }

  /// Inputs the planter assembles before rendering a `Payload`.
  struct RenderInputs: Equatable {
    var profile: Profile
    var guestUserName: String
    var guestFullName: String
    var publicKeyData: Data
    var generatedPassword: String
    /// Bytes of the CompassGuestAgent executable to ship. The caller
    /// (SharedCompassVM) reads this from the host bundle just before
    /// kicking off `plant`.
    var guestAgentBinary: Data

    static func makeStandard(
      profile: Profile,
      publicKeyData: Data,
      generatedPassword: String,
      guestAgentBinary: Data,
      guestUserName: String = SharedCompassVMBundle.State.defaultGuestUserName
    ) -> RenderInputs {
      RenderInputs(
        profile: profile,
        guestUserName: guestUserName,
        guestFullName: "Compass",
        publicKeyData: publicKeyData,
        generatedPassword: generatedPassword,
        guestAgentBinary: guestAgentBinary
      )
    }
  }

  /// Renders the full payload. Pure — no filesystem access — so unit tests
  /// can lock down every byte the planter is about to write.
  static func renderPayload(from inputs: RenderInputs) -> Payload {
    let plist = renderLaunchDaemonPlist(profile: inputs.profile)
    let script = renderBootstrapScript(inputs: inputs)
    let sudoers = renderSudoersFragment(guestUserName: inputs.guestUserName)
    let guestAgentPlist = renderGuestAgentLaunchDaemonPlist(profile: inputs.profile)
    let autoLoginScript = renderAutoLoginScript(profile: inputs.profile, guestUserName: inputs.guestUserName)
    let autoLoginPlist = renderAutoLoginLaunchDaemonPlist(profile: inputs.profile)
    return Payload(
      profile: inputs.profile,
      guestUserName: inputs.guestUserName,
      guestFullName: inputs.guestFullName,
      launchDaemonPlist: Data(plist.utf8),
      bootstrapScript: script,
      sudoersFragment: sudoers,
      stagedPublicKey: inputs.publicKeyData,
      stagedPassword: inputs.generatedPassword,
      guestAgentBinary: inputs.guestAgentBinary,
      guestAgentLaunchDaemonPlist: Data(guestAgentPlist.utf8),
      autoLoginScript: autoLoginScript,
      autoLoginLaunchDaemonPlist: Data(autoLoginPlist.utf8)
    )
  }

  /// LaunchDaemon plist for the in-guest Compass agent. Loaded by
  /// launchd at boot in the system context (no user session required),
  /// then drops to the compass user via `UserName`. The binary listens
  /// on AF_VSOCK at the canonical Compass port. `KeepAlive=true` so a
  /// crashed agent comes back automatically — the host treats vsock
  /// unavailability as a hard failure, so leaving a dead agent isn't
  /// acceptable.
  static func renderGuestAgentLaunchDaemonPlist(profile: Profile) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(guestAgentLaunchDaemonLabel)</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(profile.guestAgentBinaryGuestPath)</string>
        </array>
        <key>UserName</key>
        <string>\(SharedCompassVMBundle.State.defaultGuestUserName)</string>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardOutPath</key>
        <string>/tmp/compass-guest-agent.log</string>
        <key>StandardErrorPath</key>
        <string>/tmp/compass-guest-agent.log</string>
    </dict>
    </plist>
    """
  }

  /// Shell snippet that XOR-encodes `$PASSWORD` into `/etc/kcpassword`.
  /// `$PASSWORD` must be set in the caller's environment.
  static func shellWriteKcpasswordFromPasswordEnv() -> String {
    """
      PASSWORD="$PASSWORD" /usr/bin/perl -e '
      my $key = pack("H*", "7D895223D2BCDDEAA3B91F");
      my $pw = $ENV{PASSWORD};
      my $pad_len = 12 - (length($pw) % 12);
      $pw .= "\\x00" x $pad_len;
      my $out = "";
      for (my $i = 0; $i < length($pw); $i++) {
          $out .= chr(ord(substr($pw, $i, 1)) ^ ord(substr($key, $i % 11, 1)));
      }
      print $out;
      ' > /etc/kcpassword
      /usr/sbin/chown root:wheel /etc/kcpassword
      /bin/chmod 600 /etc/kcpassword
    """
  }

  /// Shell snippet that sets `autoLoginUser` in loginwindow preferences.
  static func shellApplyAutoLoginUserPreference() -> String {
    """
      /usr/bin/defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser -string "$GUEST_USER" 2>&1 || true
      /usr/sbin/chown root:wheel /Library/Preferences/com.apple.loginwindow.plist 2>&1 || true
      /bin/chmod 644 /Library/Preferences/com.apple.loginwindow.plist 2>&1 || true
    """
  }

  /// Persistent helper invoked at every boot. Waits for the console
  /// password file first-boot publishes, verifies credentials, re-applies
  /// auto-login, then restarts `loginwindow` if the console is still at
  /// the login screen.
  static func renderAutoLoginScript(profile: Profile, guestUserName: String) -> String {
    let consolePasswordPath = profile.consolePasswordGuestPath
    return """
      #!/bin/bash
      #
      # Compass auto-login helper. Planted before first boot; runs at every
      # boot via \(autoLoginLaunchDaemonLabel). Re-applies /etc/kcpassword
      # once the guest user and console password file exist.
      #
      set -euo pipefail
      umask 022

      GUEST_USER="\(guestUserName)"
      PASSWORD_FILE="\(consolePasswordPath)"
      LOG="/var/log/compass-autologin.log"

      exec >> "$LOG" 2>&1
      echo "----"
      echo "[compass-autologin] $(date -u '+%Y-%m-%dT%H:%M:%SZ') starting"

      ready=0
      for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
               21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 \
               41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 \
               61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 \
               81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 \
               101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120; do
        if [ -f "$PASSWORD_FILE" ] \
           && /usr/bin/dscl . -read "/Users/$GUEST_USER" UniqueID >/dev/null 2>&1; then
          ready=1
          break
        fi
        sleep 1
      done
      if [ "$ready" -ne 1 ]; then
        echo "[compass-autologin] guest user or password file not ready; exiting"
        exit 0
      fi

      PASSWORD="$(cat "$PASSWORD_FILE")"
      if ! /usr/bin/dscl . -authonly "$GUEST_USER" "$PASSWORD" >/dev/null 2>&1; then
        echo "[compass-autologin] dscl authonly failed; exiting"
        exit 1
      fi

      echo "[compass-autologin] applying auto-login for $GUEST_USER"
      \(shellWriteKcpasswordFromPasswordEnv())
      \(shellApplyAutoLoginUserPreference())

      console_owner="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || echo loginwindow)"
      echo "[compass-autologin] /dev/console owner: $console_owner"
      if [ "$console_owner" = "loginwindow" ] || [ "$console_owner" = "_unknown" ]; then
        echo "[compass-autologin] waiting for SecurityAgent before restarting loginwindow"
        sleep 5
        /usr/bin/killall loginwindow 2>&1 || true
      else
        echo "[compass-autologin] console already has session for $console_owner"
      fi
      echo "[compass-autologin] done."
      """
  }

  static func renderAutoLoginLaunchDaemonPlist(profile: Profile) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(autoLoginLaunchDaemonLabel)</string>
        <key>ProgramArguments</key>
        <array>
            <string>/bin/bash</string>
            <string>\(profile.autoLoginScriptGuestPath)</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <false/>
        <key>StandardOutPath</key>
        <string>/var/log/compass-autologin.log</string>
        <key>StandardErrorPath</key>
        <string>/var/log/compass-autologin.log</string>
    </dict>
    </plist>
    """
  }

  // MARK: - Content renderers

  /// Renders the LaunchDaemon plist content. Boots once at system start,
  /// runs the bootstrap script with `/bin/bash`, and is removed by the
  /// script itself on success so it never fires again.
  static func renderLaunchDaemonPlist(profile: Profile) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(launchDaemonLabel)</string>
        <key>ProgramArguments</key>
        <array>
            <string>/bin/bash</string>
            <string>\(profile.bootstrapScriptGuestPath)</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <false/>
        <key>LaunchOnlyOnce</key>
        <true/>
        <key>StandardOutPath</key>
        <string>\(profile.stagingDirectoryGuestPath)/firstboot.log</string>
        <key>StandardErrorPath</key>
        <string>\(profile.stagingDirectoryGuestPath)/firstboot.log</string>
    </dict>
    </plist>
    """
  }

  /// Renders the bootstrap script. Idempotent — re-running is a no-op
  /// after the first successful run because each step short-circuits on
  /// "already done" probes.
  static func renderBootstrapScript(inputs: RenderInputs) -> String {
    let stagingDir = inputs.profile.stagingDirectoryGuestPath
    let pubKeyPath = "\(stagingDir)/\(inputs.profile.stagedPublicKeyName)"
    let passwordPath = "\(stagingDir)/\(inputs.profile.stagedPasswordFileName)"
    let markerPath = "\(stagingDir)/\(inputs.profile.completionMarkerName)"
    let sudoersPath = inputs.profile.sudoersFragmentGuestPath
    let launchDaemonPath = inputs.profile.launchDaemonGuestPath
    let scriptPath = inputs.profile.bootstrapScriptGuestPath

    return """
      #!/bin/bash
      #
      # Compass headless first-boot bootstrap. Planted by the host onto the
      # freshly-installed guest disk before first boot; invoked by the
      # \(launchDaemonLabel) LaunchDaemon at boot. Idempotent.
      #
      set -euo pipefail
      umask 022

      STAGING="\(stagingDir)"
      PUBKEY="\(pubKeyPath)"
      PASSWORD_FILE="\(passwordPath)"
      MARKER="\(markerPath)"
      SUDOERS_FRAGMENT="\(sudoersPath)"
      LAUNCH_DAEMON="\(launchDaemonPath)"
      SCRIPT_PATH="\(scriptPath)"

      GUEST_USER="\(inputs.guestUserName)"
      GUEST_FULL_NAME="\(inputs.guestFullName)"

      exec >> "$STAGING/firstboot.log" 2>&1
      echo "----"
      echo "[compass-firstboot] $(date -u '+%Y-%m-%dT%H:%M:%SZ') starting"

      if [ -f "$MARKER" ]; then
        echo "[compass-firstboot] marker exists; nothing to do."
        exit 0
      fi

      if [ ! -f "$PASSWORD_FILE" ]; then
        echo "[compass-firstboot] FATAL: password file missing at $PASSWORD_FILE" >&2
        exit 1
      fi
      PASSWORD="$(cat "$PASSWORD_FILE")"

      echo "[compass-firstboot] [1/6] Creating user $GUEST_USER via dscl"

      # On a first-boot system with `.AppleSetupDone` bypassed,
      # opendirectoryd may not have fully initialized the local
      # Default node when this LaunchDaemon fires. dscl operations
      # issued before then silently exit 0 yet never persist to
      # /var/db/dslocal — leaving the guest with no local user
      # records and the login window stuck on an empty user list.
      # Wait until dscl can see the Default node and enumerate
      # /Users before attempting any writes.
      echo "  Waiting for opendirectoryd readiness (max 30s)..."
      opendirectoryd_ready=0
      for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
        if /usr/bin/dscl . -list / >/dev/null 2>&1 \
           && /usr/bin/dscl . -list /Users >/dev/null 2>&1; then
          opendirectoryd_ready=1
          echo "  opendirectoryd ready after ${i}s"
          break
        fi
        sleep 1
      done
      if [ "$opendirectoryd_ready" -ne 1 ]; then
        echo "  opendirectoryd not responsive after 30s; bootstrapping explicitly"
        /bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.opendirectoryd.plist 2>&1 || true
        /bin/launchctl kickstart -k system/com.apple.opendirectoryd 2>&1 || true
        sleep 5
      fi

      if /usr/bin/dscl . -read "/Users/$GUEST_USER" UniqueID >/dev/null 2>&1; then
        echo "  user already exists; skipping create"
      else
        # We deliberately avoid `sysadminctl -addUser` here. On Apple
        # Silicon, sysadminctl tries to set up a Secure Token for the
        # first admin via Keybag, which is not reachable from a
        # LaunchDaemon at first boot — it fails mid-record with
        # `### Error:-14120 ... DSRecord.m:418` (eDSReceiveFailed),
        # leaving the dslocal record half-initialized so LoginWindow
        # cannot see the user. We don't need Secure Token for our use
        # case (SSH + sudo; no FileVault), so we plant the
        # record directly via dscl and only set the admin group
        # membership separately.
        NEXT_UID=501
        while /usr/bin/dscl . -list /Users UniqueID 2>/dev/null | awk '{print $2}' | grep -qx "$NEXT_UID"; do
          NEXT_UID=$((NEXT_UID + 1))
        done
        echo "  Creating $GUEST_USER with UID $NEXT_UID"
        /usr/bin/dscl . -create "/Users/$GUEST_USER"
        /usr/bin/dscl . -create "/Users/$GUEST_USER" RealName "$GUEST_FULL_NAME"
        /usr/bin/dscl . -create "/Users/$GUEST_USER" UniqueID "$NEXT_UID"
        /usr/bin/dscl . -create "/Users/$GUEST_USER" PrimaryGroupID 20
        /usr/bin/dscl . -create "/Users/$GUEST_USER" UserShell /bin/zsh
        /usr/bin/dscl . -create "/Users/$GUEST_USER" NFSHomeDirectory "/Users/$GUEST_USER"
        /usr/bin/dscl . -passwd "/Users/$GUEST_USER" "$PASSWORD"
        /usr/sbin/dseditgroup -o edit -a "$GUEST_USER" -t user admin

        # Verify the user actually persisted to disk, not just to
        # opendirectoryd's in-memory state. If opendirectoryd is in
        # a degraded mode (e.g. the on-disk Default node never got
        # initialized) dscl returns 0 but writes nothing — the
        # earlier headless-firstboot bug that left the guest with
        # no users on disk despite the script reporting success.
        echo "  Verifying dscl persisted user to disk..."
        if ! /usr/bin/dscl . -read "/Users/$GUEST_USER" UniqueID >/dev/null 2>&1; then
          echo "  FATAL: dscl said create succeeded but read fails"
          echo "  dslocal /Users dump:"
          /usr/bin/dscl . -list /Users 2>&1 || true
          exit 1
        fi
        DSLOCAL_PLIST="/var/db/dslocal/nodes/Default/users/$GUEST_USER.plist"
        # Give opendirectoryd a beat to flush before checking disk.
        sleep 1
        if [ ! -f "$DSLOCAL_PLIST" ]; then
          echo "  $DSLOCAL_PLIST missing; restarting opendirectoryd to force flush"
          /bin/launchctl kickstart -k system/com.apple.opendirectoryd 2>&1 || true
          sleep 3
        fi
        if [ ! -f "$DSLOCAL_PLIST" ]; then
          echo "  FATAL: dslocal plist never appeared on disk"
          echo "  /var/db/dslocal/nodes/Default/users:"
          ls -la /var/db/dslocal/nodes/Default/users/ 2>&1 || echo "  (directory missing)"
          echo "  /var/db/dslocal/nodes/Default:"
          ls -la /var/db/dslocal/nodes/Default/ 2>&1 || echo "  (directory missing)"
          echo "  /var/db/dslocal:"
          ls -la /var/db/dslocal/ 2>&1 || echo "  (directory missing)"
          echo "  launchctl opendirectoryd status:"
          /bin/launchctl print system/com.apple.opendirectoryd 2>&1 | head -40 || true
          exit 1
        fi
        echo "  Confirmed: $DSLOCAL_PLIST exists on disk"

        # createhomedir does not always succeed cleanly on first boot
        # (the user directory in /Users may already exist as a stub).
        # Fall back to mkdir + chown so the home tree is at least
        # owned correctly even when createhomedir bails. Capture
        # output to the log instead of silencing it — useful for
        # diagnosing future failures.
        if ! /usr/sbin/createhomedir -c -u "$GUEST_USER" 2>&1; then
          echo "  createhomedir failed; falling back to mkdir + chown"
          mkdir -p "/Users/$GUEST_USER"
          chown "$GUEST_USER:staff" "/Users/$GUEST_USER"
        fi
      fi

      # Ventura+ macOS gates SSH on membership in
      # com.apple.access_ssh — admin membership alone is not enough.
      # The group is auto-created the first time Remote Login is
      # turned on in System Settings; from a LaunchDaemon we cannot
      # rely on that, so we create-or-edit the group and add the
      # guest user. Belt-and-suspenders also adds the user to
      # com.apple.access_ssh-disabled removal (no-op if absent).
      echo "  Granting $GUEST_USER SSH access (com.apple.access_ssh)"
      /usr/sbin/dseditgroup -o create -q com.apple.access_ssh 2>&1 || true
      /usr/sbin/dseditgroup -o edit -a "$GUEST_USER" -t user com.apple.access_ssh 2>&1 \
        || echo "  (access group add failed; SSH may still work if 'All users' policy is in effect)"

      # Flush dscache and HUP opendirectoryd so loginwindow / sshd
      # observe the freshly-added user and group membership without
      # waiting for cache TTLs to expire.
      /usr/bin/dscacheutil -flushcache 2>&1 || true
      /usr/bin/killall -HUP opendirectoryd 2>&1 || true

      # Auto-login the guest user so the VM view shows a desktop
      # instead of an empty username/password prompt. Compass drives
      # the guest entirely through SSH, so the graphical login window
      # is purely cosmetic — but seeing it boot to a desktop is a
      # cleaner first impression and means VNC-style takeover (a
      # future Compass feature) doesn't need to deal with auth first.
      #
      # macOS auto-login needs two artifacts:
      #   1. /etc/kcpassword: the user's password XOR-obfuscated with
      #      Apple's well-known 11-byte key, NUL-padded to a multiple
      #      of 12 bytes. Mode 0600 root:wheel.
      #   2. autoLoginUser in /Library/Preferences/com.apple.loginwindow.
      #
      # Persist the password at \(inputs.profile.consolePasswordGuestPath)
      # so the compass-autologin LaunchDaemon can re-apply kcpassword on
      # every boot — macOS 26 often rejects auto-login when it is planted
      # only during the first-boot race with loginwindow already up.
      #
      # Threat-model note: kcpassword is obfuscation, not encryption.
      # An attacker with root inside the guest can recover the password.
      # That's fine here because (a) the password is randomly generated
      # per-VM and stored only in the host's Keychain, (b) compass
      # already has NOPASSWD sudo, so root-in-guest already implies
      # password-equivalent access, and (c) the guest is a sandbox
      # that runs untrusted agent-generated code — by design.
      echo "  Setting up auto-login for $GUEST_USER"
      if ! /usr/bin/dscl . -authonly "$GUEST_USER" "$PASSWORD" >/dev/null 2>&1; then
        echo "  FATAL: dscl authonly failed before planting auto-login"
        exit 1
      fi
      CONSOLE_PASSWORD_FILE="\(inputs.profile.consolePasswordGuestPath)"
      umask 077
      printf '%s' "$PASSWORD" > "$CONSOLE_PASSWORD_FILE"
      /usr/sbin/chown root:wheel "$CONSOLE_PASSWORD_FILE"
      /bin/chmod 600 "$CONSOLE_PASSWORD_FILE"
      umask 022
      \(shellWriteKcpasswordFromPasswordEnv())
      \(shellApplyAutoLoginUserPreference())
      echo "  autoLoginUser preference: $(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>&1 || true)"
      echo "  kcpassword bytes: $(/usr/bin/wc -c < /etc/kcpassword 2>&1 || true)"
      # loginwindow caches the auto-login config at startup. Give
      # SecurityAgent a beat to finish init, then restart loginwindow
      # so the change takes effect on this boot (not just the next one).
      echo "  waiting for SecurityAgent before restarting loginwindow"
      sleep 5
      /usr/bin/killall loginwindow 2>&1 || true

      echo "[compass-firstboot] [2/6] Authorising Compass SSH public key"
      GUEST_HOME="/Users/$GUEST_USER"
      mkdir -p "$GUEST_HOME/.ssh"
      chmod 700 "$GUEST_HOME/.ssh"
      touch "$GUEST_HOME/.ssh/authorized_keys"
      if ! grep -qxFf "$PUBKEY" "$GUEST_HOME/.ssh/authorized_keys"; then
        cat "$PUBKEY" >> "$GUEST_HOME/.ssh/authorized_keys"
      fi
      chmod 600 "$GUEST_HOME/.ssh/authorized_keys"
      chown -R "$GUEST_USER":staff "$GUEST_HOME/.ssh"

      echo "[compass-firstboot] [3/6] Enabling Remote Login (sshd)"
      # `systemsetup -setremotelogin on` blocks on an interactive
      # yes/no prompt; with no stdin in a LaunchDaemon it hangs and
      # never returns. Pipe `yes` in to bypass. On modern macOS the
      # command often refuses outright (privacy / MDM) so we also
      # drive launchctl directly. On modern macOS the path is
      # `launchctl enable` + `launchctl bootstrap system <plist>`,
      # then `kickstart -k` to force-start. All steps are wrapped in
      # `|| true` so a no-op on one path doesn't abort the script —
      # we verify success below by probing the listening port.
      echo "yes" | /usr/sbin/systemsetup -setremotelogin on >/dev/null 2>&1 || true
      /bin/launchctl enable system/com.openssh.sshd 2>&1 || true
      /bin/launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>&1 || true
      /bin/launchctl kickstart -k system/com.openssh.sshd 2>&1 || true
      # Verify sshd is actually listening before declaring success —
      # otherwise the host's post-boot SSH probe times out and we
      # land at `Finishing macOS setup` indefinitely.
      sshd_up=0
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        if /usr/bin/nc -z -G 1 127.0.0.1 22 >/dev/null 2>&1; then
          sshd_up=1
          break
        fi
        sleep 1
      done
      if [ "$sshd_up" -eq 1 ]; then
        echo "  sshd is listening on 127.0.0.1:22"
      else
        echo "  WARNING: sshd did not come up within 10s; host SSH probe will fail"
      fi

      # Diagnostic dump so the next dump-firstboot-log run shows
      # everything we'd need to debug a failing host-side SSH probe
      # without rebooting the VM or shelling in by other means.
      echo "  --- sshd diagnostic snapshot ---"
      echo "  systemsetup remotelogin: $(/usr/sbin/systemsetup -getremotelogin 2>&1 || true)"
      echo "  $GUEST_USER in admin?           $(/usr/sbin/dseditgroup -o checkmember -m \"$GUEST_USER\" admin 2>&1 || true)"
      echo "  $GUEST_USER in access_ssh?      $(/usr/sbin/dseditgroup -o checkmember -m \"$GUEST_USER\" com.apple.access_ssh 2>&1 || true)"
      echo "  $GUEST_USER UniqueID resolves:  $(/usr/bin/dscl . -read \"/Users/$GUEST_USER\" UniqueID 2>&1 || true)"
      echo "  authorized_keys listing:"
      /bin/ls -la "$GUEST_HOME/.ssh/authorized_keys" 2>&1 || true
      echo "  authorized_keys first line:"
      /usr/bin/head -1 "$GUEST_HOME/.ssh/authorized_keys" 2>&1 || true
      echo "  sshd_config auth/access lines:"
      /usr/bin/grep -E '^(PubkeyAuthentication|PasswordAuthentication|PermitRootLogin|AllowUsers|AllowGroups|Match)' /etc/ssh/sshd_config 2>&1 || true
      echo "  netstat sshd listeners:"
      /usr/sbin/netstat -an -p tcp 2>&1 | /usr/bin/grep '\\.22 ' || true
      echo "  primary interface address:"
      /sbin/ifconfig en0 2>&1 | /usr/bin/grep 'inet ' || true
      echo "  --- end sshd snapshot ---"

      echo "[compass-firstboot] [4/6] Creating guest-local worktrees root"
      # macOS guests TCC-block AppleVirtIOFS reads from every process —
      # including LaunchAgents inside the GUI session and even root via
      # LaunchDaemon — so Compass abandoned the VirtioFS share and now
      # keeps each iteration's worktree under the compass user's home.
      # The host streams worktree contents in/out via vsock-tunneled tar
      # at iteration boundaries; see SharedCompassVMWorktreeSync.
      WORKTREES_ROOT="$GUEST_HOME/Compass/Worktrees"
      mkdir -p "$WORKTREES_ROOT"
      chown -R "$GUEST_USER":staff "$GUEST_HOME/Compass"

      # macOS sshd runs commands via the user's login shell in
      # NON-interactive, NON-login mode (e.g. `zsh -c "command"`).
      # That path skips `/etc/zprofile`, which is where path_helper
      # — and therefore `/usr/local/bin` — would normally get onto
      # PATH. Plant a `~/.zshenv`, which IS sourced for every zsh
      # invocation including non-interactive ones, so PATH is set
      # up consistently for SSH commands and interactive logins.
      echo "[compass-firstboot] [5/6] Planting ~/.zshenv with path_helper for $GUEST_USER"
      ZSHENV="$GUEST_HOME/.zshenv"
      # Single-quoted echo lines so `$(...)` and `$PATH` reach the
      # file literally (to be evaluated by zsh when sourced), rather
      # than getting expanded here at plant time. The `compass:path_helper`
      # sentinel makes the planting idempotent across reboots.
      if [ ! -f "$ZSHENV" ] || ! /usr/bin/grep -q "compass:path_helper" "$ZSHENV" 2>/dev/null; then
        {
          echo '# compass:path_helper — planted by Compass headless first-boot.'
          echo '# Without this, non-interactive SSH commands (`ssh user@host command`)'
          echo '# run with PATH=/usr/bin:/bin:/usr/sbin:/sbin and cannot find /usr/local/bin'
          echo '# binaries (brew-installed tools, etc.).'
          echo 'if [ -x /usr/libexec/path_helper ]; then'
          echo '  eval "$(/usr/libexec/path_helper -s)"'
          echo 'else'
          echo '  export PATH="/usr/local/bin:$PATH"'
          echo 'fi'
        } >> "$ZSHENV"
        chown "$GUEST_USER:staff" "$ZSHENV"
        chmod 644 "$ZSHENV"
      fi

      echo "[compass-firstboot] [6/6] Sealing sudoers + cleaning up"
      chmod 0440 "$SUDOERS_FRAGMENT"
      chown root:wheel "$SUDOERS_FRAGMENT"
      # Self-disable: unload + delete the LaunchDaemon plist + script so we
      # never fire again. Note: /bin/launchctl bootout would be the modern
      # call, but the daemon is configured with LaunchOnlyOnce=true so
      # simply removing the plist suffices.
      rm -f "$LAUNCH_DAEMON"
      rm -f "$PASSWORD_FILE"
      touch "$MARKER"
      # Leave SCRIPT_PATH in place for forensic diagnostics; it's harmless
      # without the LaunchDaemon to invoke it. (Intentional — easier than
      # rm-the-script-while-running gymnastics.)
      echo "[compass-firstboot] done."
      """
  }

  /// Renders the sudoers fragment that grants the compass user passwordless
  /// sudo. Written with `Defaults:` line to disable the env_reset warning
  /// chatter agent shell calls would otherwise pipe through.
  static func renderSudoersFragment(guestUserName: String) -> String {
    """
    # Compass — passwordless sudo for the headless guest account.
    # Planted at first boot by /Library/LaunchDaemons/\(launchDaemonLabel).
    \(guestUserName) ALL=(ALL) NOPASSWD: ALL
    """
  }
}

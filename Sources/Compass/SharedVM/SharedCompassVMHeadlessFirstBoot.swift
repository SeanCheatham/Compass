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
///      authorises the Compass SSH key, enables Remote Login, installs codex,
///      symlinks `/opt/compass/workspaces`, then removes itself.
///   4. `/etc/sudoers.d/compass` — `compass ALL=(ALL) NOPASSWD: ALL` so codex
///      can run privileged steps without prompting.
///
/// Two supporting payload files travel alongside under `/Users/Shared/compass-firstboot/`:
/// the SSH public key and (optionally) the codex binary copied from the host.
/// Those land in a world-readable location because the planter cannot easily
/// chown into root-only directories before first boot; the bootstrap script
/// re-permissions them as it runs.
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
        /// public key, codex binary, and password file. The planter writes
        /// here without elevation (host user can chown into `/Users/Shared/`
        /// without root); the bootstrap script re-permissions to root:wheel
        /// 0700 as it runs.
        var stagingDirectoryGuestPath: String

        /// Filename (not path) of the SSH public key inside the staging directory.
        var stagedPublicKeyName: String

        /// Filename (not path) of the staged codex binary. Optional payload —
        /// the script reports a clear notice if absent.
        var stagedCodexBinaryName: String

        /// Filename (not path) of the password file used to seed
        /// `sysadminctl -password`. Removed by the script on first boot.
        var stagedPasswordFileName: String

        /// Bootstrap completion marker filename inside the staging directory.
        /// The script touches this once it has finished; useful for
        /// post-mortem diagnostics from the host side.
        var completionMarkerName: String

        /// Default profile shared across recent macOS majors. Override fields
        /// per-version in the registry when Apple moves things around.
        static func standard(macOSMajor: Int) -> Profile {
            Profile(
                macOSMajor: macOSMajor,
                appleSetupDoneGuestPath: "/private/var/db/.AppleSetupDone",
                launchDaemonGuestPath: "/Library/LaunchDaemons/\(launchDaemonLabel).plist",
                bootstrapScriptGuestPath: "/usr/local/libexec/compass-firstboot.sh",
                sudoersFragmentGuestPath: "/etc/sudoers.d/compass",
                stagingDirectoryGuestPath: "/Users/Shared/compass-firstboot",
                stagedPublicKeyName: "id_ed25519.pub",
                stagedCodexBinaryName: "codex",
                stagedPasswordFileName: "user.password",
                completionMarkerName: bootstrapCompletionMarker
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
    /// public-key, codex-availability) tuple. The planter writes these byte
    /// blobs verbatim into the mounted guest volume.
    struct Payload: Equatable {
        var profile: Profile
        var guestUserName: String
        var guestFullName: String
        var launchDaemonPlist: Data
        var bootstrapScript: String
        var sudoersFragment: String
        var stagedPublicKey: Data
        var stagedCodexBinary: Data?
        var stagedPassword: String
    }

    /// Inputs the planter assembles before rendering a `Payload`.
    struct RenderInputs: Equatable {
        var profile: Profile
        var guestUserName: String
        var guestFullName: String
        var publicKeyData: Data
        var codexBinaryData: Data?
        var generatedPassword: String

        static func makeStandard(
            profile: Profile,
            publicKeyData: Data,
            codexBinaryData: Data?,
            generatedPassword: String,
            guestUserName: String = SharedCompassVMBundle.State.defaultGuestUserName
        ) -> RenderInputs {
            RenderInputs(
                profile: profile,
                guestUserName: guestUserName,
                guestFullName: "Compass",
                publicKeyData: publicKeyData,
                codexBinaryData: codexBinaryData,
                generatedPassword: generatedPassword
            )
        }
    }

    /// Renders the full payload. Pure — no filesystem access — so unit tests
    /// can lock down every byte the planter is about to write.
    static func renderPayload(from inputs: RenderInputs) -> Payload {
        let plist = renderLaunchDaemonPlist(profile: inputs.profile)
        let script = renderBootstrapScript(inputs: inputs)
        let sudoers = renderSudoersFragment(guestUserName: inputs.guestUserName)
        return Payload(
            profile: inputs.profile,
            guestUserName: inputs.guestUserName,
            guestFullName: inputs.guestFullName,
            launchDaemonPlist: Data(plist.utf8),
            bootstrapScript: script,
            sudoersFragment: sudoers,
            stagedPublicKey: inputs.publicKeyData,
            stagedCodexBinary: inputs.codexBinaryData,
            stagedPassword: inputs.generatedPassword
        )
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
        let codexPath = "\(stagingDir)/\(inputs.profile.stagedCodexBinaryName)"
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
        CODEX="\(codexPath)"
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

        echo "[compass-firstboot] [1/6] Creating user $GUEST_USER"
        if /usr/bin/dscl . -read "/Users/$GUEST_USER" >/dev/null 2>&1; then
          echo "  user already exists; skipping create"
        else
          /usr/sbin/sysadminctl \\
            -addUser "$GUEST_USER" \\
            -fullName "$GUEST_FULL_NAME" \\
            -password "$PASSWORD" \\
            -admin
        fi

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
        /usr/sbin/systemsetup -setremotelogin on >/dev/null

        echo "[compass-firstboot] [4/6] Creating /opt/compass/workspaces symlink"
        SHARE_ROOT="/Volumes/My Shared Files/compass-workspaces"
        # Wait briefly for the VirtioFS share to mount. If it never appears the
        # symlink will be a broken dangling link, which is fine — codex
        # iterations on a guest without the share will fail loudly with a
        # clear ENOENT rather than silently succeeding in the wrong place.
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          if [ -d "$SHARE_ROOT" ]; then break; fi
          sleep 1
        done
        mkdir -p /opt/compass
        rm -f /opt/compass/workspaces
        ln -s "$SHARE_ROOT" /opt/compass/workspaces

        echo "[compass-firstboot] [5/6] Installing codex into /usr/local/bin"
        if [ -x "$CODEX" ]; then
          install -m 755 "$CODEX" /usr/local/bin/codex
        else
          echo "  codex binary not staged; install one inside the guest manually."
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
    /// chatter Codex would otherwise pipe through.
    static func renderSudoersFragment(guestUserName: String) -> String {
        """
        # Compass — passwordless sudo for the headless guest account.
        # Planted at first boot by /Library/LaunchDaemons/\(launchDaemonLabel).
        \(guestUserName) ALL=(ALL) NOPASSWD: ALL
        """
    }
}

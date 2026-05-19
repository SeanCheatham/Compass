import Foundation

/// Generator + manifest for the Compass first-boot bootstrap script.
///
/// The bootstrap script is the one-shot guest-side prep that bridges the
/// gap between Setup Assistant completion and Compass being able to ssh
/// into the guest. It runs once inside the guest's `Terminal.app` (so it
/// can call `sudo`) and does the four things that cannot be done from
/// host-side VZ alone:
///
///   1. Plants the Compass-owned Ed25519 public key into the guest user's
///      `~/.ssh/authorized_keys` (with correct 0600 / 0700 perms).
///   2. Creates the `/opt/compass/workspaces → /Volumes/My Shared Files/compass-workspaces`
///      symlink so `SharedVMRoute`'s guest paths resolve.
///   3. Enables Remote Login (`systemsetup -setremotelogin on`) so sshd
///      starts accepting connections.
///   4. Installs the host's codex binary into `/usr/local/bin/codex` so
///      remote codex execs work without further setup.
///
/// All four steps are idempotent — re-running the script is harmless.
///
/// Compass deposits the script (plus the public key and the codex binary)
/// inside the VirtioFS share at `.compass-firstboot/`. The user invokes
/// it from the guest with the exact command surfaced in
/// `SharedCompassVMFirstBootScript.guestRunCommand`.
enum SharedCompassVMFirstBootScript {
    /// Subdirectory under the workspaces root that holds all first-boot
    /// artifacts (script, public key, codex copy).
    static let directoryName = ".compass-firstboot"
    /// Filename of the generated bootstrap script.
    static let scriptName = "install.sh"
    /// Filename of the planted public key inside the firstboot directory.
    static let publicKeyName = "id_ed25519.pub"
    /// Filename of the planted codex binary inside the firstboot directory.
    static let codexBinaryName = "codex"
    /// VirtioFS tag used by the parent workspaces share. Mirrors
    /// `SharedCompassVMFileShare.defaultWorkspacesTag` but inlined here so
    /// the script generator stays decoupled from the share builder.
    static let workspacesShareTag = "compass-workspaces"

    /// Single bash command the user pastes into the guest's Terminal.
    /// Wraps the path in double quotes so the "My Shared Files" space
    /// isn't a word break.
    static let guestRunCommand =
        #"bash "/Volumes/My Shared Files/compass-workspaces/.compass-firstboot/install.sh""#

    /// Artifact paths Compass writes when materializing the script.
    struct Layout {
        var directoryURL: URL
        var scriptURL: URL
        var publicKeyURL: URL
        var codexBinaryURL: URL
    }

    static func layout(workspacesRootURL: URL) -> Layout {
        let dir = workspacesRootURL
            .appendingPathComponent(directoryName, isDirectory: true)
        return Layout(
            directoryURL: dir,
            scriptURL: dir.appendingPathComponent(scriptName, isDirectory: false),
            publicKeyURL: dir.appendingPathComponent(publicKeyName, isDirectory: false),
            codexBinaryURL: dir.appendingPathComponent(codexBinaryName, isDirectory: false)
        )
    }

    /// Materializes `.compass-firstboot/{install.sh, id_ed25519.pub, codex}`
    /// under `workspacesRootURL`. Idempotent — re-running overwrites the
    /// artifacts. Returns the layout so callers can sanity-check or surface
    /// the script path in the UI.
    ///
    /// `codexBinaryPath` is best-effort: if absent or not executable the
    /// codex copy is skipped and the generated script reports that codex
    /// must be installed manually.
    @discardableResult
    static func materialize(
        workspacesRootURL: URL,
        publicKeyURL: URL,
        codexBinaryPath: String?,
        fileManager: FileManager = .default
    ) throws -> Layout {
        let layout = layout(workspacesRootURL: workspacesRootURL)
        try fileManager.createDirectory(
            at: layout.directoryURL,
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: layout.publicKeyURL.path) {
            try fileManager.removeItem(at: layout.publicKeyURL)
        }
        try fileManager.copyItem(at: publicKeyURL, to: layout.publicKeyURL)

        let includeCodex = installableCodexBinary(path: codexBinaryPath, fileManager: fileManager)
        if let source = includeCodex {
            if fileManager.fileExists(atPath: layout.codexBinaryURL.path) {
                try fileManager.removeItem(at: layout.codexBinaryURL)
            }
            try fileManager.copyItem(at: URL(fileURLWithPath: source), to: layout.codexBinaryURL)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: layout.codexBinaryURL.path
            )
        } else if fileManager.fileExists(atPath: layout.codexBinaryURL.path) {
            try? fileManager.removeItem(at: layout.codexBinaryURL)
        }

        let body = scriptContent(includesCodex: includeCodex != nil)
        try body.write(to: layout.scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: layout.scriptURL.path
        )

        return layout
    }

    /// Returns the codex binary path to copy if it exists and is an
    /// executable regular file (not a Codex.app *bundle* root, which
    /// `FileManager.copyItem` would happily clone in full).
    private static func installableCodexBinary(path: String?, fileManager: FileManager) -> String? {
        guard let path, !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        guard !isDirectory.boolValue else { return nil }
        guard fileManager.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    /// Renders the actual bash script body. Exposed for unit tests so the
    /// guest-side semantics can be locked in without spinning up a VM.
    static func scriptContent(includesCodex: Bool) -> String {
        let codexBlock: String
        if includesCodex {
            codexBlock = """
            echo "[4/4] Installing codex into /usr/local/bin/codex"
            sudo install -m 755 "$FIRSTBOOT_DIR/codex" /usr/local/bin/codex
            if command -v codex >/dev/null 2>&1; then
              echo "  codex available: $(codex --version 2>&1 || echo 'version probe failed')"
            else
              echo "  WARNING: codex install completed but the binary is not on PATH yet. Open a new shell."
            fi
            """
        } else {
            codexBlock = """
            echo "[4/4] No codex binary shipped from the host. Install one inside the guest"
            echo "      (e.g. download Codex.app or 'brew install codex') before Develop iterations."
            """
        }
        return """
        #!/bin/bash
        #
        # Compass first-boot bootstrap. Run once inside the guest macOS Terminal
        # after Setup Assistant completes. Idempotent — safe to re-run.
        #
        # The script needs sudo for the /opt/compass symlink, Remote Login,
        # and the codex install. You will be prompted for your guest password.
        #
        set -euo pipefail

        SHARE_TAG="\(workspacesShareTag)"
        SHARE_ROOT="/Volumes/My Shared Files/$SHARE_TAG"
        FIRSTBOOT_DIR="$SHARE_ROOT/\(directoryName)"
        PUBKEY="$FIRSTBOOT_DIR/\(publicKeyName)"

        echo "Compass first-boot bootstrap"
        echo "----"

        if [ ! -d "$SHARE_ROOT" ]; then
          echo "ERROR: VirtioFS share is not mounted at $SHARE_ROOT" >&2
          echo "       The Compass shared VM has not attached its workspace share." >&2
          exit 1
        fi
        if [ ! -f "$PUBKEY" ]; then
          echo "ERROR: Public key not found at $PUBKEY" >&2
          exit 1
        fi

        echo "[1/4] Authorising Compass SSH key for $USER"
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        touch "$HOME/.ssh/authorized_keys"
        cat "$PUBKEY" >> "$HOME/.ssh/authorized_keys"
        # De-duplicate authorized_keys in place.
        awk '!seen[$0]++' "$HOME/.ssh/authorized_keys" > "$HOME/.ssh/authorized_keys.tmp" \\
          && mv "$HOME/.ssh/authorized_keys.tmp" "$HOME/.ssh/authorized_keys"
        chmod 600 "$HOME/.ssh/authorized_keys"

        echo "[2/4] Creating /opt/compass/workspaces -> $SHARE_ROOT"
        sudo mkdir -p /opt/compass
        sudo rm -f /opt/compass/workspaces
        sudo ln -s "$SHARE_ROOT" /opt/compass/workspaces

        echo "[3/4] Enabling Remote Login (sshd)"
        sudo systemsetup -setremotelogin on >/dev/null

        \(codexBlock)

        echo
        echo "Compass first-boot bootstrap complete."
        echo "Return to Compass on the host and click 'Mark setup complete'."
        """
    }
}

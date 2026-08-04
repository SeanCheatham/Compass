import Foundation

/// Re-applies guest graphical auto-login over SSH once the guest is
/// reachable. The planted LaunchDaemon often races SecurityAgent on
/// macOS 26 (`no autologin because no conditions for autologin were
/// met`); this host-driven repair re-writes `/etc/kcpassword` +
/// `autoLoginUser` and restarts `loginwindow` after SSH is up.
public enum SharedCompassVMAutoLoginRepair {
  public enum RepairError: LocalizedError {
    case missingCredentials
    case sshFailed(exitCode: Int32, detail: String)

    public var errorDescription: String? {
      switch self {
      case .missingCredentials:
        return "Guest console password is not available in the host Keychain."
      case .sshFailed(let exitCode, let detail):
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
          return "Auto-login repair over SSH failed (exit \(exitCode))."
        }
        return "Auto-login repair over SSH failed (exit \(exitCode)): \(trimmed)"
      }
    }
  }

  /// Guest paths must stay aligned with
  /// `SharedCompassVMHeadlessFirstBoot.Profile`.
  public static let autoLoginScriptGuestPath = "/usr/local/libexec/compass-autologin.sh"
  public static let consolePasswordGuestPath = "/var/root/.compass-console-password"
  public static let autoLoginLaunchDaemonLabel =
    SharedCompassVMHeadlessFirstBoot.autoLoginLaunchDaemonLabel

  /// Builds the remote shell command that re-applies auto-login using the
  /// host-known password (so repair works even when the planted helper
  /// or password file is missing/stale).
  public static func repairRemoteCommand(guestUserName: String, password: String) -> String {
    let quotedUser = SharedCompassVMGuestBridge.posixQuote(guestUserName)
    let quotedPassword = SharedCompassVMGuestBridge.posixQuote(password)
    let quotedPasswordFile = SharedCompassVMGuestBridge.posixQuote(consolePasswordGuestPath)
    let quotedScript = SharedCompassVMGuestBridge.posixQuote(autoLoginScriptGuestPath)
    return """
      set -euo pipefail
      GUEST_USER=\(quotedUser)
      PASSWORD=\(quotedPassword)
      PASSWORD_FILE=\(quotedPasswordFile)
      LOG=/var/log/compass-autologin.log
      exec >>"$LOG" 2>&1
      echo "----"
      echo "[compass-autologin-repair] $(date -u '+%Y-%m-%dT%H:%M:%SZ') host-triggered repair for $GUEST_USER"
      if ! /usr/bin/dscl . -read "/Users/$GUEST_USER" UniqueID >/dev/null 2>&1; then
        echo "[compass-autologin-repair] guest user missing"
        exit 1
      fi
      if ! /usr/bin/dscl . -authonly "$GUEST_USER" "$PASSWORD" >/dev/null 2>&1; then
        echo "[compass-autologin-repair] dscl authonly failed"
        exit 1
      fi
      printf '%s' "$PASSWORD" > "$PASSWORD_FILE"
      /usr/sbin/chown root:wheel "$PASSWORD_FILE"
      /bin/chmod 600 "$PASSWORD_FILE"
      \(SharedCompassVMHeadlessFirstBoot.shellWriteKcpasswordFromPasswordEnv())
      \(SharedCompassVMHeadlessFirstBoot.shellApplyAutoLoginUserPreference())
      # Prefer the planted helper when present (keeps guest/host logic aligned).
      if [ -x \(quotedScript) ]; then
        /bin/bash \(quotedScript) || true
      fi
      /bin/launchctl kickstart -k system/\(autoLoginLaunchDaemonLabel) 2>/dev/null || true
      for attempt in 1 2 3 4 5 6; do
        console_owner="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || echo loginwindow)"
        echo "[compass-autologin-repair] attempt $attempt /dev/console owner: $console_owner"
        if [ "$console_owner" != "loginwindow" ] && [ "$console_owner" != "_unknown" ]; then
          echo "[compass-autologin-repair] desktop session active for $console_owner"
          exit 0
        fi
        echo "[compass-autologin-repair] restarting loginwindow"
        /usr/bin/killall loginwindow 2>/dev/null || true
        sleep 8
      done
      echo "[compass-autologin-repair] still at loginwindow after retries"
      exit 0
      """
  }

  public static func repairOverSSH(
    destination: String,
    options: SharedCompassVMGuestBridge.ConnectionOptions,
    guestUserName: String,
    password: String
  ) async throws {
    let result = try await ProcessRunner.run(
      executable: options.executablePath,
      arguments: SharedCompassVMGuestBridge.sshArguments(
        destination: destination,
        remoteCommand: repairRemoteCommand(guestUserName: guestUserName, password: password),
        options: options
      ),
      timeout: 120
    )
    guard result.exitCode == 0 else {
      throw RepairError.sshFailed(
        exitCode: result.exitCode,
        detail: result.stderr + result.stdout
      )
    }
  }

  /// Returns `true` when `/dev/console` is already owned by a real user
  /// session (auto-login succeeded). Failures / timeouts return `false`.
  public static func isDesktopSessionActive(
    destination: String,
    options: SharedCompassVMGuestBridge.ConnectionOptions
  ) async -> Bool {
    let result = try? await ProcessRunner.run(
      executable: options.executablePath,
      arguments: SharedCompassVMGuestBridge.sshArguments(
        destination: destination,
        remoteCommand:
          "owner=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || echo loginwindow); "
          + "echo \"$owner\"; "
          + "case \"$owner\" in loginwindow|_unknown) exit 1 ;; *) exit 0 ;; esac",
        options: options
      ),
      timeout: 10
    )
    return result?.exitCode == 0
  }
}

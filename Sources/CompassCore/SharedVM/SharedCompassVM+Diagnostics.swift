import Foundation

/// One line in the Settings → macOS VM Console ring buffer.
public struct SharedCompassVMDiagnosticLine: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let timestamp: Date
  public let source: String
  public let text: String

  public init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    source: String,
    text: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.source = source
    self.text = text
  }

  public var displayText: String {
    let formatter = SharedCompassVMDiagnosticLine.timeFormatter
    return "[\(formatter.string(from: timestamp))] [\(source)] \(text)"
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()
}

@MainActor
extension SharedCompassVM {
  public func appendDiagnostic(_ text: String, source: String = "host") {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var next = diagnosticLines
    next.append(SharedCompassVMDiagnosticLine(source: source, text: trimmed))
    if next.count > Self.diagnosticLineCap {
      next.removeFirst(next.count - Self.diagnosticLineCap)
    }
    diagnosticLines = next
  }

  public func clearDiagnostics() {
    diagnosticLines = []
  }

  /// Re-applies guest graphical auto-login over SSH using the Keychain
  /// password. Safe to call whenever SSH is up (idempotent).
  @discardableResult
  public func repairAutoLogin(destination: String? = nil) async -> Bool {
    let resolved =
      destination
      ?? lastResolvedSSHDestination
      ?? {
        if case .ready(let ssh) = readiness { return ssh }
        return nil
      }()
    guard let resolved else {
      appendDiagnostic("Auto-login repair skipped: no SSH destination yet.", source: "autologin")
      return false
    }
    guard let login = guestConsoleLogin() else {
      appendDiagnostic(
        "Auto-login repair skipped: guest password missing from Keychain.",
        source: "autologin"
      )
      return false
    }
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 10
    )
    appendDiagnostic("Repairing auto-login over SSH (\(resolved))…", source: "autologin")
    do {
      try await SharedCompassVMAutoLoginRepair.repairOverSSH(
        destination: resolved,
        options: options,
        guestUserName: login.userName,
        password: login.password
      )
      let active = await SharedCompassVMAutoLoginRepair.isDesktopSessionActive(
        destination: resolved,
        options: options
      )
      appendDiagnostic(
        active
          ? "Auto-login repair succeeded; desktop session is active."
          : "Auto-login repair finished; desktop may still be at the login window — open Desktop to check.",
        source: "autologin"
      )
      return true
    } catch {
      appendDiagnostic(
        "Auto-login repair failed: \(error.localizedDescription)",
        source: "autologin"
      )
      return false
    }
  }

  /// Starts (or restarts) a background SSH `tail -F` of guest provisioning
  /// / agent / auto-login logs into ``diagnosticLines``.
  public func startDiagnosticLogTail(destination: String? = nil) {
    let resolved =
      destination
      ?? lastResolvedSSHDestination
      ?? {
        if case .ready(let ssh) = readiness { return ssh }
        return nil
      }()
    guard let resolved else { return }
    stopDiagnosticLogTail()
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 10
    )
    let remoteCommand = """
      sudo /usr/bin/tail -n 80 -F \
        /var/log/compass-autologin.log \
        /Users/Shared/compass-firstboot/firstboot.log \
        /tmp/compass-guest-agent.log \
        2>/dev/null
      """
    appendDiagnostic("Starting guest log tail over SSH (\(resolved))…", source: "console")
    diagnosticTailTask = Task { [weak self] in
      guard let self else { return }
      do {
        _ = try await ProcessRunner.run(
          executable: options.executablePath,
          arguments: SharedCompassVMGuestBridge.sshArguments(
            destination: resolved,
            remoteCommand: remoteCommand,
            options: options
          ),
          timeout: 60 * 60 * 12,
          onStdout: { chunk in
            let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)
            Task { @MainActor [weak self] in
              for line in lines {
                let text = String(line)
                guard !text.isEmpty else { continue }
                self?.appendDiagnostic(text, source: "guest")
              }
            }
          },
          onStderr: { chunk in
            let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)
            Task { @MainActor [weak self] in
              for line in lines {
                let text = String(line)
                guard !text.isEmpty else { continue }
                self?.appendDiagnostic(text, source: "guest-err")
              }
            }
          }
        )
      } catch is CancellationError {
        await MainActor.run { [weak self] in
          self?.appendDiagnostic("Guest log tail cancelled.", source: "console")
        }
      } catch {
        await MainActor.run { [weak self] in
          self?.appendDiagnostic(
            "Guest log tail ended: \(error.localizedDescription)",
            source: "console"
          )
        }
      }
    }
  }

  public func stopDiagnosticLogTail() {
    diagnosticTailTask?.cancel()
    diagnosticTailTask = nil
  }
}

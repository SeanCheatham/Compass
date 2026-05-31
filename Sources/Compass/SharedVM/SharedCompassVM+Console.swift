import Foundation
import Virtualization

@MainActor
extension SharedCompassVM {
  // MARK: - Console pipe (guest IP discovery)

  /// Wires a host-owned `Pipe()` to the virtio console device.
  ///
  /// Per Apple's docs / sample (see `Running Linux in a Virtual Machine`):
  /// `fileHandleForReading` is what VZ reads from (host→guest input) and
  /// `fileHandleForWriting` is what VZ writes guest output to. To capture
  /// guest output only, leave the read side nil and pass the write end of
  /// our pipe for the write side, then read from the matching read end.
  ///
  /// IP discovery itself runs host-side via dhcpd_leases / `arp -an`
  /// keyed on the guest's pinned MAC (`SharedCompassVMGuestIPDiscovery`),
  /// so the guest does not need a serial-reporting agent. The pipe stays
  /// wired so future guest-side telemetry has a place to land; any line
  /// matching `COMPASS_GUEST_IP=<addr>` is still treated as authoritative.
  func attachConsolePipe(to configuration: VZVirtualMachineConfiguration) {
    let pipe = Pipe()
    let attachment = VZFileHandleSerialPortAttachment(
      fileHandleForReading: nil,
      fileHandleForWriting: pipe.fileHandleForWriting
    )
    do {
      try SharedCompassVMConfiguration.replaceConsoleAttachment(attachment, on: configuration)
    } catch {
      // No console device on this configuration — bail without retaining
      // the pipe. Nothing else relies on it being live.
      return
    }
    self.consoleOutputPipe = pipe

    let readHandle = pipe.fileHandleForReading
    consoleReadTask = Task.detached { [weak self] in
      var buffer = ""
      while !Task.isCancelled {
        let data = readHandle.availableData
        if data.isEmpty {
          // The far side closed; the VM has likely stopped.
          break
        }
        if let chunk = String(data: data, encoding: .utf8) {
          buffer += chunk
          while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[..<newlineRange.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
            await Self.handleConsoleLine(line, host: self)
          }
        }
      }
    }
  }

  func tearDownConsolePipe() {
    consoleReadTask?.cancel()
    consoleReadTask = nil
    if let pipe = consoleOutputPipe {
      try? pipe.fileHandleForReading.close()
      try? pipe.fileHandleForWriting.close()
    }
    consoleOutputPipe = nil
  }

  @MainActor

  private static func handleConsoleLine(_ line: String, host: SharedCompassVM?) async {
    guard let host else { return }
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("COMPASS_GUEST_IP=") else { return }
    let ip = String(trimmed.dropFirst("COMPASS_GUEST_IP=".count))
    guard !ip.isEmpty else { return }
    _ = try? host.bundle.mutateState(fileManager: host.dependencies.fileManager) {
      $0.lastKnownGoodIP = ip
    }
  }
}

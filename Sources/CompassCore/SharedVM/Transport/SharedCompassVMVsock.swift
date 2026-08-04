import Foundation
import Virtualization

/// Host-side vsock connector. Wraps `VZVirtioSocketDevice.connect(toPort:)`
/// in an async/await call so callers don't have to juggle completion
/// handlers, and centralises the port constant the guest agent listens on
/// so both sides can't drift.
///
/// Compass uses a single vsock connection per logical request — the
/// `AgentVsockClient` (Phase 8) opens, sends one length-prefixed RPC,
/// reads the response, and closes. That keeps the wire format trivial
/// and makes the connection itself disposable, so a half-broken agent
/// can't poison subsequent calls.
enum SharedCompassVMVsock {
  /// Port the in-guest Compass agent listens on. `0x4007ACE5` decodes to
  /// `"COMPACE5"` if you squint at it as hex-ASCII — a Compass-specific
  /// nonce chosen high enough to avoid any potential collision with
  /// other vsock-using software on the guest.
  static let guestAgentPort: UInt32 = 0x4007_ACE5

  /// Port the host-side Git service listens on for guest-initiated
  /// `git-remote-compass` connections. This is the inverse direction
  /// of `guestAgentPort`: the guest dials the host, then Compass
  /// bridges the connection to `git-upload-pack` / `git-receive-pack`
  /// against a Compass-owned bare exchange repo.
  static let gitServicePort: UInt32 = 0x4007_ACE6

  enum ConnectError: Error, CustomStringConvertible {
    /// VZVirtualMachine had no `VZVirtioSocketDevice` — typically means
    /// the configuration didn't attach a `VZVirtioSocketDeviceConfiguration`,
    /// or the VM was instantiated before the socket device was wired in.
    case noSocketDevice
    case connectionFailed(detail: String)

    var description: String {
      switch self {
      case .noSocketDevice:
        return "VM has no virtio-vsock device attached"
      case .connectionFailed(let detail):
        return "vsock connect failed: \(detail)"
      }
    }
  }

  /// Polls until the in-guest Compass agent completes a minimal bash RPC.
  /// A bare vsock connect can succeed before the agent speaks the wire
  /// protocol, which surfaces as `lengthHeaderTooShort` on the first real
  /// RPC. SSH coming up first is a separate, earlier race — callers must
  /// still wait here after sshd responds.
  @MainActor
  static func waitUntilReachable(
    on machine: VZVirtualMachine,
    port: UInt32 = guestAgentPort,
    timeout: TimeInterval = 300,
    probeTimeout: TimeInterval = 10,
    sleep: @Sendable (UInt64) async -> Void = { ns in try? await Task.sleep(nanoseconds: ns) }
  ) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    var attemptIntervalNanoseconds: UInt64 = 2_000_000_000
    while Date() < deadline {
      let client = AgentVsockClient(
        transportFactory: {
          let connection = try await connect(port: port, on: machine)
          return VZVirtioSocketTransport(connection: connection)
        },
        requestTimeout: probeTimeout
      )
      do {
        let result = try await client.run(
          command: "true",
          workingDirectory: URL(fileURLWithPath: SharedCompassVMGuestLayout.current.homeDirectory),
          timeout: probeTimeout
        )
        if result.exitCode == 0 {
          return true
        }
      } catch {
        // Agent not ready yet — retry after backoff.
      }
      await sleep(attemptIntervalNanoseconds)
      attemptIntervalNanoseconds = min(attemptIntervalNanoseconds * 2, 10_000_000_000)
    }
    return false
  }

  /// Opens a vsock connection to `port` on the guest. Returns the live
  /// `VZVirtioSocketConnection`; the caller owns it and is responsible
  /// for reading/writing on its file descriptor and closing it when done.
  ///
  /// `@MainActor`: `VZVirtioSocketDevice.connect(toPort:)` asserts it
  /// runs on the queue VZ was constructed on — for Compass that's the
  /// main queue (`SharedCompassVM` is `@MainActor`). Calling it from a
  /// background Swift Concurrency executor crashes with
  /// `_dispatch_assert_queue_fail` deep inside Virtualization.framework.
  /// The annotation pulls the call onto main automatically when invoked
  /// from non-MainActor async contexts (e.g. `AgentVsockClient`'s
  /// transport factory). The completion handler may fire on any queue;
  /// the continuation resume is queue-agnostic.
  @MainActor
  static func connect(
    port: UInt32 = guestAgentPort,
    on machine: VZVirtualMachine
  ) async throws -> VZVirtioSocketConnection {
    guard let socketDevice = machine.socketDevices.first as? VZVirtioSocketDevice else {
      throw ConnectError.noSocketDevice
    }
    return try await withCheckedThrowingContinuation { continuation in
      socketDevice.connect(toPort: port) { result in
        switch result {
        case .success(let connection):
          continuation.resume(returning: connection)
        case .failure(let error):
          continuation.resume(
            throwing: ConnectError.connectionFailed(detail: error.localizedDescription))
        }
      }
    }
  }
}

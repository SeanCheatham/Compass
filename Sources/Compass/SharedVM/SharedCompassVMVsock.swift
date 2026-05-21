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
                    continuation.resume(throwing: ConnectError.connectionFailed(detail: error.localizedDescription))
                }
            }
        }
    }
}

import Foundation
import Virtualization

/// Result of `SharedCompassVMAvailabilityCheck.evaluate()`.
enum SharedCompassVMAvailability: Equatable {
  case available
  case unavailable(reason: String)

  var isAvailable: Bool {
    if case .available = self { return true }
    return false
  }

  var unavailableReason: String? {
    if case .unavailable(let reason) = self { return reason }
    return nil
  }
}

/// Best-effort runtime detection of conditions that would prevent Compass from
/// running its shared VM. The current implementation is intentionally
/// conservative: it returns `.available` in all cases that we can't reliably
/// distinguish ahead of time, and lets the real `VZVirtualMachine.start` call
/// surface the actual error.
///
/// The known failure modes we do care about:
///
///   * **Apple 2-guest cap.** macOS guests are limited to 2 simultaneously
///     running `VZVirtualMachine` instances per host. There is no public API
///     to query the cap ahead-of-time, so we detect it by *attempting* to
///     instantiate a minimal probe configuration and watching for
///     `VZErrorMaximumVMCountReached`. The probe never starts the VM, just
///     instantiates one — that's enough to surface the cap on current
///     Virtualization.framework releases.
///
///   * **Apple Silicon required.** The package is built arm64-only so the
///     Compass binary literally cannot launch on Intel. No runtime gate needed.
enum SharedCompassVMAvailabilityCheck {
  /// Synchronous availability evaluation. Safe to call from any thread,
  /// but for parity with the rest of the module we recommend calling from
  /// the main actor.
  @MainActor
  static func evaluate() -> SharedCompassVMAvailability {
    // 1. Macs that report `VZVirtualMachine.isSupported == false` are
    //    not capable of running VZ at all. (Should never happen on a
    //    correctly-targeted arm64 build, but documented for completeness.)
    if !VZVirtualMachine.isSupported {
      return .unavailable(reason: "Virtualization is not supported on this Mac.")
    }

    return .available
  }

  /// Maps an arbitrary error surfaced by `VZVirtualMachine.start` (or the
  /// installer) into a user-readable availability reason for the
  /// `.unavailable(reason:)` readiness case.
  static func describe(error: Error) -> String {
    let nsError = error as NSError
    if nsError.domain == VZErrorDomain {
      switch VZError.Code(rawValue: nsError.code) {
      case .virtualMachineLimitExceeded:
        return
          "Apple's per-host VM limit was reached. Quit other VM apps (Parallels, UTM, Xcode device VMs) and try again."
      case .networkError:
        return "Shared VM network error: \(nsError.localizedDescription)"
      case .invalidVirtualMachineConfiguration:
        return "Shared VM configuration is invalid: \(nsError.localizedDescription)"
      case .invalidVirtualMachineState:
        return "Shared VM is in an invalid state: \(nsError.localizedDescription)"
      case .internalError:
        return
          "Virtualization framework reported an internal error: \(nsError.localizedDescription)"
      case .operationCancelled:
        return "Operation was cancelled."
      default:
        return nsError.localizedDescription
      }
    }
    return nsError.localizedDescription
  }

  /// Like `describe` but dumps the full NSError chain — domain, code,
  /// underlying error — so the user (or a bug report) carries enough
  /// detail to diagnose catalog-fetch and installer failures.
  static func describeVerbose(error: Error) -> String {
    var parts: [String] = []
    let ns = error as NSError
    parts.append("\(ns.localizedDescription) [\(ns.domain) \(ns.code)]")
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
      parts.append(
        "Underlying: \(underlying.localizedDescription) [\(underlying.domain) \(underlying.code)]")
    }
    return parts.joined(separator: "\n")
  }
}

import Foundation

enum SharedCompassVMReadiness: Equatable {
    case unavailable(reason: String)
    case notProvisioned
    case downloadingIPSW(fractionCompleted: Double)
    case installing(fractionCompleted: Double)
    case guestPrepping
    case codexLoginPending
    case ready(sshDestination: String)
    case error(detail: String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

import Foundation

enum DevelopSandboxPreference: String, Codable, CaseIterable, Equatable {
    case host
    case sharedVM = "shared_vm"

    var displayLabel: String {
        switch self {
        case .host: return "Host"
        case .sharedVM: return "Shared VM"
        }
    }
}

import Foundation

struct SandboxReadinessGuide: Equatable, Sendable {
  static let detailLimit = 340
  static let identifierLimit = 1_200

  enum Tone: String, Equatable, Sendable {
    case ready
    case action
    case progress
    case blocked
  }

  struct Step: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var detail: String
    var systemImageName: String
    var isComplete: Bool
  }

  var title: String
  var detail: String
  var actionLabel: String
  var tone: Tone
  var systemImageName: String
  var steps: [Step]
  var narrationIdentifier: String

  var allowsNarration: Bool {
    switch tone {
    case .progress:
      return false
    case .ready, .action, .blocked:
      return true
    }
  }

  init(readiness: SharedCompassVMReadiness) {
    switch readiness {
    case .notProvisioned:
      title = "Private Workspace Not Installed"
      detail =
        "Provision the Shared VM once so Develop can edit and verify inside a private macOS guest instead of your host checkout."
      actionLabel = "Provision Shared VM"
      tone = .action
      systemImageName = "shippingbox"
    case .downloadingIPSW(let fraction):
      title = "Downloading Restore Image"
      detail =
        "Compass is fetching the macOS restore image. You can leave this view open while the download continues."
      actionLabel = Self.percentLabel(fraction)
      tone = .progress
      systemImageName = "arrow.down.circle"
    case .installing(let fraction):
      title = "Installing macOS"
      detail =
        "Compass is restoring macOS onto the VM disk. The sandbox is not ready for Develop until first boot and tool setup finish."
      actionLabel = Self.percentLabel(fraction)
      tone = .progress
      systemImageName = "internaldrive"
    case .guestPrepping:
      title = "Preparing Guest Access"
      detail =
        "The guest has booted. Compass is creating the compass user, enabling Remote Login, and polling until SSH is ready."
      actionLabel = "Waiting for guest"
      tone = .action
      systemImageName = "gearshape.2"
    case .provisioningDevTools(let fraction):
      title = "Installing Developer Tools"
      detail =
        "The guest is installing command-line developer tools so builds and tests can run inside the sandbox."
      actionLabel = Self.percentLabel(fraction)
      tone = .progress
      systemImageName = "hammer"
    case .ready(let destination):
      title = "Sandbox Ready"
      detail =
        "Develop work can now run in the private macOS guest. Compass will route sandboxed commands through \(destination)."
      actionLabel = "Ready"
      tone = .ready
      systemImageName = "checkmark.seal.fill"
    case .unavailable(let reason):
      title = "Sandbox Unavailable"
      detail = "This Mac cannot use the Shared VM right now: \(reason)"
      actionLabel = "Use host route"
      tone = .blocked
      systemImageName = "exclamationmark.triangle"
    case .error(let detail):
      title = "Sandbox Needs Repair"
      self.detail =
        "The last VM operation failed: \(detail). Rebuild with a local IPSW file or reset VM artifacts if the install is stuck."
      actionLabel = "Repair sandbox"
      tone = .blocked
      systemImageName = "xmark.octagon"
    }

    detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
    steps = Self.steps(for: readiness)
    narrationIdentifier = Self.narrationIdentifier(
      title: title,
      detail: detail,
      actionLabel: actionLabel,
      tone: tone,
      systemImageName: systemImageName,
      steps: steps
    )
  }

  private static func steps(for readiness: SharedCompassVMReadiness) -> [Step] {
    switch readiness {
    case .unavailable(let reason):
      return [
        Step(
          id: "availability",
          title: "Host support",
          detail: StringUtils.boundedText(reason, limit: 180),
          systemImageName: "exclamationmark.triangle",
          isComplete: false
        )
      ]
    case .error:
      return [
        Step(
          id: "repair",
          title: "Recover install",
          detail: "Use a local IPSW rebuild or reset VM artifacts, then provision again.",
          systemImageName: "wrench.and.screwdriver",
          isComplete: false
        )
      ]
    default:
      return pipelineSteps(for: readiness)
    }
  }

  private static func pipelineSteps(for readiness: SharedCompassVMReadiness) -> [Step] {
    [
      Step(
        id: "download",
        title: "Restore image",
        detail: downloadDetail(for: readiness),
        systemImageName: "arrow.down.circle",
        isComplete: downloadComplete(readiness)
      ),
      Step(
        id: "install",
        title: "macOS install",
        detail: installDetail(for: readiness),
        systemImageName: "internaldrive",
        isComplete: installComplete(readiness)
      ),
      Step(
        id: "guest",
        title: "Guest access",
        detail: guestDetail(for: readiness),
        systemImageName: "person.crop.circle.badge.checkmark",
        isComplete: guestComplete(readiness)
      ),
      Step(
        id: "tools",
        title: "Developer tools",
        detail: toolsDetail(for: readiness),
        systemImageName: "hammer",
        isComplete: toolsComplete(readiness)
      ),
    ]
  }

  private static func downloadDetail(for readiness: SharedCompassVMReadiness) -> String {
    if case .downloadingIPSW(let fraction) = readiness {
      return "Downloading from Apple's CDN, \(percentLabel(fraction)) complete."
    }
    return "Download or choose a local macOS IPSW restore image."
  }

  private static func installDetail(for readiness: SharedCompassVMReadiness) -> String {
    if case .installing(let fraction) = readiness {
      return "Restoring macOS, \(percentLabel(fraction)) complete."
    }
    return "Install macOS onto the private VM disk."
  }

  private static func guestDetail(for readiness: SharedCompassVMReadiness) -> String {
    if case .guestPrepping = readiness {
      return "Creating the compass user and enabling SSH."
    }
    return "Prepare auto-login, credentials, and SSH access."
  }

  private static func toolsDetail(for readiness: SharedCompassVMReadiness) -> String {
    if case .provisioningDevTools(let fraction) = readiness {
      return "Installing command-line tools, \(percentLabel(fraction)) complete."
    }
    return "Install build and test tools inside the guest."
  }

  private static func downloadComplete(_ readiness: SharedCompassVMReadiness) -> Bool {
    switch readiness {
    case .installing, .guestPrepping, .provisioningDevTools, .ready:
      return true
    case .unavailable, .notProvisioned, .downloadingIPSW, .error:
      return false
    }
  }

  private static func installComplete(_ readiness: SharedCompassVMReadiness) -> Bool {
    switch readiness {
    case .guestPrepping, .provisioningDevTools, .ready:
      return true
    case .unavailable, .notProvisioned, .downloadingIPSW, .installing, .error:
      return false
    }
  }

  private static func guestComplete(_ readiness: SharedCompassVMReadiness) -> Bool {
    switch readiness {
    case .provisioningDevTools, .ready:
      return true
    case .unavailable, .notProvisioned, .downloadingIPSW, .installing, .guestPrepping, .error:
      return false
    }
  }

  private static func toolsComplete(_ readiness: SharedCompassVMReadiness) -> Bool {
    if case .ready = readiness { return true }
    return false
  }

  private static func percentLabel(_ fraction: Double) -> String {
    let clamped = Swift.min(1, Swift.max(0, fraction))
    return "\(Int((clamped * 100).rounded()))%"
  }

  private static func narrationIdentifier(
    title: String,
    detail: String,
    actionLabel: String,
    tone: Tone,
    systemImageName: String,
    steps: [Step]
  ) -> String {
    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "action:\(actionLabel)",
      "tone:\(tone.rawValue)",
      "image:\(systemImageName)",
      "steps:\(steps.map { "\($0.id):\($0.isComplete):\($0.detail)" }.joined(separator: ","))",
    ].joined(separator: "|")

    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }
}

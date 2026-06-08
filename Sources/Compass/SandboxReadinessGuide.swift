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
        "Set up the private workspace once so Develop can edit and verify away from your main checkout."
      actionLabel = "Set Up Workspace"
      tone = .action
      systemImageName = "shippingbox"
    case .downloadingIPSW(let fraction):
      title = "Downloading macOS"
      detail =
        "Compass is fetching the macOS download. You can leave this view open while it continues."
      actionLabel = Self.percentLabel(fraction)
      tone = .progress
      systemImageName = "arrow.down.circle"
    case .installing(let fraction):
      title = "Installing macOS"
      detail =
        "Compass is installing macOS for the private workspace. Develop unlocks after first boot and tool setup finish."
      actionLabel = Self.percentLabel(fraction)
      tone = .progress
      systemImageName = "internaldrive"
    case .guestPrepping:
      title = "Finishing Workspace Setup"
      detail =
        "The workspace has booted. Compass is creating its account, enabling secure access, and waiting until commands can run."
      actionLabel = "Finishing setup"
      tone = .action
      systemImageName = "gearshape.2"
    case .provisioningDevTools(let fraction):
      title = "Installing Developer Tools"
      detail =
        "The private workspace is installing command-line developer tools so builds and tests can run there."
      actionLabel = Self.percentLabel(fraction)
      tone = .progress
      systemImageName = "hammer"
    case .ready:
      title = "Private Workspace Ready"
      detail =
        "Develop work can now run in the private workspace. Compass will use its saved workspace connection."
      actionLabel = "Ready"
      tone = .ready
      systemImageName = "checkmark.seal.fill"
    case .unavailable(let reason):
      title = "Private Workspace Unavailable"
      detail =
        "This Mac cannot use the private workspace right now: \(PrivateWorkspaceCopy.userFacingInfrastructureDetail(reason, limit: 220))"
      actionLabel = "Use This Mac"
      tone = .blocked
      systemImageName = "exclamationmark.triangle"
    case .error(let operationDetail):
      title = "Private Workspace Needs Repair"
      self.detail =
        "The last workspace operation failed: \(PrivateWorkspaceCopy.userFacingInfrastructureDetail(operationDetail, limit: 180)). Rebuild with a downloaded macOS restore image or reset workspace files if the install is stuck."
      actionLabel = "Repair Workspace"
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
          title: "Mac support",
          detail: PrivateWorkspaceCopy.userFacingInfrastructureDetail(reason, limit: 180),
          systemImageName: "exclamationmark.triangle",
          isComplete: false
        )
      ]
    case .error:
      return [
        Step(
          id: "repair",
          title: "Recover install",
          detail:
            "Use a downloaded macOS restore image or reset workspace files, then set up the workspace again.",
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
        title: "Workspace access",
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
    return "Download or choose a macOS restore image."
  }

  private static func installDetail(for readiness: SharedCompassVMReadiness) -> String {
    if case .installing(let fraction) = readiness {
      return "Restoring macOS, \(percentLabel(fraction)) complete."
    }
    return "Install macOS for the private workspace."
  }

  private static func guestDetail(for readiness: SharedCompassVMReadiness) -> String {
    if case .guestPrepping = readiness {
      return "Creating the Compass account and enabling secure access."
    }
    return "Prepare sign-in, credentials, and secure command access."
  }

  private static func toolsDetail(for readiness: SharedCompassVMReadiness) -> String {
    if case .provisioningDevTools(let fraction) = readiness {
      return "Installing command-line tools, \(percentLabel(fraction)) complete."
    }
    return "Install build and test tools inside the workspace."
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

struct SandboxReadinessClipboardPayload: Equatable, Sendable {
  static let textLimit = 3_000
  private static let readinessDetailLimit = 600

  var text: String

  init(readiness: SharedCompassVMReadiness, guide: SandboxReadinessGuide) {
    var sections: [String] = [
      "Compass Private Workspace Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded private workspace readiness context. Do not invent logs, "
        + "downloaded restore image paths, credentials, connection destinations, Mac support, or hidden state.",
      "- Use the exact readiness state, action, and checklist to choose the next safe step.",
      "- If repair is needed, prefer the visible Compass controls named here before "
        + "suggesting manual filesystem cleanup.",
      "- If the packet is progress-only, wait or ask for a fresh status instead of "
        + "claiming the sandbox is ready.",
      "",
      "Status: \(guide.title) (\(guide.tone.rawValue))",
      "Action: \(guide.actionLabel)",
      "Detail: \(guide.detail)",
      "Readiness: \(Self.readinessLabel(readiness))",
      "",
      "Checklist:",
    ]

    for step in guide.steps {
      sections.append(
        "- \(step.isComplete ? "[complete]" : "[open]") \(step.title): \(step.detail)"
      )
    }

    text = SandboxReadinessClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func readinessLabel(_ readiness: SharedCompassVMReadiness) -> String {
    switch readiness {
    case .unavailable(let reason):
      return "unavailable: \(bounded(reason))"
    case .notProvisioned:
      return "private workspace not installed"
    case .downloadingIPSW(let fraction):
      return "downloading macOS: \(percentLabel(fraction))"
    case .installing(let fraction):
      return "installing macOS: \(percentLabel(fraction))"
    case .guestPrepping:
      return "finishing workspace setup"
    case .provisioningDevTools(let fraction):
      return "installing developer tools: \(percentLabel(fraction))"
    case .ready:
      return "ready"
    case .error(let detail):
      return "error: \(bounded(detail))"
    }
  }

  private static func percentLabel(_ fraction: Double) -> String {
    let clamped = Swift.min(1, Swift.max(0, fraction))
    return "\(Int((clamped * 100).rounded()))%"
  }

  private static func bounded(_ text: String) -> String {
    PrivateWorkspaceCopy.userFacingInfrastructureDetail(text, limit: readinessDetailLimit)
  }
}

enum PrivateWorkspaceCopy {
  static func userFacingInfrastructureDetail(_ text: String, limit: Int) -> String {
    var rewritten = StringUtils.boundedText(text, limit: limit)
    let replacements = [
      ("Shared VM", "private workspace"),
      ("shared VM", "private workspace"),
      ("VM", "workspace"),
      ("2-guest cap", "workspace capacity limit"),
      ("guest disk", "workspace disk"),
      ("guest access", "workspace access"),
      ("guest", "workspace"),
      ("Remote Login", "secure access"),
      ("SSH destinations", "connection destinations"),
      ("SSH destination", "connection destination"),
      ("SSH", "secure connection"),
      ("local IPSW", "downloaded macOS restore image"),
      ("IPSW", "macOS restore image"),
    ]
    for (original, replacement) in replacements {
      rewritten = rewritten.replacingOccurrences(of: original, with: replacement)
    }
    rewritten = rewritten.replacingOccurrences(
      of: #"\b[\w.-]+@\d{1,3}(?:\.\d{1,3}){3}\b"#,
      with: "saved workspace connection",
      options: .regularExpression
    )
    return StringUtils.boundedText(rewritten, limit: limit)
  }

  static func containsImplementationTerm(_ text: String) -> Bool {
    let normalized = text.lowercased()
    return normalized.contains("shared vm")
      || normalized.contains("ssh")
      || normalized.contains("ipsw")
      || normalized.contains("guest")
      || normalized.range(
        of: #"\b[\w.-]+@\d{1,3}(?:\.\d{1,3}){3}\b"#,
        options: .regularExpression
      ) != nil
  }
}

private enum SandboxReadinessClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

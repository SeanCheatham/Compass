import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Virtualization

/// Detail-pane content for the top-level "Sandbox" sidebar entry.
///
/// Hosts the embedded `SharedCompassVMView` plus the readiness affordances
/// (status chip, first-boot checklist, IPSW download + install progress bars).
/// All layout is inline so the user never loses visibility into a long-running
/// provisioning task — the plan deliberately rejects a modal here.
struct SandboxView: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject private var vmHost: SharedCompassVM = .shared
  @State private var readinessGuideNarration: SandboxReadinessGuideNarration?

  var body: some View {
    let readinessGuide = SandboxReadinessGuide(readiness: vmHost.readiness)

    VStack(spacing: 0) {
      SandboxHeader(readiness: vmHost.readiness)
      Divider()
      HSplitView {
        SharedCompassVMView(virtualMachine: vmHost.virtualMachine)
          .frame(minWidth: 480, minHeight: 360)
          .overlay(alignment: .topTrailing) {
            SandboxStatusChip(readiness: vmHost.readiness)
              .padding(12)
          }
          .overlay {
            if vmHost.virtualMachine == nil {
              SandboxPlaceholder(readiness: vmHost.readiness)
            }
          }
        SandboxSidePanel(
          vmHost: vmHost,
          readinessGuide: readinessGuide,
          narration: matchingNarration(for: readinessGuide)
        )
          .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
      }
    }
    .task(id: vmHost.readiness.headlessAutoStartToken) {
      await autoStartHeadlessGuestIfNeeded()
    }
    .task(id: readinessGuide.narrationIdentifier) {
      readinessGuideNarration = nil
      readinessGuideNarration = await SandboxReadinessGuideNarrator.narrate(
        guide: readinessGuide
      )
    }
  }

  /// After provisioning lands at `.guestPrepping`, the planted LaunchDaemon
  /// finishes the user-creation + SSH-key dance inside the guest. We just
  /// need the VM running; SharedCompassVM's internal poll loop then
  /// auto-finalises readiness to `.ready` without any user click.
  private func autoStartHeadlessGuestIfNeeded() async {
    guard case .guestPrepping = vmHost.readiness, vmHost.virtualMachine == nil else { return }
    do {
      try await vmHost.start()
    } catch {
      // `start()` publishes the visible error state.
    }
  }

  private func matchingNarration(
    for guide: SandboxReadinessGuide
  ) -> SandboxReadinessGuideNarration? {
    guard readinessGuideNarration?.guideIdentifier == guide.narrationIdentifier else {
      return nil
    }
    return readinessGuideNarration
  }
}

// MARK: - Header

private struct SandboxHeader: View {
  let readiness: SharedCompassVMReadiness

  var body: some View {
    HStack(spacing: 10) {
      SandboxReadinessDot(readiness: readiness, size: 11)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Sandbox")
          .font(.headline)
        Text(readiness.statusSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

// MARK: - Placeholder (no live VM yet)

private struct SandboxPlaceholder: View {
  let readiness: SharedCompassVMReadiness

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: readiness.systemImage)
        .font(.system(size: 40, weight: .regular))
        .foregroundStyle(readiness.tintColor)
      Text(readiness.placeholderTitle)
        .font(.title3.weight(.semibold))
      Text(readiness.placeholderDetail)
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(28)
    .frame(maxWidth: 460)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
  }
}

// MARK: - Status chip (overlay on the VZ view)

private struct SandboxStatusChip: View {
  let readiness: SharedCompassVMReadiness

  var body: some View {
    HStack(spacing: 6) {
      SandboxReadinessDot(readiness: readiness, size: 8)
      Text(readiness.chipLabel)
        .font(.caption.weight(.semibold))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(.thinMaterial, in: Capsule())
    .overlay(Capsule().stroke(readiness.tintColor.opacity(0.35)))
    .help(readiness.statusSummary)
  }
}

// MARK: - Side panel — checklist, progress, controls

private struct SandboxSidePanel: View {
  @ObservedObject var vmHost: SharedCompassVM
  var readinessGuide: SandboxReadinessGuide
  var narration: SandboxReadinessGuideNarration?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        SandboxReadinessSection(readiness: vmHost.readiness)
        SandboxReadinessGuideSection(
          readiness: vmHost.readiness,
          guide: readinessGuide,
          narration: narration
        )

        switch vmHost.readiness {
        case .downloadingIPSW(let fraction):
          SandboxProgressSection(
            title: "Downloading macOS",
            systemImage: "arrow.down.circle",
            downloadFraction: fraction,
            installFraction: nil
          )
        case .installing(let fraction):
          SandboxProgressSection(
            title: "Installing macOS",
            systemImage: "internaldrive",
            downloadFraction: 1.0,
            installFraction: fraction
          )
        case .guestPrepping:
          SandboxHeadlessFirstBootSection(vmHost: vmHost)
        case .provisioningDevTools(let fraction):
          SandboxProgressSection(
            title: "Installing developer tools",
            systemImage: "hammer",
            downloadFraction: 1.0,
            installFraction: fraction
          )
        case .ready(let destination):
          SandboxReadySection(sshDestination: destination)
        case .unavailable(let reason):
          SandboxUnavailableSection(reason: reason)
        case .error(let detail):
          SandboxErrorSection(detail: detail, vmHost: vmHost)
        case .notProvisioned:
          SandboxIdleSection(vmHost: vmHost)
        }

        if let consoleLogin = vmHost.guestConsoleLogin() {
          SandboxConsoleLoginSection(login: consoleLogin, vmIsRunning: vmHost.virtualMachine != nil)
        }

        Spacer(minLength: 0)
      }
      .padding(16)
    }
    .background(.background)
  }
}

// MARK: - Sub-sections

private struct SandboxReadinessSection: View {
  let readiness: SharedCompassVMReadiness

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Status")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        SandboxReadinessDot(readiness: readiness, size: 10)
        Text(readiness.statusSummary)
          .font(.body.weight(.medium))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct SandboxReadinessGuideSection: View {
  let readiness: SharedCompassVMReadiness
  let guide: SandboxReadinessGuide
  let narration: SandboxReadinessGuideNarration?

  var body: some View {
    let clipboardPayload = SandboxReadinessClipboardPayload(
      readiness: readiness,
      guide: guide
    )

    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: guide.systemImageName)
          .foregroundStyle(tintColor)
        Text(guide.title)
          .font(.subheadline.weight(.semibold))
        Spacer(minLength: 0)
        CopySandboxReadinessButton(payload: clipboardPayload)
      }
      Text(guide.actionLabel)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tintColor)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      Text(narration?.text ?? guide.detail)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 7) {
        ForEach(guide.steps) { step in
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: step.isComplete ? "checkmark.circle.fill" : step.systemImageName)
              .font(.caption)
              .foregroundStyle(step.isComplete ? Color.green : tintColor)
              .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
              Text(step.title)
                .font(.caption.weight(.semibold))
              Text(step.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
    }
    .padding(12)
    .background(tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(tintColor.opacity(0.25)))
    .accessibilityLabel("\(guide.title). \(narration?.text ?? guide.detail)")
  }

  private var tintColor: Color {
    switch guide.tone {
    case .ready:
      return .green
    case .action, .progress:
      return .blue
    case .blocked:
      return .orange
    }
  }
}

private struct CopySandboxReadinessButton: View {
  var payload: SandboxReadinessClipboardPayload
  @State private var copied = false

  var body: some View {
    Button {
      copyTextToPasteboard(payload.text)
      copied = true
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        copied = false
      }
    } label: {
      Label(
        copied ? "Copied" : "Copy Sandbox",
        systemImage: copied ? "checkmark" : "doc.on.doc"
      )
      .lineLimit(1)
    }
    .controlSize(.small)
    .disabled(payload.isEmpty)
    .help("Copy a bounded sandbox readiness handoff for another model or teammate.")
  }
}

private struct SandboxProgressSection: View {
  let title: String
  let systemImage: String
  let downloadFraction: Double?
  let installFraction: Double?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: systemImage)
        .font(.subheadline.weight(.semibold))

      if let downloadFraction {
        VStack(alignment: .leading, spacing: 3) {
          HStack {
            Text("Restore image")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Text(percentLabel(downloadFraction))
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
          ProgressView(value: downloadFraction.clamped01)
        }
      }

      if let installFraction {
        VStack(alignment: .leading, spacing: 3) {
          HStack {
            Text("Installer")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Text(percentLabel(installFraction))
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
          ProgressView(value: installFraction.clamped01)
        }
      }

      // No cancel button while SharedCompassVM lacks a cancellation handle
      // for the IPSW download / VZ installer. Surface one here when the
      // host exposes it.
    }
    .padding(12)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
  }

  private func percentLabel(_ fraction: Double) -> String {
    let pct = Int((fraction.clamped01 * 100).rounded())
    return "\(pct)%"
  }
}

/// Passive status panel shown while the planted LaunchDaemon finishes its
/// work inside the freshly-booted guest. There is nothing for the user to
/// click — `SharedCompassVM` is polling SSH in the background and will
/// transition readiness to `.ready` on its own.
private struct SandboxHeadlessFirstBootSection: View {
  @ObservedObject var vmHost: SharedCompassVM

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Finishing macOS setup", systemImage: "gearshape.2")
        .font(.subheadline.weight(.semibold))
      Text(
        "Compass is finishing the workspace account and secure command access. This usually takes 30 to 90 seconds."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      ProgressView()
        .progressViewStyle(.linear)

      if let failure = vmHost.setupFailureMessage {
        SandboxSetupFailureBanner(message: failure)
      }
    }
    .padding(12)
    .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.tint.opacity(0.25)))
  }
}

/// Inline error banner for a recent setup-probe failure during first-boot
/// finalisation. Cleared on the next probe attempt.
private struct SandboxSetupFailureBanner: View {
  let message: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Color.orange)
      Text(message)
        .font(.caption)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.30)))
  }
}

private struct SandboxConsoleLoginSection: View {
  let login: SharedCompassVMGuestCredential.GuestConsoleLogin
  let vmIsRunning: Bool

  @State private var didCopyPassword = false
  @State private var didCopyUserName = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Console login", systemImage: "person.crop.circle")
        .font(.subheadline.weight(.semibold))

      Text(
        vmIsRunning
          ? "If the embedded workspace shows a login screen instead of a desktop, sign in with these credentials. Compass normally signs in automatically; use this when it does not."
          : "When the workspace is running, sign in with these credentials if automatic sign-in did not complete."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        Text("Username")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(width: 72, alignment: .leading)
        Text(login.userName)
          .font(.callout.monospaced())
          .textSelection(.enabled)
        Spacer(minLength: 0)
        Button(didCopyUserName ? "Copied" : "Copy") {
          copyRuntimeDiagnosticsToPasteboard(login.userName)
          didCopyUserName = true
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyUserName = false
          }
        }
        .buttonStyle(.borderless)
        .font(.caption)
      }

      HStack(spacing: 8) {
        Text("Password")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(width: 72, alignment: .leading)
        Text(String(repeating: "•", count: min(login.password.count, 16)))
          .font(.callout.monospaced())
        Spacer(minLength: 0)
        Button(didCopyPassword ? "Copied" : "Copy password") {
          copyRuntimeDiagnosticsToPasteboard(login.password)
          didCopyPassword = true
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyPassword = false
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(12)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
  }
}

private struct SandboxReadySection: View {
  let sshDestination: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Private workspace ready", systemImage: "checkmark.seal.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.green)
      Text("Develop work now runs away from your main checkout using Compass's saved workspace connection.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .padding(12)
    .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.25)))
  }
}

private struct SandboxIdleSection: View {
  @ObservedObject var vmHost: SharedCompassVM

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Private workspace not installed", systemImage: "shippingbox")
        .font(.subheadline.weight(.semibold))
      Text(
        "Compass can set up a private macOS workspace for Develop. First setup downloads about 14 GB and can take 30 to 50 minutes."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      Button {
        Task {
          do {
            try await vmHost.provisionIfNeeded()
            try await vmHost.start()
          } catch {
            // Errors are reflected in `vmHost.readiness`; the
            // top-level status chip surfaces them.
          }
        }
      } label: {
        Label("Set Up Workspace", systemImage: "play.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(vmHost.readiness.isUnavailable)
      SandboxLocalIPSWButton(vmHost: vmHost)
    }
    .padding(12)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
  }
}

private struct SandboxUnavailableSection: View {
  let reason: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Private workspace unavailable", systemImage: "exclamationmark.triangle.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.orange)
      Text(SandboxReadinessCopy.userFacingInfrastructureDetail(reason, limit: 260))
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.30)))
  }
}

private struct SandboxErrorSection: View {
  let detail: String
  @ObservedObject var vmHost: SharedCompassVM

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Private workspace needs repair", systemImage: "xmark.octagon.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.red)
      Text(SandboxReadinessCopy.userFacingInfrastructureDetail(detail, limit: 300))
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      SandboxLocalIPSWButton(
        vmHost: vmHost,
        title: "Rebuild with downloaded restore image",
        rebuildBeforeProvisioning: true
      )
      SandboxResetVMButton(vmHost: vmHost)
    }
    .padding(12)
    .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.30)))
  }
}

// MARK: - Local IPSW picker button

private struct SandboxLocalIPSWButton: View {
  @ObservedObject var vmHost: SharedCompassVM
  var title: String = "Use downloaded restore image"
  var rebuildBeforeProvisioning: Bool = false

  var body: some View {
    Button {
      let panel = NSOpenPanel()
      panel.title = "Select a macOS restore image"
      panel.allowedContentTypes = [UTType(filenameExtension: "ipsw") ?? .data]
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      guard panel.runModal() == .OK, let url = panel.url else { return }
      if rebuildBeforeProvisioning, !Self.confirmRebuild() {
        return
      }
      Task {
        do {
          if rebuildBeforeProvisioning {
            try await vmHost.rebuild(localIPSWURL: url)
          } else {
            try await vmHost.provisionIfNeeded(localIPSWURL: url)
            try await vmHost.start()
          }
        } catch {
          // Errors surface through vmHost.readiness.
        }
      }
    } label: {
      Label(title, systemImage: "doc.badge.arrow.up")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .help(
      "Select a macOS restore image (.ipsw) you have already downloaded. Use this if Compass cannot fetch the download automatically."
    )
  }

  private static func confirmRebuild() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Rebuild private workspace?"
    alert.informativeText =
      "This removes the partially installed workspace disk and starts installation again. Cached macOS downloads and secure connection keys are preserved."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Rebuild")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}

private struct SandboxResetVMButton: View {
  @ObservedObject var vmHost: SharedCompassVM

  var body: some View {
    Button(role: .destructive) {
      guard confirmReset() else { return }
      Task {
        do {
          try await vmHost.resetProvisioningArtifacts()
        } catch {
          // Errors surface through vmHost.readiness.
        }
      }
    } label: {
      Label("Reset workspace files", systemImage: "trash")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .help(
      "Remove installed workspace files while preserving cached macOS downloads and secure connection keys."
    )
  }

  private func confirmReset() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Reset private workspace files?"
    alert.informativeText =
      "This removes the workspace disk, auxiliary storage, platform identity, and stale connection trust. Cached macOS downloads and secure connection keys are preserved."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Reset")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}

// MARK: - Shared readiness dot

/// Sidebar-friendly readiness indicator. Reused by the sidebar header status
/// pill so the meaning stays consistent across the app.
struct SandboxReadinessDot: View {
  let readiness: SharedCompassVMReadiness
  var size: CGFloat = 9

  var body: some View {
    Circle()
      .fill(readiness.tintColor)
      .frame(width: size, height: size)
      .overlay(
        Circle().stroke(readiness.tintColor.opacity(0.35), lineWidth: 1)
      )
  }
}

// MARK: - Readiness display helpers

extension SharedCompassVMReadiness {
  /// Identity used by SandboxView's `.task(id:)` modifier to auto-start
  /// the VM once provisioning lands at `.guestPrepping` (the post-plant
  /// state in the headless first-boot pipeline). Stable string per state
  /// — switching to anything else cancels the auto-start task.
  var headlessAutoStartToken: String {
    if case .guestPrepping = self {
      return "guestPrepping"
    }
    return "inactive"
  }

  /// Single-line status summary suitable for the workspace header subtitle.
  var statusSummary: String {
    switch self {
    case .unavailable(let reason):
      return "Unavailable. \(SandboxReadinessCopy.userFacingInfrastructureDetail(reason, limit: 180))"
    case .notProvisioned:
      return "Not installed"
    case .downloadingIPSW(let fraction):
      let pct = Int((fraction.clamped01 * 100).rounded())
      return "Downloading macOS (\(pct)%)"
    case .installing(let fraction):
      let pct = Int((fraction.clamped01 * 100).rounded())
      return "Installing macOS (\(pct)%)"
    case .guestPrepping:
      return "Finishing workspace setup"
    case .provisioningDevTools(let fraction):
      let pct = Int((fraction.clamped01 * 100).rounded())
      return "Installing developer tools (\(pct)%)"
    case .ready:
      return "Ready"
    case .error(let detail):
      return "Error. \(SandboxReadinessCopy.userFacingInfrastructureDetail(detail, limit: 180))"
    }
  }

  /// Short label for the floating status chip overlay.
  var chipLabel: String {
    switch self {
    case .unavailable: return "Unavailable"
    case .notProvisioned: return "Not provisioned"
    case .downloadingIPSW: return "Downloading"
    case .installing: return "Installing"
    case .guestPrepping: return "Preparing"
    case .provisioningDevTools: return "Installing tools"
    case .ready: return "Ready"
    case .error: return "Error"
    }
  }

  /// Color used by the dot indicator and surrounding chrome.
  var tintColor: Color {
    switch self {
    case .ready:
      return .green
    case .downloadingIPSW, .installing, .guestPrepping, .provisioningDevTools:
      return .blue
    case .unavailable:
      return .orange
    case .error:
      return .red
    case .notProvisioned:
      return .secondary
    }
  }

  var systemImage: String {
    switch self {
    case .ready: return "checkmark.seal.fill"
    case .downloadingIPSW: return "arrow.down.circle"
    case .installing: return "internaldrive"
    case .guestPrepping: return "gearshape.2"
    case .provisioningDevTools: return "hammer"
    case .unavailable: return "exclamationmark.triangle"
    case .error: return "xmark.octagon"
    case .notProvisioned: return "shippingbox"
    }
  }

  var placeholderTitle: String {
    switch self {
    case .ready: return "Private workspace is ready"
    case .downloadingIPSW: return "Downloading macOS"
    case .installing: return "Installing macOS"
    case .guestPrepping: return "Finishing workspace setup"
    case .provisioningDevTools: return "Installing developer tools"
    case .unavailable: return "Private workspace unavailable"
    case .error: return "Private workspace needs repair"
    case .notProvisioned: return "Private workspace not installed"
    }
  }

  var placeholderDetail: String {
    switch self {
    case .ready:
      return "The private workspace is ready, but no live view is attached yet."
    case .downloadingIPSW(let fraction):
      let pct = Int((fraction.clamped01 * 100).rounded())
      return "Fetching ~14 GB from Apple's CDN. \(pct)% complete."
    case .installing(let fraction):
      let pct = Int((fraction.clamped01 * 100).rounded())
      return "Installing macOS for the private workspace. \(pct)% complete."
    case .guestPrepping:
      return
        "Compass is creating the workspace account and enabling secure command access. It is polling for readiness."
    case .provisioningDevTools(let fraction):
      let pct = Int((fraction.clamped01 * 100).rounded())
      return
        "Installing Xcode Command Line Tools inside the workspace. One-time, about 5 minutes. \(pct)% complete."
    case .unavailable(let reason):
      return SandboxReadinessCopy.userFacingInfrastructureDetail(reason, limit: 260)
    case .error(let detail):
      return SandboxReadinessCopy.userFacingInfrastructureDetail(detail, limit: 260)
    case .notProvisioned:
      return "Set up the private workspace to enable isolated Develop iterations."
    }
  }
}

extension Double {
  fileprivate var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}

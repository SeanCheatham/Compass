import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Virtualization

/// Mandatory gate shown until both onboarding requirements are satisfied:
/// the Text provider can run, and the Shared VM has reached `.ready`.
/// The rest of the app is hidden behind this — there is no "skip" path,
/// because every agent run routes through the VM.
struct OnboardingView: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject private var vmHost: SharedCompassVM = .shared
  @ObservedObject private var localModelManager = LocalModelManager.shared
  @State private var readinessNarration: OnboardingReadinessGuideNarration?

  var body: some View {
    let readinessGuide = OnboardingReadinessGuide(
      settings: model.agentSettings,
      vmReadiness: vmHost.readiness,
      modelSnapshot: localModelManager.snapshot
    )
    let setupPayload = OnboardingSetupClipboardPayload(
      guide: readinessGuide,
      settings: model.agentSettings,
      vmReadiness: vmHost.readiness,
      modelSnapshot: localModelManager.snapshot
    )

    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        header
        if let message = model.errorMessage, !message.isEmpty {
          onboardingErrorBanner(message: message)
        }
        OnboardingReadinessGuidePanel(
          guide: readinessGuide,
          setupPayload: setupPayload,
          narration: matchingNarration(for: readinessGuide)
        )
        OnboardingStep(
          number: 1,
          title: "Download the local model",
          description:
            "Compass uses one approved MLX model on this Mac with no API key or hosted model provider.",
          isComplete: textProviderConfigured
        ) {
          LocalModelStepBody()
        }
        OnboardingStep(
          number: 2,
          title: "Prepare the private workspace",
          description:
            "Compass routes agent work through an isolated macOS workspace. First install downloads about 14 GB and runs for roughly 30-50 minutes; you only do this once.",
          isComplete: vmHost.readiness.isReady
        ) {
          SharedVMOnboardingPanel(vmHost: vmHost)
        }
        footer
      }
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
      .padding(28)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
    .task(id: vmHost.readiness.headlessAutoStartToken) {
      await autoStartHeadlessGuestIfNeeded()
    }
    .task(id: readinessGuide.narrationIdentifier) {
      readinessNarration = nil
      readinessNarration = await OnboardingReadinessGuideNarrator.narrate(
        guide: readinessGuide
      )
    }
  }

  /// Surfaces `AppModel.errorMessage` while the user is gated by onboarding.
  /// Without this, setup failures can look like a locked run button with no
  /// explanation.
  private func onboardingErrorBanner(message: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .padding(.top, 2)
      Text(message)
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange.opacity(0.35)))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        Image(systemName: "safari")
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(.tint)
        Text("Welcome to Compass")
          .font(.title.weight(.semibold))
      }
      Text("Finish two quick steps before using Compass.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  /// True when the Text capability is ready to drive a run. Mirrors
  /// `ContentView.isOnboardingComplete`'s Text-side check — see
  /// `AgentRuntimeSettings.isTextCapabilityReady`.
  private var textProviderConfigured: Bool {
    model.agentSettings.isTextCapabilityReady
  }

  @ViewBuilder
  private var footer: some View {
    let blockedByTextProvider = !textProviderConfigured
    let blockedByVM = !vmHost.readiness.isReady
    if blockedByTextProvider || blockedByVM {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "lock.fill")
          .foregroundStyle(.secondary)
          .padding(.top, 2)
        VStack(alignment: .leading, spacing: 4) {
          Text("Compass unlocks once both steps are complete.")
            .font(.callout.weight(.semibold))
          if blockedByTextProvider {
            Text("• \(textProviderBlockerText)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if blockedByVM {
            Text("• \(vmHost.readiness.privateWorkspaceStatusSummary).")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
  }

  private var textProviderBlockerText: String {
    "Download the blessed MLX model in Settings."
  }

  /// After provisioning lands at `.guestPrepping`, we need to kick the
  /// VZ instance so SharedCompassVM's poll loop can finalise readiness.
  /// Mirrors `SandboxView.autoStartHeadlessGuestIfNeeded`.
  private func autoStartHeadlessGuestIfNeeded() async {
    guard case .guestPrepping = vmHost.readiness, vmHost.virtualMachine == nil else { return }
    do {
      try await vmHost.start()
    } catch {
      // Errors surface through vmHost.readiness.
    }
  }

  private func matchingNarration(
    for guide: OnboardingReadinessGuide
  ) -> OnboardingReadinessGuideNarration? {
    guard readinessNarration?.guideIdentifier == guide.narrationIdentifier else {
      return nil
    }
    return readinessNarration
  }
}

private struct OnboardingReadinessGuidePanel: View {
  let guide: OnboardingReadinessGuide
  let setupPayload: OnboardingSetupClipboardPayload
  let narration: OnboardingReadinessGuideNarration?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(guide.title, systemImage: guide.systemImageName)
          .font(.headline)
          .foregroundStyle(color)

        Spacer(minLength: 8)

        CopySetupButton(payload: setupPayload)

        Text(guide.actionLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(color)
          .lineLimit(1)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(color.opacity(0.12), in: Capsule())
      }

      Text(narration?.text ?? guide.detail)
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      VStack(alignment: .leading, spacing: 7) {
        ForEach(guide.steps) { step in
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: step.isComplete ? "checkmark.circle.fill" : step.systemImageName)
              .foregroundStyle(step.isComplete ? .green : color)
              .frame(width: 18, height: 18)
              .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
              Text(step.label)
                .font(.caption.weight(.semibold))
              Text(step.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }

      Divider()
        .opacity(0.6)

      VStack(alignment: .leading, spacing: 7) {
        Label(unlockTitle, systemImage: "sparkles")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        ForEach(guide.unlockPreview) { unlock in
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: unlock.isUnlocked ? "checkmark.circle.fill" : unlock.systemImageName)
              .foregroundStyle(unlock.isUnlocked ? .green : color)
              .frame(width: 18, height: 18)
              .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
              Text(unlock.label)
                .font(.caption.weight(.semibold))
              Text(unlock.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }

      if narration != nil {
        Label("On-device setup note", systemImage: "sparkles")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(0.22))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(guide.title). \(narration?.text ?? guide.detail)")
  }

  private var unlockTitle: String {
    guide.unlockPreview.allSatisfy { $0.isUnlocked } ? "Unlocked now" : "Unlocks after setup"
  }

  private var color: Color {
    switch guide.tone {
    case .ready:
      return .green
    case .needsText:
      return .orange
    case .needsWorkspace:
      return .blue
    case .inProgress:
      return .teal
    }
  }
}

private struct CopySetupButton: View {
  var payload: OnboardingSetupClipboardPayload
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
        copied ? "Copied" : "Copy Setup",
        systemImage: copied ? "checkmark" : "doc.on.doc"
      )
      .lineLimit(1)
    }
    .controlSize(.small)
    .disabled(payload.isEmpty)
    .help(ClipboardHelpText.setup)
  }
}

// MARK: - Step wrapper

private struct OnboardingStep<Content: View>: View {
  let number: Int
  let title: String
  let description: String
  let isComplete: Bool
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        stepBadge
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.title3.weight(.semibold))
          Text(description)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
      }
      content()
        .padding(.leading, 40)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      (isComplete ? Color.green : Color.accentColor).opacity(0.07),
      in: RoundedRectangle(cornerRadius: 10)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke((isComplete ? Color.green : Color.accentColor).opacity(0.22))
    }
  }

  private var stepBadge: some View {
    ZStack {
      Circle()
        .fill((isComplete ? Color.green : Color.accentColor).opacity(0.18))
        .frame(width: 28, height: 28)
      Group {
        if isComplete {
          Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.green)
        } else {
          Text("\(number)")
            .font(.callout.weight(.bold))
            .foregroundStyle(Color.accentColor)
        }
      }
    }
    .accessibilityHidden(true)
  }
}

// MARK: - Local model step

private struct LocalModelStepBody: View {
  @ObservedObject private var localModelManager = LocalModelManager.shared

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: localModelManager.snapshot.isRunnable ? "cpu" : "arrow.down.circle")
        .foregroundStyle(localModelManager.snapshot.isRunnable ? Color.accentColor : .orange)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 4) {
        Text(localModelManager.snapshot.isRunnable ? "MLX model ready" : "MLX model missing")
          .font(.callout.weight(.semibold))
        Text(
          "\(localModelManager.snapshot.modelID) is \(localModelManager.snapshot.statusLabel.lowercased())."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        HStack {
          Button {
            localModelManager.downloadBlessedModel()
          } label: {
            Label("Download", systemImage: "arrow.down.circle")
          }
          .disabled(localModelManager.isDownloadActive || localModelManager.snapshot.isRunnable)

          Button {
            localModelManager.cancelDownload()
          } label: {
            Label("Cancel", systemImage: "xmark.circle")
          }
          .disabled(!localModelManager.isDownloadActive)

          SettingsLink {
            Label("Runtime Settings", systemImage: "gearshape")
          }
        }
      }
      Spacer()
    }
    .onAppear {
      localModelManager.refresh()
    }
  }
}

// MARK: - Shared VM step

enum OnboardingWorkspaceRecoveryCopy {
  static let resetButtonTitle = "Reset workspace"
  static let resetHelp =
    "Remove installed private workspace files while keeping the cached macOS download and Compass's secure connection keys."
  static let resetAlertTitle = "Reset private workspace?"
  static let resetAlertDetail =
    "Compass removes the workspace disk, saved workspace identity, and old connection records. The cached macOS download and Compass's secure connection keys are preserved."

  static let localRestoreButtonTitle = "Use downloaded restore file"
  static let localRestoreHelp =
    "Select a macOS restore image (.ipsw) you have already downloaded. Use this if Compass cannot fetch Apple's restore image automatically."

  static let rebuildButtonTitle = "Rebuild with downloaded file"
  static let rebuildAlertTitle = "Rebuild private workspace?"
  static let rebuildAlertDetail =
    "Compass removes the partially installed workspace disk and starts installation again. The cached macOS download and Compass's secure connection keys are preserved."
}

private struct SharedVMOnboardingPanel: View {
  @ObservedObject var vmHost: SharedCompassVM

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      statusRow

      switch vmHost.readiness {
      case .notProvisioned:
        provisionActions
      case .downloadingIPSW(let fraction):
        progressSection(
          title: "Downloading macOS restore image",
          systemImage: "arrow.down.circle",
          primaryLabel: "Restore image",
          primary: fraction
        )
      case .installing(let fraction):
        progressSection(
          title: "Installing macOS",
          systemImage: "internaldrive",
          primaryLabel: "Restore image",
          primary: 1.0,
          secondaryLabel: "Installer",
          secondary: fraction
        )
      case .guestPrepping:
        guestPreppingSection
      case .provisioningDevTools(let fraction):
        progressSection(
          title: "Installing developer tools",
          systemImage: "hammer",
          primaryLabel: "Restore image",
          primary: 1.0,
          secondaryLabel: "Command Line Tools",
          secondary: fraction
        )
      case .ready:
        readySection
      case .unavailable(let reason):
        unavailableSection(reason: reason)
      case .error(let detail):
        errorSection(detail: detail)
      }

      // Surface the VZ display while a live VM is up so the user
      // can see the install screen. Hidden once readiness flips to
      // `.ready`, since the step badge already shows completion.
      if let virtualMachine = vmHost.virtualMachine, !vmHost.readiness.isReady {
        SharedCompassVMView(virtualMachine: virtualMachine)
          .frame(minHeight: 320)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay {
            RoundedRectangle(cornerRadius: 8)
              .stroke(Color.secondary.opacity(0.2))
          }
      }
    }
  }

  private var statusRow: some View {
    HStack(spacing: 8) {
      SandboxReadinessDot(readiness: vmHost.readiness, size: 10)
      Text(vmHost.readiness.privateWorkspaceStatusSummary)
        .font(.callout.weight(.medium))
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
    }
  }

  private var provisionActions: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        "Downloads about 14 GB from Apple's CDN and installs the private macOS workspace. You can keep using your Mac while it runs."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 10) {
        Button {
          Task {
            do {
              try await vmHost.provisionIfNeeded()
              try await vmHost.start()
            } catch {
              // Errors surface through vmHost.readiness.
            }
          }
        } label: {
          Label("Prepare Workspace", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(vmHost.readiness.isUnavailable)

        OnboardingLocalIPSWButton(vmHost: vmHost)
      }
    }
  }

  @ViewBuilder
  private func progressSection(
    title: String,
    systemImage: String,
    primaryLabel: String,
    primary: Double,
    secondaryLabel: String? = nil,
    secondary: Double? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: systemImage)
        .font(.subheadline.weight(.semibold))
      progressBar(label: primaryLabel, fraction: primary)
      if let secondaryLabel, let secondary {
        progressBar(label: secondaryLabel, fraction: secondary)
      }
    }
  }

  private func progressBar(label: String, fraction: Double) -> some View {
    let clamped = min(1, max(0, fraction))
    return VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(label)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Text("\(Int((clamped * 100).rounded()))%")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      ProgressView(value: clamped)
    }
  }

  private var guestPreppingSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Finishing macOS setup", systemImage: "gearshape.2")
        .font(.subheadline.weight(.semibold))
      Text(
        "Compass is finishing access to the private workspace so future agent runs can start safely. This usually takes 30-90 seconds."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      ProgressView().progressViewStyle(.linear)
      if let failure = vmHost.setupFailureMessage {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.orange)
          Text(failure)
            .font(.caption)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
      }
    }
  }

  private var readySection: some View {
    Label("Private workspace is ready.", systemImage: "checkmark.seal.fill")
      .font(.callout.weight(.semibold))
      .foregroundStyle(Color.green)
  }

  private func unavailableSection(reason: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(
        "Private workspace unavailable on this Mac", systemImage: "exclamationmark.triangle.fill"
      )
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(Color.orange)
      Text(reason)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Text(
        "Compass routes every agent run through the private workspace, so it can't continue until this resolves. Apple-Silicon hardware on a supported macOS version is required."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func errorSection(detail: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Private workspace error", systemImage: "xmark.octagon.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.red)
      Text(detail)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 10) {
        OnboardingLocalIPSWButton(
          vmHost: vmHost,
          title: OnboardingWorkspaceRecoveryCopy.rebuildButtonTitle,
          rebuildBeforeProvisioning: true
        )
        Button(role: .destructive) {
          guard Self.confirmReset() else { return }
          Task {
            try? await vmHost.resetProvisioningArtifacts()
          }
        } label: {
          Label(OnboardingWorkspaceRecoveryCopy.resetButtonTitle, systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .help(OnboardingWorkspaceRecoveryCopy.resetHelp)
      }
    }
  }

  private static func confirmReset() -> Bool {
    let alert = NSAlert()
    alert.messageText = OnboardingWorkspaceRecoveryCopy.resetAlertTitle
    alert.informativeText = OnboardingWorkspaceRecoveryCopy.resetAlertDetail
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Reset")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}

private struct OnboardingLocalIPSWButton: View {
  @ObservedObject var vmHost: SharedCompassVM
  var title: String = OnboardingWorkspaceRecoveryCopy.localRestoreButtonTitle
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
    }
    .buttonStyle(.bordered)
    .help(OnboardingWorkspaceRecoveryCopy.localRestoreHelp)
  }

  private static func confirmRebuild() -> Bool {
    let alert = NSAlert()
    alert.messageText = OnboardingWorkspaceRecoveryCopy.rebuildAlertTitle
    alert.informativeText = OnboardingWorkspaceRecoveryCopy.rebuildAlertDetail
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Rebuild")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}

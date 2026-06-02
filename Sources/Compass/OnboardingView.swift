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
  @State private var readinessNarration: OnboardingReadinessGuideNarration?

  var body: some View {
    let foundationModelsAvailable = FoundationModelsAvailability.isAvailable
    let readinessGuide = OnboardingReadinessGuide(
      settings: model.agentSettings,
      vmReadiness: vmHost.readiness,
      foundationModelsAvailable: foundationModelsAvailable
    )
    let setupPayload = OnboardingSetupClipboardPayload(
      guide: readinessGuide,
      settings: model.agentSettings,
      vmReadiness: vmHost.readiness,
      foundationModelsAvailable: foundationModelsAvailable
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
          title: "Choose a Text provider",
          description:
            "Compass can use Apple Intelligence on this Mac with no API key. You can also choose a cloud Text provider like MiniMax Token or OpenAI API from Settings.",
          isComplete: textProviderConfigured
        ) {
          if model.agentSettings.textProvider.requiresCredentials {
            APIKeyStepBody()
          } else {
            FoundationModelsStepBody(isAvailable: foundationModelsAvailable)
          }
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
  /// Without this, a failed write to the secrets file (permissions, full
  /// disk) silently zeroed the API key field on every paste, so the user
  /// couldn't tell why the field kept "clearing".
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
    if model.agentSettings.textProvider == .appleFoundationModels {
      return
        "Apple Intelligence is unavailable; switch Text provider in Settings."
    }
    return "Add an API key for \(model.agentSettings.textProvider.displayName)."
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
    .help("Copy a bounded setup handoff for another model or teammate.")
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

// MARK: - API key step

private struct APIKeyStepBody: View {
  @EnvironmentObject private var model: AppModel
  /// Local mirror of the API key. SwiftUI's `SecureField` on macOS wraps
  /// `NSSecureTextField`, whose `stringValue` is intentionally unreadable
  /// for security. Paste/typing events don't always round-trip the bound
  /// value cleanly, and submit (Return / focus loss) sometimes re-fires
  /// the setter with an empty string. We hold the typed value here and
  /// only push to the model on real, non-empty changes — plus expose an
  /// explicit Save button so the user always has a deterministic way to
  /// commit the field even if SwiftUI's auto-propagation misses a paste.
  @State private var apiKey: String = ""
  @State private var baseURL: String = ""

  private var apiKeyMatchesModel: Bool {
    apiKey == model.agentSettings.apiKey
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Base URL")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        TextField("Base URL", text: $baseURL)
          .textFieldStyle(.roundedBorder)
          .help(
            "Chat API endpoint for this provider. Default: \(AgentRuntimeSettings.defaultBaseURLString)"
          )
          .onChange(of: baseURL) { _, newValue in
            guard newValue != model.agentSettings.baseURL.absoluteString else { return }
            model.setAgentBaseURL(newValue)
          }
      }

      VStack(alignment: .leading, spacing: 4) {
        Text("API key")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        HStack(spacing: 8) {
          // Deliberately a plain TextField, not a SecureField:
          // macOS `NSSecureTextField` keeps pasted text in an
          // internal secure buffer that SwiftUI's binding can't
          // reread, so pastes silently failed to reach the model
          // (the field showed dots, but `@State apiKey` stayed
          // empty and Save had nothing to commit). Onboarding is
          // a one-shot, gated flow — once the key is saved the
          // gate unlocks and this field is gone — so showing it
          // in plaintext during entry is an acceptable trade
          // for entering it correctly the first time. Settings
          // (⌘,) keeps the SecureField for ongoing edits.
          TextField("sk-…", text: $apiKey)
            .textFieldStyle(.roundedBorder)
            .help("Stored in a 0600 file under ~/Library/Application Support/Compass.")
            .onSubmit {
              commitAPIKey()
            }
            .onChange(of: apiKey) { _, newValue in
              guard !newValue.isEmpty else { return }
              guard newValue != model.agentSettings.apiKey else { return }
              model.setAgentAPIKey(newValue)
            }
          Button("Save") {
            commitAPIKey()
          }
          .disabled(apiKey.isEmpty || apiKeyMatchesModel)
          .keyboardShortcut(.defaultAction)
        }
        if !apiKey.isEmpty && !apiKeyMatchesModel {
          Text("Click Save (or press Return) to store this key.")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }

      Text(
        "Visible while you enter it, then stored in a 0600 file under ~/Library/Application Support/Compass. Change later from Compass → Settings… (⌘,)."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .onAppear {
      apiKey = model.agentSettings.apiKey
      baseURL = model.agentSettings.baseURL.absoluteString
    }
    // If something else updates the model (env-var fallback, Settings
    // window, etc.) while onboarding is visible, refresh the local
    // mirrors so they don't drift out of sync.
    .onChange(of: model.agentSettings.apiKey) { _, newValue in
      if apiKey != newValue { apiKey = newValue }
    }
    .onChange(of: model.agentSettings.baseURL.absoluteString) { _, newValue in
      if baseURL != newValue { baseURL = newValue }
    }
  }

  private func commitAPIKey() {
    guard !apiKey.isEmpty else { return }
    guard apiKey != model.agentSettings.apiKey else { return }
    model.setAgentAPIKey(apiKey)
  }
}

// MARK: - Foundation Models step

/// Replaces the API-key field when the Text capability is wired to
/// Apple's on-device Foundation Models. There is nothing for the
/// user to enter — selecting a different provider happens via the
/// Settings screen — so this just confirms the default and points
/// at where to switch.
private struct FoundationModelsStepBody: View {
  var isAvailable: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: isAvailable ? "cpu" : "exclamationmark.triangle.fill")
        .foregroundStyle(isAvailable ? Color.accentColor : .orange)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 4) {
        Text(isAvailable ? "Using Apple Intelligence" : "Apple Intelligence unavailable")
          .font(.callout.weight(.semibold))
        if isAvailable {
          Text(
            "Runs on this Mac with no API key. Switch to MiniMax Token or OpenAI API in Settings (⌘,) if you want Text to use a cloud provider."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        } else {
          Text(
            "The on-device Text provider cannot run on this Mac right now. Choose MiniMax Token or OpenAI API in Settings, or enable Apple Intelligence if supported."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          SettingsLink {
            Label("Open Text Provider Settings", systemImage: "gearshape")
          }
        }
      }
      Spacer()
    }
  }
}

// MARK: - Shared VM step

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
      Label("Private workspace unavailable on this Mac", systemImage: "exclamationmark.triangle.fill")
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
          title: "Rebuild with local IPSW",
          rebuildBeforeProvisioning: true
        )
        Button(role: .destructive) {
          guard Self.confirmReset() else { return }
          Task {
            try? await vmHost.resetProvisioningArtifacts()
          }
        } label: {
          Label("Reset workspace artifacts", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .help(
          "Remove installed workspace artifacts while preserving cached restore images and Compass SSH keys."
        )
      }
    }
  }

  private static func confirmReset() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Reset private workspace artifacts?"
    alert.informativeText =
      "This removes the workspace disk, auxiliary storage, platform identity, and stale SSH trust. Cached restore images and Compass SSH keys are preserved."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Reset")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}

private struct OnboardingLocalIPSWButton: View {
  @ObservedObject var vmHost: SharedCompassVM
  var title: String = "Use local IPSW file"
  var rebuildBeforeProvisioning: Bool = false

  var body: some View {
    Button {
      let panel = NSOpenPanel()
      panel.title = "Select a macOS IPSW restore image"
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
    .help(
      "Select a macOS restore image (.ipsw) you've already downloaded. Bypasses Apple's catalog service."
    )
  }

  private static func confirmRebuild() -> Bool {
    let alert = NSAlert()
    alert.messageText = "Rebuild private workspace?"
    alert.informativeText =
      "This removes the partially installed workspace disk and starts installation again. Cached restore images and Compass SSH keys are preserved."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Rebuild")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }
}

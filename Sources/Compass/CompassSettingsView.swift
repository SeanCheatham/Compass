import SwiftUI

struct CompassSettingsView: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    TabView {
      AgentSettingsTab()
        .environmentObject(model)
        .tabItem { Label("Agent", systemImage: "bolt.horizontal") }

      ProductTournamentSettingsTab()
        .environmentObject(model)
        .tabItem { Label("Tournament", systemImage: "trophy") }
    }
    .frame(minWidth: 580, minHeight: 520)
  }
}

// MARK: - Agent tab

private struct AgentSettingsTab: View {
  @EnvironmentObject var model: AppModel
  @State private var settingsNarration: AgentSettingsGuideNarration?

  var body: some View {
    let settingsGuide = AgentSettingsGuide(
      settings: model.agentSettings,
      foundationModelsAvailable: FoundationModelsAvailability.isAvailable
    )
    let settingsPayload = AgentSettingsClipboardPayload(
      settings: model.agentSettings,
      guide: settingsGuide,
      foundationModelsAvailable: FoundationModelsAvailability.isAvailable
    )

    Form {
      Section {
        AgentSettingsGuidePanel(
          guide: settingsGuide,
          clipboardPayload: settingsPayload,
          narration: matchingNarration(for: settingsGuide)
        )
      }

      ForEach(AgentCapability.allCases, id: \.self) { capability in
        capabilitySection(for: capability)
      }

      Section {
        Text(
          "Settings persist per (capability, provider) cell — switching providers preserves each cell's key and models. Environment variables `COMPASS_AGENT_BASE_URL`, `COMPASS_AGENT_API_KEY`, and `COMPASS_AGENT_MODEL[_PLAN/_DEV/_REFLECT/_CRITIC]` seed the active Text provider's fields when empty."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding()
    .task(id: settingsGuide.narrationIdentifier) {
      settingsNarration = nil
      settingsNarration = await AgentSettingsGuideNarrator.narrate(guide: settingsGuide)
    }
  }

  private func matchingNarration(
    for guide: AgentSettingsGuide
  ) -> AgentSettingsGuideNarration? {
    guard settingsNarration?.guideIdentifier == guide.narrationIdentifier else {
      return nil
    }
    return settingsNarration
  }

  @ViewBuilder
  private func capabilitySection(for capability: AgentCapability) -> some View {
    Section(header: Label(capability.displayName, systemImage: capability.systemImageName)) {
      providerPicker(for: capability)
      if let provider = model.agentSettings.selectedProvider(for: capability),
        provider.requiresCredentials
      {
        cellCredentialsFields(capability: capability, provider: provider)
        cellModelFields(capability: capability, provider: provider)
      } else if let provider = model.agentSettings.selectedProvider(for: capability),
        !provider.requiresCredentials
      {
        Text(onDeviceHint(for: provider))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func providerPicker(for capability: AgentCapability) -> some View {
    let options = providerOptions(for: capability)
    Picker(
      "Provider",
      selection: Binding(
        get: { model.agentSettings.selectedProvider(for: capability) },
        set: { model.setProvider($0, for: capability) }
      )
    ) {
      ForEach(options, id: \.tagID) { option in
        Text(option.label).tag(option.provider as AgentProviderKind?)
      }
    }
    .pickerStyle(.menu)
  }

  @ViewBuilder
  private func cellCredentialsFields(
    capability: AgentCapability, provider: AgentProviderKind
  ) -> some View {
    TextField(
      "Base URL",
      text: Binding(
        get: { model.agentSettings.baseURLString(for: capability, provider: provider) },
        set: { model.setCellBaseURL($0, capability: capability, provider: provider) }
      )
    )
    .textFieldStyle(.roundedBorder)
    .help(
      "OpenAI-compatible endpoint for \(provider.displayName). Default: \(provider.defaultBaseURLString ?? "—")"
    )

    SecureField(
      "API key",
      text: Binding(
        get: { model.agentSettings.apiKey(for: capability, provider: provider) },
        set: { model.setCellAPIKey($0, capability: capability, provider: provider) }
      )
    )
    .textFieldStyle(.roundedBorder)
    .help(
      "Stored in a 0600 file under ~/Library/Application Support/Compass, scoped to this \(capability.displayName) + \(provider.displayName) cell."
    )
  }

  @ViewBuilder
  private func cellModelFields(
    capability: AgentCapability, provider: AgentProviderKind
  ) -> some View {
    if provider.usesModelField(for: capability) {
      if capability == .text, provider == .minimaxToken {
        minimaxVersionPicker()
      } else {
        let placeholder = provider.defaultModel(for: capability) ?? "—"
        TextField(
          "\(capability == .text ? "Default model" : "\(capability.displayName) model")",
          text: Binding(
            get: { model.agentSettings.model(for: capability, provider: provider) },
            set: { model.setCellModel($0, capability: capability, provider: provider) }
          )
        )
        .textFieldStyle(.roundedBorder)
        .help("Default for \(provider.displayName): \(placeholder)")
      }
    } else {
      Text("\(provider.displayName) uses a fixed \(capability.displayName) service endpoint.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    if capability == .text {
      ForEach(AgentPhase.allCases, id: \.self) { phase in
        phaseModelField(phase, provider: provider)
      }
    }
  }

  @ViewBuilder
  private func minimaxVersionPicker() -> some View {
    Picker(
      "MiniMax version",
      selection: Binding(
        get: {
          MiniMaxTextModelVersion(modelIdentifier: model.agentSettings.model)
            ?? MiniMaxTextModelVersion.default
        },
        set: { version in
          model.setCellModel(
            version.modelIdentifier,
            capability: .text,
            provider: .minimaxToken
          )
        }
      )
    ) {
      ForEach(MiniMaxTextModelVersion.allCases) { version in
        Text(version.displayName).tag(version)
      }
    }
    .pickerStyle(.menu)
    .help("Selects the MiniMax text model and matching context window.")
  }

  @ViewBuilder
  private func phaseModelField(_ phase: AgentPhase, provider: AgentProviderKind) -> some View {
    if provider == .minimaxToken {
      minimaxPhaseModelPicker(phase)
    } else {
      TextField(
        "\(phaseLabel(phase)) model (optional)",
        text: Binding(
          get: {
            model.agentSettings.phaseOverride(phase, provider: provider) ?? ""
          },
          set: { model.setTextPhaseOverride(phase, $0, provider: provider) }
        )
      )
      .textFieldStyle(.roundedBorder)
      .help(phaseHelp(phase))
    }
  }

  @ViewBuilder
  private func minimaxPhaseModelPicker(_ phase: AgentPhase) -> some View {
    let defaultModel =
      model.agentSettings.textProvider.defaultModel(
        for: phase,
        baseModel: model.agentSettings.model
      ) ?? MiniMaxTextModelVersion.default.modelIdentifier
    Picker(
      "\(phaseLabel(phase)) model",
      selection: Binding(
        get: {
          minimaxPhaseSelection(for: phase)
        },
        set: { selection in
          switch selection {
          case .defaultRole:
            model.setTextPhaseOverride(phase, "", provider: .minimaxToken)
          case .version(let version):
            model.setTextPhaseOverride(
              phase,
              version.modelIdentifier,
              provider: .minimaxToken
            )
          }
        }
      )
    ) {
      Text("Default (\(defaultModel))").tag(MiniMaxPhaseModelSelection.defaultRole)
      ForEach(MiniMaxTextModelVersion.allCases) { version in
        Text(version.displayName).tag(MiniMaxPhaseModelSelection.version(version))
      }
    }
    .pickerStyle(.menu)
    .help(phaseHelp(phase))
  }

  private func minimaxPhaseSelection(for phase: AgentPhase) -> MiniMaxPhaseModelSelection {
    guard
      let raw = model.agentSettings.phaseOverride(phase, provider: .minimaxToken),
      let version = MiniMaxTextModelVersion(modelIdentifier: raw)
    else {
      return .defaultRole
    }
    return .version(version)
  }

  private enum MiniMaxPhaseModelSelection: Hashable {
    case defaultRole
    case version(MiniMaxTextModelVersion)
  }

  private struct ProviderOption {
    let provider: AgentProviderKind?
    let label: String
    var tagID: String { provider?.rawValue ?? "__none__" }
  }

  private func providerOptions(for capability: AgentCapability) -> [ProviderOption] {
    var out: [ProviderOption] = []
    if !capability.isRequired {
      out.append(ProviderOption(provider: nil, label: "None"))
    }
    out.append(
      contentsOf: capability.availableProviders.map {
        ProviderOption(provider: $0, label: $0.displayName)
      }
    )
    return out
  }

  private func onDeviceHint(for provider: AgentProviderKind) -> String {
    switch provider {
    case .appleFoundationModels:
      return
        "Runs on this Mac through Apple Intelligence. No API key or model name is needed; macOS selects the available on-device model."
    default:
      return ""
    }
  }

  private func phaseLabel(_ phase: AgentPhase) -> String {
    switch phase {
    case .plan: return "Plan"
    case .develop: return "Develop"
    case .reflect: return "Reflect"
    case .critic: return "Critic"
    }
  }

  private func phaseHelp(_ phase: AgentPhase) -> String {
    switch phase {
    case .plan:
      return
        "Optional override for the reasoning and architecture phase. Defaults to the 'Default model' when empty."
    case .develop:
      return
        "Optional override for the code implementation phase. Defaults to the 'Default model' when empty."
    case .reflect:
      return
        "Optional override for the iteration assessment phase. Defaults to the 'Default model' when empty."
    case .critic:
      return
        "Adversarial review pass that gates Develop output. Pointing this at a different / stronger model than Develop produces more independent critique."
    }
  }
}

private struct AgentSettingsGuidePanel: View {
  let guide: AgentSettingsGuide
  let clipboardPayload: AgentSettingsClipboardPayload
  let narration: AgentSettingsGuideNarration?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(guide.title, systemImage: guide.systemImageName)
          .font(.headline)
          .foregroundStyle(toneColor)

        Spacer(minLength: 8)

        CopyAgentSettingsButton(payload: clipboardPayload)

        Text(guide.actionLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(toneColor)
          .lineLimit(1)
      }

      Text(narration?.text ?? guide.detail)
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      VStack(alignment: .leading, spacing: 4) {
        Label(guide.runtimeCoverage.label, systemImage: "gauge.medium")
          .font(.caption.weight(.semibold))
          .foregroundStyle(toneColor)
        ProgressView(value: guide.runtimeCoverage.fraction)
          .tint(toneColor)
        Text(guide.runtimeCoverage.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 7) {
        ForEach(guide.rows) { row in
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: rowIconName(row))
              .foregroundStyle(rowColor(row))
              .frame(width: 18, height: 18)
              .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
              Text(row.label)
                .font(.caption.weight(.semibold))
              Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  private var toneColor: Color {
    switch guide.tone {
    case .ready: return .green
    case .blocked: return .red
    case .optionalAttention: return .orange
    }
  }

  private func rowIconName(_ row: AgentSettingsGuide.Row) -> String {
    switch row.status {
    case .ready: return "checkmark.circle.fill"
    case .blocked: return "xmark.octagon.fill"
    case .off: return "circle.slash"
    case .attention: return "exclamationmark.triangle.fill"
    }
  }

  private func rowColor(_ row: AgentSettingsGuide.Row) -> Color {
    switch row.status {
    case .ready: return .green
    case .blocked: return .red
    case .off: return .secondary
    case .attention: return .orange
    }
  }
}

private struct CopyAgentSettingsButton: View {
  var payload: AgentSettingsClipboardPayload
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
        copied ? "Copied" : "Copy Runtime",
        systemImage: copied ? "checkmark" : "doc.on.doc"
      )
      .lineLimit(1)
    }
    .controlSize(.small)
    .disabled(payload.isEmpty)
    .help(ClipboardHelpText.runtimeSettings)
  }
}

// MARK: - Product Tournament tab

private struct ProductTournamentSettingsTab: View {
  @EnvironmentObject var model: AppModel
  @State private var tournamentNarration: ProductTournamentSettingsGuideNarration?

  private var sortedProjects: [CompassProject] {
    model.projects.sorted {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
  }

  var body: some View {
    let tournamentGuide = ProductTournamentSettingsGuide(projects: tournamentGuideProjects)
    let tournamentPayload = ProductTournamentSettingsClipboardPayload(guide: tournamentGuide)

    Form {
      Section {
        ProductTournamentSettingsGuidePanel(
          guide: tournamentGuide,
          clipboardPayload: tournamentPayload,
          narration: matchingNarration(for: tournamentGuide)
        )
      }

      if sortedProjects.isEmpty {
        Section("Projects") {
          Text("Add a Git repository from the Compass sidebar to configure tournament verification options.")
            .foregroundStyle(.secondary)
        }
      } else {
        Section("Host Xcode Build/Test") {
          ForEach(sortedProjects) { project in
            ProductTournamentProjectHostXcodeRow(
              project: project,
              isSelected: model.selectedProjectID == project.id,
              recommendsHostXcode: ForgeProfileService.prefersHostXcodeBridge(in: project.repoURL),
              onToggle: { model.saveProjects() }
            )
          }
        }

        Section {
          Text(
            "Legacy imported SwiftPM and Xcode repositories can use this when Compass recommends it. Generated projects stay Rust-only and verify inside the private workspace without Host Xcode."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .formStyle(.grouped)
    .padding()
    .task(id: tournamentGuide.narrationIdentifier) {
      tournamentNarration = nil
      tournamentNarration = await ProductTournamentSettingsGuideNarrator.narrate(guide: tournamentGuide)
    }
  }

  private var tournamentGuideProjects: [ProductTournamentSettingsGuide.Project] {
    sortedProjects.map { project in
      ProductTournamentSettingsGuide.Project(
        id: project.id,
        displayName: project.displayName,
        hostXcodeBuildTestEnabled: project.hostXcodeBuildTestEnabled,
        recommendsHostXcode: ForgeProfileService.prefersHostXcodeBridge(in: project.repoURL),
        isSelected: model.selectedProjectID == project.id
      )
    }
  }

  private func matchingNarration(
    for guide: ProductTournamentSettingsGuide
  ) -> ProductTournamentSettingsGuideNarration? {
    guard tournamentNarration?.guideIdentifier == guide.narrationIdentifier else {
      return nil
    }
    return tournamentNarration
  }
}

private struct ProductTournamentSettingsGuidePanel: View {
  let guide: ProductTournamentSettingsGuide
  let clipboardPayload: ProductTournamentSettingsClipboardPayload
  let narration: ProductTournamentSettingsGuideNarration?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(guide.title, systemImage: guide.systemImageName)
          .font(.headline)
          .foregroundStyle(toneColor)

        Spacer(minLength: 8)

        CopyProductTournamentSettingsButton(payload: clipboardPayload)

        Text(guide.actionLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(toneColor)
          .lineLimit(1)
      }

      Text(narration?.text ?? guide.detail)
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      VStack(alignment: .leading, spacing: 4) {
        Label(guide.routingCoverage.label, systemImage: "checklist")
          .font(.caption.weight(.semibold))
          .foregroundStyle(toneColor)
        ProgressView(value: guide.routingCoverage.fraction)
          .tint(toneColor)
        Text(guide.routingCoverage.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 7) {
        ForEach(guide.rows) { row in
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: rowIconName(row))
              .foregroundStyle(rowColor(row))
              .frame(width: 18, height: 18)
              .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
              Text(row.label)
                .font(.caption.weight(.semibold))
              Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  private var toneColor: Color {
    switch guide.tone {
    case .ready: return .green
    case .attention: return .orange
    case .empty: return .secondary
    }
  }

  private func rowIconName(_ row: ProductTournamentSettingsGuide.Row) -> String {
    switch row.status {
    case .ready: return "checkmark.circle.fill"
    case .recommended: return "exclamationmark.triangle.fill"
    case .off: return "circle.slash"
    }
  }

  private func rowColor(_ row: ProductTournamentSettingsGuide.Row) -> Color {
    switch row.status {
    case .ready: return .green
    case .recommended: return .orange
    case .off: return .secondary
    }
  }
}

private struct CopyProductTournamentSettingsButton: View {
  var payload: ProductTournamentSettingsClipboardPayload
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
        copied ? "Copied" : "Copy Tournament",
        systemImage: copied ? "checkmark" : "doc.on.doc"
      )
      .lineLimit(1)
    }
    .controlSize(.small)
    .disabled(payload.isEmpty)
    .help(ClipboardHelpText.tournamentRouting)
  }
}

private struct ProductTournamentProjectHostXcodeRow: View {
  @ObservedObject var project: CompassProject
  var isSelected: Bool
  var recommendsHostXcode: Bool
  var onToggle: () -> Void

  var body: some View {
    Toggle(isOn: hostXcodeBinding) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(project.displayName)
            .font(.body.weight(.medium))
          if isSelected {
            Text("selected")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.quaternary, in: Capsule())
          }
          if recommendsHostXcode && !project.hostXcodeBuildTestEnabled {
            Text("recommended")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.orange)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.orange.opacity(0.15), in: Capsule())
          }
        }
        Text(project.repoURL.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .truncationMode(.middle)
      }
    }
    .help(
      "Route Swift and Xcode build/test through the host Mac. Required for reliable SwiftPM tests in the private workspace."
    )
  }

  private var hostXcodeBinding: Binding<Bool> {
    Binding(
      get: { project.hostXcodeBuildTestEnabled },
      set: { newValue in
        project.hostXcodeBuildTestEnabled = newValue
        onToggle()
      }
    )
  }
}

// MARK: - AgentRuntimeSettings UI helpers

extension AgentRuntimeSettings {
  /// Provider selected for `capability` based on this snapshot.
  /// For text this is always `textProvider`; for media capabilities
  /// it's derived from the matching `MediaAssignment` (nil = None).
  func selectedProvider(for capability: AgentCapability) -> AgentProviderKind? {
    switch capability {
    case .text: return textProvider
    case .webSearch: return webSearchAssignment?.provider
    case .imageUnderstanding: return imageUnderstandingAssignment?.provider
    case .image: return imageAssignment?.provider
    case .audio: return audioAssignment?.provider
    case .video: return videoAssignment?.provider
    }
  }

  /// Base URL string the UI shows for the `(capability, provider)`
  /// cell. Returns "" for cells whose provider does not require
  /// credentials (Foundation Models) or whose stored URL has not
  /// diverged from the provider default.
  func baseURLString(for capability: AgentCapability, provider: AgentProviderKind) -> String {
    guard provider.requiresCredentials else { return "" }
    if selectedProvider(for: capability) == provider {
      switch capability {
      case .text: return baseURL.absoluteString
      case .webSearch: return webSearchAssignment?.baseURL.absoluteString ?? ""
      case .imageUnderstanding: return imageUnderstandingAssignment?.baseURL.absoluteString ?? ""
      case .image: return imageAssignment?.baseURL.absoluteString ?? ""
      case .audio: return audioAssignment?.baseURL.absoluteString ?? ""
      case .video: return videoAssignment?.baseURL.absoluteString ?? ""
      }
    }
    return provider.defaultBaseURLString ?? ""
  }

  func apiKey(for capability: AgentCapability, provider: AgentProviderKind) -> String {
    guard provider.requiresCredentials else { return "" }
    if selectedProvider(for: capability) == provider {
      switch capability {
      case .text: return apiKey
      case .webSearch: return webSearchAssignment?.apiKey ?? ""
      case .imageUnderstanding: return imageUnderstandingAssignment?.apiKey ?? ""
      case .image: return imageAssignment?.apiKey ?? ""
      case .audio: return audioAssignment?.apiKey ?? ""
      case .video: return videoAssignment?.apiKey ?? ""
      }
    }
    return ""
  }

  func model(for capability: AgentCapability, provider: AgentProviderKind) -> String {
    guard provider.usesModelField(for: capability) else { return "" }
    if selectedProvider(for: capability) == provider {
      switch capability {
      case .text: return model
      case .webSearch: return webSearchAssignment?.model ?? ""
      case .imageUnderstanding: return imageUnderstandingAssignment?.model ?? ""
      case .image: return imageAssignment?.model ?? ""
      case .audio: return audioAssignment?.model ?? ""
      case .video: return videoAssignment?.model ?? ""
      }
    }
    return ""
  }

  func phaseOverride(_ phase: AgentPhase, provider: AgentProviderKind) -> String? {
    guard provider.requiresCredentials, textProvider == provider else { return nil }
    switch phase {
    case .plan: return planModelOverride
    case .develop: return developModelOverride
    case .reflect: return reflectModelOverride
    case .critic: return criticModelOverride
    }
  }
}

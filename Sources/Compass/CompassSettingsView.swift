import SwiftUI

struct CompassSettingsView: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    TabView {
      Form {
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
      .tabItem { Label("Agent", systemImage: "bolt.horizontal") }
    }
    .frame(minWidth: 580, minHeight: 520)
  }

  // MARK: - Per-capability sections

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

    if capability == .text {
      ForEach(AgentPhase.allCases, id: \.self) { phase in
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
  }

  // MARK: - Helpers

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
      })
    return out
  }

  private func onDeviceHint(for provider: AgentProviderKind) -> String {
    switch provider {
    case .appleFoundationModels:
      return "Runs on-device via Apple's Foundation Models framework. No API key or model identifier needed; the OS selects the available system model."
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
    case .critic:
      return
        "Adversarial review pass that gates Develop output. Pointing this at a different / stronger model than Develop produces more independent critique."
    default:
      return "Optional override; leaves \"Default model\" when empty."
    }
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
      case .image: return imageAssignment?.apiKey ?? ""
      case .audio: return audioAssignment?.apiKey ?? ""
      case .video: return videoAssignment?.apiKey ?? ""
      }
    }
    return ""
  }

  func model(for capability: AgentCapability, provider: AgentProviderKind) -> String {
    guard provider.requiresCredentials else { return "" }
    if selectedProvider(for: capability) == provider {
      switch capability {
      case .text: return model
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

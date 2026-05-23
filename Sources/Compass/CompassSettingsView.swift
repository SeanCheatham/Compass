import SwiftUI

struct CompassSettingsView: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    TabView {
      Form {
        Section(header: Text("Endpoint")) {
          TextField(
            "Base URL",
            text: Binding(
              get: { model.agentSettings.baseURL.absoluteString },
              set: { model.setAgentBaseURL($0) }
            )
          )
          .textFieldStyle(.roundedBorder)
          .help(
            "OpenAI-compatible chat completions endpoint. Default: \(AgentRuntimeSettings.defaultBaseURLString)"
          )

          SecureField(
            "API key",
            text: Binding(
              get: { model.agentSettings.apiKey },
              set: { model.setAgentAPIKey($0) }
            )
          )
          .textFieldStyle(.roundedBorder)
          .help("Stored in the macOS Keychain. Clearing this field removes the saved key.")
        }

        Section(header: Text("Model")) {
          TextField(
            "Default model",
            text: Binding(
              get: { model.agentSettings.model },
              set: { model.setAgentDefaultModel($0) }
            )
          )
          .textFieldStyle(.roundedBorder)
          .help(
            "Used for any phase that has no override. Default: \(AgentRuntimeSettings.defaultModelIdentifier)"
          )

          TextField(
            "Plan model (optional)",
            text: Binding(
              get: { model.agentSettings.planModelOverride ?? "" },
              set: { model.setAgentPlanModelOverride($0) }
            )
          )
          .textFieldStyle(.roundedBorder)

          TextField(
            "Develop model (optional)",
            text: Binding(
              get: { model.agentSettings.developModelOverride ?? "" },
              set: { model.setAgentDevelopModelOverride($0) }
            )
          )
          .textFieldStyle(.roundedBorder)

          TextField(
            "Reflect model (optional)",
            text: Binding(
              get: { model.agentSettings.reflectModelOverride ?? "" },
              set: { model.setAgentReflectModelOverride($0) }
            )
          )
          .textFieldStyle(.roundedBorder)
        }

        Section {
          Text(
            "These settings persist across launches. Environment variables `COMPASS_AGENT_BASE_URL`, `COMPASS_AGENT_API_KEY`, and `COMPASS_AGENT_MODEL[_PLAN/_DEV/_REFLECT]` seed empty fields on first launch."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .padding()
      .tabItem { Label("Agent", systemImage: "bolt.horizontal") }
    }
    .frame(minWidth: 540, minHeight: 420)
  }
}

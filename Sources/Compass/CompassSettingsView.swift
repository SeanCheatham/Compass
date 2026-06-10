import SwiftUI

struct CompassSettingsView: View {
  @EnvironmentObject var model: AppModel

  var body: some View {
    AgentSettingsTab()
      .environmentObject(model)
      .frame(minWidth: 580, minHeight: 420)
  }
}

private struct AgentSettingsTab: View {
  @EnvironmentObject var model: AppModel
  @ObservedObject private var localModelManager = LocalModelManager.shared
  @State private var settingsNarration: AgentSettingsGuideNarration?
  @AppStorage(AgentSettingsStore.Key.contextWindowTokens.rawValue)
  private var contextWindowTokens = "\(AgentRuntimeSettings.defaultContextWindowTokens)"

  var body: some View {
    let settingsGuide = AgentSettingsGuide(
      settings: model.agentSettings,
      modelSnapshot: localModelManager.snapshot
    )
    let settingsPayload = AgentSettingsClipboardPayload(
      settings: model.agentSettings,
      guide: settingsGuide,
      modelSnapshot: localModelManager.snapshot
    )

    Form {
      Section {
        AgentSettingsGuidePanel(
          guide: settingsGuide,
          clipboardPayload: settingsPayload,
          narration: matchingNarration(for: settingsGuide)
        )
      }

      Section(header: Label("Local Model", systemImage: "cpu")) {
        LabeledContent("Runtime", value: localModelManager.snapshot.runtimeName)
        LabeledContent("Model", value: localModelManager.snapshot.modelID)
        LabeledContent("Status", value: localModelManager.snapshot.statusLabel)
        LabeledContent("Storage", value: localModelManager.snapshot.directory.path)
          .textSelection(.enabled)
        LabeledContent("Credentials", value: "Not required")
        LabeledContent("Network calls", value: "Only approved model download")

        if let error = localModelManager.snapshot.errorMessage {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }

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

          Button(role: .destructive) {
            localModelManager.deleteBlessedModel()
          } label: {
            Label("Delete", systemImage: "trash")
          }
          .disabled(localModelManager.isDownloadActive || localModelManager.snapshot.status == .missing)

          Button {
            localModelManager.openModelFolder()
          } label: {
            Label("Open Model Folder", systemImage: "folder")
          }
        }

        if localModelManager.isDownloadActive {
          if let fraction = localModelManager.snapshot.progressFraction {
            ProgressView(value: fraction)
              .help("Downloading \(localModelManager.snapshot.modelID)")
          } else {
            ProgressView()
              .help("Downloading \(localModelManager.snapshot.modelID)")
          }
        }
      }

      Section(header: Label("Local Execution", systemImage: "cpu")) {
        TextField("Context window tokens", text: $contextWindowTokens)
          .textFieldStyle(.roundedBorder)
          .onSubmit {
            normalizeContextWindow()
          }
          .help("Used as the local planning budget for MLX prompts.")

        Text("Compass uses deterministic tools for files, shell commands, verification, and state updates. The model is only asked for narrow decomposition, implementation text, and review.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      localModelManager.refresh()
      contextWindowTokens = "\(model.agentSettings.contextWindowTokens)"
    }
    .onChange(of: contextWindowTokens) { _, _ in
      normalizeContextWindow()
    }
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

  private func normalizeContextWindow() {
    let trimmed = contextWindowTokens.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsed = Int(trimmed), parsed > 0 else {
      contextWindowTokens = "\(AgentRuntimeSettings.defaultContextWindowTokens)"
      model.setAgentContextWindowTokens(AgentRuntimeSettings.defaultContextWindowTokens)
      return
    }
    contextWindowTokens = "\(parsed)"
    model.setAgentContextWindowTokens(parsed)
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

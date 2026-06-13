import CompassSandbox
import SwiftUI
import CompassCore

struct ContainerRuntimeView: View {
  @State private var status: ContainerRuntimeStatus?
  @State private var isChecking = false
  @State private var isResetting = false
  @State private var lastError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      header

      VStack(alignment: .leading, spacing: 12) {
        LabeledContent("Runtime", value: "containerized Linux")
        LabeledContent("Image", value: status?.runtimeImage ?? "docker.io/library/node:22-bookworm")
        LabeledContent("Initfs", value: status?.initfsReference ?? "ghcr.io/apple/containerization/vminit:0.33.4")
        LabeledContent("Cache", value: ContainerizedLinuxSandbox.shared.stateRoot.path)
        if let kernelURL = status?.kernelURL {
          LabeledContent("Kernel", value: kernelURL.path)
        }
      }
      .textSelection(.enabled)

      HStack(spacing: 10) {
        Button {
          Task { await runSmokeTest() }
        } label: {
          Label("Smoke Test", systemImage: "checkmark.seal")
        }
        .disabled(isChecking || isResetting)

        Button(role: .destructive) {
          Task { await resetCache() }
        } label: {
          Label("Reset Cache", systemImage: "trash")
        }
        .disabled(isChecking || isResetting)
      }

      if let message = lastMessage {
        Text(message)
          .font(.callout)
          .foregroundStyle(status?.ok == false ? .red : .secondary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task {
      if status == nil {
        await runSmokeTest()
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: statusIcon)
        .font(.title2)
        .foregroundStyle(statusColor)
      VStack(alignment: .leading, spacing: 4) {
        Text("Container Runtime")
          .font(.title2.weight(.semibold))
        Text(statusSubtitle)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if isChecking || isResetting {
        ProgressView()
          .controlSize(.small)
      }
    }
  }

  private var statusIcon: String {
    if isChecking || isResetting { return "hourglass" }
    guard let status else { return "shippingbox" }
    return status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
  }

  private var statusColor: Color {
    if isChecking || isResetting { return .secondary }
    guard let status else { return .secondary }
    return status.ok ? .green : .red
  }

  private var statusSubtitle: String {
    if isResetting { return "Resetting cache..." }
    if isChecking { return "Checking Apple Containerization runtime..." }
    guard let status else { return "Not checked yet." }
    return status.ok ? "Ready for local agent commands." : "Runtime needs attention."
  }

  private var lastMessage: String? {
    if let lastError {
      return lastError
    }
    let message = status?.message.trimmingCharacters(in: .whitespacesAndNewlines)
    return message?.isEmpty == false ? message : nil
  }

  @MainActor
  private func runSmokeTest() async {
    isChecking = true
    lastError = nil
    let newStatus = await ContainerizedLinuxSandbox.shared.smokeTest()
    status = newStatus
    isChecking = false
  }

  @MainActor
  private func resetCache() async {
    isResetting = true
    lastError = nil
    do {
      try ContainerizedLinuxSandbox.shared.resetCache()
      status = nil
    } catch {
      lastError = error.localizedDescription
    }
    isResetting = false
  }
}

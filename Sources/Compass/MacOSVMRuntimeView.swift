import CompassCore
import SwiftUI

struct MacOSVMRuntimeView: View {
  @ObservedObject private var vm = SharedCompassVM.shared
  @AppStorage(MacOSVerifyRuntime.defaultsKey)
  private var macOSVerifyRuntime = MacOSVerifyRuntime.vm.rawValue
  @State private var isWorking = false
  @State private var lastError: String?
  @State private var smokeTestMessage: String?
  @State private var showingConsole = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      header

      VStack(alignment: .leading, spacing: 12) {
        LabeledContent("Status", value: statusText)
        LabeledContent("Bundle", value: vm.bundle.rootURL.path)
        if let login = vm.guestConsoleLogin() {
          LabeledContent("Guest login", value: "\(login.userName) / \(login.password)")
        }
        Picker("macOS verify runs in", selection: $macOSVerifyRuntime) {
          Text("macOS VM (host fallback)").tag(MacOSVerifyRuntime.vm.rawValue)
          Text("Host shell").tag(MacOSVerifyRuntime.host.rawValue)
        }
        .pickerStyle(.inline)
      }
      .textSelection(.enabled)

      HStack(spacing: 10) {
        Button {
          Task { await provisionAndStart() }
        } label: {
          Label("Provision & Start", systemImage: "play.circle")
        }
        .disabled(isWorking || vm.readiness.isReady)

        Button {
          Task { await vm.stop() }
        } label: {
          Label("Stop", systemImage: "stop.circle")
        }
        .disabled(isWorking || vm.virtualMachine == nil)

        Button {
          Task { await runSmokeTest() }
        } label: {
          Label("Smoke Test", systemImage: "checkmark.seal")
        }
        .disabled(isWorking || !vm.readiness.isReady)

        Button {
          showingConsole = true
        } label: {
          Label("Console", systemImage: "display")
        }
        .disabled(vm.virtualMachine == nil)

        Button(role: .destructive) {
          Task { await reset() }
        } label: {
          Label("Reset", systemImage: "trash")
        }
        .disabled(isWorking)
      }

      if let message = lastError ?? smokeTestMessage ?? vm.setupFailureMessage {
        Text(message)
          .font(.callout)
          .foregroundStyle(lastError != nil ? .red : .secondary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .sheet(isPresented: $showingConsole) {
      SharedCompassVMView(virtualMachine: vm.virtualMachine)
        .frame(minWidth: 960, minHeight: 640)
    }
    .task {
      try? await vm.warmup()
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: statusIcon)
        .font(.title2)
        .foregroundStyle(statusColor)
      VStack(alignment: .leading, spacing: 4) {
        Text("macOS VM")
          .font(.title2.weight(.semibold))
        Text(statusSubtitle)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if isWorking {
        ProgressView()
          .controlSize(.small)
      }
    }
  }

  private var statusText: String {
    switch vm.readiness {
    case .unavailable(let reason): return "Unavailable — \(reason)"
    case .notProvisioned: return "Not provisioned"
    case .downloadingIPSW(let fraction):
      return "Downloading macOS restore image (\(Int(fraction * 100))%)"
    case .installing(let fraction): return "Installing macOS (\(Int(fraction * 100))%)"
    case .guestPrepping: return "Preparing guest (first boot)"
    case .provisioningDevTools(let fraction):
      return "Installing developer tools (\(Int(fraction * 100))%)"
    case .ready(let destination): return "Ready — \(destination)"
    case .error(let detail): return "Error — \(detail)"
    }
  }

  private var statusSubtitle: String {
    if isWorking { return "Working..." }
    if vm.readiness.isReady { return "Ready to build generated apps inside the guest." }
    return "Embedded macOS VM (Apple Virtualization.framework)."
  }

  private var statusIcon: String {
    if isWorking { return "hourglass" }
    switch vm.readiness {
    case .ready: return "checkmark.circle.fill"
    case .error, .unavailable: return "exclamationmark.triangle.fill"
    default: return "desktopcomputer"
    }
  }

  private var statusColor: Color {
    if isWorking { return .secondary }
    switch vm.readiness {
    case .ready: return .green
    case .error, .unavailable: return .red
    default: return .secondary
    }
  }

  @MainActor
  private func provisionAndStart() async {
    isWorking = true
    lastError = nil
    defer { isWorking = false }
    do {
      try await vm.provisionIfNeeded()
      try await vm.start()
    } catch {
      lastError = error.localizedDescription
    }
  }

  @MainActor
  private func reset() async {
    isWorking = true
    lastError = nil
    defer { isWorking = false }
    do {
      try await vm.resetProvisioningArtifacts()
    } catch {
      lastError = error.localizedDescription
    }
  }

  @MainActor
  private func runSmokeTest() async {
    isWorking = true
    lastError = nil
    smokeTestMessage = nil
    defer { isWorking = false }
    guard let machine = vm.virtualMachine else { return }
    let client = SharedCompassVM.makeVsockClient(on: machine)
    do {
      let result = try await client.run(
        command: "sw_vers && swift --version",
        workingDirectory: URL(fileURLWithPath: "/"),
        timeout: 60
      )
      smokeTestMessage =
        result.exitCode == 0
        ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        : "Smoke test exited \(result.exitCode): \(result.stderr)"
    } catch {
      lastError = error.localizedDescription
    }
  }
}

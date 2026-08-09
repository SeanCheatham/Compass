import AppKit
import CompassCore
import SwiftUI

struct MacOSVMRuntimeView: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject private var vm = SharedCompassVM.shared
  @State private var isWorking = false
  @State private var isGrowingDisk = false
  @State private var lastError: String?
  @State private var smokeTestMessage: String?
  @State private var showingDesktop = false
  @State private var showingConsole = false
  /// Desired capacity in GiB for the slider (integer steps).
  @State private var desiredDiskGiB: Double = 64

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      header

      VStack(alignment: .leading, spacing: 12) {
        LabeledContent("Status", value: statusText)
        LabeledContent("Bundle", value: vm.bundle.rootURL.path)
        if let login = vm.guestConsoleLogin() {
          HStack(alignment: .firstTextBaseline) {
            LabeledContent("Guest login", value: "\(login.userName) / \(login.password)")
            Button("Copy password") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(login.password, forType: .string)
            }
            .buttonStyle(.borderless)
          }
        }
        Text("Factory bash, verify, coverage, and mutation all require this VM.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        diskCapacityControls
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
          showingDesktop = true
        } label: {
          Label("Desktop", systemImage: "display")
        }
        .disabled(vm.virtualMachine == nil)

        Button {
          showingConsole = true
          if vm.lastResolvedSSHDestination != nil || vm.readiness.isReady {
            vm.startDiagnosticLogTail()
          }
        } label: {
          Label("Console", systemImage: "terminal")
        }

        Button {
          Task { await repairAutoLogin() }
        } label: {
          Label("Repair Auto-Login", systemImage: "person.crop.circle.badge.checkmark")
        }
        .disabled(isWorking || (vm.lastResolvedSSHDestination == nil && !vm.readiness.isReady))

        Button {
          Task { await resetGuestWorkspace() }
        } label: {
          Label("Reset Guest Workspace", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(isWorking || !vm.readiness.isReady || model.selectedProject == nil)
        .help(
          model.selectedProject == nil
            ? "Select a project first to reset its guest workspace."
            : "Delete the selected project's guest Repos/<id> tree and force-sync a fresh worktree."
        )

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
    .sheet(isPresented: $showingDesktop) {
      NavigationStack {
        SharedCompassVMView(
          virtualMachine: vm.virtualMachine,
          becomesFirstResponderOnAppear: false
        )
        .frame(minWidth: 960, minHeight: 640)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { showingDesktop = false }
              .keyboardShortcut(.defaultAction)
          }
        }
      }
    }
    .sheet(isPresented: $showingConsole) {
      MacOSVMDiagnosticConsoleView(vm: vm)
    }
    .task {
      try? await vm.warmup()
      syncDesiredDiskFromVM()
    }
  }

  private var diskCapacityControls: some View {
    let currentBytes = vm.currentDiskCapacityBytes
    let currentGiB = Double(currentBytes) / Double(1024 * 1024 * 1024)
    let minGiB = max(64, currentGiB)
    let maxGiB = Double(SharedCompassVM.maximumDiskCapacityBytes) / Double(1024 * 1024 * 1024)
    let stepGiB = Double(SharedCompassVM.diskCapacityStepBytes) / Double(1024 * 1024 * 1024)
    let diskLocked = vm.isDiskCapacityLockedByRunningVM
    let hasDiskImage = vm.hasGuestDiskImage
    let canApplyGrow =
      !isWorking && !diskLocked && hasDiskImage && desiredDiskGiB + 0.5 >= currentGiB
    let canSlide = minGiB < maxGiB

    return VStack(alignment: .leading, spacing: 8) {
      LabeledContent("Disk capacity", value: SharedCompassVM.formatGiB(currentBytes))
      if canSlide {
        HStack(spacing: 12) {
          Slider(
            value: $desiredDiskGiB,
            in: minGiB...maxGiB,
            step: stepGiB
          )
          .disabled(isWorking || diskLocked)
          Text("\(Int(desiredDiskGiB.rounded())) GiB")
            .font(.callout.monospacedDigit())
            .frame(minWidth: 64, alignment: .trailing)
        }
        .help(
          diskLocked
            ? "Stop the VM before changing disk size."
            : "Grow-only. Apply extends the sparse Disk.img and boots the guest to expand APFS."
        )
      } else {
        Text("Already at maximum capacity (\(Int(maxGiB)) GiB).")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Button {
        Task { await applyDiskSize() }
      } label: {
        Label("Apply Disk Size", systemImage: "externaldrive.badge.plus")
      }
      .disabled(!canApplyGrow)
      .help(
        diskLocked
          ? "Stop the VM before changing disk size."
          : hasDiskImage
            ? (desiredDiskGiB > currentGiB + 0.5
              ? "Extend Disk.img and start the VM to finish the APFS resize."
              : "Re-run guest APFS resize if a previous grow left unused space.")
            : "Provision the VM before growing the disk."
      )
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
    case .stopped: return "Stopped"
    case .starting: return "Starting (waiting for guest SSH)"
    }
  }

  private var statusSubtitle: String {
    if isGrowingDisk { return "Growing disk…" }
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

  private func syncDesiredDiskFromVM() {
    let currentGiB = Double(vm.currentDiskCapacityBytes) / Double(1024 * 1024 * 1024)
    let preferredGiB = Double(vm.preferredDiskCapacityBytes) / Double(1024 * 1024 * 1024)
    desiredDiskGiB = max(currentGiB, preferredGiB, 64)
  }

  @MainActor
  private func applyDiskSize() async {
    isWorking = true
    isGrowingDisk = true
    lastError = nil
    smokeTestMessage = nil
    defer {
      isWorking = false
      isGrowingDisk = false
    }
    let bytes = UInt64(desiredDiskGiB.rounded()) * 1024 * 1024 * 1024
    do {
      try await vm.growDisk(toBytes: bytes)
      smokeTestMessage = "Disk grown to \(SharedCompassVM.formatGiB(bytes))."
      syncDesiredDiskFromVM()
    } catch {
      lastError = error.localizedDescription
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
      syncDesiredDiskFromVM()
    } catch {
      lastError = error.localizedDescription
    }
  }

  @MainActor
  private func repairAutoLogin() async {
    isWorking = true
    lastError = nil
    defer { isWorking = false }
    let ok = await vm.repairAutoLogin()
    if !ok {
      lastError = "Auto-login repair did not complete successfully. Check Console for details."
    }
  }

  @MainActor
  private func resetGuestWorkspace() async {
    isWorking = true
    lastError = nil
    smokeTestMessage = nil
    defer { isWorking = false }
    guard let repoURL = model.selectedProject?.repoURL else {
      lastError = "Select a project before resetting its guest workspace."
      return
    }
    do {
      let outcome = try await SharedCompassVMGuestWorkspaceReset.reset(
        repoURL: repoURL,
        mode: .full
      )
      smokeTestMessage = outcome.detail
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
        command: "sw_vers && git --version && cargo --version && swift --version",
        workingDirectory: URL(fileURLWithPath: SharedCompassVMGuestLayout.current.homeDirectory),
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

/// Host readiness + guest SSH/virtio log viewer for the macOS VM.
struct MacOSVMDiagnosticConsoleView: View {
  @ObservedObject var vm: SharedCompassVM
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            if vm.diagnosticLines.isEmpty {
              Text(
                "No diagnostics yet. Start the VM to capture readiness, virtio, and guest log output."
              )
              .foregroundStyle(.secondary)
              .padding(.vertical, 8)
            }
            ForEach(vm.diagnosticLines) { line in
              Text(line.displayText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(line.id)
            }
          }
          .padding(16)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: vm.diagnosticLines.count) { _, _ in
          if let last = vm.diagnosticLines.last {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
      .frame(minWidth: 860, minHeight: 520)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Clear") { vm.clearDiagnostics() }
        }
        ToolbarItem(placement: .automatic) {
          Button("Refresh Tail") {
            vm.startDiagnosticLogTail()
          }
          .disabled(vm.lastResolvedSSHDestination == nil && !vm.readiness.isReady)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .keyboardShortcut(.defaultAction)
        }
      }
      .navigationTitle("Console")
    }
  }
}

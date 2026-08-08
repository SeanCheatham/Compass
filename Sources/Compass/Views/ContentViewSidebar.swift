import AppKit
import CompassCore
import SwiftUI

struct SidebarView: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject private var localModelManager: LocalModelManager = .shared
  var onCollapse: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Label("Compass", systemImage: "safari")
            .font(.title2.weight(.semibold))
          Spacer()
          SidebarRuntimeStatusButton {
            model.selectRuntime()
          }
          Button(action: onCollapse) {
            Image(systemName: "sidebar.left")
              .font(.body)
          }
          .buttonStyle(.borderless)
          .help("Hide projects sidebar")
          .accessibilityLabel("Hide projects sidebar")
        }
        Text("Local software factory")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .padding(.bottom, 4)

      SidebarRuntimeRow(
        isSelected: model.workspaceSelection.isRuntime
      ) {
        model.selectRuntime()
      }

      HStack {
        Text("Projects")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          Task { await model.createRustProject() }
        } label: {
          Label("New Factory Project", systemImage: "plus.square.dashed")
        }
        .labelStyle(.iconOnly)
        .help("New factory project (Rust core + CLI/macOS/server)")

        Button {
          Task { await model.chooseRepository() }
        } label: {
          Label("Add Factory Project", systemImage: "folder.badge.plus")
        }
        .labelStyle(.iconOnly)
        .help("Add existing Git repo as factory project")

        Button {
          Task { await model.chooseChamberRepository() }
        } label: {
          Label("Open Chamber", systemImage: "flame")
        }
        .labelStyle(.iconOnly)
        .help("Open existing Rust repo as chamber (test hunt)")
      }

      if model.projects.isEmpty {
        EmptyProjectList {
          Task { await model.chooseRepository() }
        }
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(model.projects) { project in
              ProjectListRow(
                project: project,
                isSelected: model.workspaceSelection == .project(project.id)
              )
              .onTapGesture {
                model.selectProject(project)
              }
              .contextMenu {
                Button("Reveal in Finder") {
                  NSWorkspace.shared.activateFileViewerSelecting([project.repoURL])
                }
                Button("Refresh") {
                  Task { await project.refresh() }
                }
                Divider()
                Button("Remove from Compass", role: .destructive) {
                  model.removeProject(project)
                }
              }
            }
          }
          .padding(.vertical, 2)
        }
      }

      Spacer(minLength: 8)

      DisclosureGroup {
        let runtimeSummary = AgentRuntimeSidebarSummary(
          settings: model.agentSettings,
          modelSnapshot: localModelManager.snapshot
        )
        VStack(alignment: .leading, spacing: 8) {
          ForEach(runtimeSummary.lines) { line in
            Text("\(line.label): \(line.value)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Text("Settings: Runtime… (⌘,) → Agent.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
          if let diagnosticsAction = model.selectedProject?.runtimeDiagnosticsMenu
            .copyDiagnosticsAction
          {
            Button {
              copyRuntimeDiagnosticsToPasteboard(diagnosticsAction.copyText)
            } label: {
              Label(diagnosticsAction.title, systemImage: diagnosticsAction.systemImage)
            }
            .help(diagnosticsAction.helpText)
          }
        }
        .padding(.top, 8)
      } label: {
        Label("Runtime", systemImage: "terminal")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }

      if let message = model.errorMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding()
    .frame(maxHeight: .infinity, alignment: .topLeading)
  }
}

/// Narrow strip shown when the projects sidebar is collapsed.
struct SidebarCollapsedRail: View {
  var onExpand: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Button(action: onExpand) {
        Image(systemName: "sidebar.left")
          .font(.body)
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.borderless)
      .help("Show projects sidebar")
      .accessibilityLabel("Show projects sidebar")

      Spacer(minLength: 0)
    }
    .padding(.top, 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

struct EmptyProjectList: View {
  var addProject: () -> Void

  var body: some View {
    ProjectIntakeGuideCard(
      guide: ProjectIntakeGuide(projectCount: 0),
      compact: true,
      addProject: addProject
    )
  }
}

/// Sidebar entry for the singleton runtime section (the embedded macOS VM).

struct SidebarRuntimeRow: View {
  let isSelected: Bool
  let action: () -> Void
  @ObservedObject private var vm = SharedCompassVM.shared

  var statusText: String {
    switch vm.readiness {
    case .ready: return "Ready"
    case .notProvisioned: return "Not provisioned"
    case .stopped: return "Stopped"
    case .starting: return "Starting..."
    case .downloadingIPSW, .installing, .guestPrepping, .provisioningDevTools:
      return "Provisioning..."
    case .error, .unavailable: return "Needs attention"
    }
  }

  var statusColor: Color {
    switch vm.readiness {
    case .ready: return .green
    case .error, .unavailable: return .red
    default: return .secondary
    }
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Circle()
          .fill(statusColor)
          .frame(width: 10, height: 10)
          .padding(.top, 1)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Image(systemName: "desktopcomputer")
              .font(.callout)
            Text("macOS VM")
              .font(.callout.weight(.semibold))
          }
          Text(statusText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
      }
      .contentShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help("Open macOS VM status")
    .accessibilityLabel("macOS VM, \(statusText)")
  }
}

/// Status indicator next to the sidebar title. Tapping it activates the
/// runtime detail pane.

struct SidebarRuntimeStatusButton: View {
  let action: () -> Void

  var helpText: String {
    "macOS VM runtime status"
  }

  var accessibilityText: String {
    "macOS VM runtime status"
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Circle()
          .fill(Color.green)
          .frame(width: 8, height: 8)
        Image(systemName: "shippingbox")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.green)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(Color.green.opacity(0.12), in: Capsule())
      .overlay(Capsule().stroke(Color.green.opacity(0.30)))
    }
    .buttonStyle(.plain)
    .help(helpText)
    .accessibilityLabel(accessibilityText)
  }
}

struct ProjectListRow: View {
  @ObservedObject var project: CompassProject
  var isSelected: Bool

  var body: some View {
    let sidebarStatus = project.sidebarStatus

    HStack(alignment: .top, spacing: 10) {
      ProjectPhaseMark(project: project, sidebarStatus: sidebarStatus)
        .frame(width: 16, height: 16)
        .padding(.top, 3)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(project.displayName)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          if project.projectKind == .chamber {
            Text("Chamber")
              .font(.caption2.weight(.semibold))
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(Color.indigo.opacity(0.15))
              .foregroundStyle(.indigo)
              .clipShape(Capsule())
          }
          if project.isRunning || project.isAutoPlaying {
            ProgressView()
              .controlSize(.small)
          }
        }

        Text(project.repoPath)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)

        if sidebarStatus.hasReliabilityCue {
          ProjectSidebarReliabilitySummary(status: sidebarStatus)
        } else {
          Text(sidebarStatus.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
      in: RoundedRectangle(cornerRadius: 8)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
    }
    .contentShape(RoundedRectangle(cornerRadius: 8))
    .help(sidebarStatus.helpText)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(rowAccessibilityLabel(status: sidebarStatus))
    .accessibilityHint(sidebarStatus.accessibilityHint)
  }

  private func rowAccessibilityLabel(status: ProjectSidebarStatus) -> String {
    [
      project.displayName,
      project.repoPath,
      status.accessibilityLabel,
    ]
    .filter { !$0.isEmpty }
    .joined(separator: ", ")
  }
}

struct ProjectPhaseMark: View {
  @ObservedObject var project: CompassProject
  var sidebarStatus: ProjectSidebarStatus

  var body: some View {
    Group {
      if project.isRunning || project.isAutoPlaying {
        ProgressView()
          .controlSize(.small)
      } else {
        ZStack {
          Circle()
            .fill(phaseColor(project.isPaused ? .paused : project.phase))
            .frame(width: 9, height: 9)
          if sidebarStatus.hasReliabilityCue {
            Circle()
              .stroke(reliabilityColor(for: sidebarStatus.severity).opacity(0.75), lineWidth: 1.4)
              .frame(width: 15, height: 15)
          }
        }
      }
    }
    .help(sidebarStatus.helpText)
    .accessibilityLabel(sidebarStatus.phaseLabel)
  }
}

struct ProjectSidebarReliabilitySummary: View {
  var status: ProjectSidebarStatus

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 5) {
        Image(systemName: status.systemImage)
          .font(.system(size: 10, weight: .bold))
        Text(status.badgeLabel)
          .lineLimit(1)
        if status.cueCount > 1 {
          Text(status.countLabel)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.14), in: Capsule())
        }
      }
      .font(.caption2.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(color.opacity(0.11), in: Capsule())
      .overlay {
        Capsule()
          .stroke(color.opacity(0.22))
      }
      .fixedSize(horizontal: false, vertical: true)

      Text(status.subtitle)
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .help(status.helpText)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(status.accessibilityLabel)
    .accessibilityHint(status.accessibilityHint)
  }

  private var color: Color {
    reliabilityColor(for: status.severity)
  }
}

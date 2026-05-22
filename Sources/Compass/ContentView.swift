import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var sharedVMHost: SharedCompassVM = .shared

    var body: some View {
        if isOnboardingComplete {
            NavigationSplitView {
                SidebarView()
            } detail: {
                switch model.workspaceSelection {
                case .sandbox:
                    SandboxView()
                case .project:
                    if let project = model.selectedProject {
                        MainWorkspaceView(project: project)
                            .id(project.id)
                    } else {
                        NoProjectView()
                    }
                }
            }
        } else {
            OnboardingView()
        }
    }

    /// Mandatory onboarding gate. Compass routes every agent run through
    /// the Shared VM and needs an API key to call the LLM, so neither is
    /// optional — the rest of the UI is hidden until both land.
    private var isOnboardingComplete: Bool {
        sharedVMHost.readiness.isReady && !model.agentSettings.apiKey.isEmpty
    }
}

private func copyRuntimeDiagnosticsToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var sharedVMHost: SharedCompassVM = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label("Compass", systemImage: "safari")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    SidebarSharedVMStatusButton(readiness: sharedVMHost.readiness) {
                        model.selectSandbox()
                    }
                }
                Text("Agent-powered macOS workspace")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            SidebarSandboxRow(
                readiness: sharedVMHost.readiness,
                isSelected: model.workspaceSelection.isSandbox
            ) {
                model.selectSandbox()
            }

            HStack {
                Text("Projects")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await model.chooseRepository() }
                } label: {
                    Label("Add Project", systemImage: "folder.badge.plus")
                }
                .labelStyle(.iconOnly)
                .help("Add project")
            }

            if model.projects.isEmpty {
                EmptyProjectList()
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Agent endpoint: \(model.agentSettings.baseURL.host() ?? model.agentSettings.baseURL.absoluteString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Model: \(model.agentSettings.model)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Configure via Compass → Settings… (⌘,).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let selectedProject = model.selectedProject {
                        DevelopSandboxPicker(
                            project: selectedProject,
                            readiness: sharedVMHost.readiness
                        )
                    }
                    if let diagnosticsAction = model.selectedProject?.runtimeDiagnosticsMenu.copyDiagnosticsAction {
                        Button {
                            copyRuntimeDiagnosticsToPasteboard(diagnosticsAction.copyText)
                        } label: {
                            Label(diagnosticsAction.title, systemImage: diagnosticsAction.systemImage)
                        }
                        .help(diagnosticsAction.helpText)
                    }
                    if let mutationAction = model.selectedProject?.runtimeDiagnosticsMenu.mutationTestingAction {
                        Button {
                            Task { await model.runMutationTestingForSelectedProject() }
                        } label: {
                            Label(mutationAction.title, systemImage: mutationAction.systemImage)
                        }
                        .disabled(!mutationAction.isEnabled)
                        .help(mutationAction.helpText)
                    }
                    if let recovery = model.selectedProject?.runtimeDiagnosticsMenu.mutationRecoveryDescriptor {
                        Button {
                            copyRuntimeDiagnosticsToPasteboard(recovery.copyText)
                        } label: {
                            Label(recovery.copyActionLabel, systemImage: "doc.on.doc")
                        }
                        .help(recovery.helpText)
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
        .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 380)
    }
}

private struct EmptyProjectList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "folder")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No projects yet.")
                .font(.headline)
            Text("Add a Git repository to start using Compass.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Sidebar entry for the singleton Sandbox section. Selecting it sets
/// `workspaceSelection = .sandbox` and swaps the detail pane to `SandboxView`.
private struct SidebarSandboxRow: View {
    let readiness: SharedCompassVMReadiness
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SandboxReadinessDot(readiness: readiness, size: 10)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox")
                            .font(.callout)
                        Text("Sandbox")
                            .font(.callout.weight(.semibold))
                    }
                    Text(readiness.statusSummary)
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
        .help("Open the shared macOS VM sandbox")
        .accessibilityLabel("Sandbox, \(readiness.statusSummary)")
    }
}

/// Status indicator next to the sidebar title. Tapping it activates the
/// Sandbox detail pane.
private struct SidebarSharedVMStatusButton: View {
    let readiness: SharedCompassVMReadiness
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                SandboxReadinessDot(readiness: readiness, size: 8)
                Image(systemName: readiness.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(readiness.tintColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(readiness.tintColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(readiness.tintColor.opacity(0.30)))
        }
        .buttonStyle(.plain)
        .help("Shared VM status: \(readiness.statusSummary)")
        .accessibilityLabel("Shared VM status, \(readiness.statusSummary)")
    }
}

/// Per-project picker for the Develop sandbox preference. The `.sharedVM`
/// option is disabled when the shared VM is unavailable.
private struct DevelopSandboxPicker: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var project: CompassProject
    let readiness: SharedCompassVMReadiness

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Develop sandbox", selection: $project.developSandbox) {
                ForEach(DevelopSandboxPreference.allCases, id: \.self) { preference in
                    Text(preference.displayLabel).tag(preference)
                }
            }
            .pickerStyle(.menu)
            .help(pickerHelpText)
            .onChange(of: project.developSandbox) { _, newValue in
                if newValue == .sharedVM, readiness.isUnavailable {
                    project.developSandbox = .host
                    return
                }
                model.saveProjects()
            }
            if readiness.isUnavailable, case .unavailable(let reason) = readiness {
                Text("Shared VM unavailable: \(reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pickerHelpText: String {
        switch readiness {
        case .unavailable(let reason):
            return "Shared VM is unavailable (\(reason)). Develop runs on the host."
        case .ready:
            return "Choose whether Develop iterations run on the host or inside the shared macOS VM."
        default:
            return "Develop iterations route to the Shared VM once it reaches the Ready state."
        }
    }
}

private struct ProjectListRow: View {
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
            status.accessibilityLabel
        ]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

private struct ProjectPhaseMark: View {
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

private struct ProjectSidebarReliabilitySummary: View {
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

private struct NoProjectView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Choose a project")
                .font(.title2.weight(.semibold))
            Text("Compass remembers Git repositories here, then lets each one run independently.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                Task { await model.chooseRepository() }
            } label: {
                Label("Add Project", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MainWorkspaceView: View {
    @ObservedObject var project: CompassProject
    @State private var selectedTab: WorkspaceTab = .live
    @State private var cinematicPresentationState = CinematicTabPresentationState()

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(project: project, selectedTab: $selectedTab)
            Divider()
            WorkspaceContent(
                project: project,
                selectedTab: selectedTab,
                cinematicPresentationState: $cinematicPresentationState
            )
                .padding(16)
                .overlay(alignment: .bottom) {
                    if let message = project.errorMessage {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.red, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 12)
                    }
                }
        }
    }
}

private struct WorkspaceHeader: View {
    @ObservedObject var project: CompassProject
    @Binding var selectedTab: WorkspaceTab

    var body: some View {
        let reliabilityStatus = project.reliabilityStatus
        let storageAssessment = project.storageAssessment
        let storagePreflight = CompassWorkspaceStoragePreflight(assessment: storageAssessment)
        let storageBoundary = CompassWorkspaceStorageBoundary(
            assessment: storageAssessment,
            preflight: storagePreflight
        )
        let activeStorageRootURL = CompassProjectStorageResolver.storageRootURL(
            for: project.repoURL,
            activeStorage: project.activeStorage,
            applicationSupportRoots: project.storageApplicationSupportRoots
        )
        let storageDisplayStatus = CompassWorkspaceStorageDisplayStatus(
            repoURL: project.repoURL,
            activeStorage: project.activeStorage,
            applicationSupportRoots: project.storageApplicationSupportRoots,
            activeStorageRootURL: activeStorageRootURL,
            assessment: storageAssessment,
            preflight: storagePreflight
        )
        let activitySourceStatus = ProjectActivitySourceStatus(
            snapshot: project.activitySourceSnapshot
        )
        let storageMigrationPlan = project.storageMigrationPlan()
        let storageActivationPlan = project.activeStorageActivationPlan()
        let storageActivationIsIdle = !project.isRunning && !project.isAutoPlaying && !project.isPaused
        let storageActions = CompassWorkspaceStorageHeaderActions(
            activeStorage: project.activeStorage,
            candidatePreparationIsAvailable: storageMigrationPlan.isAvailable,
            candidatePreparationShouldShowFeedback: project.storageMigrationState.shouldShowFeedback,
            activationIsAvailable: storageActivationPlan.isAvailable,
            activationShouldShowFeedback: project.activeStorageActivationState.shouldShowFeedback,
            activationIsIdle: storageActivationIsIdle,
            repoLocalRepairActionIsAvailable: storageAssessment.repairAction != nil,
            applicationSupportRepairActionIsAvailable: storageDisplayStatus.supportRepairAction != nil
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(project.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(project.repoPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                ProjectStorageAssessmentPill(
                    displayStatus: storageDisplayStatus,
                    assessment: storageAssessment,
                    preflight: storagePreflight,
                    boundary: storageBoundary,
                    migrationPlan: storageMigrationPlan,
                    activationPlan: storageActivationPlan
                )
                if activitySourceStatus.isVisible {
                    ProjectActivitySourceStatusPill(status: activitySourceStatus)
                }
                if storageActions.showsCandidatePreparation {
                    ProjectStorageMigrationButton(
                        project: project,
                        plan: storageMigrationPlan
                    )
                }
                if storageActions.showsActivation {
                    ProjectStorageActivationButton(
                        project: project,
                        plan: storageActivationPlan
                    )
                }
                if storageActions.showsRepoLocalRepair, let repairAction = storageAssessment.repairAction {
                    ProjectStorageRepairButton(
                        label: repairAction.label,
                        systemImage: repairAction.systemImage,
                        helpText: repairAction.helpText,
                        accessibilityLabel: repairAction.label,
                        isDisabled: project.isRunning || project.isAutoPlaying
                    ) {
                        Task { await project.initializeWorkspace() }
                    }
                }
                if storageActions.showsApplicationSupportRepair,
                   let repairAction = storageDisplayStatus.supportRepairAction {
                    ProjectStorageRepairButton(
                        label: repairAction.label,
                        systemImage: repairAction.systemImage,
                        helpText: repairAction.helpText,
                        accessibilityLabel: repairAction.label,
                        isDisabled: project.isRunning || project.isAutoPlaying
                    ) {
                        Task { await project.initializeWorkspace() }
                    }
                }
                if !reliabilityStatus.isEmpty {
                    ProjectReliabilityAttentionPill(status: reliabilityStatus)
                }
                ProjectPhasePill(project: project)
            }

            HStack(spacing: 4) {
                ForEach(WorkspaceTab.allCases) { tab in
                    WorkspaceTabButton(tab: tab, selectedTab: $selectedTab)
                }
                Spacer()
                ProjectRunControls(project: project)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private extension CompassProject {
    var reliabilityStatus: ProjectReliabilityStatus {
        ProjectReliabilityStatus(
            feedback: PlanReliabilityFeedback(state: state, sessions: sessions)
        )
    }

    var sidebarStatus: ProjectSidebarStatus {
        ProjectSidebarStatus(
            reliabilityStatus: reliabilityStatus,
            immediateTitle: immediateTitle,
            phase: phase,
            isRunning: isRunning,
            isAutoPlaying: isAutoPlaying,
            isPaused: isPaused,
            pauseMode: pauseMode
        )
    }

    var storageAssessment: CompassWorkspaceStorageAssessment {
        CompassWorkspaceStorageAssessment(
            repoURL: repoURL,
            applicationSupportRoots: storageApplicationSupportRoots
        )
    }

    var storagePreflight: CompassWorkspaceStoragePreflight {
        CompassWorkspaceStoragePreflight(
            assessment: storageAssessment
        )
    }
}

private struct ProjectStorageAssessmentPill: View {
    var displayStatus: CompassWorkspaceStorageDisplayStatus
    var assessment: CompassWorkspaceStorageAssessment
    var preflight: CompassWorkspaceStoragePreflight
    var boundary: CompassWorkspaceStorageBoundary
    var migrationPlan: CompassWorkspaceStorageMigrationPlan
    var activationPlan: CompassWorkspaceStorageActivationPlan

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: displayStatus.systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(displayStatus.label)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(displayStatus.severity == .healthy ? 0.10 : 0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(displayStatus.severity == .healthy ? 0.20 : 0.28))
        }
        .help(helpText)
        .accessibilityLabel("Storage: \(displayStatus.label)")
        .accessibilityValue(displayStatus.detail)
        .accessibilityHint(displayStatus.recommendation)
    }

    private var color: Color {
        storageAssessmentColor(for: displayStatus.severity)
    }

    private var helpText: String {
        var lines = [
            "Current state root: \(displayStatus.activeStorageRootURL.path)",
            "Active storage: \(displayStatus.activeStorageDisplayName)",
            "Active root health: \(displayStatus.activeRootHealth.displayName)",
            displayStatus.detail,
            displayStatus.recommendation
        ]

        if displayStatus.activeStorage == .applicationSupport {
            if let compatibility = displayStatus.applicationSupportCompatibility {
                lines.append("Repo-local compatibility: \(compatibility.repoLocalContext.kind.displayName)")
                lines.append(compatibility.detail)
                lines.append(compatibility.helpText)
            }
            lines.append("Project storage ID: \(displayStatus.projectStorageIdentifier)")
        } else {
            lines += [
                "Repo-local boundary: \(boundary.label)",
                boundary.detail,
                boundary.recommendation,
                "Technical migration eligible: \(boundary.migrationCouldBeTechnicallyEligible ? "yes" : "no")",
                "Repo-local assessment: \(assessment.label)",
                assessment.detail,
                assessment.recommendation,
                "Candidate preparation: \(migrationPlan.label)",
                migrationPlan.detail,
                migrationPlan.recommendation,
                "Activation: \(activationPlan.label)",
                activationPlan.detail,
                activationPlan.recommendation,
                "Migration preflight: \(preflight.label)",
                preflight.detail,
                preflight.recommendation,
                "Repo-local readiness: \(preflight.repoLocalReadiness.displayName)",
                missingCoreFilesText,
                "Sessions directory: \(preflight.sessionsDirectoryExists ? "present" : "missing")",
                "Project storage ID: \(preflight.projectStorageIdentifier)",
                candidateText(preflight.currentApplicationSupportCandidate),
                candidateText(preflight.legacyApplicationSupportCandidate)
            ]
        }

        return lines
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var missingCoreFilesText: String {
        guard !preflight.missingCoreFiles.isEmpty else {
            return "Missing core files: none"
        }
        return "Missing core files: \(preflight.missingCoreFiles.map(\.relativePath).joined(separator: ", "))"
    }

    private func candidateText(
        _ candidate: CompassWorkspaceStoragePreflight.ApplicationSupportCandidate
    ) -> String {
        "\(candidate.kind.displayName) support candidate: \(candidate.occupancy.displayName) \(candidate.url.path)"
    }
}

private struct ProjectActivitySourceStatusPill: View {
    var status: ProjectActivitySourceStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(status.label)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(status.severity == .healthy ? 0.10 : 0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(status.severity == .healthy ? 0.20 : 0.28))
        }
        .help(status.helpText)
        .accessibilityLabel(status.accessibilityLabel)
        .accessibilityValue(status.accessibilityValue)
        .accessibilityHint(status.accessibilityHint)
    }

    private var color: Color {
        storageAssessmentColor(for: status.severity)
    }
}

private struct ProjectStorageMigrationButton: View {
    @ObservedObject var project: CompassProject
    var plan: CompassWorkspaceStorageMigrationPlan

    var body: some View {
        Button {
            project.prepareStorageMigrationConfirmation()
        } label: {
            Group {
                if project.storageMigrationState.isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: presentation.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isDisabled)
        .help(presentation.helpText)
        .accessibilityLabel(presentation.label)
        .accessibilityHint(presentation.detail)
        .alert(item: $project.storageMigrationConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .default(Text(confirmation.confirmLabel)) {
                    Task { await project.confirmStorageMigration(confirmation) }
                },
                secondaryButton: .cancel(Text(confirmation.cancelLabel)) {
                    project.cancelStorageMigrationConfirmation()
                }
            )
        }
    }

    private var isDisabled: Bool {
        project.storageMigrationState.isRunning
            || project.isRunning
            || project.isAutoPlaying
            || (project.storageMigrationState.phase == .succeeded && !plan.isAvailable)
            || (!plan.isAvailable && !project.storageMigrationState.shouldShowFeedback)
    }

    private var presentation: CompassProjectStorageMigrationState {
        project.storageMigrationState.shouldShowFeedback
            ? project.storageMigrationState
            : .idle
    }
}

private struct ProjectStorageActivationButton: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var project: CompassProject
    var plan: CompassWorkspaceStorageActivationPlan

    var body: some View {
        Button {
            project.prepareActiveStorageActivationConfirmation()
        } label: {
            Group {
                if project.activeStorageActivationState.isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: presentation.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isDisabled)
        .help(presentation.helpText)
        .accessibilityLabel(presentation.label)
        .accessibilityHint(presentation.detail)
        .alert(item: $project.activeStorageActivationConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .default(Text(confirmation.confirmLabel)) {
                    Task {
                        await project.confirmActiveStorageActivation(confirmation) {
                            try model.saveProjectsThrowing()
                        }
                    }
                },
                secondaryButton: .cancel(Text(confirmation.cancelLabel)) {
                    project.cancelActiveStorageActivationConfirmation()
                }
            )
        }
    }

    private var isDisabled: Bool {
        project.activeStorageActivationState.isRunning
            || project.isRunning
            || project.isAutoPlaying
            || project.isPaused
            || (!plan.isAvailable && !project.activeStorageActivationState.shouldShowFeedback)
    }

    private var presentation: CompassProjectActiveStorageState {
        project.activeStorageActivationState.shouldShowFeedback
            ? project.activeStorageActivationState
            : .idle
    }
}

private struct ProjectStorageRepairButton: View {
    var label: String
    var systemImage: String
    var helpText: String
    var accessibilityLabel: String
    var isDisabled: Bool
    var performRepair: () -> Void

    var body: some View {
        Button(action: performRepair) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isDisabled)
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(helpText)
    }
}

private struct ProjectReliabilityAttentionPill: View {
    var status: ProjectReliabilityStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.systemImage)
                .font(.system(size: 12, weight: .semibold))

            Text(status.primaryCue)
                .lineLimit(1)

            if status.noticeCount > 1 {
                Text(status.countLabel)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.14), in: Capsule())
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(0.24))
        }
        .help(helpText)
        .accessibilityLabel("\(status.primaryCue), \(status.countLabel)")
        .accessibilityHint(status.actionLabel)
    }

    private var color: Color {
        reliabilityColor(for: status.severity)
    }

    private var helpText: String {
        [
            status.primaryCue,
            status.actionLabel,
            status.metadata,
            status.detail
        ]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }
}

private struct ProjectPhasePill: View {
    @ObservedObject var project: CompassProject

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(phaseColor(project.isPaused ? .paused : project.phase))
                .frame(width: 8, height: 8)
            Text(phaseText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.55), in: Capsule())
    }

    private var phaseText: String {
        if project.isPaused && project.isRunning {
            switch project.pauseMode {
            case .immediate:
                return "Pausing"
            case .afterIteration:
                return "Pausing after iteration"
            }
        }
        if project.isAutoPlaying {
            return "Auto - \(project.phase.rawValue)"
        }
        return project.phase.rawValue
    }
}

private struct ProjectRunControls: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var project: CompassProject

    var body: some View {
        let deliverySnapshot = NativeFeedbackService.shared.deliverySnapshot(
            mode: project.nativeFeedbackMode
        )
        let feedbackMenu = NativeFeedbackModeMenu(
            selectedMode: project.nativeFeedbackMode,
            projectName: project.displayName,
            deliverySnapshot: deliverySnapshot
        )
        let executionEnvironmentMenu = project.runtimeDiagnosticsMenu

        HStack(spacing: 5) {
            Menu {
                Text(executionEnvironmentMenu.statusText)
                Divider()
                let diagnosticsAction = executionEnvironmentMenu.copyDiagnosticsAction
                Button {
                    copyRuntimeDiagnosticsToPasteboard(diagnosticsAction.copyText)
                } label: {
                    Label(diagnosticsAction.title, systemImage: diagnosticsAction.systemImage)
                }
                Text(diagnosticsAction.description)
                if let mutationAction = executionEnvironmentMenu.mutationTestingAction {
                    Divider()
                    Button {
                        Task { await project.runMutationTesting() }
                    } label: {
                        Label(mutationAction.title, systemImage: mutationAction.systemImage)
                    }
                    .disabled(!mutationAction.isEnabled)
                    .help(mutationAction.helpText)
                    Text(mutationAction.description)
                    Text(mutationAction.helpText)
                }
                if let recovery = executionEnvironmentMenu.mutationRecoveryDescriptor {
                    Divider()
                    Text(recovery.badgeText)
                    Button {
                        copyRuntimeDiagnosticsToPasteboard(recovery.copyText)
                    } label: {
                        Label(recovery.copyActionLabel, systemImage: "doc.on.doc")
                    }
                    .help(recovery.helpText)
                    Text(recovery.detailText)
                }
                Divider()
                ForEach(Array(executionEnvironmentMenu.items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        let target = item.preference.developSandbox
                        if target == .sharedVM, SharedCompassVM.shared.readiness.isUnavailable {
                            return
                        }
                        project.developSandbox = target
                        model.saveProjects()
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                    Text(item.description)
                    if index < executionEnvironmentMenu.items.count - 1 {
                        Divider()
                    }
                }
            } label: {
                Image(systemName: executionEnvironmentMenu.labelSystemImage)
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .help(executionEnvironmentMenu.helpText)

            Menu {
                Text(feedbackMenu.deliveryStatusText)
                Divider()
                ForEach(Array(feedbackMenu.items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        project.nativeFeedbackMode = item.mode
                        NativeFeedbackService.shared.applyModeChange(item.mode)
                        model.saveProjects()
                    } label: {
                        Label(
                            item.title,
                            systemImage: item.systemImage
                        )
                    }
                    Text(item.description)
                    Text(item.permissionHint)
                    if index < feedbackMenu.items.count - 1 {
                        Divider()
                    }
                }
            } label: {
                Image(systemName: feedbackMenu.labelSystemImage)
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .help(feedbackMenu.helpText)

            Button {
                Task {
                    await project.play(
                        agentSettings: model.agentSettings,
                        modelOverride: model.modelOverride
                    )
                }
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderedProminent)
            .disabled(project.isRunning || project.isAutoPlaying || !project.hasRepository)
            .help(project.isPaused ? "Resume auto-play" : "Start auto-play")

            Menu {
                ForEach(PauseMode.allCases) { mode in
                    Button {
                        project.requestPause(mode)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(mode.label)
                            Text(mode.hint)
                        }
                    }
                }
            } label: {
                Image(systemName: "pause.fill")
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .disabled((!project.isRunning && !project.isAutoPlaying) || project.isPaused)
            .help("Pause")

            Button {
                project.stopRun()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.bordered)
            .disabled(!project.canStop)
            .help("Stop")
        }
        .controlSize(.regular)
    }
}

private struct WorkspaceTabButton: View {
    var tab: WorkspaceTab
    @Binding var selectedTab: WorkspaceTab

    var body: some View {
        Button {
            selectedTab = tab
        } label: {
            Label(tab.title, systemImage: tab.systemImage)
                .labelStyle(.titleAndIcon)
                .font(.callout.weight(selectedTab == tab ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(minWidth: 82)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
        .background(
            selectedTab == tab ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
    }
}

private struct WorkspaceContent: View {
    @ObservedObject var project: CompassProject
    var selectedTab: WorkspaceTab
    @Binding var cinematicPresentationState: CinematicTabPresentationState

    var body: some View {
        switch selectedTab {
        case .live:
            LiveTab(project: project)
        case .cinematic:
            CinematicTab(project: project, presentationState: $cinematicPresentationState)
        case .plan:
            PlanTab(project: project)
        case .drafts:
            DraftsTab(project: project)
        case .vision:
            VisionTab(project: project)
        case .lessons:
            LessonsTab(project: project)
        }
    }
}

private enum WorkspaceTab: String, CaseIterable, Identifiable {
    case live
    case cinematic
    case plan
    case drafts
    case vision
    case lessons

    var id: Self { self }

    var title: String {
        switch self {
        case .live: return "Live"
        case .cinematic: return "Cinematic"
        case .plan: return "Plan"
        case .drafts: return "Drafts"
        case .vision: return "Vision"
        case .lessons: return "Lessons"
        }
    }

    var systemImage: String {
        switch self {
        case .live: return "waveform.path.ecg"
        case .cinematic: return "wand.and.stars"
        case .plan: return "map"
        case .drafts: return "square.and.pencil"
        case .vision: return "scope"
        case .lessons: return "book.closed"
        }
    }
}

private struct PlanTab: View {
    @ObservedObject var project: CompassProject
    @State private var selectedItemID = PlanTimelineItem.immediateID
    @State private var showAllSessionHistory = false
    @State private var sessionHistoryFilter = PlanSessionHistoryFilter.all

    var body: some View {
        let items = PlanTimelineItem.items(for: project.state)
        let executionEnvironment = project.agentExecutionEnvironment
        let launchPlan = executionEnvironment.launchPlan(repoURL: project.repoURL)
        let overview = PlanWorkflowOverview(
            state: project.state,
            languageProfile: project.languageProfile,
            launchPlan: launchPlan
        )
        let sessionHistory = PlanSessionHistory.displayItems(for: project.sessions)
        let reliabilityFeedback = PlanReliabilityFeedback(
            state: project.state,
            sessions: project.sessions,
            historyItems: sessionHistory
        )
        let sessionHistoryDisplay = PlanSessionHistoryDisplay(
            items: sessionHistory,
            mode: showAllSessionHistory ? .all : .recent,
            filter: sessionHistoryFilter,
            runCues: reliabilityFeedback.recentRunCues
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PlanTimelineHeader(
                    items: items,
                    selectedItemID: $selectedItemID,
                    completedCount: project.state.completed.count
                )

                PlanWorkflowOverviewView(
                    overview: overview,
                    selectedKind: PlanWorkflowOverview.Kind(timelineItemID: selectedItemID)
                ) { kind in
                    let destinationID = kind.timelineItemID
                    guard items.contains(where: { $0.id == destinationID }) else {
                        return
                    }

                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedItemID = destinationID
                    }
                }

                PlanReliabilityFeedbackView(feedback: reliabilityFeedback)

                PlanFocusPanel(item: selectedItem(in: items))

                PlanSessionHistorySection(
                    display: sessionHistoryDisplay,
                    showAllRuns: $showAllSessionHistory,
                    selectedFilter: $sessionHistoryFilter,
                    runCues: reliabilityFeedback.recentRunCues
                )
            }
            .frame(maxWidth: 1060, alignment: .leading)
        }
        .onAppear {
            normalizeSelection(for: items)
        }
        .onChange(of: project.state) {
            normalizeSelection(for: PlanTimelineItem.items(for: project.state))
        }
    }

    private func selectedItem(in items: [PlanTimelineItem]) -> PlanTimelineItem {
        items.first { $0.id == selectedItemID } ?? items.first { $0.id == PlanTimelineItem.immediateID } ?? items[0]
    }

    private func normalizeSelection(for items: [PlanTimelineItem]) {
        if !items.contains(where: { $0.id == selectedItemID }) {
            selectedItemID = items.first { $0.id == PlanTimelineItem.immediateID }?.id ?? items[0].id
        }
    }
}

private struct PlanWorkflowOverviewView: View {
    var overview: PlanWorkflowOverview
    var selectedKind: PlanWorkflowOverview.Kind?
    var onSelect: (PlanWorkflowOverview.Kind) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionHeader("Workflow Overview", systemImage: "rectangle.3.group")
                    Text("Current work, queued direction, and the strategic arc stay visible together.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label("\(overview.completedCount) completed", systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.55), in: Capsule())
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(overview.sections) { section in
                    PlanWorkflowOverviewCard(
                        section: section,
                        isSelected: section.kind == selectedKind
                    ) {
                        onSelect(section.kind)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlanWorkflowOverviewCard: View {
    var section: PlanWorkflowOverview.Section
    var isSelected: Bool
    var action: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            cardContent
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .help("Show \(section.title.lowercased())")
        .accessibilityLabel("\(section.label): \(section.title)")
        .accessibilityValue(section.excerpt ?? section.emptyMessage)
        .accessibilityHint("Shows this plan section in the focus panel.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader

            Text(section.excerpt ?? section.emptyMessage)
                .font(.callout)
                .foregroundStyle(section.isEmpty ? .secondary : .primary)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            PlanWorkflowMetadataRow(section: section, color: color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .background(color.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(borderOpacity), lineWidth: isSelected ? 1.5 : 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(isFocused ? 0.38 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .padding(3)
        }
    }

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: section.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(isSelected ? 0.2 : 0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.92))
                Text(section.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }

            Spacer(minLength: 8)

            statusIcon
        }
    }

    @ViewBuilder private var statusIcon: some View {
        ZStack {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(color)
            } else if isHovered || isFocused {
                Image(systemName: "chevron.right.circle")
                    .foregroundStyle(color.opacity(0.72))
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .frame(width: 18, height: 18)
    }

    private var color: Color {
        switch section.kind {
        case .immediate:
            return .blue
        case .midTerm:
            return .orange
        case .longTerm:
            return .purple
        }
    }

    private var backgroundOpacity: Double {
        if isSelected {
            return 0.15
        }

        return isHovered || isFocused ? 0.1 : 0.07
    }

    private var borderOpacity: Double {
        if isSelected {
            return 0.72
        }

        return isHovered || isFocused ? 0.38 : 0.2
    }
}

private struct PlanWorkflowMetadataRow: View {
    var section: PlanWorkflowOverview.Section
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            if let verifyCommand = section.verifyCommand {
                metadataLabel(verifyCommand, systemImage: "checkmark.seal")
                    .textSelection(.enabled)
            } else if section.kind == .immediate {
                metadataLabel("No verify command", systemImage: "checkmark.seal")
            }

            if let timeoutLabel = section.verifyTimeoutLabel {
                metadataLabel(timeoutLabel, systemImage: "timer")
            }

            if let difficulty = section.estimatedDifficultyLabel {
                metadataLabel(difficulty, systemImage: "gauge.with.dots.needle.bottom.50percent")
            } else if section.kind == .immediate {
                metadataLabel("No difficulty", systemImage: "gauge.with.dots.needle.bottom.50percent")
            }

            if let mutationTestingReadiness = section.mutationTestingReadiness {
                mutationReadinessLabel(mutationTestingReadiness, color: color)
            }

            if section.kind != .immediate {
                metadataLabel("\(section.completedCount) completed", systemImage: "checkmark.circle")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func metadataLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func mutationReadinessLabel(
        _ readiness: AgentMutationTestingPlan,
        color: Color
    ) -> some View {
        Label(readiness.badgeLabel, systemImage: readiness.systemImage)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(readiness.isReady ? 0.12 : 0.08), in: Capsule())
            .help(readiness.detailText)
    }
}

private struct PlanReliabilityFeedbackView: View {
    var feedback: PlanReliabilityFeedback

    var body: some View {
        if !feedback.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("Needs Attention", systemImage: "exclamationmark.triangle")

                    Spacer()

                    Label(
                        "\(feedback.notices.count) \(feedback.notices.count == 1 ? "cue" : "cues")",
                        systemImage: "waveform.path.ecg"
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.quaternary.opacity(0.55), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(feedback.notices) { notice in
                        PlanReliabilityNoticeRow(notice: notice)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sectionColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(sectionColor.opacity(0.2))
            }
        }
    }

    private var sectionColor: Color {
        feedback.notices.first.map { reliabilityColor(for: $0.severity) } ?? .red
    }
}

private struct PlanReliabilityNoticeRow: View {
    var notice: PlanReliabilityFeedback.Notice

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: notice.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(notice.title)
                        .font(.callout.weight(.semibold))

                    Text(notice.actionLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12), in: Capsule())

                    if let metadata = notice.metadata {
                        Text(metadata)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(notice.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var color: Color {
        reliabilityColor(for: notice.severity)
    }
}

private struct PlanTimelineHeader: View {
    var items: [PlanTimelineItem]
    @Binding var selectedItemID: String
    var completedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionHeader("Plan", systemImage: "map")
                    Text("Completed work fades into the rail; upcoming intent stays prominent.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("\(completedCount) completed", systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.55), in: Capsule())
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 0) {
                        ForEach(items) { item in
                            PlanTimelineTickButton(
                                item: item,
                                isSelected: item.id == selectedItemID
                            ) {
                                selectedItemID = item.id
                            }
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(alignment: .top) {
                        Capsule()
                            .fill(.secondary.opacity(0.16))
                            .frame(height: 3)
                            .padding(.horizontal, 16)
                            .padding(.top, 26)
                    }
                }
                .onChange(of: selectedItemID) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(selectedItemID, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(selectedItemID, anchor: .center)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PlanTimelineTickButton: View {
    var item: PlanTimelineItem
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(item.kind.color.opacity(isSelected ? 0.18 : item.kind.backgroundOpacity))
                        .frame(width: item.kind.hitSize, height: item.kind.hitSize)

                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: item.kind.iconSize, weight: .semibold))
                        .foregroundStyle(item.kind.color.opacity(isSelected ? 1 : item.kind.idleOpacity))
                        .frame(width: item.kind.hitSize, height: item.kind.hitSize)
                }
                .frame(height: 36)
                .overlay {
                    Circle()
                        .stroke(item.kind.color.opacity(isSelected ? 0.95 : 0), lineWidth: 2)
                }

                if item.kind.showsLabel {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .frame(width: item.kind.width)
                } else {
                    Text(" ")
                        .font(.caption)
                        .hidden()
                }
            }
            .frame(width: item.kind.width, height: 54, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.helpText)
        .accessibilityLabel(item.helpText)
    }
}

private struct PlanFocusPanel: View {
    var item: PlanTimelineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(item.title, systemImage: item.kind.systemImage)
                    .font(.headline)
                    .foregroundStyle(item.kind.color)

                Text(item.kind.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.7), in: Capsule())

                Spacer()

                if item.metadata != nil || item.verifyTimeoutLabel != nil {
                    HStack(spacing: 6) {
                        if let metadata = item.metadata {
                            Text(metadata)
                        }

                        if let timeoutLabel = item.verifyTimeoutLabel {
                            Label(timeoutLabel, systemImage: "timer")
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            MarkdownContent(item.body, empty: item.emptyMessage)

            if let verify = item.verify {
                VerifyCommandView(command: verify)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.kind.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.kind.color.opacity(0.22))
        }
    }
}

private struct VerifyCommandView: View {
    var command: String

    var body: some View {
        Label(command, systemImage: "checkmark.seal")
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(.top, 2)
    }
}

private struct PlanSessionHistorySection: View {
    var display: PlanSessionHistoryDisplay
    @Binding var showAllRuns: Bool
    @Binding var selectedFilter: PlanSessionHistoryFilter
    var runCues: [Int: PlanReliabilityFeedback.RunCue] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionHeader("Run History", systemImage: "clock.arrow.circlepath")
                    Text("Recent plan runs, checks, notes, and commits.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    if display.unfilteredTotalCount > 0 {
                        Picker("Status filter", selection: $selectedFilter) {
                            ForEach(display.filterOptions) { option in
                                Label(
                                    "\(option.filter.title) (\(option.count))",
                                    systemImage: option.filter.systemImage
                                )
                                .tag(option.filter)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }

                    Label(display.countSummary, systemImage: "number")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.quaternary.opacity(0.55), in: Capsule())

                    if display.shouldOfferModeToggle {
                        Button {
                            showAllRuns.toggle()
                        } label: {
                            Label(
                                display.mode == .all ? "Show Recent" : "Show All",
                                systemImage: display.mode == .all ? "clock.arrow.circlepath" : "list.bullet"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            if let hiddenStatusSummary = display.hiddenStatusSummary {
                Label(
                    hiddenSummaryText(hiddenStatusSummary),
                    systemImage: "archivebox"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if display.unfilteredTotalCount == 0 {
                EmptyState("No run history recorded.")
            } else if display.totalCount == 0 {
                EmptyState("No \(display.filter.emptyStateName) match this filter.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(display.visibleItems) { item in
                        PlanSessionHistoryCard(
                            item: item,
                            reliabilityCue: runCues[item.sessionNumber]
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hiddenSummaryText(_ statusSummary: String) -> String {
        let matchingText = display.filter == .all ? "" : " matching"
        return "\(display.hiddenCount) older\(matchingText) \(PlanSessionHistoryDisplay.runWord(for: display.hiddenCount)) hidden: \(statusSummary)"
    }
}

private struct PlanSessionHistoryCard: View {
    var item: PlanSessionHistoryItem
    var reliabilityCue: PlanReliabilityFeedback.RunCue?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(item.sessionNumber)")
                    .font(.headline.monospacedDigit())

                Text(item.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12), in: Capsule())

                if let reliabilityCue {
                    Label(reliabilityCue.label, systemImage: reliabilityCue.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(reliabilityColor(for: reliabilityCue.severity))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(reliabilityColor(for: reliabilityCue.severity).opacity(0.12), in: Capsule())
                        .help(reliabilityCue.detail)
                }

                Spacer()

                Text(dateString(item.startedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(item.planExcerpt ?? "No plan recorded.")
                .font(.callout)
                .foregroundStyle(item.planExcerpt == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let verifyCommand = item.verifyCommand {
                Label(verifyCommand, systemImage: "checkmark.seal")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Label("No verify command recorded.", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.runtimeRouteDescriptor.isSnapshotAvailable {
                RuntimeRouteBadge(descriptor: item.runtimeRouteDescriptor)
            }

            if let mutationTestingDescriptor = item.mutationTestingDescriptor {
                MutationTestingHistoryBadge(descriptor: mutationTestingDescriptor)
            }

            if let mutationRecoveryDescriptor = item.mutationRecoveryDescriptor {
                MutationTestingRecoveryHistoryBadge(descriptor: mutationRecoveryDescriptor)
            }

            if let feedback = item.feedback {
                LabeledHistoryBlock(title: "Feedback", systemImage: "text.bubble") {
                    MarkdownContent(feedback, compact: true)
                        .foregroundStyle(.secondary)
                }
            }

            if !item.notes.isEmpty {
                LabeledHistoryBlock(title: "Notes", systemImage: "note.text") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(item.notes, id: \.self) { note in
                            MarkdownContent(note, compact: true)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !item.commits.isEmpty {
                LabeledHistoryBlock(title: "Commits", systemImage: "arrow.triangle.branch") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(item.commits) { commit in
                            Label("\(commit.short) \(commit.subject)", systemImage: "arrow.triangle.branch")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if let failedVerify = item.failedVerify {
                DisclosureGroup("Verify failed (\(failedVerify.exitCodeText))") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(failedVerify.command)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        Text(failedVerify.tail)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.top, 4)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch item.status {
        case .planning:
            return .blue
        case .awaitingApproval:
            return .purple
        case .developing:
            return .orange
        case .succeeded:
            return .green
        case .failed, .rejectedByPlan:
            return .red
        case .cancelled, .skipped:
            return .secondary
        }
    }

    private func dateString(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private func reliabilityColor(for severity: PlanReliabilityFeedback.Severity) -> Color {
    switch severity {
    case .warning:
        return .orange
    case .failure:
        return .red
    case .paused:
        return .blue
    }
}

private func storageAssessmentColor(for severity: CompassWorkspaceStorageAssessment.Severity) -> Color {
    switch severity {
    case .healthy:
        return .green
    case .info:
        return .blue
    case .warning:
        return .orange
    case .failure:
        return .red
    }
}

private struct RuntimeRouteBadge: View {
    var descriptor: PlanSessionHistoryItem.RuntimeRouteDescriptor

    var body: some View {
        Label(descriptor.badgeText, systemImage: descriptor.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .help(descriptor.helpText)
    }
}

private struct MutationTestingHistoryBadge: View {
    var descriptor: PlanSessionHistoryItem.MutationTestingDescriptor

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "\(descriptor.routeLabel) · \(descriptor.languageLabel) · \(descriptor.exitCodeText) · \(descriptor.durationText)",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(descriptor.seedCommandLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !descriptor.tailSummary.isEmpty {
                    Text(descriptor.tailSummary)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.top, 4)
        } label: {
            Label(descriptor.badgeText, systemImage: descriptor.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help(descriptor.helpText)
    }

    private var color: Color {
        descriptor.isSuccessful ? .green : .red
    }
}

private struct MutationTestingRecoveryHistoryBadge: View {
    var descriptor: MutationTestingRecoveryDescriptor

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Label(descriptor.detailText, systemImage: descriptor.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(descriptor.copyText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))

                Button {
                    copyRuntimeDiagnosticsToPasteboard(descriptor.copyText)
                } label: {
                    Label(descriptor.copyActionLabel, systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        } label: {
            Label(descriptor.badgeText, systemImage: descriptor.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help(descriptor.helpText)
    }

    private var color: Color {
        descriptor.isActive ? .red : .secondary
    }
}

private struct LabeledHistoryBlock<Content: View>: View {
    var title: String
    var systemImage: String
    var content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PlanTimelineItem: Identifiable, Equatable {
    static let immediateID = PlanWorkflowOverview.TimelineDestination.immediate.itemID
    private static let midTermID = PlanWorkflowOverview.TimelineDestination.midTerm.itemID
    private static let longTermID = PlanWorkflowOverview.TimelineDestination.longTerm.itemID

    var id: String
    var kind: Kind
    var title: String
    var body: String
    var verify: String?
    var verifyTimeoutLabel: String?
    var metadata: String?
    var emptyMessage: String

    var helpText: String {
        switch kind {
        case .history:
            return "\(title): \(body)"
        default:
            return title
        }
    }

    static func items(for state: PlanState) -> [PlanTimelineItem] {
        let history = state.completed.enumerated().map { index, item in
            PlanTimelineItem(
                id: "plan-history-\(index)",
                kind: .history,
                title: "Iteration \(index + 1)",
                body: item,
                metadata: "#\(index + 1)",
                emptyMessage: "No detail recorded for this iteration."
            )
        }

        let immediate = PlanTimelineItem(
            id: immediateID,
            kind: .immediate,
            title: "Immediate",
            body: state.immediate?.plan ?? "",
            verify: state.immediate?.verify,
            verifyTimeoutLabel: state.immediate.map { PlanVerifyMetadata(timeoutMs: $0.verifyTimeoutMs).label },
            metadata: state.immediate?.estimatedDifficulty?.rawValue.capitalized,
            emptyMessage: "No immediate plan."
        )

        let midTerm = PlanTimelineItem(
            id: midTermID,
            kind: .midTerm,
            title: "Mid-Term",
            body: state.midTerm,
            emptyMessage: "No mid-term queue."
        )

        let longTerm = PlanTimelineItem(
            id: longTermID,
            kind: .longTerm,
            title: "Long-Term",
            body: state.longTerm,
            emptyMessage: "No long-term arc."
        )

        return history + [immediate, midTerm, longTerm]
    }

    enum Kind: Equatable {
        case history
        case immediate
        case midTerm
        case longTerm

        var label: String {
            switch self {
            case .history: return "History"
            case .immediate: return "Next"
            case .midTerm: return "Queue"
            case .longTerm: return "Arc"
            }
        }

        var systemImage: String {
            switch self {
            case .history: return "circle.fill"
            case .immediate: return "target"
            case .midTerm: return "point.3.connected.trianglepath.dotted"
            case .longTerm: return "mountain.2.fill"
            }
        }

        var color: Color {
            switch self {
            case .history: return .secondary
            case .immediate: return .blue
            case .midTerm: return .orange
            case .longTerm: return .purple
            }
        }

        var width: CGFloat {
            switch self {
            case .history: return 18
            case .immediate, .midTerm, .longTerm: return 112
            }
        }

        var hitSize: CGFloat {
            switch self {
            case .history: return 14
            case .immediate, .midTerm, .longTerm: return 34
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .history: return 5
            case .immediate, .midTerm, .longTerm: return 16
            }
        }

        var backgroundOpacity: Double {
            switch self {
            case .history: return 0.05
            case .immediate, .midTerm, .longTerm: return 0.13
            }
        }

        var idleOpacity: Double {
            switch self {
            case .history: return 0.36
            case .immediate, .midTerm, .longTerm: return 0.85
            }
        }

        var showsLabel: Bool {
            self != .history
        }
    }
}

private struct DraftsTab: View {
    @ObservedObject var project: CompassProject
    @State private var draftRefinementPreview: DraftRefinement?
    @State private var draftRefinementTask: Task<Void, Never>?
    @State private var draftRefinementCache: [DraftRefinementPreviewKey: DraftRefinement] = [:]
    @State private var activeDraftRefinementKey: DraftRefinementPreviewKey?
    @State private var isDraftRefinementGenerating = false
    @State private var isDraftRefinementModelAvailable = DraftRefinementService.isPreviewAvailable

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("New Draft", systemImage: "square.and.pencil")
            HStack(alignment: .top, spacing: 10) {
                TextField("Describe the next direction", text: $project.draftEntry, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await project.addDraft() }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!project.hasRepository || project.draftEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if shouldShowDraftRefinementPreview {
                DraftRefinementPreviewCard(
                    refinement: draftRefinementPreview,
                    isGenerating: isDraftRefinementGenerating,
                    canAccept: project.hasRepository,
                    accept: acceptDraftRefinement,
                    modify: modifyDraftRefinement
                )
            }

            HStack {
                SectionHeader("Pending Drafts", systemImage: "tray")
                Spacer()
                Button {
                    Task { await project.saveDrafts() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!project.hasRepository)
            }
            TextEditor(text: $project.drafts)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if project.drafts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No drafts queued.")
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
        }
        .onAppear {
            refreshDraftRefinementAvailability()
        }
        .onDisappear {
            cancelDraftRefinementPreview()
        }
        .onChange(of: project.draftEntry) {
            scheduleDraftRefinementPreview()
        }
        .onChange(of: project.state) {
            scheduleDraftRefinementPreview()
        }
        .onChange(of: project.languageProfile) {
            scheduleDraftRefinementPreview()
        }
        .onChange(of: project.repoURL) {
            scheduleDraftRefinementPreview()
        }
    }

    private var trimmedDraftEntry: String {
        DraftRefinementService.normalizeDraft(project.draftEntry)
    }

    private var draftRefinementContext: DraftRefinementContext {
        DraftRefinementContext(project: project)
    }

    private var shouldShowDraftRefinementPreview: Bool {
        isDraftRefinementModelAvailable
            && !trimmedDraftEntry.isEmpty
            && (isDraftRefinementGenerating || draftRefinementPreview != nil)
    }

    private func refreshDraftRefinementAvailability() {
        isDraftRefinementModelAvailable = DraftRefinementService.isPreviewAvailable
        if isDraftRefinementModelAvailable {
            scheduleDraftRefinementPreview()
        } else {
            cancelDraftRefinementPreview()
        }
    }

    private func scheduleDraftRefinementPreview() {
        isDraftRefinementModelAvailable = DraftRefinementService.isPreviewAvailable
        let context = draftRefinementContext
        let plan = DraftRefinementPreviewPlanner.plan(
            draft: project.draftEntry,
            context: context,
            isModelAvailable: isDraftRefinementModelAvailable,
            cachedKeys: Set(draftRefinementCache.keys)
        )

        switch plan.visibility {
        case .hiddenEmptyDraft, .hiddenUnavailableModel:
            cancelDraftRefinementPreview()
        case .cached:
            draftRefinementTask?.cancel()
            isDraftRefinementGenerating = false
            activeDraftRefinementKey = plan.cacheKey
            draftRefinementPreview = plan.cacheKey.flatMap { draftRefinementCache[$0] }
        case .debounce:
            guard let key = plan.cacheKey else {
                cancelDraftRefinementPreview()
                return
            }
            draftRefinementTask?.cancel()
            activeDraftRefinementKey = key
            draftRefinementPreview = nil
            isDraftRefinementGenerating = false
            let draft = key.trimmedDraft
            draftRefinementTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: plan.delayNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled, activeDraftRefinementKey == key else { return }
                isDraftRefinementGenerating = true
                let refinement = await DraftRefinementService.makeRefinement(
                    draft: draft,
                    context: context
                )
                guard !Task.isCancelled, activeDraftRefinementKey == key else { return }
                if let refinement {
                    draftRefinementCache[key] = refinement
                    trimDraftRefinementCache()
                }
                draftRefinementPreview = refinement
                isDraftRefinementGenerating = false
            }
        }
    }

    private func cancelDraftRefinementPreview() {
        draftRefinementTask?.cancel()
        draftRefinementTask = nil
        activeDraftRefinementKey = nil
        draftRefinementPreview = nil
        isDraftRefinementGenerating = false
    }

    private func trimDraftRefinementCache() {
        while draftRefinementCache.count > 12, let key = draftRefinementCache.keys.first {
            draftRefinementCache.removeValue(forKey: key)
        }
    }

    private func acceptDraftRefinement(_ refinement: DraftRefinement) {
        cancelDraftRefinementPreview()
        Task {
            await project.acceptDraftRefinement(refinement)
        }
    }

    private func modifyDraftRefinement(_ refinement: DraftRefinement) {
        cancelDraftRefinementPreview()
        project.modifyDraft(with: refinement)
    }
}

private struct DraftRefinementPreviewCard: View {
    var refinement: DraftRefinement?
    var isGenerating: Bool
    var canAccept: Bool
    var accept: (DraftRefinement) -> Void
    var modify: (DraftRefinement) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Refined draft", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let refinement {
                Text(refinement.refinedText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        modify(refinement)
                    } label: {
                        Label("Modify", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        accept(refinement)
                    } label: {
                        Label("Accept", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAccept)
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.26), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.12))
        }
    }
}

private struct LiveTab: View {
    @ObservedObject var project: CompassProject
    @State private var liveActivitySummaryCache: [String: LiveActivitySummary] = [:]
    @State private var liveActivitySummaryInFlightKeys: Set<String> = []
    @State private var expandedLiveActivityClusterKeys: Set<String> = []
    @State private var liveActivityPlanningNow = Date()
    private static let thinkingRowID = "live-thinking-row"

    var body: some View {
        let reliabilityStatus = project.reliabilityStatus
        let liveActivityInputIdentifier = LiveActivitySummaryPlanner.inputIdentifier(for: project.liveLog)
        let liveActivityPlan = LiveActivitySummaryPlanner.plan(
            lines: project.liveLog,
            now: liveActivityPlanningNow
        )
        let liveActivitySummaryIdentifier = liveActivityPlan.frozenClusters
            .map(\.key)
            .joined(separator: "|")

        VStack(alignment: .leading, spacing: 10) {
            if !reliabilityStatus.isEmpty {
                ProjectReliabilityBanner(status: reliabilityStatus)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(liveActivityPlan.items) { item in
                            switch item {
                            case .frozenCluster(let cluster):
                                LiveActivityClusterRow(
                                    cluster: cluster,
                                    summary: liveActivitySummaryCache[cluster.key]
                                        ?? LiveActivitySummaryService.deterministicSummary(for: cluster),
                                    isGenerating: liveActivitySummaryInFlightKeys.contains(cluster.key),
                                    isExpanded: expansionBinding(for: cluster.key)
                                )
                                .id(item.id)
                            case .line(let line):
                                LiveRow(line: line)
                                    .id(item.id)
                            }
                        }
                        if showsThinkingIndicator {
                            ThinkingLiveRow(phase: project.phase)
                                .id(Self.thinkingRowID)
                        }
                    }
                    .padding(10)
                }
                .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: project.liveLog.count) {
                    scrollToLiveEnd(proxy, liveActivityPlan: liveActivityPlan)
                }
                .onChange(of: liveActivitySummaryIdentifier) {
                    scrollToLiveEnd(proxy, liveActivityPlan: liveActivityPlan)
                }
                .onChange(of: project.isRunning) {
                    scrollToLiveEnd(proxy, liveActivityPlan: liveActivityPlan)
                }
                .onChange(of: showsThinkingIndicator) {
                    scrollToLiveEnd(proxy, liveActivityPlan: liveActivityPlan)
                }
                .task(id: liveActivityInputIdentifier) {
                    await refreshLiveActivityPlanningClock()
                }
                .task(id: liveActivitySummaryIdentifier) {
                    refreshLiveActivitySummaries(for: liveActivityPlan.frozenClusters)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var showsThinkingIndicator: Bool {
        project.isRunning && !project.liveLog.contains {
            $0.status == .running && ($0.kind == .command || $0.kind == .fileChange)
        }
    }

    @MainActor
    private func refreshLiveActivityPlanningClock() async {
        liveActivityPlanningNow = Date()
        let delay = LiveActivitySummaryPlanner.quietGap + 0.25
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled else { return }
        liveActivityPlanningNow = Date()
    }

    @MainActor
    private func refreshLiveActivitySummaries(for clusters: [LiveActivityCluster]) {
        let cachePlan = LiveActivitySummaryCachePlanner.plan(
            clusters: clusters,
            cachedKeys: Set(liveActivitySummaryCache.keys),
            inFlightKeys: liveActivitySummaryInFlightKeys
        )

        for staleKey in cachePlan.staleCacheKeys {
            liveActivitySummaryCache.removeValue(forKey: staleKey)
        }
        liveActivitySummaryInFlightKeys.subtract(cachePlan.staleInFlightKeys)

        for cluster in cachePlan.requestedClusters {
            liveActivitySummaryInFlightKeys.insert(cluster.key)
            Task { [cluster] in
                let summary = await LiveActivitySummaryService.makeSummary(for: cluster)
                await MainActor.run {
                    guard liveActivitySummaryInFlightKeys.contains(cluster.key) else { return }
                    liveActivitySummaryCache[cluster.key] = summary
                    liveActivitySummaryInFlightKeys.remove(cluster.key)
                }
            }
        }
    }

    private func expansionBinding(for key: String) -> Binding<Bool> {
        Binding {
            expandedLiveActivityClusterKeys.contains(key)
        } set: { isExpanded in
            if isExpanded {
                expandedLiveActivityClusterKeys.insert(key)
            } else {
                expandedLiveActivityClusterKeys.remove(key)
            }
        }
    }

    private func scrollToLiveEnd(
        _ proxy: ScrollViewProxy,
        liveActivityPlan: LiveActivitySummaryPlan
    ) {
        if showsThinkingIndicator {
            proxy.scrollTo(Self.thinkingRowID, anchor: .bottom)
        } else if let last = liveActivityPlan.items.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

private struct LiveActivityClusterRow: View {
    var cluster: LiveActivityCluster
    var summary: LiveActivitySummary
    var isGenerating: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(cluster.lines) { line in
                    LiveRow(line: line)
                        .id(line.id)
                }
            }
            .padding(.top, 5)
            .padding(.leading, 10)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(timestamp(cluster.startDate))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)

                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(summary.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .textSelection(.enabled)

                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.72)
                        }

                        Spacer(minLength: 6)
                    }

                    HStack(spacing: 6) {
                        Text(countLabel)
                        if let durationLabel {
                            Text(durationLabel)
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.secondary.opacity(0.12))
        }
    }

    private var countLabel: String {
        let count = cluster.lines.count
        return count == 1 ? "1 event" : "\(count) events"
    }

    private var durationLabel: String? {
        guard let startDate = cluster.startDate,
              let endDate = cluster.endDate else {
            return nil
        }
        let seconds = max(0, endDate.timeIntervalSince(startDate))
        if seconds < 1 {
            return "\(Int((seconds * 1000).rounded()))ms"
        }
        return String(format: "%.1fs", seconds)
    }

    private var iconName: String {
        switch cluster.freezeReason {
        case .lifecycleBoundary:
            return "flag.checkered"
        case .quietGap:
            return "rectangle.stack.fill"
        }
    }

    private var iconColor: Color {
        if cluster.lines.contains(where: { $0.status == .failed || $0.level == .error }) {
            return .red
        }
        if cluster.lines.contains(where: { $0.level == .warning }) {
            return .orange
        }
        return .blue
    }

    private func timestamp(_ date: Date?) -> String {
        guard let date else { return "batch" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct ProjectReliabilityBanner: View {
    var status: ProjectReliabilityStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(status.primaryCue)
                        .font(.callout.weight(.semibold))

                    Text(status.actionLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12), in: Capsule())

                    if let metadata = status.metadata {
                        Text(metadata)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(status.countLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(status.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.22))
        }
        .help(helpText)
    }

    private var color: Color {
        reliabilityColor(for: status.severity)
    }

    private var helpText: String {
        [
            status.primaryCue,
            status.actionLabel,
            status.metadata,
            status.detail
        ]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }
}

private struct LiveRow: View {
    var line: LiveLine

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timestamp(line.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            LiveStatusIcon(line: line)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.text)
                        .font(.callout.weight(titleWeight))
                        .foregroundStyle(titleColor)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let duration {
                        Text(duration)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.7), in: Capsule())
                    }
                }

                if let detail = line.detail, !detail.isEmpty {
                    LiveDetail(line: line, detail: detail)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
    }

    private var titleWeight: Font.Weight {
        switch line.status {
        case .running:
            return .semibold
        default:
            return line.kind == .lifecycle ? .regular : .medium
        }
    }

    private var titleColor: Color {
        switch line.level {
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        case .raw:
            return .primary.opacity(0.82)
        case .info:
            return .primary
        }
    }

    private var rowBackground: Color {
        switch line.status {
        case .running:
            return .blue.opacity(0.07)
        case .failed:
            return .red.opacity(0.08)
        default:
            return .clear
        }
    }

    private var duration: String? {
        guard let completedAt = line.completedAt else { return nil }
        let seconds = completedAt.timeIntervalSince(line.date)
        if seconds < 1 {
            return "\(Int((seconds * 1000).rounded()))ms"
        }
        return String(format: "%.1fs", seconds)
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct ThinkingLiveRow: View {
    var phase: LoopPhase
    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("live")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            Image(systemName: "brain.head.profile")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .scaleEffect(isAnimating ? 1.12 : 0.92)
                .opacity(isAnimating ? 1 : 0.55)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    ThinkingDots()
                }
                .foregroundStyle(.primary)

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .onAppear {
            isAnimating = true
        }
        .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: isAnimating)
    }

    private var title: String {
        switch phase {
        case .planning:
            return "Agent is planning"
        case .developing:
            return "Agent is thinking"
        case .verifying:
            return "Compass is checking"
        default:
            return "Agent is working"
        }
    }

    private var detail: String {
        switch phase {
        case .planning:
            return "Waiting for the next planning event."
        case .developing:
            return "Waiting for the next development event."
        case .verifying:
            return "Running post-checks for this project."
        default:
            return "Waiting for the next live event."
        }
    }
}

private struct ThinkingDots: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 3.5, height: 3.5)
                    .opacity(isAnimating ? 1 : 0.28)
                    .animation(
                        .easeInOut(duration: 0.65)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.16),
                        value: isAnimating
                    )
            }
        }
        .padding(.top, 8)
        .onAppear {
            isAnimating = true
        }
    }
}

private struct LiveStatusIcon: View {
    var line: LiveLine

    var body: some View {
        switch line.status {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .none:
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        switch line.level {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .info, .raw:
            switch line.kind {
            case .command:
                return "terminal"
            case .agentMessage:
                return "sparkles"
            case .fileChange:
                return "doc.badge.gearshape"
            case .lifecycle:
                return "circle"
            case .message:
                return "info.circle"
            }
        }
    }

    private var iconColor: Color {
        switch line.level {
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        case .raw:
            return .secondary
        case .info:
            return .blue
        }
    }
}

private struct LiveDetail: View {
    var line: LiveLine
    var detail: String

    var body: some View {
        switch line.kind {
        case .command:
            Text(detail)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(nil)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
        case .agentMessage:
            MarkdownContent(detail, compact: true)
                .foregroundStyle(.secondary)
        default:
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct VisionTab: View {
    @ObservedObject var project: CompassProject
    @State private var mode = MarkdownDocumentMode.preview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader("Project Vision", systemImage: "scope")
                Spacer()
                Picker("Vision display mode", selection: $mode) {
                    ForEach(MarkdownDocumentMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                Button {
                    Task { await project.saveVision() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
            MarkdownDocumentBody(text: $project.vision, mode: mode, empty: "No project vision.")
        }
    }
}

private struct LessonsTab: View {
    @ObservedObject var project: CompassProject

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Lessons", systemImage: "book.closed")
            ScrollView {
                MarkdownBlock(project.lessons, empty: "No lessons captured.")
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct SectionHeader: View {
    var title: String
    var systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}

private enum MarkdownDocumentMode: String, CaseIterable, Identifiable {
    case preview = "Preview"
    case edit = "Edit"

    var id: Self { self }
}

private struct MarkdownDocumentBody: View {
    @Binding var text: String
    var mode: MarkdownDocumentMode
    var empty: String

    var body: some View {
        Group {
            switch mode {
            case .preview:
                ScrollView {
                    MarkdownBlock(text, empty: empty)
                        .padding(12)
                }
            case .edit:
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MarkdownBlock: View {
    var text: String
    var empty: String

    init(_ text: String, empty: String) {
        self.text = text
        self.empty = empty
    }

    var body: some View {
        MarkdownContent(text, empty: empty)
    }
}

private struct EmptyState: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

private func phaseColor(_ phase: LoopPhase) -> Color {
    switch phase {
    case .idle: return .secondary
    case .planning: return .blue
    case .developing: return .orange
    case .verifying: return .purple
    case .paused: return .yellow
    case .failed: return .red
    case .succeeded: return .green
    case .cancelled: return .yellow
    }
}

import AppKit
import SwiftUI

struct NoProjectView: View {
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

struct MainWorkspaceView: View {
  @ObservedObject var project: CompassProject
  @State private var selectedTab: WorkspaceTab = .live

  var body: some View {
    VStack(spacing: 0) {
      WorkspaceHeader(project: project, selectedTab: $selectedTab)
      Divider()
      WorkspaceContent(
        project: project,
        selectedTab: $selectedTab
      )
      .padding(16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

struct WorkspaceHeader: View {
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
          let repairAction = storageDisplayStatus.supportRepairAction
        {
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

extension CompassProject {
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

struct ProjectStorageAssessmentPill: View {
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
      displayStatus.recommendation,
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
      ]
    }

    return
      lines
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
  }

  private var missingCoreFilesText: String {
    guard !preflight.missingCoreFiles.isEmpty else {
      return "Missing core files: none"
    }
    return
      "Missing core files: \(preflight.missingCoreFiles.map(\.relativePath).joined(separator: ", "))"
  }

  private func candidateText(
    _ candidate: CompassWorkspaceStoragePreflight.ApplicationSupportCandidate
  ) -> String {
    "Support candidate: \(candidate.occupancy.displayName) \(candidate.url.path)"
  }
}

struct ProjectActivitySourceStatusPill: View {
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

struct ProjectStorageMigrationButton: View {
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

struct ProjectStorageActivationButton: View {
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

struct ProjectStorageRepairButton: View {
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

struct ProjectReliabilityAttentionPill: View {
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
      status.detail,
    ]
    .compactMap { $0?.isEmpty == false ? $0 : nil }
    .joined(separator: " · ")
  }
}

struct ProjectPhasePill: View {
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

struct ProjectRunControls: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject var project: CompassProject
  @State private var runGuideNarration: ProjectRunControlGuideNarration?

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
    let runGuide = ProjectRunControlGuide(
      state: project.state,
      reliabilityStatus: project.reliabilityStatus,
      hasRepository: project.hasRepository,
      isRunning: project.isRunning,
      isAutoPlaying: project.isAutoPlaying,
      isPaused: project.isPaused,
      languageProfile: project.languageProfile,
      forgeProfile: project.forgeProfile,
      drafts: project.drafts
    )
    let runNarration = matchingNarration(for: runGuide)
    let primaryExplanation = runNarration?.text ?? runGuide.primaryHelp

    HStack(spacing: 5) {
      Menu {
        Text(executionEnvironmentMenu.statusText)
        Divider()
        Button {
          project.hostXcodeBuildTestEnabled.toggle()
          model.saveProjects()
        } label: {
          Label(
            project.hostXcodeBuildTestEnabled
              ? "Disable Host Xcode Build/Test" : "Enable Host Xcode Build/Test",
            systemImage: project.hostXcodeBuildTestEnabled ? "checkmark.square" : "square"
          )
        }
        Text(
          "Routes Swift and Xcode build/test through the host. Also in Settings (⌘,) → Factory."
        )
        SettingsLink {
          Label("Open Factory Settings…", systemImage: "hammer")
        }
        Divider()
        let diagnosticsAction = executionEnvironmentMenu.copyDiagnosticsAction
        Button {
          copyRuntimeDiagnosticsToPasteboard(diagnosticsAction.copyText)
        } label: {
          Label(diagnosticsAction.title, systemImage: diagnosticsAction.systemImage)
        }
        Text(diagnosticsAction.description)
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
        run(runGuide.primaryOption.kind)
      } label: {
        Label(runGuide.primaryOption.title, systemImage: runGuide.primaryOption.systemImage)
          .lineLimit(1)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!runGuide.primaryOption.isEnabled)
      .help("\(primaryExplanation) \(runGuide.primaryOption.detail)")
      .accessibilityHint(runGuide.primaryOption.detail)

      Menu {
        Label(runGuide.readiness.title, systemImage: runGuide.readiness.systemImage)
        Text(runGuide.readiness.detail)
        if let runNarration {
          Divider()
          Label("Run note", systemImage: "sparkles")
          Text(runNarration.text)
        }
        Divider()
        Label("Next run preview", systemImage: "list.bullet.rectangle")
        ForEach(runGuide.previewSteps) { step in
          Label(step.title, systemImage: step.systemImage)
          Text(step.detail)
        }
        Divider()
        ForEach(runGuide.options) { option in
          Button {
            run(option.kind)
          } label: {
            Label(option.title, systemImage: option.systemImage)
          }
          .disabled(!option.isEnabled)
          Text(option.detail)
        }
      } label: {
        Image(systemName: "chevron.down.circle")
          .frame(width: 18, height: 18)
      }
      .menuStyle(.borderlessButton)
      .disabled(project.isRunning || project.isAutoPlaying || !project.hasRepository)
      .help("Choose a factory run mode. \(runGuide.primaryHelp)")

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
    .task(id: runGuide.narrationIdentifier) {
      runGuideNarration = nil
      runGuideNarration = await ProjectRunControlGuideNarrator.narrate(guide: runGuide)
    }
  }

  private func run(_ kind: ProjectRunControlGuide.Kind) {
    Task {
      switch kind {
      case .loop:
        await project.play(
          agentSettings: model.agentSettings,
          modelOverride: model.modelOverride
        )
      case .planOnly:
        await project.runPlanOnly(
          agentSettings: model.agentSettings,
          modelOverride: model.modelOverride
        )
      case .developOnly:
        await project.runDevelopOnly(
          agentSettings: model.agentSettings,
          modelOverride: model.modelOverride
        )
      }
    }
  }

  private func matchingNarration(
    for guide: ProjectRunControlGuide
  ) -> ProjectRunControlGuideNarration? {
    guard runGuideNarration?.guideIdentifier == guide.narrationIdentifier else {
      return nil
    }
    return runGuideNarration
  }
}

struct WorkspaceTabButton: View {
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
        .frame(minWidth: tab.minWidth)
    }
    .buttonStyle(.plain)
    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
    .background(
      selectedTab == tab ? Color.accentColor.opacity(0.16) : Color.clear,
      in: RoundedRectangle(cornerRadius: 7)
    )
  }
}

struct WorkspaceContent: View {
  @ObservedObject var project: CompassProject
  @Binding var selectedTab: WorkspaceTab
  @State private var keepExploreTabMounted = false

  var body: some View {
    ZStack(alignment: .topLeading) {
      switch selectedTab {
      case .live:
        LiveTab(project: project)
      case .plan:
        PlanTab(project: project)
      case .drafts:
        DraftsTab(project: project)
      case .assumptions:
        AssumptionsTab(project: project)
      case .vision:
        VisionTab(project: project)
      case .lessons:
        LessonsTab(project: project)
      case .world:
        WorldTab(
          repoURL: project.repoURL,
          workspace: project.workspace,
          isActive: selectedTab == .world,
          onOpenInExplore: { _ in
            keepExploreTabMounted = true
            selectedTab = .explore
          }
        )
      case .explore:
        Color.clear
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityHidden(true)
      }

      if keepExploreTabMounted {
        ExploreTab(
          repoURL: project.repoURL,
          workspace: project.workspace,
          isActive: selectedTab == .explore,
          sessionRecords: { project.allSessions },
          onLoadArchivedSessions: {
            await project.loadArchivedSessionsIfNeeded()
          }
        )
        .equatable()
        .opacity(selectedTab == .explore ? 1 : 0)
        .allowsHitTesting(selectedTab == .explore)
        .accessibilityHidden(selectedTab != .explore)
      }
    }
    .onChange(of: selectedTab) { _, tab in
      if tab == .explore {
        keepExploreTabMounted = true
      }
    }
  }
}

enum WorkspaceTab: String, CaseIterable, Identifiable {
  case live
  case plan
  case drafts
  case assumptions
  case vision
  case lessons
  case world
  case explore

  var id: Self { self }

  var title: String {
    switch self {
    case .live: return "Live"
    case .plan: return "Plan"
    case .drafts: return "Drafts"
    case .assumptions: return "Assumptions"
    case .vision: return "Vision"
    case .lessons: return "Lessons"
    case .world: return "World"
    case .explore: return "Explore"
    }
  }

  var systemImage: String {
    switch self {
    case .live: return "waveform.path.ecg"
    case .plan: return "map"
    case .drafts: return "square.and.pencil"
    case .assumptions: return "checklist.checked"
    case .vision: return "scope"
    case .lessons: return "book.closed"
    case .world: return "cube.transparent"
    case .explore: return "magnifyingglass"
    }
  }

  var minWidth: CGFloat {
    switch self {
    case .assumptions:
      return 116
    default:
      return 82
    }
  }
}

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let project = model.selectedProject {
                MainWorkspaceView(project: project)
                    .id(project.id)
            } else {
                NoProjectView()
            }
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Compass", systemImage: "safari")
                    .font(.title2.weight(.semibold))
                Text("Codex-powered macOS workspace")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

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
                                isSelected: project.id == model.selectedProjectID
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
                    TextField("codex binary", text: $model.codexBinary)
                        .textFieldStyle(.roundedBorder)
                    TextField("model override", text: $model.modelOverride)
                        .textFieldStyle(.roundedBorder)
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

private struct ProjectListRow: View {
    @ObservedObject var project: CompassProject
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProjectPhaseMark(project: project)
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

                Text(project.immediateTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
    }
}

private struct ProjectPhaseMark: View {
    @ObservedObject var project: CompassProject

    var body: some View {
        Group {
            if project.isRunning || project.isAutoPlaying {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(phaseColor(project.isPaused ? .paused : project.phase))
                    .frame(width: 9, height: 9)
            }
        }
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
    @State private var hasOpenedCinematic = false

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(project: project, selectedTab: $selectedTab)
            Divider()
            WorkspaceContent(project: project, selectedTab: selectedTab)
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
                .background {
                    if hasOpenedCinematic && selectedTab != .cinematic {
                        CinematicSceneView(
                            projectID: project.id,
                            lines: project.liveLog,
                            phase: project.phase,
                            isActive: project.isRunning || project.isAutoPlaying,
                            languageProfile: project.languageProfile,
                            activityProfile: project.activityProfile,
                            influenceSettings: project.cinematicInfluenceSettings
                        )
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
        }
        .onAppear {
            if selectedTab == .cinematic {
                hasOpenedCinematic = true
            }
        }
        .onChange(of: selectedTab) {
            if selectedTab == .cinematic {
                hasOpenedCinematic = true
            }
        }
    }
}

private struct WorkspaceHeader: View {
    @ObservedObject var project: CompassProject
    @Binding var selectedTab: WorkspaceTab

    var body: some View {
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
        HStack(spacing: 5) {
            Menu {
                ForEach(NativeFeedbackMode.allCases) { mode in
                    Button {
                        project.nativeFeedbackMode = mode
                        NativeFeedbackService.shared.applyModeChange(mode)
                        model.saveProjects()
                    } label: {
                        Label(
                            mode.title,
                            systemImage: project.nativeFeedbackMode == mode ? "checkmark" : mode.systemImage
                        )
                    }
                }
            } label: {
                Image(systemName: project.nativeFeedbackMode.systemImage)
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .help("Feedback: \(project.nativeFeedbackMode.title)")

            Button {
                Task {
                    await project.play(
                        codexBinary: model.codexBinary,
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

    var body: some View {
        switch selectedTab {
        case .live:
            LiveTab(project: project)
        case .cinematic:
            CinematicTab(project: project)
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

    var body: some View {
        let items = PlanTimelineItem.items(for: project.state)
        let overview = PlanWorkflowOverview(state: project.state)
        let sessionHistory = PlanSessionHistory.displayItems(for: project.sessions)
        let reliabilityFeedback = PlanReliabilityFeedback(
            state: project.state,
            sessions: project.sessions,
            historyItems: sessionHistory
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
                    items: sessionHistory,
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
    var items: [PlanSessionHistoryItem]
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
                Label("\(items.count) runs", systemImage: "number")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.55), in: Capsule())
            }

            if items.isEmpty {
                EmptyState("No run history recorded.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
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
    }
}

private struct LiveTab: View {
    @ObservedObject var project: CompassProject
    private static let thinkingRowID = "live-thinking-row"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(project.liveLog) { line in
                        LiveRow(line: line)
                            .id(line.id)
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
                scrollToLiveEnd(proxy)
            }
            .onChange(of: project.isRunning) {
                scrollToLiveEnd(proxy)
            }
            .onChange(of: showsThinkingIndicator) {
                scrollToLiveEnd(proxy)
            }
        }
    }

    private var showsThinkingIndicator: Bool {
        project.isRunning && !project.liveLog.contains {
            $0.status == .running && ($0.kind == .command || $0.kind == .fileChange)
        }
    }

    private func scrollToLiveEnd(_ proxy: ScrollViewProxy) {
        if showsThinkingIndicator {
            proxy.scrollTo(Self.thinkingRowID, anchor: .bottom)
        } else if let last = project.liveLog.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
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
            return "Codex is planning"
        case .developing:
            return "Codex is thinking"
        case .verifying:
            return "Compass is checking"
        default:
            return "Codex is working"
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

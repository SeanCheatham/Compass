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
                Label("CompassNative", systemImage: "safari")
                    .font(.title2.weight(.semibold))
                Text("Codex-only macOS prototype")
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
        case .state:
            StateTab(project: project)
        case .drafts:
            DraftsTab(project: project)
        case .vision:
            VisionTab(project: project)
        case .lessons:
            LessonsTab(project: project)
        case .history:
            HistoryTab(project: project)
        }
    }
}

private enum WorkspaceTab: String, CaseIterable, Identifiable {
    case live
    case state
    case drafts
    case vision
    case lessons
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .live: return "Live"
        case .state: return "State"
        case .drafts: return "Drafts"
        case .vision: return "Vision"
        case .lessons: return "Lessons"
        case .history: return "History"
        }
    }

    var systemImage: String {
        switch self {
        case .live: return "waveform.path.ecg"
        case .state: return "list.bullet.rectangle"
        case .drafts: return "square.and.pencil"
        case .vision: return "scope"
        case .lessons: return "book.closed"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

private struct StateTab: View {
    @ObservedObject var project: CompassProject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader("Immediate", systemImage: "target")
                if let immediate = project.state.immediate {
                    MarkdownBlock(immediate.plan, empty: "No immediate plan.")
                    Label(immediate.verify, systemImage: "checkmark.seal")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    EmptyState("No immediate plan.")
                }

                Divider()

                SectionHeader("Completed", systemImage: "checklist")
                if project.state.completed.isEmpty {
                    EmptyState("No shipped iterations yet.")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(project.state.completed, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                                    .frame(width: 18)
                                InlineMarkdownText(text: item)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                Divider()

                SectionHeader("Mid-Term", systemImage: "point.3.connected.trianglepath.dotted")
                MarkdownBlock(project.state.midTerm, empty: "No mid-term queue.")

                Divider()

                SectionHeader("Long-Term", systemImage: "mountain.2")
                MarkdownBlock(project.state.longTerm, empty: "No long-term arc.")
            }
            .frame(maxWidth: 900, alignment: .leading)
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

private struct HistoryTab: View {
    @ObservedObject var project: CompassProject

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if project.sessions.isEmpty {
                    EmptyState("No history recorded.")
                } else {
                    ForEach(project.sessions.sorted { $0.startedAt > $1.startedAt }) { session in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("#\(session.session)")
                                    .font(.headline)
                                Text(session.status.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                                Spacer()
                                Text(dateString(session.startedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let plan = session.plan {
                                MarkdownContent(plan, compact: true)
                            }
                            if let verify = session.verify {
                                Text(verify)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            if let feedback = session.feedback, !feedback.isEmpty {
                                MarkdownContent(feedback, compact: true)
                                    .foregroundStyle(.secondary)
                            }
                            if let verifyOutput = session.verifyOutput {
                                DisclosureGroup("verify failed (\(verifyOutput.exitCode.map { String($0) } ?? "exit unknown"))") {
                                    Text(verifyOutput.tail)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 4)
                                }
                            }
                            ForEach(session.notes, id: \.self) { note in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "note.text")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)
                                    MarkdownContent(note, compact: true)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ForEach(session.commits) { commit in
                                Label("\(commit.short) \(commit.subject)", systemImage: "arrow.triangle.branch")
                                    .font(.caption)
                            }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func dateString(_ milliseconds: Double) -> String {
        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        return date.formatted(date: .abbreviated, time: .shortened)
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

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            MainWorkspaceView()
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label("CompassNative", systemImage: "safari")
                    .font(.title2.weight(.semibold))
                Text("Codex-only macOS prototype")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Repository")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Repository path", text: $model.repoPath)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button {
                        Task { await model.chooseRepository() }
                    } label: {
                        Label("Choose", systemImage: "folder")
                    }
                    Button {
                        Task { await model.initializeWorkspace() }
                    } label: {
                        Label("Init", systemImage: "plus.circle")
                    }
                    .disabled(!model.hasRepository)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Codex")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("codex binary", text: $model.codexBinary)
                    .textFieldStyle(.roundedBorder)
                TextField("model override", text: $model.modelOverride)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle()
                        .fill(phaseColor)
                        .frame(width: 9, height: 9)
                    Text(model.phase.rawValue)
                        .font(.headline)
                }

                Text(model.immediateTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 8) {
                Button {
                    Task { await model.runIteration() }
                } label: {
                    Label("Run Iteration", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning || !model.hasRepository)

                HStack {
                    Button {
                        Task { await model.runPlanOnly() }
                    } label: {
                        Label("Plan", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isRunning || !model.hasRepository)

                    Button {
                        Task { await model.runDevelopOnly() }
                    } label: {
                        Label("Develop", systemImage: "hammer")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(model.isRunning || !model.hasRepository || model.state.immediate == nil)
                }

                Button {
                    model.cancelRun()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.isRunning)

                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.hasRepository)
            }

            Spacer()
        }
        .padding()
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
    }

    private var phaseColor: Color {
        switch model.phase {
        case .idle: return .secondary
        case .planning: return .blue
        case .developing: return .orange
        case .verifying: return .purple
        case .failed: return .red
        case .succeeded: return .green
        case .cancelled: return .yellow
        }
    }
}

private struct MainWorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            StateTab()
                .tabItem { Label("State", systemImage: "list.bullet.rectangle") }
            DraftsTab()
                .tabItem { Label("Drafts", systemImage: "square.and.pencil") }
            ActivityTab()
                .tabItem { Label("Activity", systemImage: "waveform.path.ecg") }
            VisionTab()
                .tabItem { Label("Vision", systemImage: "scope") }
            LessonsTab()
                .tabItem { Label("Lessons", systemImage: "book.closed") }
            SessionsTab()
                .tabItem { Label("Sessions", systemImage: "clock.arrow.circlepath") }
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
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

private struct StateTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader("Immediate", systemImage: "target")
                if let immediate = model.state.immediate {
                    MarkdownBlock(immediate.plan, empty: "No immediate plan.")
                    Label(immediate.verify, systemImage: "checkmark.seal")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    EmptyState("No immediate plan.")
                }

                Divider()

                SectionHeader("Completed", systemImage: "checklist")
                if model.state.completed.isEmpty {
                    EmptyState("No shipped iterations yet.")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.state.completed, id: \.self) { item in
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
                MarkdownBlock(model.state.midTerm, empty: "No mid-term queue.")

                Divider()

                SectionHeader("Long-Term", systemImage: "mountain.2")
                MarkdownBlock(model.state.longTerm, empty: "No long-term arc.")
            }
            .frame(maxWidth: 900, alignment: .leading)
        }
    }
}

private struct DraftsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("New Draft", systemImage: "square.and.pencil")
            HStack(alignment: .top, spacing: 10) {
                TextField("Describe the next direction", text: $model.draftEntry, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await model.addDraft() }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.hasRepository || model.draftEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                SectionHeader("Pending Drafts", systemImage: "tray")
                Spacer()
                Button {
                    Task { await model.saveDrafts() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!model.hasRepository)
            }
            TextEditor(text: $model.drafts)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if model.drafts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No drafts queued.")
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
        }
    }
}

private struct ActivityTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.activity) { line in
                        ActivityRow(line: line)
                        .id(line.id)
                    }
                }
                .padding(10)
            }
            .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: model.activity.count) {
                if let last = model.activity.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

private struct ActivityRow: View {
    var line: ActivityLine

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timestamp(line.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            ActivityStatusIcon(line: line)
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
                    ActivityDetail(line: line, detail: detail)
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

private struct ActivityStatusIcon: View {
    var line: ActivityLine

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

private struct ActivityDetail: View {
    var line: ActivityLine
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
    @EnvironmentObject private var model: AppModel
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
                    Task { await model.saveVision() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
            MarkdownDocumentBody(text: $model.vision, mode: mode, empty: "No project vision.")
        }
    }
}

private struct LessonsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Lessons", systemImage: "book.closed")
            ScrollView {
                MarkdownBlock(model.lessons, empty: "No lessons captured.")
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct SessionsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if model.sessions.isEmpty {
                    EmptyState("No sessions recorded.")
                } else {
                    ForEach(model.sessions.sorted { $0.startedAt > $1.startedAt }) { session in
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

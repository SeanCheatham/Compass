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
                    Text(immediate.plan)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                            Label(item, systemImage: "checkmark")
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
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(model.activity) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(timestamp(line.date))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 74, alignment: .leading)
                            Text(line.text)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(color(for: line.level))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(line.id)
                    }
                }
                .padding(12)
            }
            .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: model.activity.count) {
                if let last = model.activity.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func color(for level: ActivityLine.Level) -> Color {
        switch level {
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .raw: return .secondary
        }
    }
}

private struct VisionTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader("Project Vision", systemImage: "scope")
                Spacer()
                Button {
                    Task { await model.saveVision() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
            TextEditor(text: $model.vision)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct LessonsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader("Lessons", systemImage: "book.closed")
                Spacer()
                Button {
                    Task { await model.saveLessons() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
            TextEditor(text: $model.lessons)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
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
                                Text(plan)
                                    .lineLimit(3)
                            }
                            if let verify = session.verify {
                                Text(verify)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            if let feedback = session.feedback, !feedback.isEmpty {
                                Text(feedback)
                                    .font(.callout)
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
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
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

private struct MarkdownBlock: View {
    var text: String
    var empty: String

    init(_ text: String, empty: String) {
        self.text = text
        self.empty = empty
    }

    var body: some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyState(empty)
        } else {
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

import AppKit
import SwiftUI

struct CinematicTab: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var project: CompassProject

    var body: some View {
        GeometryReader { proxy in
            let caption = CinematicCaption(project: project)
            let displayPlan = cinematicOverlayDisplayPlan

            ZStack(alignment: .bottomLeading) {
                CinematicSceneView(
                    projectID: project.id,
                    lines: project.liveLog,
                    phase: project.phase,
                    isActive: project.isRunning || project.isAutoPlaying,
                    languageProfile: project.languageProfile,
                    activityProfile: project.activityProfile,
                    influenceSettings: project.cinematicInfluenceSettings,
                    worldText: project.cinematicWorldText,
                    briefing: project.cinematicBriefing
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(displayPlan.gradientStrength)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: max(160, proxy.size.height * 0.28))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 10) {
                    if displayPlan.showsWorldTextOverlay {
                        CinematicWorldTextOverlay(
                            worldText: project.cinematicWorldText,
                            tint: caption.activityColor,
                            displayPlan: displayPlan
                        )
                    }
                    CinematicHUD(caption: caption, displayPlan: displayPlan)
                }
                .padding(18)

                VStack {
                    HStack {
                        Spacer()
                        CinematicInfluenceControls(project: project)
                            .environmentObject(model)
                    }
                    Spacer()
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.08))
            }
        }
        .frame(minHeight: 520)
    }

    private var cinematicOverlayDisplayPlan: CinematicOverlayDisplayPlan {
        let currentPhase = project.isPaused ? LoopPhase.paused : project.phase
        let readability = CinematicOverlayDisplayPlanner.narrativeCueReadabilitySignals(
            phase: currentPhase,
            worldText: project.cinematicWorldText,
            briefing: project.cinematicBriefing,
            languageProfile: project.languageProfile,
            activityProfile: project.activityProfile,
            influenceSettings: project.cinematicInfluenceSettings
        )
        return CinematicOverlayDisplayPlanner.plan(
            phase: project.phase,
            isRunning: project.isRunning,
            isAutoPlaying: project.isAutoPlaying,
            isPaused: project.isPaused,
            hasRepository: project.hasRepository,
            worldText: project.cinematicWorldText,
            briefing: project.cinematicBriefing,
            languageProfile: project.languageProfile,
            activityProfile: project.activityProfile,
            influenceSettings: project.cinematicInfluenceSettings,
            narrativeCueReadability: readability
        )
    }
}

private struct CinematicInfluenceControls: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var project: CompassProject
    @State private var isShowingDiagnostics = false

    private var trimmedDraft: String {
        project.draftEntry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var diagnosticsSummary: CinematicDiagnosticsSummary {
        CinematicDiagnosticsSummary(report: CinematicDiagnostics.currentReport(for: project))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Picker("Camera", selection: $project.cinematicInfluenceSettings.cameraStyle) {
                    ForEach(CinematicInfluenceSettings.CameraStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Camera style")

                Button {
                    isShowingDiagnostics.toggle()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .frame(width: 17, height: 17)
                }
                .help("Show cinematic diagnostics")
                .popover(isPresented: $isShowingDiagnostics, arrowEdge: .top) {
                    CinematicDiagnosticsPopover(summary: diagnosticsSummary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "dial.medium")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.74))
                    .frame(width: 18)

                Slider(
                    value: $project.cinematicInfluenceSettings.intensity,
                    in: CinematicInfluenceSettings.intensityRange
                )
                .frame(width: 132)
                .help("Cinematic intensity")

                Text("\(Int(project.cinematicInfluenceSettings.intensity * 100))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .frame(width: 36, alignment: .trailing)
            }

            HStack(spacing: 7) {
                TextField("Quick draft", text: $project.draftEntry, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)

                Button {
                    Task { await project.addDraft() }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 17, height: 17)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!project.hasRepository || trimmedDraft.isEmpty)
                .help("Add draft")
            }
        }
        .controlSize(.small)
        .padding(10)
        .frame(width: 286, alignment: .leading)
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.1))
        }
        .onChange(of: project.cinematicInfluenceSettings) {
            model.saveProjects()
        }
    }
}

private struct CinematicDiagnosticsPopover: View {
    var summary: CinematicDiagnosticsSummary
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Diagnostics")
                    .font(.headline.weight(.semibold))

                Spacer()

                Button {
                    copyToPasteboard(summary.exportText)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .frame(width: 17, height: 17)
                }
                .help("Copy diagnostics report")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(summary.sections) { section in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 6) {
                                Text(section.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(section.rowCountLabel)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(section.rows) { row in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(row.label)
                                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 108, alignment: .leading)

                                        Text(row.detail)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .lineLimit(detailLineLimit(for: row))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 360)
        }
        .padding(14)
        .frame(width: 430, alignment: .leading)
        .onChange(of: summary.exportText) {
            copied = false
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func detailLineLimit(for row: CinematicDiagnosticsSummary.Row) -> Int {
        row.id.hasPrefix("effect-") || row.id == "stage-effect" ? 4 : 2
    }
}

private struct CinematicWorldTextOverlay: View {
    var worldText: CinematicWorldText
    var tint: Color
    var displayPlan: CinematicOverlayDisplayPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(displayPlan.visiblePills) { pill in
                CinematicWorldTextPill(
                    systemImage: pill.systemImage,
                    text: pill.text(from: worldText),
                    tint: pill.tint(activityTint: tint),
                    lineLimit: displayPlan.pillLineLimit,
                    opacity: displayPlan.overlayOpacity
                )
            }
        }
        .frame(maxWidth: CGFloat(displayPlan.worldTextMaxWidth), alignment: .leading)
    }
}

private struct CinematicWorldTextPill: View {
    var systemImage: String
    var text: String
    var tint: Color
    var lineLimit: Int
    var opacity: Double

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 15)

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.black.opacity(0.34 * opacity), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.white.opacity(0.09))
        }
    }
}

private struct CinematicHUD: View {
    var caption: CinematicCaption
    var displayPlan: CinematicOverlayDisplayPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: caption.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(caption.color)
                Text(caption.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(displayPlan.hudTitleLineLimit)
                    .minimumScaleFactor(0.82)
                Text(caption.phase)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: Capsule())
            }

            if displayPlan.showsHUDDetail {
                Text(caption.detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(displayPlan.hudDetailLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if displayPlan.showsHUDProfiles, let repositoryProfile = caption.repositoryProfile {
                Text(repositoryProfile)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(caption.profileColor.opacity(0.88))
                    .lineLimit(displayPlan.hudProfileLineLimit)
            }

            if displayPlan.showsHUDProfiles, let activityProfile = caption.activityProfile {
                Text(activityProfile)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(caption.activityColor.opacity(0.9))
                    .lineLimit(displayPlan.hudProfileLineLimit)
            }

            if let status = caption.status {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(caption.color.opacity(0.86))
                    .lineLimit(displayPlan.hudStatusLineLimit)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: CGFloat(displayPlan.hudMaxWidth), alignment: .leading)
        .background(.black.opacity(0.36 * displayPlan.overlayOpacity), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(caption.color)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

private extension CinematicOverlayPill {
    var systemImage: String {
        switch self {
        case .quest:
            return "sparkle.magnifyingglass"
        case .arena:
            return "scope"
        case .activity:
            return "waveform.path.ecg"
        }
    }

    func text(from worldText: CinematicWorldText) -> String {
        switch self {
        case .quest:
            return worldText.questLabel
        case .arena:
            return worldText.arenaCallout
        case .activity:
            return worldText.activityCallout
        }
    }

    func tint(activityTint: Color) -> Color {
        switch self {
        case .quest:
            return activityTint
        case .arena:
            return .white.opacity(0.76)
        case .activity:
            return activityTint.opacity(0.92)
        }
    }
}

private struct CinematicCaption {
    var title: String
    var detail: String
    var phase: String
    var status: String?
    var repositoryProfile: String?
    var activityProfile: String?
    var systemImage: String
    var color: Color
    var profileColor: Color
    var activityColor: Color

    @MainActor
    init(project: CompassProject) {
        let latest = project.liveLog.last
        let currentPhase = project.isPaused ? LoopPhase.paused : project.phase
        let briefing = project.cinematicBriefing
        let profile = project.languageProfile
        let activity = project.activityProfile
        title = briefing.title
        detail = briefing.detail
        phase = currentPhase.rawValue
        status = nil
        repositoryProfile = profile.hudSummary
        activityProfile = activity.hudSummary
        profileColor = profile.primaryLanguage.cinematicColor
        activityColor = activity.pressureLevel.cinematicColor

        if (project.isRunning || project.isAutoPlaying) && Self.isThinking(project: project) {
            status = "Codex is thinking while wards slow the wave."
            systemImage = "brain.head.profile"
            color = .blue
            return
        }

        guard let latest else {
            systemImage = "moon.stars"
            color = .secondary
            return
        }

        let spell = SpellSchool(line: latest)
        color = spell.swiftUIColor
        systemImage = spell.systemImage

        switch latest.status {
        case .running:
            status = "\(spell.name) is being cast"
        case .completed:
            status = "\(spell.name) landed"
        case .failed:
            status = "The spell backfired"
        case .none:
            status = Self.detail(for: latest)
        }
    }

    @MainActor
    private static func isThinking(project: CompassProject) -> Bool {
        !project.liveLog.contains {
            $0.status == .running && ($0.kind == .command || $0.kind == .fileChange)
        }
    }

    private static func detail(for line: LiveLine) -> String? {
        if let detail = line.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty {
            return detail
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)
        }
        return line.text.isEmpty ? nil : line.text
    }
}

private extension RepositoryWorktreePressureLevel {
    var cinematicColor: Color {
        switch self {
        case .clean:
            return .green
        case .light:
            return .mint
        case .moderate:
            return .orange
        case .heavy:
            return .red
        }
    }
}

private extension RepositoryLanguage {
    var cinematicColor: Color {
        switch self {
        case .swift:
            return .orange
        case .typeScriptJavaScript:
            return .cyan
        case .python:
            return .blue
        case .go:
            return .mint
        case .rust:
            return .brown
        case .markdown:
            return .indigo
        case .other:
            return .secondary
        case .unknown:
            return .secondary
        }
    }
}


enum SpellSchool: Equatable {
    case scan
    case shell
    case edit
    case git
    case verify
    case insight
    case lifecycle
    case pressure
    case failure

    init(line: LiveLine) {
        if line.status == .failed || line.level == .error {
            self = .failure
            return
        }

        switch line.kind {
        case .command:
            self = SpellSchool.command(line.detail ?? line.text)
        case .fileChange:
            self = .edit
        case .agentMessage:
            self = .insight
        case .lifecycle:
            self = .lifecycle
        case .message:
            self = .shell
        }
    }

    var name: String {
        switch self {
        case .scan: return "Search spell"
        case .shell: return "Shell spell"
        case .edit: return "Forge spell"
        case .git: return "History spell"
        case .verify: return "Seal spell"
        case .insight: return "Insight spell"
        case .lifecycle: return "Gate spell"
        case .pressure: return "Pressure"
        case .failure: return "Backlash"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: return "magnifyingglass"
        case .shell: return "terminal"
        case .edit: return "hammer"
        case .git: return "point.3.connected.trianglepath.dotted"
        case .verify: return "checkmark.seal"
        case .insight: return "sparkles"
        case .lifecycle: return "circle.hexagongrid"
        case .pressure: return "flame"
        case .failure: return "exclamationmark.triangle"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .scan:
            return NSColor(calibratedRed: 0.18, green: 0.64, blue: 1.0, alpha: 1)
        case .shell:
            return NSColor(calibratedRed: 0.58, green: 0.44, blue: 1.0, alpha: 1)
        case .edit:
            return NSColor(calibratedRed: 0.15, green: 0.96, blue: 0.72, alpha: 1)
        case .git:
            return NSColor(calibratedRed: 0.46, green: 0.95, blue: 0.3, alpha: 1)
        case .verify:
            return NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.2, alpha: 1)
        case .insight:
            return NSColor(calibratedRed: 0.86, green: 0.52, blue: 1.0, alpha: 1)
        case .lifecycle:
            return NSColor(calibratedRed: 0.32, green: 0.84, blue: 1.0, alpha: 1)
        case .pressure:
            return NSColor(calibratedRed: 1.0, green: 0.22, blue: 0.18, alpha: 1)
        case .failure:
            return NSColor(calibratedRed: 1.0, green: 0.12, blue: 0.18, alpha: 1)
        }
    }

    var swiftUIColor: Color {
        Color(nsColor)
    }

    var enemyGlow: NSColor {
        nsColor.withAlphaComponent(0.38)
    }

    private static func command(_ detail: String) -> SpellSchool {
        let lowercased = detail.lowercased()
        if lowercased.contains("swift test")
            || lowercased.contains("swift build")
            || lowercased.contains("npm test")
            || lowercased.contains("pytest")
            || lowercased.contains("cargo test")
            || lowercased.contains("verify") {
            return .verify
        }
        if lowercased.contains("git ") {
            return .git
        }
        if lowercased.contains("rg ")
            || lowercased.contains("grep")
            || lowercased.contains("find ")
            || lowercased.contains("ls ")
            || lowercased.contains("sed ")
            || lowercased.contains("cat ") {
            return .scan
        }
        return .shell
    }
}

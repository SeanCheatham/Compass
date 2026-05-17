import AppKit
import SwiftUI

struct CinematicTab: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var project: CompassProject
    @State private var overlayMode = CinematicTabOverlayMode.live
    @State private var selectedTimelineBeatID: String?

    var body: some View {
        GeometryReader { proxy in
            let caption = CinematicCaption(project: project)
            let displayPlan = cinematicOverlayDisplayPlan
            let reliabilityFeedback = PlanReliabilityFeedback(
                state: project.state,
                sessions: project.sessions
            )
            let timelinePlan = CinematicSessionTimelinePlan(
                sessions: project.sessions,
                runCues: reliabilityFeedback.recentRunCues,
                selectedBeatID: selectedTimelineBeatID
            )

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
                    briefing: project.cinematicBriefing,
                    commitConstellationPlan: project.cinematicCommitConstellationPlan
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
                    CinematicTabOverlayModePicker(selection: $overlayMode)

                    if overlayMode == .timeline {
                        CinematicTimelineOverlay(
                            plan: timelinePlan,
                            selectedBeatID: $selectedTimelineBeatID
                        )
                    } else {
                        if displayPlan.showsWorldTextOverlay {
                            CinematicWorldTextOverlay(
                                worldText: project.cinematicWorldText,
                                tint: caption.activityColor,
                                displayPlan: displayPlan
                            )
                        }
                        CinematicHUD(caption: caption, displayPlan: displayPlan)
                    }
                }
                .padding(18)
                .onAppear {
                    selectedTimelineBeatID = timelinePlan.selectedBeatID
                }
                .onChange(of: timelinePlan.identifier) {
                    selectedTimelineBeatID = timelinePlan.selectedBeatID
                }
                .onChange(of: overlayMode) {
                    if overlayMode == .timeline {
                        selectedTimelineBeatID = timelinePlan.selectedBeatID
                    }
                }

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

private enum CinematicTabOverlayMode: String, CaseIterable, Identifiable {
    case live
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live:
            return "Live"
        case .timeline:
            return "Timeline"
        }
    }
}

private struct CinematicTabOverlayModePicker: View {
    @Binding var selection: CinematicTabOverlayMode

    var body: some View {
        Picker("Cinematic overlay mode", selection: $selection) {
            ForEach(CinematicTabOverlayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 174)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
        .help("Switch cinematic overlay mode")
    }
}

private struct CinematicTimelineOverlay: View {
    var plan: CinematicSessionTimelinePlan
    @Binding var selectedBeatID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("Timeline", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))

                Spacer()

                Text(plan.countLabel)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }

            if plan.isEmpty {
                Label("No session beats yet.", systemImage: "clock.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .center, spacing: 5) {
                        ForEach(plan.beats) { beat in
                            CinematicTimelineTick(
                                beat: beat,
                                isSelected: beat.stableID == plan.selectedBeatID
                            ) {
                                selectedBeatID = beat.stableID
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 38)

                if let selectedBeat = plan.selectedBeat {
                    CinematicTimelineBeatSummary(beat: selectedBeat)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(width: 430, alignment: .leading)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.11))
        }
    }
}

private struct CinematicTimelineTick: View {
    var beat: CinematicSessionTimelinePlan.Beat
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(beat.style.color.opacity(isSelected ? 1 : 0.62))
                    .frame(width: isSelected ? 7 : 5, height: beat.tickHeight)
                    .overlay {
                        if beat.hasAttention {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(.white.opacity(0.86), lineWidth: 1)
                        }
                    }

                Circle()
                    .fill(isSelected ? .white.opacity(0.84) : .white.opacity(0.22))
                    .frame(width: 3, height: 3)
            }
            .frame(width: 14, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(beat.label)
        .accessibilityLabel(beat.label)
    }
}

private struct CinematicTimelineBeatSummary: View {
    var beat: CinematicSessionTimelinePlan.Beat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: beat.systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(beat.style.color)
                    .frame(width: 16)

                Text(beat.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(beat.moment.shortTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: Capsule())

                Spacer()

                Text(beat.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.52))
            }

            Text(beat.detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                if let metadata = beat.metadata {
                    Text(metadata)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white.opacity(0.54))
                }

                if let attentionLabel = beat.attentionLabel {
                    Label(attentionLabel, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(beat.style.color.opacity(0.9))
                        .lineLimit(1)
                        .help(beat.attentionDetail ?? attentionLabel)
                }
            }
        }
        .padding(.top, 1)
    }
}

private extension CinematicSessionTimelinePlan.Beat {
    var tickHeight: CGFloat {
        switch moment {
        case .plan:
            return 13
        case .develop:
            return 18
        case .verify:
            return 22
        case .outcome:
            return 26
        case .commit:
            return 31
        }
    }
}

private extension CinematicSessionTimelinePlan.Beat.Style {
    var color: Color {
        switch self {
        case .neutral:
            return .white.opacity(0.68)
        case .active:
            return .cyan
        case .success:
            return .green
        case .warning:
            return .orange
        case .failure:
            return .red
        case .paused:
            return .blue
        case .commit:
            return .mint
        }
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
                    displayPlan: displayPlan
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
    var displayPlan: CinematicOverlayDisplayPlan

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint.opacity(displayPlan.worldTextPillIconEmphasis))
                .frame(width: 15)

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(displayPlan.worldTextPillTextEmphasis))
                .lineLimit(displayPlan.pillLineLimit)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, CGFloat(displayPlan.worldTextPillHorizontalPadding))
        .padding(.vertical, CGFloat(displayPlan.worldTextPillVerticalPadding))
        .background(
            .black.opacity(displayPlan.worldTextPillBackgroundOpacity * displayPlan.overlayOpacity),
            in: RoundedRectangle(cornerRadius: CGFloat(displayPlan.worldTextPillCornerRadius))
        )
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(displayPlan.worldTextPillCornerRadius))
                .stroke(.white.opacity(displayPlan.worldTextPillStrokeOpacity * displayPlan.overlayOpacity))
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
                    .foregroundStyle(caption.color.opacity(displayPlan.hudIconEmphasis))
                Text(caption.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(displayPlan.hudTitleEmphasis))
                    .lineLimit(displayPlan.hudTitleLineLimit)
                    .minimumScaleFactor(0.82)
                Text(caption.phase)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(displayPlan.hudStatusTextEmphasis))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        .white.opacity(displayPlan.hudPhaseBackgroundOpacity * displayPlan.overlayOpacity),
                        in: Capsule()
                    )
            }

            if displayPlan.showsHUDDetail {
                Text(caption.detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(displayPlan.hudDetailTextEmphasis))
                    .lineLimit(displayPlan.hudDetailLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if displayPlan.showsHUDProfiles, let repositoryProfile = caption.repositoryProfile {
                Text(repositoryProfile)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(caption.profileColor.opacity(displayPlan.hudDetailTextEmphasis))
                    .lineLimit(displayPlan.hudProfileLineLimit)
            }

            if displayPlan.showsHUDProfiles, let activityProfile = caption.activityProfile {
                Text(activityProfile)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(caption.activityColor.opacity(displayPlan.hudStatusTextEmphasis))
                    .lineLimit(displayPlan.hudProfileLineLimit)
            }

            if let status = caption.status {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(caption.color.opacity(displayPlan.hudStatusTextEmphasis))
                    .lineLimit(displayPlan.hudStatusLineLimit)
            }
        }
        .padding(.horizontal, CGFloat(displayPlan.hudHorizontalPadding))
        .padding(.vertical, CGFloat(displayPlan.hudVerticalPadding))
        .frame(maxWidth: CGFloat(displayPlan.hudMaxWidth), alignment: .leading)
        .background(
            .black.opacity(displayPlan.hudBackgroundOpacity * displayPlan.overlayOpacity),
            in: RoundedRectangle(cornerRadius: CGFloat(displayPlan.hudCornerRadius))
        )
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(displayPlan.hudCornerRadius))
                .stroke(.white.opacity(displayPlan.hudStrokeOpacity * displayPlan.overlayOpacity))
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(caption.color.opacity(displayPlan.hudAccentOpacity))
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

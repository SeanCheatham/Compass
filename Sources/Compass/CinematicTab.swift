import AppKit
import SwiftUI

struct CinematicTab: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var project: CompassProject
    @State private var overlayMode = CinematicTabOverlayMode.live
    @State private var selectedTimelineBeatID: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
        GeometryReader { proxy in
            let caption = CinematicCaption(project: project)
            let displayPlan = cinematicOverlayDisplayPlan
            let nativeFeedbackCue = project.cinematicNativeFeedbackCue
            let displayedNativeFeedbackCue = displayPlan.showsNativeFeedbackBanner ? nativeFeedbackCue : nil
            let reliabilityFeedback = PlanReliabilityFeedback(
                state: project.state,
                sessions: project.sessions
            )
            let recapPlan = CinematicRunRecapPlanner.plan(
                state: project.state,
                sessions: project.sessions,
                isRunning: project.isRunning,
                isAutoPlaying: project.isAutoPlaying,
                recentRunCues: reliabilityFeedback.recentRunCues,
                commitConstellationPlan: project.cinematicCommitConstellationPlan,
                nativeFeedbackLifecycle: project.cinematicNativeFeedbackCueLifecycle,
                flavor: project.cinematicRunRecapFlavor
            )
            let timelinePlan = CinematicSessionTimelinePlan(
                sessions: project.sessions,
                runCues: reliabilityFeedback.recentRunCues,
                selectedBeatID: selectedTimelineBeatID
            )
            let recoveryCuePlan = CinematicRecoveryCuePlanner.plan(
                recentRunCues: reliabilityFeedback.recentRunCues,
                influenceSettings: project.cinematicInfluenceSettings
            )
            let timelineSceneFocusCandidatePlan = CinematicTimelineSceneFocusPlanner.plan(
                    selectedBeat: timelinePlan.selectedBeat,
                    commitConstellationPlan: project.cinematicCommitConstellationPlan,
                    recoveryCuePlan: recoveryCuePlan
                )
            let timelineSceneFocusPlan = overlayMode == .timeline
                ? timelineSceneFocusCandidatePlan
                : .none
            let runRecapSceneFocusCandidatePlan = CinematicRunRecapSceneFocusPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: recapPlan,
                commitConstellationPlan: project.cinematicCommitConstellationPlan,
                timelinePlan: timelinePlan
            )
            let runRecapSceneFocusPlan = overlayMode == .recap
                ? runRecapSceneFocusCandidatePlan
                : .none
            let runRecapEndCardCandidatePlan = CinematicRunRecapEndCardPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: recapPlan
            )
            let runRecapEndCardPlan = overlayMode == .recap
                ? runRecapEndCardCandidatePlan
                : .none
            let idleStoryCyclePlan = CinematicIdleStoryCyclePlanner.plan(
                session: CinematicIdleStoryCyclePlan.SessionInput(
                    elapsedTime: timeline.date.timeIntervalSinceReferenceDate,
                    sessionOrdinal: project.sessions.last?.session ?? project.sessions.count
                ),
                isLiveFollowActive: CinematicIdleStoryCyclePlanner.hasLiveFollowTarget(lines: project.liveLog),
                hasExplicitUserFocus: overlayMode != .live,
                influenceSettings: project.cinematicInfluenceSettings,
                commitConstellationPlan: project.cinematicCommitConstellationPlan,
                timelineSceneFocusPlan: timelineSceneFocusCandidatePlan,
                nativeFeedbackCue: nativeFeedbackCue,
                nativeFeedbackPlaqueDescriptor: CinematicIdleStoryCyclePlanner.nativeFeedbackPlaqueDescriptor(
                    phase: project.isPaused ? .paused : project.phase,
                    languageProfile: project.languageProfile,
                    activityProfile: project.activityProfile,
                    influenceSettings: project.cinematicInfluenceSettings,
                    worldText: project.cinematicWorldText,
                    briefing: project.cinematicBriefing,
                    recoveryCuePlan: recoveryCuePlan,
                    nativeFeedbackCue: nativeFeedbackCue
                ),
                runRecapPlan: recapPlan,
                runRecapSceneFocusPlan: runRecapSceneFocusCandidatePlan,
                runRecapEndCardPlan: runRecapEndCardCandidatePlan
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
                    commitConstellationPlan: project.cinematicCommitConstellationPlan,
                    recoveryCuePlan: recoveryCuePlan,
                    idleStoryCyclePlan: idleStoryCyclePlan,
                    timelineSceneFocusPlan: timelineSceneFocusPlan,
                    runRecapSceneFocusPlan: runRecapSceneFocusPlan,
                    runRecapEndCardPlan: runRecapEndCardPlan,
                    nativeFeedbackCue: nativeFeedbackCue
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

                    if let nativeFeedbackCue = displayedNativeFeedbackCue {
                        CinematicNativeFeedbackBanner(
                            cue: nativeFeedbackCue,
                            displayPlan: displayPlan
                        )
                    }

                    if overlayMode == .timeline {
                        CinematicTimelineOverlay(
                            plan: timelinePlan,
                            selectedBeatID: $selectedTimelineBeatID
                        )
                    } else if overlayMode == .recap {
                        CinematicRunRecapOverlay(
                            plan: recapPlan,
                            displayPlan: displayPlan
                        )
                    } else {
                        if displayPlan.showsWorldTextOverlay {
                            CinematicWorldTextOverlay(
                                worldText: project.cinematicWorldText,
                                tint: caption.activityColor,
                                displayPlan: displayPlan
                            )
                        }
                        CinematicHUD(
                            caption: caption,
                            nativeFeedbackCue: displayedNativeFeedbackCue,
                            displayPlan: displayPlan
                        )
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
                        CinematicInfluenceControls(
                            project: project,
                            idleStoryCyclePlan: idleStoryCyclePlan,
                            timelineSceneFocusPlan: timelineSceneFocusPlan,
                            runRecapSceneFocusPlan: runRecapSceneFocusPlan,
                            runRecapEndCardPlan: runRecapEndCardPlan
                        )
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
    }

    private var cinematicOverlayDisplayPlan: CinematicOverlayDisplayPlan {
        let currentPhase = project.isPaused ? LoopPhase.paused : project.phase
        let readability = CinematicOverlayDisplayPlanner.narrativeCueReadabilitySignals(
            phase: currentPhase,
            worldText: project.cinematicWorldText,
            briefing: project.cinematicBriefing,
            languageProfile: project.languageProfile,
            activityProfile: project.activityProfile,
            influenceSettings: project.cinematicInfluenceSettings,
            nativeFeedbackCue: project.cinematicNativeFeedbackCue
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
            narrativeCueReadability: readability,
            nativeFeedbackCue: project.cinematicNativeFeedbackCue,
            nativeFeedbackLifecycleIdentifier: project.cinematicNativeFeedbackCueLifecycle.hasState
                ? project.cinematicNativeFeedbackCueLifecycle.identifier
                : nil
        )
    }
}

private enum CinematicTabOverlayMode: String, CaseIterable, Identifiable {
    case live
    case timeline
    case recap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live:
            return "Live"
        case .timeline:
            return "Timeline"
        case .recap:
            return "Recap"
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
        .frame(width: 246)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
        .help("Switch cinematic overlay mode")
    }
}

private struct CinematicNativeFeedbackBanner: View {
    var cue: CinematicNativeFeedbackCuePlan
    var displayPlan: CinematicOverlayDisplayPlan

    var body: some View {
        let tint = cue.style.color

        HStack(alignment: .top, spacing: 8) {
            Image(systemName: cue.systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint.opacity(displayPlan.hudIconEmphasis))
                .frame(width: 17)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(cue.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(displayPlan.hudTitleEmphasis))
                        .lineLimit(displayPlan.hudTitleLineLimit)
                        .minimumScaleFactor(0.82)

                    Text(cue.phaseLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint.opacity(0.9))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.16), in: Capsule())
                }

                Text(cue.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(displayPlan.hudDetailTextEmphasis))
                    .lineLimit(min(2, displayPlan.hudDetailLineLimit))
                    .fixedSize(horizontal: false, vertical: true)

                Text(cue.status)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(displayPlan.hudStatusTextEmphasis))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.horizontal, CGFloat(max(10, displayPlan.hudHorizontalPadding - 1)))
        .padding(.vertical, CGFloat(max(7, displayPlan.hudVerticalPadding - 2)))
        .frame(maxWidth: CGFloat(min(displayPlan.hudMaxWidth, 520)), alignment: .leading)
        .background(
            .black.opacity(min(0.54, displayPlan.hudBackgroundOpacity + 0.12) * displayPlan.overlayOpacity),
            in: RoundedRectangle(cornerRadius: CGFloat(displayPlan.hudCornerRadius))
        )
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(displayPlan.hudCornerRadius))
                .stroke(tint.opacity(max(0.16, displayPlan.hudStrokeOpacity)), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tint.opacity(displayPlan.hudAccentOpacity))
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .help(cue.detail)
        .accessibilityIdentifier("cinematic-native-feedback-\(cue.identifier)")
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

private struct CinematicRunRecapOverlay: View {
    var plan: CinematicRunRecapPlan
    var displayPlan: CinematicOverlayDisplayPlan

    var body: some View {
        let tint = plan.style.color

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: plan.systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tint.opacity(displayPlan.hudIconEmphasis))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(displayPlan.hudTitleEmphasis))
                        .lineLimit(displayPlan.hudTitleLineLimit)
                        .minimumScaleFactor(0.82)

                    Text(plan.status)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white.opacity(displayPlan.hudStatusTextEmphasis))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer()

                Text(plan.statusIdentifier == "none" ? plan.availabilityIdentifier : plan.statusIdentifier)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint.opacity(0.92))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.16), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(displayPlan.hudDetailTextEmphasis))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let newestCommit = plan.newestCommitHighlight {
                    Label(newestCommit, systemImage: "arrow.triangle.branch")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .help(newestCommit)
                }
            }

            if !plan.eventChips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(plan.eventChips) { chip in
                        CinematicRunRecapEventChip(chip: chip)
                    }
                }
            }
        }
        .padding(.horizontal, CGFloat(max(11, displayPlan.hudHorizontalPadding)))
        .padding(.vertical, CGFloat(max(9, displayPlan.hudVerticalPadding - 1)))
        .frame(width: 430, alignment: .leading)
        .background(
            .black.opacity(min(0.5, displayPlan.hudBackgroundOpacity + 0.1) * displayPlan.overlayOpacity),
            in: RoundedRectangle(cornerRadius: CGFloat(displayPlan.hudCornerRadius))
        )
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(displayPlan.hudCornerRadius))
                .stroke(tint.opacity(max(0.14, displayPlan.hudStrokeOpacity)), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tint.opacity(displayPlan.hudAccentOpacity))
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .help(plan.detail)
        .accessibilityIdentifier("cinematic-run-recap-\(plan.identifier)")
    }
}

private struct CinematicRunRecapEventChip: View {
    var chip: CinematicRunRecapPlan.EventChip

    var body: some View {
        let tint = chip.color

        HStack(spacing: 5) {
            Image(systemName: chip.systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint.opacity(0.92))
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 1) {
                Text(chip.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(chip.detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: 134, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
        .help(chip.detail)
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
    var idleStoryCyclePlan: CinematicIdleStoryCyclePlan = .none
    var timelineSceneFocusPlan: CinematicTimelineSceneFocusPlan = .none
    var runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan = .none
    var runRecapEndCardPlan: CinematicRunRecapEndCardPlan = .none
    @State private var isShowingDiagnostics = false

    private var trimmedDraft: String {
        project.draftEntry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var diagnosticsSummary: CinematicDiagnosticsSummary {
        CinematicDiagnosticsSummary(
            report: CinematicDiagnostics.currentReport(
                for: project,
                idleStoryCyclePlan: idleStoryCyclePlan,
                timelineFocusPlan: timelineSceneFocusPlan,
                runRecapSceneFocusPlan: runRecapSceneFocusPlan,
                runRecapEndCardPlan: runRecapEndCardPlan
            )
        )
    }

    var body: some View {
        let summary = diagnosticsSummary

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
                    diagnosticsButtonLabel(summary.visualSmoke)
                }
                .help(summary.visualSmoke.help)
                .popover(isPresented: $isShowingDiagnostics, arrowEdge: .top) {
                    CinematicDiagnosticsPopover(summary: summary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: project.cinematicInfluenceSettings.comfortMode.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.74))
                    .frame(width: 18)

                Picker("Motion comfort", selection: $project.cinematicInfluenceSettings.comfortMode) {
                    ForEach(CinematicInfluenceSettings.ComfortMode.allCases) { mode in
                        Text(mode.compactTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
                .help("Motion comfort")
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

    @ViewBuilder
    private func diagnosticsButtonLabel(
        _ visualSmoke: CinematicDiagnosticsSummary.VisualSmokeSection
    ) -> some View {
        switch visualSmoke.status {
        case .pass:
            Image(systemName: "list.bullet.rectangle")
                .frame(width: 17, height: 17)
        case .warning:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))

                Text(visualSmoke.warningBadgeLabel)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .frame(minWidth: 8)
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 5)
            .frame(minHeight: 20)
            .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.orange.opacity(0.4))
            }
        }
    }
}

private struct CinematicDiagnosticsPopover: View {
    var summary: CinematicDiagnosticsSummary
    @State private var copied = false
    @State private var groupExpansion: [String: Bool] = [:]
    @FocusState private var focusedGroupID: String?

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

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        attentionSummarySection(scrollProxy: scrollProxy)

                        ForEach(summary.sections) { section in
                            diagnosticsDisclosureGroup(
                                id: section.id,
                                presentation: section.presentation
                            ) {
                                diagnosticsHeader(
                                    title: section.label,
                                    presentation: section.presentation
                                )
                            } content: {
                                diagnosticsRows(section.rows)
                            }
                        }

                        visualSmokeSection

                        plaqueTreatmentLegendSection
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: 360)
            }
        }
        .padding(14)
        .frame(width: 430, alignment: .leading)
        .onChange(of: summary.exportText) {
            copied = false
            resetExpansionDefaults()
        }
        .onAppear {
            resetExpansionDefaults()
        }
    }

    @ViewBuilder
    private func attentionSummarySection(scrollProxy: ScrollViewProxy) -> some View {
        if !summary.attentionSummary.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Warnings")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                ForEach(summary.attentionSummary.targets) { target in
                    Button {
                        jumpToAttentionTarget(target, scrollProxy: scrollProxy)
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.orange)
                                .frame(width: 13)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text(target.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text(target.targetGroupID)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }

                                Text(attentionTargetDetail(target))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(target.warningCount)")
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(.orange)
                                .frame(minWidth: 16)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.orange.opacity(0.35))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Show \(target.label)")
                }
            }
        }
    }

    private var visualSmokeSection: some View {
        diagnosticsDisclosureGroup(
            id: summary.visualSmoke.id,
            presentation: summary.visualSmoke.presentation
        ) {
            diagnosticsHeader(
                title: summary.visualSmoke.label,
                presentation: summary.visualSmoke.presentation,
                systemImage: visualSmokeSystemImage(for: summary.visualSmoke.status),
                tint: visualSmokeColor(for: summary.visualSmoke.status)
            )
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.visualSmoke.help)
                    .font(.caption2.monospaced())
                    .foregroundStyle(summary.visualSmoke.presentation.needsAttention ? .orange : .secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                ForEach(summary.visualSmoke.checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Image(systemName: visualSmokeSystemImage(for: check.status))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(visualSmokeColor(for: check.status))
                                .frame(width: 12)

                            Text(check.label)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(check.status == .warning ? .orange : .secondary)
                        }
                        .frame(width: 108, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(check.detail)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let warningIdentifier = check.warningIdentifier {
                                Text(warningIdentifier)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var plaqueTreatmentLegendSection: some View {
        diagnosticsDisclosureGroup(
            id: summary.plaqueTreatmentLegend.id,
            presentation: summary.plaqueTreatmentLegend.presentation
        ) {
            diagnosticsHeader(
                title: summary.plaqueTreatmentLegend.label,
                presentation: summary.plaqueTreatmentLegend.presentation,
                systemImage: visualSmokeSystemImage(for: summary.plaqueTreatmentLegend.status),
                tint: visualSmokeColor(for: summary.plaqueTreatmentLegend.status)
            )
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.plaqueTreatmentLegend.detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(summary.plaqueTreatmentLegend.presentation.needsAttention ? .orange : .secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                ForEach(summary.plaqueTreatmentLegend.rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Text(row.label)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 108, alignment: .leading)

                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func diagnosticsDisclosureGroup<Header: View, Content: View>(
        id: String,
        presentation: CinematicDiagnosticsSummary.PresentationMetadata,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(
            isExpanded: groupExpansionBinding(
                id: id,
                defaultExpanded: presentation.defaultExpanded
            )
        ) {
            content()
                .padding(.top, 7)
        } label: {
            header()
        }
        .id(id)
        .focusable()
        .focused($focusedGroupID, equals: id)
    }

    private func diagnosticsHeader(
        title: String,
        presentation: CinematicDiagnosticsSummary.PresentationMetadata,
        systemImage: String? = nil,
        tint: Color = .secondary
    ) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text(presentation.headerDetail)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(presentation.needsAttention ? .orange : .secondary)
                .lineLimit(1)
        }
    }

    private func diagnosticsRows(_ rows: [CinematicDiagnosticsSummary.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
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

    private func groupExpansionBinding(id: String, defaultExpanded: Bool) -> Binding<Bool> {
        Binding(
            get: { groupExpansion[id] ?? defaultExpanded },
            set: { groupExpansion[id] = $0 }
        )
    }

    private func resetExpansionDefaults() {
        groupExpansion = summary.defaultExpandedGroupStates
        focusedGroupID = nil
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func jumpToAttentionTarget(
        _ target: CinematicDiagnosticsSummary.AttentionTarget,
        scrollProxy: ScrollViewProxy
    ) {
        groupExpansion[target.targetGroupID] = true
        withAnimation(.easeInOut(duration: 0.16)) {
            scrollProxy.scrollTo(target.targetGroupID, anchor: .top)
        }
        focusedGroupID = target.targetGroupID
    }

    private func attentionTargetDetail(
        _ target: CinematicDiagnosticsSummary.AttentionTarget
    ) -> String {
        let warnings = target.visibleWarningIdentifiers.isEmpty
            ? "warnings unavailable"
            : target.visibleWarningIdentifiers.joined(separator: ", ")
        return "\(target.detail) | \(warnings)"
    }

    private func detailLineLimit(for row: CinematicDiagnosticsSummary.Row) -> Int {
        row.id.hasPrefix("effect-") || row.id == "stage-effect" ? 4 : 2
    }

    private func visualSmokeSystemImage(for status: CinematicVisualSmokeReport.Status) -> String {
        switch status {
        case .pass:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private func visualSmokeColor(for status: CinematicVisualSmokeReport.Status) -> Color {
        switch status {
        case .pass:
            return .green
        case .warning:
            return .orange
        }
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
    var nativeFeedbackCue: CinematicNativeFeedbackCuePlan?
    var displayPlan: CinematicOverlayDisplayPlan

    var body: some View {
        let tint = nativeFeedbackCue?.style.color ?? caption.color
        let systemImage = nativeFeedbackCue?.systemImage ?? caption.systemImage
        let title = nativeFeedbackCue?.title ?? caption.title
        let detail = nativeFeedbackCue?.detail ?? caption.detail
        let phase = nativeFeedbackCue?.phaseLabel ?? caption.phase
        let status = nativeFeedbackCue?.status ?? caption.status

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint.opacity(displayPlan.hudIconEmphasis))
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(displayPlan.hudTitleEmphasis))
                    .lineLimit(displayPlan.hudTitleLineLimit)
                    .minimumScaleFactor(0.82)
                Text(phase)
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
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(displayPlan.hudDetailTextEmphasis))
                    .lineLimit(displayPlan.hudDetailLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if nativeFeedbackCue == nil,
               displayPlan.showsHUDProfiles,
               let repositoryProfile = caption.repositoryProfile {
                Text(repositoryProfile)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(caption.profileColor.opacity(displayPlan.hudDetailTextEmphasis))
                    .lineLimit(displayPlan.hudProfileLineLimit)
            }

            if nativeFeedbackCue == nil,
               displayPlan.showsHUDProfiles,
               let activityProfile = caption.activityProfile {
                Text(activityProfile)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(caption.activityColor.opacity(displayPlan.hudStatusTextEmphasis))
                    .lineLimit(displayPlan.hudProfileLineLimit)
            }

            if let status {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint.opacity(displayPlan.hudStatusTextEmphasis))
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
                .fill(tint.opacity(displayPlan.hudAccentOpacity))
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

private extension CinematicNativeFeedbackCuePlan.Style {
    var color: Color {
        switch self {
        case .plan:
            return .indigo
        case .develop:
            return .cyan
        case .verify:
            return .yellow
        case .success:
            return .green
        case .warning:
            return .orange
        case .failure:
            return .red
        case .paused:
            return .blue
        case .idle:
            return .secondary
        }
    }
}

private extension CinematicRunRecapPlan.Style {
    var color: Color {
        switch self {
        case .success:
            return .green
        case .failure:
            return .red
        case .warning:
            return .orange
        case .paused:
            return .blue
        case .empty:
            return .secondary
        }
    }
}

private extension CinematicRunRecapPlan.EventChip {
    var color: Color {
        switch colorIdentifier {
        case "green":
            return .green
        case "red":
            return .red
        case "orange":
            return .orange
        case "blue":
            return .blue
        case "cyan":
            return .cyan
        case "yellow":
            return .yellow
        case "indigo":
            return .indigo
        default:
            return .secondary
        }
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

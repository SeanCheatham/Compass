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
            let recapArtifactLibraryContext = project.cinematicRunRecapShareArtifactLibraryContext
            let recapArtifactComparisonPlan = CinematicRunRecapShareArtifactComparisonPlanner.plan(
                historyPlan: project.cinematicRunRecapShareArtifactHistory,
                selectedEntryIdentifier: recapArtifactLibraryContext.selectedEntryIdentifier,
                searchQuery: recapArtifactLibraryContext.searchText,
                targetMode: recapArtifactLibraryContext.comparisonTargetMode,
                pinnedEntryIdentifiers: recapArtifactLibraryContext.pinnedEntryIdentifiers,
                savedTourHoldEntryIdentifier: recapArtifactLibraryContext.savedTourHoldEntryIdentifier
            )
            let runRecapEndCardCandidatePlan = CinematicRunRecapEndCardPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: recapPlan,
                artifactComparisonPlan: recapArtifactComparisonPlan
            )
            let runRecapEndCardPlan = overlayMode == .recap
                ? runRecapEndCardCandidatePlan
                : .none
            let runRecapSharePlan = CinematicRunRecapSharePlanner.plan(
                recapPlan: recapPlan,
                recapFocusDescriptor: runRecapSceneFocusCandidatePlan.descriptor,
                endCardDescriptor: runRecapEndCardCandidatePlan.descriptor
            )
            let idleStorySession = CinematicIdleStoryCyclePlan.SessionInput(
                elapsedTime: timeline.date.timeIntervalSinceReferenceDate,
                sessionOrdinal: project.sessions.last?.session ?? project.sessions.count
            )
            let recapArtifactTourPlan = CinematicRunRecapShareArtifactTourPlanner.plan(
                historyPlan: project.cinematicRunRecapShareArtifactHistory,
                libraryContext: recapArtifactLibraryContext,
                rotationSeed: idleStorySession.sessionOrdinal
                    + Int(idleStorySession.elapsedTime / (CinematicIdleStoryCyclePlan.defaultCadence * 2))
            )
            let idleStoryCyclePlan = CinematicIdleStoryCyclePlanner.plan(
                session: idleStorySession,
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
                runRecapEndCardPlan: runRecapEndCardCandidatePlan,
                runRecapShareArtifactTourPlan: recapArtifactTourPlan
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
                            project: project,
                            plan: recapPlan,
                            sharePlan: runRecapSharePlan,
                            artifactHistoryPlan: project.cinematicRunRecapShareArtifactHistory,
                            artifactTourPlan: recapArtifactTourPlan,
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
    @ObservedObject var project: CompassProject
    var plan: CinematicRunRecapPlan
    var sharePlan: CinematicRunRecapSharePlan
    var artifactHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan
    var artifactTourPlan: CinematicRunRecapShareArtifactTourPlan
    var displayPlan: CinematicOverlayDisplayPlan
    @State private var shareFeedbackLabel: String?
    @State private var shareFeedbackHelp: String?
    @State private var shareFeedbackStatus: CinematicRunRecapShareArtifactRecordingResult.Status?

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

                Button {
                    copyShareTextAndRecordArtifact()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint.opacity(sharePlan.isAvailable ? 0.9 : 0.34))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!sharePlan.isAvailable)
                .help(shareHelp)
                .accessibilityLabel("Copy recap share text")
                .accessibilityIdentifier("cinematic-run-recap-share-\(sharePlan.identifier)")

                if let shareFeedbackLabel {
                    Text(shareFeedbackLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(shareFeedbackColor.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .help(shareFeedbackHelp ?? shareFeedbackLabel)
                        .accessibilityIdentifier("cinematic-run-recap-share-artifact-status")
                }

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

            CinematicRunRecapArtifactLibraryControl(
                project: project,
                plan: artifactHistoryPlan,
                tourPlan: artifactTourPlan,
                tint: tint,
                displayPlan: displayPlan
            )

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
        .onChange(of: sharePlan.identifier) {
            clearShareFeedback()
        }
    }

    private var shareHelp: String {
        if !sharePlan.isAvailable {
            return "Recap share unavailable: \(sharePlan.availabilityReason)"
        }
        if let shareFeedbackHelp {
            return shareFeedbackHelp
        }
        return "Copy recap share text and record a session artifact"
    }

    private var shareFeedbackColor: Color {
        switch shareFeedbackStatus {
        case .recorded:
            return .green
        case .failed:
            return .orange
        case .skipped:
            return .gray
        case nil:
            return plan.style.color
        }
    }

    private func copyShareTextAndRecordArtifact() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sharePlan.text, forType: .string)
        shareFeedbackLabel = "Copied"
        shareFeedbackHelp = "Copied recap share text; recording the session artifact."
        shareFeedbackStatus = nil

        Task {
            let result = await project.recordRunRecapShareArtifact(sharePlan: sharePlan)
            await MainActor.run {
                shareFeedbackLabel = result.label
                shareFeedbackHelp = result.help
                shareFeedbackStatus = result.status
            }
        }
    }

    private func clearShareFeedback() {
        shareFeedbackLabel = nil
        shareFeedbackHelp = nil
        shareFeedbackStatus = nil
    }
}

private struct CinematicRunRecapArtifactLibraryControl: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var project: CompassProject
    var plan: CinematicRunRecapShareArtifactHistoryPlan
    var tourPlan: CinematicRunRecapShareArtifactTourPlan
    var tint: Color
    var displayPlan: CinematicOverlayDisplayPlan
    @State private var feedback: String?
    @State private var feedbackStatus: CinematicRunRecapShareArtifactCleanupResult.Status?
    @State private var preservedFeedbackPlanIdentifier: String?

    var body: some View {
        let previewPlan = currentPreviewPlan
        let rollupPlan = currentRollupPlan
        let comparisonPlan = currentComparisonPlan
        let pinnedReferencePlan = currentPinnedReferencePlan
        let selectedExportPlan = subsetExportPlan(scope: .selected)
        let filteredExportPlan = subsetExportPlan(scope: .filtered)

        VStack(alignment: .leading, spacing: 4) {
            rollupScanline(rollupPlan)
            comparisonStrip(comparisonPlan)
            pinnedReferenceStrip(pinnedReferencePlan, previewPlan: previewPlan)
            tourStrip(tourPlan, previewPlan: previewPlan)

            HStack(alignment: .center, spacing: 7) {
                Image(systemName: previewPlan.hasWarnings ? "archivebox.fill" : "archivebox")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint.opacity(previewPlan.isAvailable ? 0.84 : 0.42))
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedLabel(previewPlan))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(previewPlan.isAvailable ? 0.78 : 0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(selectedDetail(previewPlan))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(previewPlan.bodyPreviewText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Spacer(minLength: 4)

                if let feedback {
                    Text(feedback)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(feedbackColor.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                searchControl(previewPlan)

                Button {
                    selectArtifact(previewPlan.previousEntryIdentifier)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!previewPlan.canNavigatePrevious)
                .foregroundStyle(tint.opacity(previewPlan.canNavigatePrevious ? 0.86 : 0.32))
                .help(previousHelp(previewPlan))
                .accessibilityLabel("Previous recap share artifact")
                .accessibilityIdentifier("cinematic-run-recap-artifact-library-previous")

                Button {
                    selectArtifact(previewPlan.nextEntryIdentifier)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!previewPlan.canNavigateNext)
                .foregroundStyle(tint.opacity(previewPlan.canNavigateNext ? 0.86 : 0.32))
                .help(nextHelp(previewPlan))
                .accessibilityLabel("Next recap share artifact")
                .accessibilityIdentifier("cinematic-run-recap-artifact-library-next")

                Button {
                    revealSelectedArtifact()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(currentSelectedEntry == nil)
                .foregroundStyle(tint.opacity(currentSelectedEntry == nil ? 0.32 : 0.86))
                .help(revealHelp(previewPlan))
                .accessibilityLabel("Reveal selected recap share artifact")
                .accessibilityIdentifier("cinematic-run-recap-artifact-library-reveal")

                Button {
                    copySubsetExport(selectedExportPlan)
                } label: {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!selectedExportPlan.isAvailable)
                .foregroundStyle(tint.opacity(selectedExportPlan.isAvailable ? 0.86 : 0.32))
                .help(selectedExportPlan.copyHelp)
                .accessibilityLabel(selectedExportPlan.copyLabel)
                .accessibilityIdentifier("cinematic-run-recap-artifact-library-copy-selected-export")

                Button {
                    copySubsetExport(filteredExportPlan)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!filteredExportPlan.isAvailable)
                .foregroundStyle(tint.opacity(filteredExportPlan.isAvailable ? 0.86 : 0.32))
                .help(filteredExportPlan.copyHelp)
                .accessibilityLabel(filteredExportPlan.copyLabel)
                .accessibilityIdentifier("cinematic-run-recap-artifact-library-copy-filtered-export")

                Button {
                    cleanupArtifacts()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(plan.cleanupCandidateCount == 0)
                .foregroundStyle(tint.opacity(plan.cleanupCandidateCount == 0 ? 0.32 : 0.86))
                .help(cleanupHelp)
                .accessibilityLabel("Clean up old recap share artifacts")
                .accessibilityIdentifier("cinematic-run-recap-artifact-library-cleanup")

                Button {
                    copyExport()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!plan.isAvailable)
                .foregroundStyle(tint.opacity(plan.isAvailable ? 0.86 : 0.32))
                .help(exportHelp)
                .accessibilityLabel("Copy recap share artifact library")
                .accessibilityIdentifier("cinematic-run-recap-artifact-library-copy")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            .white.opacity(0.045 * displayPlan.overlayOpacity),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.white.opacity(plan.hasWarnings ? 0.16 : 0.08))
        }
        .help(exportHelp)
        .accessibilityIdentifier("cinematic-run-recap-artifact-library-\(plan.identifier)")
        .onAppear {
            reconcileSelectionWithCurrentPlan()
        }
        .onChange(of: plan.identifier) {
            reconcileSelectionWithCurrentPlan()
            if preservedFeedbackPlanIdentifier == plan.identifier {
                return
            }
            feedback = nil
            feedbackStatus = nil
            preservedFeedbackPlanIdentifier = nil
        }
    }

    private var currentPreviewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan {
        CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: plan,
            selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText
        )
    }

    private var currentRollupPlan: CinematicRunRecapShareArtifactRollupPlan {
        CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: plan,
            selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText
        )
    }

    private var currentComparisonPlan: CinematicRunRecapShareArtifactComparisonPlan {
        CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: plan,
            selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText,
            targetMode: artifactLibraryContext.comparisonTargetMode,
            pinnedEntryIdentifiers: artifactLibraryContext.pinnedEntryIdentifiers,
            savedTourHoldEntryIdentifier: artifactLibraryContext.savedTourHoldEntryIdentifier
        )
    }

    private var currentPinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan {
        CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: plan,
            pinnedEntryIdentifiers: artifactLibraryContext.pinnedEntryIdentifiers,
            selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText
        )
    }

    private var currentSelectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry? {
        guard let identifier = currentPreviewPlan.selectedEntryIdentifier else { return nil }
        return plan.entries.first { $0.identifier == identifier }
    }

    private func rollupScanline(_ rollupPlan: CinematicRunRecapShareArtifactRollupPlan) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: rollupPlan.hasWarnings ? "chart.bar.fill" : "chart.bar")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint.opacity(rollupPlan.isAvailable ? 0.78 : 0.38))
                .frame(width: 14)

            Text(rollupPlan.insightText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(rollupPlan.isAvailable ? 0.7 : 0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Spacer(minLength: 4)

            Text(rollupPlan.statusBucketSummary)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Button {
                copyRollup(rollupPlan)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!rollupPlan.isAvailable)
            .foregroundStyle(tint.opacity(rollupPlan.isAvailable ? 0.82 : 0.3))
            .help(rollupPlan.copyHelp)
            .accessibilityLabel(rollupPlan.copyLabel)
            .accessibilityIdentifier("cinematic-run-recap-artifact-library-copy-rollup")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            tint.opacity(rollupPlan.isSearchActive ? 0.08 : 0.05),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(tint.opacity(rollupPlan.hasWarnings ? 0.22 : 0.1), lineWidth: 1)
        }
        .help(rollupPlan.copyHelp)
        .accessibilityIdentifier("cinematic-run-recap-artifact-library-rollup-\(rollupPlan.identifier)")
    }

    private func comparisonStrip(_ comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: comparisonPlan.isAvailable ? "rectangle.split.2x1" : "rectangle.split.2x1.slash")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint.opacity(comparisonPlan.isAvailable ? 0.78 : 0.38))
                .frame(width: 14)

            comparisonColumn(
                label: "Selected",
                sessionNumber: comparisonPlan.selectedSessionNumber,
                titleSnippet: comparisonPlan.selectedTitleSnippet,
                statusSnippet: comparisonPlan.selectedStatusSnippet,
                isAvailable: comparisonPlan.selectedEntryIdentifier != nil
            )

            Image(systemName: comparisonPlan.targetDirectionIdentifier == "newer" ? "arrow.left" : "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint.opacity(comparisonPlan.isAvailable ? 0.6 : 0.28))
                .frame(width: 12)

            comparisonColumn(
                label: comparisonTargetLabel(comparisonPlan),
                sessionNumber: comparisonPlan.compareSessionNumber,
                titleSnippet: comparisonPlan.compareTitleSnippet,
                statusSnippet: comparisonPlan.compareStatusSnippet,
                isAvailable: comparisonPlan.compareEntryIdentifier != nil
            )

            Spacer(minLength: 4)

            Text(comparisonSummary(comparisonPlan))
                .font(.caption2)
                .foregroundStyle(.white.opacity(comparisonPlan.isAvailable ? 0.5 : 0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Button {
                toggleComparisonTargetMode()
            } label: {
                Image(systemName: comparisonModeSystemImage(comparisonPlan))
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(tint.opacity(0.82))
            .help(comparisonModeToggleHelp(comparisonPlan))
            .accessibilityLabel("Switch recap artifact comparison target mode")
            .accessibilityIdentifier("cinematic-run-recap-artifact-library-toggle-comparison-mode")

            Button {
                copyComparison(comparisonPlan)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!comparisonPlan.isAvailable)
            .foregroundStyle(tint.opacity(comparisonPlan.isAvailable ? 0.82 : 0.3))
            .help(comparisonPlan.copyHelp)
            .accessibilityLabel(comparisonPlan.copyLabel)
            .accessibilityIdentifier("cinematic-run-recap-artifact-library-copy-comparison")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            tint.opacity(comparisonPlan.isSearchActive ? 0.075 : 0.045),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(tint.opacity(comparisonPlan.hasWarnings ? 0.2 : 0.09), lineWidth: 1)
        }
        .help(comparisonPlan.copyHelp)
        .accessibilityIdentifier("cinematic-run-recap-artifact-library-comparison-\(comparisonPlan.identifier)")
    }

    private func pinnedReferenceStrip(
        _ pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: pinnedReferencePlan.isAvailable ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint.opacity(pinnedReferencePlan.isAvailable ? 0.78 : 0.38))
                .frame(width: 14)

            Text(pinnedReferenceSummary(pinnedReferencePlan))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(pinnedReferencePlan.isAvailable ? 0.68 : 0.44))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            pinnedReferenceQuickSelectButtons(pinnedReferencePlan, previewPlan: previewPlan)
                .frame(minWidth: 0, maxWidth: 190, alignment: .leading)

            Spacer(minLength: 4)

            Button {
                toggleSelectedPin(previewPlan)
            } label: {
                Image(systemName: pinnedReferencePlan.selectedEntryIsPinned ? "pin.slash" : "pin")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(previewPlan.selectedEntryIdentifier == nil)
            .foregroundStyle(tint.opacity(previewPlan.selectedEntryIdentifier == nil ? 0.3 : 0.82))
            .help(togglePinHelp(pinnedReferencePlan, previewPlan: previewPlan))
            .accessibilityLabel(pinnedReferencePlan.selectedEntryIsPinned ? "Unpin selected recap share artifact" : "Pin selected recap share artifact")
            .accessibilityIdentifier("cinematic-run-recap-artifact-library-toggle-pin")

            Button {
                copyPinnedExport(pinnedReferencePlan)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!pinnedReferencePlan.isAvailable)
            .foregroundStyle(tint.opacity(pinnedReferencePlan.isAvailable ? 0.82 : 0.3))
            .help(pinnedReferencePlan.copyHelp)
            .accessibilityLabel(pinnedReferencePlan.copyLabel)
            .accessibilityIdentifier("cinematic-run-recap-artifact-library-copy-pinned-export")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            tint.opacity(pinnedReferencePlan.isSearchActive ? 0.07 : 0.045),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(tint.opacity(pinnedReferencePlan.hasWarnings ? 0.2 : 0.09), lineWidth: 1)
        }
        .help(pinnedReferencePlan.copyHelp)
        .accessibilityIdentifier("cinematic-run-recap-artifact-library-pins-\(pinnedReferencePlan.identifier)")
    }

    private func tourStrip(
        _ tourPlan: CinematicRunRecapShareArtifactTourPlan,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan
    ) -> some View {
        let tourExportPlan = tourSubsetExportPlan(tourPlan)
        let hasSavedTourHold = artifactLibraryContext.savedTourHoldEntryIdentifier != nil
        let isSelectedHeld = previewPlan.selectedEntryIdentifier != nil
            && previewPlan.selectedEntryIdentifier == artifactLibraryContext.savedTourHoldEntryIdentifier
        let canPromoteTourHold = tourPlan.retainedSavedTourHoldEntryIdentifier != nil

        return HStack(alignment: .center, spacing: 6) {
            Image(systemName: tourSystemImage(tourPlan))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint.opacity(tourPlan.isAvailable ? 0.78 : 0.38))
                .frame(width: 14)

            Text(tourSummary(tourPlan))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(tourPlan.isAvailable ? 0.68 : 0.44))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Spacer(minLength: 4)

            Button {
                holdOrReleaseCurrentTour(tourPlan.selectedEntryIdentifier)
            } label: {
                Image(systemName: hasSavedTourHold ? "lock.open" : "lock")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasSavedTourHold && tourPlan.selectedEntryIdentifier == nil)
            .foregroundStyle(tint.opacity((hasSavedTourHold || tourPlan.selectedEntryIdentifier != nil) ? 0.82 : 0.3))
            .help(tourHoldHelp(tourPlan, hasHold: hasSavedTourHold))
            .accessibilityLabel(hasSavedTourHold ? "Release saved recap tour hold" : "Hold current saved recap tour")
            .accessibilityIdentifier("cinematic-run-recap-artifact-library-toggle-tour-hold")

            Button {
                toggleTourHold(previewPlan.selectedEntryIdentifier)
            } label: {
                Image(systemName: isSelectedHeld ? "bookmark.slash" : "bookmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(previewPlan.selectedEntryIdentifier == nil)
            .foregroundStyle(tint.opacity(previewPlan.selectedEntryIdentifier == nil ? 0.3 : 0.82))
            .help(selectedHoldHelp(previewPlan, isHeld: isSelectedHeld))
            .accessibilityLabel(isSelectedHeld ? "Release selected saved recap tour hold" : "Hold selected saved recap artifact for tour")
            .accessibilityIdentifier("cinematic-run-recap-artifact-library-toggle-selected-tour-hold")

            Button {
                promoteTourHoldToPinnedReference(tourPlan)
            } label: {
                Image(systemName: "pin.circle")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canPromoteTourHold)
            .foregroundStyle(tint.opacity(canPromoteTourHold ? 0.82 : 0.3))
            .help(promoteTourHoldHelp(tourPlan))
            .accessibilityLabel("Promote saved recap tour hold to pinned comparison")
            .accessibilityIdentifier("cinematic-run-recap-artifact-library-promote-tour-hold")

            Button {
                copyTourExport(tourPlan)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!tourExportPlan.isAvailable)
            .foregroundStyle(tint.opacity(tourExportPlan.isAvailable ? 0.82 : 0.3))
            .help(tourExportPlan.copyHelp)
            .accessibilityLabel("Copy currently toured recap artifact")
            .accessibilityIdentifier("cinematic-run-recap-artifact-library-copy-tour-export")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            tint.opacity(tourPlan.savedTourHoldStateIdentifier == "none" ? 0.045 : 0.075),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(tint.opacity(tourPlan.savedTourHoldStateIdentifier == "none" ? 0.09 : 0.2), lineWidth: 1)
        }
        .help(tourSummary(tourPlan))
        .accessibilityIdentifier("cinematic-run-recap-artifact-library-tour-\(tourPlan.identifier)")
    }

    private func pinnedReferenceQuickSelectButtons(
        _ pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan
    ) -> some View {
        let references = pinnedReferencePlan.references.filter { $0.isQuickSelectable }
        return HStack(spacing: 3) {
            ForEach(references) { reference in
                pinnedReferenceQuickSelectButton(
                    reference,
                    isSelected: reference.identifier == previewPlan.selectedEntryIdentifier,
                    plan: pinnedReferencePlan
                )
            }
        }
    }

    private func pinnedReferenceQuickSelectButton(
        _ reference: CinematicRunRecapShareArtifactPinnedReferencePlan.Reference,
        isSelected: Bool,
        plan pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan
    ) -> some View {
        let label = "S\(reference.sessionNumber)"
        return Button {
            selectArtifact(reference.identifier)
        } label: {
            Text(verbatim: label)
                .font(.caption2.weight(.bold))
                .frame(width: 24, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint.opacity(isSelected ? 0.9 : 0.68))
        .background(
            .white.opacity(isSelected ? 0.09 : 0.04),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .help(pinnedReferenceHelp(reference, plan: pinnedReferencePlan))
        .accessibilityLabel("Select pinned recap share artifact session \(reference.sessionNumber)")
        .accessibilityIdentifier("cinematic-run-recap-artifact-library-select-pin-\(reference.identifier)")
    }

    private func comparisonColumn(
        label: String,
        sessionNumber: Int?,
        titleSnippet: String?,
        statusSnippet: String?,
        isAvailable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(label) \(sessionNumber.map { "S\($0)" } ?? "S-")")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(isAvailable ? 0.68 : 0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text([titleSnippet, statusSnippet].compactMap { $0 }.joined(separator: " | "))
                .font(.caption2)
                .foregroundStyle(.white.opacity(isAvailable ? 0.44 : 0.32))
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .frame(maxWidth: 150, alignment: .leading)
    }

    private func comparisonTargetLabel(_ comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan) -> String {
        if comparisonPlan.promotedHoldStateIdentifier == "retained-promoted-hold-target"
            || comparisonPlan.promotedHoldStateIdentifier == "filtered-promoted-hold-target" {
            return "Held"
        }
        if comparisonPlan.targetMode == .pinnedReference {
            return "Pinned"
        }
        switch comparisonPlan.targetDirectionIdentifier {
        case "older":
            return "Older"
        case "newer":
            return "Newer"
        default:
            return "Target"
        }
    }

    private func comparisonSummary(_ comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan) -> String {
        let mode = comparisonPlan.targetMode.title
        guard comparisonPlan.isAvailable else {
            return "\(mode) | \(comparisonPlan.availabilityReason)"
        }
        let delta = comparisonPlan.sessionDelta.map { "ΔS\($0)" } ?? "ΔS-"
        let promotedHold = comparisonPlan.promotedHoldStateIdentifier == "retained-promoted-hold-target"
            || comparisonPlan.promotedHoldStateIdentifier == "filtered-promoted-hold-target"
            ? " | promoted hold"
            : ""
        let search = comparisonPlan.isSearchActive
            ? " | \(comparisonPlan.matchingEntryCount)/\(comparisonPlan.unfilteredVisibleCount)"
            : ""
        return "\(mode) | \(comparisonPlan.targetDirectionIdentifier) | \(delta)\(promotedHold)\(search)"
    }

    private func comparisonModeSystemImage(
        _ comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan
    ) -> String {
        if comparisonPlan.promotedHoldStateIdentifier == "retained-promoted-hold-target"
            || comparisonPlan.promotedHoldStateIdentifier == "filtered-promoted-hold-target" {
            return "pin.circle.fill"
        }
        return comparisonPlan.targetMode == .pinnedReference ? "pin.fill" : "rectangle.split.2x1"
    }

    private func comparisonModeToggleHelp(
        _ comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan
    ) -> String {
        let nextMode = comparisonPlan.targetMode.toggled.title
        return "Switch recap artifact comparison target mode to \(nextMode)."
    }

    private func pinnedReferenceSummary(
        _ pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan
    ) -> String {
        guard pinnedReferencePlan.isAvailable else {
            return "Pins \(pinnedReferencePlan.pinnedEntryCount) | \(pinnedReferencePlan.availabilityReason)"
        }
        let missing = pinnedReferencePlan.missingPinnedEntryCount > 0
            ? " | \(pinnedReferencePlan.missingPinnedEntryCount) stale"
            : ""
        let filtered = pinnedReferencePlan.filteredPinnedEntryCount > 0
            ? " | \(pinnedReferencePlan.filteredPinnedEntryCount) filtered"
            : ""
        let search = pinnedReferencePlan.isSearchActive
            ? " | \(pinnedReferencePlan.quickSelectEntryCount) quick"
            : ""
        return "Pins \(pinnedReferencePlan.retainedPinnedEntryCount)/\(pinnedReferencePlan.pinnedEntryCount)\(search)\(filtered)\(missing)"
    }

    private func tourSystemImage(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) -> String {
        if tourPromotedHoldState(tourPlan) != "none" {
            return "pin.circle.fill"
        }
        switch tourPlan.savedTourHoldStateIdentifier {
        case "held":
            return "lock.fill"
        case "missing-hold":
            return "exclamationmark.triangle"
        case "filtered-hold":
            return "magnifyingglass.circle"
        default:
            return tourPlan.selectionSourceIdentifier == "pinned" ? "pin.fill" : "sparkles"
        }
    }

    private func tourSummary(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) -> String {
        guard tourPlan.isAvailable else {
            return "Tour \(tourPlan.savedTourHoldStateIdentifier) | \(tourPlan.availabilityReason)"
        }
        let session = tourPlan.sessionNumber.map { "S\($0)" } ?? "S-"
        let hold = tourPlan.savedTourHoldStateIdentifier == "none"
            ? ""
            : " | \(tourPlan.savedTourHoldStateIdentifier)"
        let promotedHold = tourPromotedHoldState(tourPlan) == "none"
            ? ""
            : " | promoted"
        let search = tourPlan.isSearchActive
            ? " | \(tourPlan.matchingEntryCount)/\(tourPlan.unfilteredVisibleCount)"
            : ""
        return "Tour \(session) | \(tourPlan.selectionSourceIdentifier)\(hold)\(promotedHold)\(search)"
    }

    private func tourPromotedHoldState(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) -> String {
        guard artifactLibraryContext.comparisonTargetMode == .pinnedReference,
              let requestedHold = tourPlan.requestedSavedTourHoldEntryIdentifier,
              artifactLibraryContext.pinnedEntryIdentifiers.contains(requestedHold) else {
            return "none"
        }
        guard tourPlan.retainedSavedTourHoldEntryIdentifier != nil else {
            return "missing-promoted-hold"
        }
        if tourPlan.filteredSavedTourHoldEntryIdentifier != nil {
            return "filtered-promoted-hold"
        }
        return "retained-promoted-hold"
    }

    private func tourHoldHelp(
        _ tourPlan: CinematicRunRecapShareArtifactTourPlan,
        hasHold: Bool
    ) -> String {
        if hasHold {
            return "Release the saved recap artifact tour hold."
        }
        guard tourPlan.selectedEntryIdentifier != nil else {
            return "No currently toured recap artifact to hold."
        }
        return "Hold the currently toured recap artifact so the idle tour keeps returning to it."
    }

    private func selectedHoldHelp(
        _ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        isHeld: Bool
    ) -> String {
        guard previewPlan.selectedEntryIdentifier != nil else {
            return "No selected recap artifact to hold for the idle tour."
        }
        if isHeld {
            return "Release the selected recap artifact from the saved tour hold."
        }
        return "Hold the selected recap artifact for the idle saved artifact tour."
    }

    private func promoteTourHoldHelp(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) -> String {
        guard let retainedSavedTourHoldEntryIdentifier = tourPlan.retainedSavedTourHoldEntryIdentifier else {
            if tourPlan.requestedSavedTourHoldEntryIdentifier == nil {
                return boundedHelp("No saved recap tour hold to promote.")
            }
            return boundedHelp("The saved recap tour hold is not retained, so it cannot be promoted to a pinned comparison.")
        }
        if tourPlan.filteredSavedTourHoldEntryIdentifier == retainedSavedTourHoldEntryIdentifier {
            return boundedHelp("Promote this retained tour hold to pinned comparison even though the current search filters it.")
        }
        return boundedHelp("Promote this saved tour hold to pinned comparison.")
    }

    private func pinnedReferenceHelp(
        _ reference: CinematicRunRecapShareArtifactPinnedReferencePlan.Reference,
        plan pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan
    ) -> String {
        let commit = reference.commitSnippet.map { " Commit: \($0)." } ?? ""
        let search = pinnedReferencePlan.isSearchActive
            ? " Visible under search \(pinnedReferencePlan.searchQuerySnippet)."
            : ""
        return "Select pinned recap artifact S\(reference.sessionNumber): \(reference.titleSnippet) | \(reference.statusSnippet).\(commit)\(search)"
    }

    private func togglePinHelp(
        _ pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan
    ) -> String {
        guard previewPlan.selectedEntryIdentifier != nil else {
            return "No selected recap share artifact to pin."
        }
        if pinnedReferencePlan.selectedEntryIsPinned {
            return "Unpin the selected recap share artifact from the pinned reference strip."
        }
        return "Pin the selected recap share artifact for quick selection and pinned export."
    }

    private func subsetExportPlan(
        scope: CinematicRunRecapShareArtifactSubsetExportPlan.Scope
    ) -> CinematicRunRecapShareArtifactSubsetExportPlan {
        CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: plan,
            selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText,
            scope: scope
        )
    }

    private func tourSubsetExportPlan(
        _ tourPlan: CinematicRunRecapShareArtifactTourPlan
    ) -> CinematicRunRecapShareArtifactSubsetExportPlan {
        CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: plan,
            selectedEntryIdentifier: tourPlan.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText,
            scope: .selected
        )
    }

    private func selectedLabel(_ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan) -> String {
        guard previewPlan.isAvailable else {
            return "Artifact preview unavailable"
        }
        let position = previewPlan.selectedOrdinal.map { "\($0)/\(previewPlan.entryCount)" } ?? "0/\(previewPlan.entryCount)"
        let session = previewPlan.sessionNumber.map { "S\($0)" } ?? "S-"
        return "\(session) \(previewPlan.filename ?? "artifact") (\(position))"
    }

    private func selectedDetail(_ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan) -> String {
        guard previewPlan.isAvailable else {
            if previewPlan.isSearchActive {
                return "\(previewPlan.availabilityReason) | \(previewPlan.matchCount)/\(previewPlan.unfilteredVisibleCount) matches | \(previewPlan.searchQuerySnippet)"
            }
            return previewPlan.availabilityReason
        }
        let commit = previewPlan.commitSnippet.map { " | \($0)" } ?? ""
        let hidden = plan.hiddenCount > 0 ? " | +\(plan.hiddenCount) hidden" : ""
        let cleanup = plan.cleanupCandidateCount > 0 ? " | \(plan.cleanupCandidateCount) cleanup" : ""
        let warnings = previewPlan.warningCount > 0 ? " | \(previewPlan.warningCount) warning" : ""
        let search = previewPlan.isSearchActive
            ? " | \(previewPlan.matchCount)/\(previewPlan.unfilteredVisibleCount) matches"
            : ""
        return "\(previewPlan.titleSnippet) | \(previewPlan.statusSnippet)\(commit)\(search)\(hidden)\(cleanup)\(warnings)"
    }

    private func searchControl(_ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint.opacity(previewPlan.isSearchActive ? 0.86 : 0.5))
                .frame(width: 11)

            TextField("", text: searchTextBinding)
                .textFieldStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.76))
                .frame(width: 66)
                .accessibilityLabel("Search saved recap artifacts")

            if !searchText.isEmpty {
                Button {
                    updateSearchText("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint.opacity(0.72))
                .help("Clear recap artifact search")
                .accessibilityLabel("Clear recap artifact search")
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 22)
        .background(
            .white.opacity(previewPlan.isSearchActive ? 0.075 : 0.04),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(tint.opacity(previewPlan.isSearchActive ? 0.26 : 0.1), lineWidth: 1)
        }
        .help(searchHelp(previewPlan))
        .accessibilityIdentifier("cinematic-run-recap-artifact-library-search")
    }

    private var artifactLibraryContext: CinematicRunRecapShareArtifactLibraryContext {
        project.cinematicRunRecapShareArtifactLibraryContext
    }

    private var searchText: String {
        artifactLibraryContext.searchText
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { artifactLibraryContext.searchText },
            set: { updateSearchText($0) }
        )
    }

    private func searchHelp(_ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan) -> String {
        guard previewPlan.isSearchActive else {
            return "Filter saved recap artifacts by filename, title, status, commit, path, or preview text."
        }
        return "\(previewPlan.matchCount) of \(previewPlan.unfilteredVisibleCount) saved recap artifact\(previewPlan.unfilteredVisibleCount == 1 ? "" : "s") match \(previewPlan.searchQuerySnippet)."
    }

    private func previousHelp(_ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan) -> String {
        if previewPlan.canNavigatePrevious {
            return previewPlan.isSearchActive
                ? "Show the newer matching saved recap share artifact."
                : "Show the newer saved recap share artifact."
        }
        return previewPlan.isSearchActive
            ? "Already showing the newest matching saved recap share artifact."
            : "Already showing the newest saved recap share artifact."
    }

    private func nextHelp(_ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan) -> String {
        if previewPlan.canNavigateNext {
            return previewPlan.isSearchActive
                ? "Show the older matching saved recap share artifact."
                : "Show the older saved recap share artifact."
        }
        return previewPlan.isSearchActive
            ? "Already showing the oldest matching saved recap share artifact."
            : "Already showing the oldest visible recap share artifact."
    }

    private func revealHelp(_ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan) -> String {
        guard currentSelectedEntry != nil else {
            return "No saved recap share artifact to reveal."
        }
        return "Reveal \(previewPlan.pathSnippet) in Finder."
    }

    private var exportHelp: String {
        if !plan.isAvailable {
            return "No recap share artifact library export is available: \(plan.availabilityReason)."
        }
        return "Copy combined Markdown export \(plan.exportIdentifier)."
    }

    private var cleanupHelp: String {
        guard plan.cleanupCandidateCount > 0 else {
            return "No old recap share artifacts to clean up; retaining newest \(plan.retentionLimit)."
        }
        return "Delete \(plan.cleanupCandidateCount) old recap share artifact\(plan.cleanupCandidateCount == 1 ? "" : "s") while retaining newest \(plan.retentionLimit)."
    }

    private var feedbackColor: Color {
        switch feedbackStatus {
        case .deleted:
            return .green
        case .failed:
            return .orange
        case .skipped:
            return .gray
        case nil:
            return tint
        }
    }

    private func boundedHelp(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 140 else { return normalized }
        return String(normalized.prefix(137)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func selectArtifact(_ identifier: String?) {
        guard let identifier else { return }
        persistContext(
            artifactLibraryContext.replacing(
                selectedEntryIdentifier: identifier,
                searchText: artifactLibraryContext.searchText
            )
        )
        feedback = nil
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = nil
    }

    private func revealSelectedArtifact() {
        guard let selected = currentSelectedEntry else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selected.url])
        feedback = "Revealed"
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = plan.identifier
    }

    private func copySubsetExport(_ exportPlan: CinematicRunRecapShareArtifactSubsetExportPlan) {
        guard exportPlan.isAvailable else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportPlan.markdownContents, forType: .string)
        switch exportPlan.scope {
        case .selected:
            feedback = "Selected export copied"
        case .filtered:
            feedback = "Filtered export copied"
        }
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = plan.identifier
    }

    private func copyRollup(_ rollupPlan: CinematicRunRecapShareArtifactRollupPlan) {
        guard rollupPlan.isAvailable else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rollupPlan.exportText, forType: .string)
        feedback = "Rollup copied"
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = plan.identifier
    }

    private func copyComparison(_ comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan) {
        guard comparisonPlan.isAvailable else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(comparisonPlan.exportText, forType: .string)
        feedback = "Comparison copied"
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = plan.identifier
    }

    private func copyPinnedExport(_ pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan) {
        guard pinnedReferencePlan.isAvailable else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pinnedReferencePlan.exportText, forType: .string)
        feedback = "Pinned export copied"
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = plan.identifier
    }

    private func copyTourExport(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) {
        let exportPlan = tourSubsetExportPlan(tourPlan)
        guard exportPlan.isAvailable else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportPlan.markdownContents, forType: .string)
        feedback = "Tour export copied"
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = plan.identifier
    }

    private func copyExport() {
        guard plan.isAvailable else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plan.combinedMarkdownExport, forType: .string)
        feedback = "Export copied"
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = plan.identifier
    }

    private func cleanupArtifacts() {
        guard plan.cleanupCandidateCount > 0 else { return }
        feedback = "Cleaning"
        feedbackStatus = nil

        Task {
            let result = await project.cleanupRunRecapShareArtifacts()
            await MainActor.run {
                feedback = result.label
                feedbackStatus = result.status
                preservedFeedbackPlanIdentifier = result.refreshedHistory.identifier
            }
        }
    }

    private func promoteTourHoldToPinnedReference(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) {
        guard tourPlan.retainedSavedTourHoldEntryIdentifier != nil else { return }
        let promotedContext = artifactLibraryContext.promotingSavedTourHoldToPinnedReference(in: plan)
        persistContext(promotedContext)
        feedback = "Tour pinned"
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = plan.identifier
    }

    private func toggleSelectedPin(_ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan) {
        guard previewPlan.selectedEntryIdentifier != nil else { return }
        let pinPlan = CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: plan,
            pinnedEntryIdentifiers: artifactLibraryContext.pinnedEntryIdentifiers,
            selectedEntryIdentifier: previewPlan.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText
        )
        let resolvedContext = artifactLibraryContext
            .togglingPinnedEntryIdentifier(previewPlan.selectedEntryIdentifier)
            .resolvingSelection(in: plan)
        persistContext(resolvedContext)
        feedback = pinPlan.selectedEntryIsPinned ? "Unpinned" : "Pinned"
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = plan.identifier
    }

    private func toggleTourHold(_ identifier: String?) {
        guard identifier != nil else { return }
        let wasHeld = artifactLibraryContext.savedTourHoldEntryIdentifier == identifier
        persistContext(
            artifactLibraryContext
                .togglingSavedTourHoldEntryIdentifier(identifier)
                .resolvingSelection(in: plan)
        )
        feedback = wasHeld ? "Tour released" : "Tour held"
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = plan.identifier
    }

    private func holdOrReleaseCurrentTour(_ identifier: String?) {
        if artifactLibraryContext.savedTourHoldEntryIdentifier != nil {
            persistContext(artifactLibraryContext.releasingSavedTourHold().resolvingSelection(in: plan))
            feedback = "Tour released"
            feedbackStatus = nil
            preservedFeedbackPlanIdentifier = plan.identifier
            return
        }
        toggleTourHold(identifier)
    }

    private func toggleComparisonTargetMode() {
        let nextMode = artifactLibraryContext.comparisonTargetMode.toggled
        persistContext(
            artifactLibraryContext.replacing(
                selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
                searchText: artifactLibraryContext.searchText,
                comparisonTargetMode: nextMode
            ).resolvingSelection(in: plan)
        )
        feedback = "Compare \(nextMode.title)"
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = plan.identifier
    }

    private func updateSearchText(_ text: String) {
        let requestedContext = artifactLibraryContext.replacing(
            selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
            searchText: text
        )
        persistContext(requestedContext.resolvingSelection(in: plan))
        feedback = nil
        feedbackStatus = nil
        preservedFeedbackPlanIdentifier = nil
    }

    private func reconcileSelectionWithCurrentPlan() {
        persistContext(artifactLibraryContext.resolvingSelection(in: plan))
    }

    private func persistContext(_ context: CinematicRunRecapShareArtifactLibraryContext) {
        guard project.cinematicRunRecapShareArtifactLibraryContext != context else { return }
        project.cinematicRunRecapShareArtifactLibraryContext = context
        model.saveProjects()
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

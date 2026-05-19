import AppKit
import SwiftUI

struct CinematicTab: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var project: CompassProject
    @Binding var presentationState: CinematicTabPresentationState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
        GeometryReader { proxy in
            let caption = CinematicCaption(project: project)
            let displayPlan = cinematicOverlayDisplayPlan
            let planCompassPlan = CinematicPlanCompassPlan(state: project.state)
            let reliabilityFeedback = PlanReliabilityFeedback(
                state: project.state,
                sessions: project.sessions
            )
            let planCompassReadinessPlan = CinematicPlanCompassReadinessPlan(
                state: project.state,
                planCompassPlan: planCompassPlan,
                reliabilityFeedback: reliabilityFeedback
            )
            let planCompassSceneFocusCandidatePlan = CinematicPlanCompassSceneFocusPlanner.plan(
                isPlanOverlaySelected: true,
                planCompassPlan: planCompassPlan,
                readinessPlan: planCompassReadinessPlan
            )
            let planCompassCommandPlan = CinematicPlanCompassCommandPlanner.plan(
                planCompassPlan: planCompassPlan,
                selectedKind: presentationState.selectedPlanCompassKind
            )
            let planCompassActionSurface = CinematicPlanCompassActionSurfacePlanner.descriptor(
                commandPlan: planCompassCommandPlan
            )
            let planCompassSceneFocusPlan = presentationState.overlayMode == .plan
                ? CinematicPlanCompassSceneFocusPlanner.plan(
                    isPlanOverlaySelected: true,
                    planCompassPlan: planCompassPlan,
                    readinessPlan: planCompassReadinessPlan,
                    selectedKind: presentationState.selectedPlanCompassKind
                )
                : .none
            let nativeFeedbackCue = project.cinematicNativeFeedbackCue
            let displayedNativeFeedbackCue = displayPlan.showsNativeFeedbackBanner ? nativeFeedbackCue : nil
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
                selectedBeatID: presentationState.selectedTimelineBeatID
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
            let timelineSceneFocusPlan = presentationState.overlayMode == .timeline
                ? timelineSceneFocusCandidatePlan
                : .none
            let runRecapSceneFocusCandidatePlan = CinematicRunRecapSceneFocusPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: recapPlan,
                commitConstellationPlan: project.cinematicCommitConstellationPlan,
                timelinePlan: timelinePlan
            )
            let runRecapSceneFocusPlan = presentationState.overlayMode == .recap
                ? runRecapSceneFocusCandidatePlan
                : .none
            let recapArtifactLibraryContext = project.cinematicRunRecapShareArtifactLibraryContext
            let recapArtifactSourceExportAuditPlan =
                CinematicRunRecapShareArtifactSourceExportAuditPlanner.plan(
                    reconciliationPlan: project.cinematicRunRecapShareArtifactSourceReconciliation
                )
            let recapArtifactComparisonPlan = CinematicRunRecapShareArtifactComparisonPlanner.plan(
                historyPlan: project.cinematicRunRecapShareArtifactHistory,
                selectedEntryIdentifier: recapArtifactLibraryContext.selectedEntryIdentifier,
                searchQuery: recapArtifactLibraryContext.searchText,
                targetMode: recapArtifactLibraryContext.comparisonTargetMode,
                pinnedEntryIdentifiers: recapArtifactLibraryContext.pinnedEntryIdentifiers,
                savedTourHoldEntryIdentifier: recapArtifactLibraryContext.savedTourHoldEntryIdentifier,
                warningPulseFilter: recapArtifactLibraryContext.warningPulseFilter,
                sourceExportAuditPlan: recapArtifactSourceExportAuditPlan
            )
            let runRecapEndCardCandidatePlan = CinematicRunRecapEndCardPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: recapPlan,
                artifactComparisonPlan: recapArtifactComparisonPlan
            )
            let runRecapEndCardPlan = presentationState.overlayMode == .recap
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
            let activitySourceBeaconPlan = CinematicActivitySourceBeaconPlan(
                snapshot: project.activitySourceSnapshot,
                influenceSettings: project.cinematicInfluenceSettings
            )
            let idleStoryCyclePlan = CinematicIdleStoryCyclePlanner.plan(
                session: idleStorySession,
                isLiveFollowActive: CinematicIdleStoryCyclePlanner.hasLiveFollowTarget(lines: project.liveLog),
                hasExplicitUserFocus: presentationState.overlayMode != .live,
                influenceSettings: project.cinematicInfluenceSettings,
                activitySourceBeaconPlan: activitySourceBeaconPlan,
                commitConstellationPlan: project.cinematicCommitConstellationPlan,
                timelineSceneFocusPlan: timelineSceneFocusCandidatePlan,
                recoveryCuePlan: recoveryCuePlan,
                planCompassSceneFocusPlan: planCompassSceneFocusCandidatePlan,
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
                diagnosticsWarningBundleHistory: project.cinematicDiagnosticsWarningBundleHistory,
                diagnosticsWarningPulseQuietingDescriptor:
                    project.cinematicDiagnosticsWarningPulseQuietingDescriptor,
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
                    planCompassSceneFocusPlan: planCompassSceneFocusPlan,
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
                    CinematicTabOverlayModePicker(selection: $presentationState.overlayMode)

                    if let nativeFeedbackCue = displayedNativeFeedbackCue {
                        CinematicNativeFeedbackBanner(
                            cue: nativeFeedbackCue,
                            displayPlan: displayPlan
                        )
                    }

                    if presentationState.overlayMode == .plan {
                        CinematicPlanCompassOverlay(
                            plan: planCompassPlan,
                            readinessPlan: planCompassReadinessPlan,
                            selectedKind: presentationState.selectedPlanCompassKind,
                            actionSurface: planCompassActionSurface,
                            performAction: { actionKind in
                                performPlanCompassCommand(actionKind, plan: planCompassPlan)
                            },
                            displayPlan: displayPlan
                        )
                    } else if presentationState.overlayMode == .timeline {
                        CinematicTimelineOverlay(
                            plan: timelinePlan,
                            selectedBeatID: $presentationState.selectedTimelineBeatID
                        )
                    } else if presentationState.overlayMode == .recap {
                        CinematicRunRecapOverlay(
                            project: project,
                            plan: recapPlan,
                            sharePlan: runRecapSharePlan,
                            artifactHistoryPlan: project.cinematicRunRecapShareArtifactHistory,
                            artifactSourceReconciliationPlan:
                                project.cinematicRunRecapShareArtifactSourceReconciliation,
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
                        if displayPlan.showsActivitySourceCue {
                            CinematicActivitySourceCueChip(
                                cue: displayPlan.activitySourceCue,
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
                    presentationState.selectedTimelineBeatID = timelinePlan.selectedBeatID
                }
                .onChange(of: timelinePlan.identifier) {
                    presentationState.selectedTimelineBeatID = timelinePlan.selectedBeatID
                }
                .onChange(of: presentationState.overlayMode) {
                    if presentationState.overlayMode == .timeline {
                        presentationState.selectedTimelineBeatID = timelinePlan.selectedBeatID
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        CinematicInfluenceControls(
                            project: project,
                            idleStoryCyclePlan: idleStoryCyclePlan,
                            selectedPlanCompassKind: presentationState.selectedPlanCompassKind,
                            planCompassSceneFocusPlan: planCompassSceneFocusPlan,
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
            .focusedValue(
                \.cinematicPlanCompassCommandDispatch,
                CinematicPlanCompassCommandDispatch(
                    plan: planCompassCommandPlan,
                    perform: { actionKind in
                        performPlanCompassCommand(actionKind, plan: planCompassPlan)
                    }
                )
            )
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
            activitySourceSnapshot: project.activitySourceSnapshot,
            influenceSettings: project.cinematicInfluenceSettings,
            narrativeCueReadability: readability,
            nativeFeedbackCue: project.cinematicNativeFeedbackCue,
            nativeFeedbackLifecycleIdentifier: project.cinematicNativeFeedbackCueLifecycle.hasState
                ? project.cinematicNativeFeedbackCueLifecycle.identifier
                : nil
        )
    }

    private func performPlanCompassCommand(
        _ actionKind: CinematicPlanCompassCommandPlan.ActionKind,
        plan: CinematicPlanCompassPlan
    ) {
        let commandPlan = CinematicPlanCompassCommandPlanner.plan(
            planCompassPlan: plan,
            selectedKind: presentationState.selectedPlanCompassKind
        )
        guard commandPlan.command(for: actionKind)?.isEnabled == true else {
            return
        }

        switch actionKind {
        case .showPlanOverlay:
            presentationState.overlayMode = .plan
        case .focusImmediateRoute:
            presentationState.selectedPlanCompassKind = .immediate
            presentationState.overlayMode = .plan
        case .focusMidTermRoute:
            presentationState.selectedPlanCompassKind = .midTerm
            presentationState.overlayMode = .plan
        case .focusLongTermRoute:
            presentationState.selectedPlanCompassKind = .longTerm
            presentationState.overlayMode = .plan
        case .copyFullPlanCompass:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(plan.copyText, forType: .string)
        case .copySelectedRoute:
            let selectedSection = plan.section(for: presentationState.selectedPlanCompassKind)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectedSection.copyText, forType: .string)
        }
    }
}

struct CinematicTabPresentationState: Equatable {
    var overlayMode = CinematicTabOverlayMode.live
    var selectedTimelineBeatID: String?
    var selectedPlanCompassKind = PlanWorkflowOverview.Kind.immediate
}

enum CinematicTabOverlayMode: String, CaseIterable, Identifiable {
    case live
    case plan
    case timeline
    case recap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live:
            return "Live"
        case .plan:
            return "Plan"
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
        .frame(width: 318)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
        .help("Switch cinematic overlay mode")
    }
}

private struct CinematicPlanCompassOverlay: View {
    var plan: CinematicPlanCompassPlan
    var readinessPlan: CinematicPlanCompassReadinessPlan
    var selectedKind: PlanWorkflowOverview.Kind
    var actionSurface: CinematicPlanCompassActionSurfaceDescriptor
    var performAction: (CinematicPlanCompassCommandPlan.ActionKind) -> Void
    var displayPlan: CinematicOverlayDisplayPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Label("Plan Compass", systemImage: "safari")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(displayPlan.hudTitleEmphasis))

                Spacer()

                Text(plan.completedLabel)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(displayPlan.hudStatusTextEmphasis))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            CinematicPlanCompassReadinessStrip(
                readinessPlan: readinessPlan,
                displayPlan: displayPlan
            )

            CinematicPlanCompassWaypointStrip(
                plan: plan,
                displayPlan: displayPlan
            )

            CinematicPlanCompassActionSurfaceControls(
                actionSurface: actionSurface,
                performAction: performAction,
                displayPlan: displayPlan
            )

            VStack(alignment: .leading, spacing: 7) {
                ForEach(plan.sections) { section in
                    CinematicPlanCompassSectionRow(
                        section: section,
                        isSelected: section.kind == selectedKind,
                        performAction: performAction,
                        displayPlan: displayPlan
                    )
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
                .stroke(.white.opacity(max(0.12, displayPlan.hudStrokeOpacity)), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.cyan.opacity(displayPlan.hudAccentOpacity))
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .help(plan.copyText)
        .accessibilityIdentifier("cinematic-plan-compass-\(plan.exportIdentifier)")
    }
}

private struct CinematicPlanCompassReadinessStrip: View {
    var readinessPlan: CinematicPlanCompassReadinessPlan
    var displayPlan: CinematicOverlayDisplayPlan

    private var tint: Color {
        switch readinessPlan.statusIdentifier {
        case "ready":
            return .green
        case "retry-cue", "missing-metadata":
            return .orange
        case "no-immediate":
            return .cyan
        default:
            return .white
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: readinessPlan.systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint.opacity(displayPlan.hudIconEmphasis))
                .frame(width: 14)

            Text(readinessPlan.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(displayPlan.hudTitleEmphasis))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: 92, alignment: .leading)

            Text(readinessPlan.verifyCommandLabel)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(displayPlan.hudStatusTextEmphasis))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            Text(readinessPlan.warningStateIdentifier)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(tint.opacity(0.92))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(tint.opacity(0.13 * displayPlan.overlayOpacity), in: Capsule())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.white.opacity(0.045 * displayPlan.overlayOpacity), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(tint.opacity(readinessPlan.hasWarning ? 0.42 : 0.18), lineWidth: 1)
        }
        .help(readinessPlan.copyText)
        .accessibilityIdentifier("cinematic-plan-compass-readiness-\(readinessPlan.exportIdentifier)")
    }
}

private struct CinematicPlanCompassActionSurfaceControls: View {
    var actionSurface: CinematicPlanCompassActionSurfaceDescriptor
    var performAction: (CinematicPlanCompassCommandPlan.ActionKind) -> Void
    var displayPlan: CinematicOverlayDisplayPlan

    private var overlayActions: [CinematicPlanCompassActionSurfaceDescriptor.Action] {
        actionSurface.actions(in: .overlay)
    }

    private var focusActions: [CinematicPlanCompassActionSurfaceDescriptor.Action] {
        actionSurface.actions(in: .focus)
    }

    private var copyActions: [CinematicPlanCompassActionSurfaceDescriptor.Action] {
        actionSurface.actions(in: .copy)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(overlayActions) { action in
                actionButton(action, width: 48)
            }

            ForEach(focusActions) { action in
                actionButton(action, width: 62)
            }

            Spacer(minLength: 4)

            ForEach(copyActions) { action in
                actionButton(action, width: 58)
            }
        }
        .frame(height: 32)
        .accessibilityIdentifier("cinematic-plan-compass-actions-\(actionSurface.identifier)")
    }

    private func actionButton(
        _ action: CinematicPlanCompassActionSurfaceDescriptor.Action,
        width: CGFloat
    ) -> some View {
        Button {
            performAction(action.sourceActionKind)
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 9.5, weight: .bold))
                        .frame(width: 11, height: 11)
                    Text(compactLabel(for: action))
                        .font(.system(size: 9.5, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Text(action.shortcutHint)
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.white.opacity(displayPlan.hudStatusTextEmphasis))
            }
            .frame(width: width, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .foregroundStyle(tint(for: action).opacity(action.isEnabled ? displayPlan.hudIconEmphasis : 0.42))
        .background(
            .white.opacity(
                (action.isSelectedRoute ? 0.14 : 0.055) * displayPlan.overlayOpacity
            ),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    action.isSelectedRoute
                        ? tint(for: action).opacity(0.66)
                        : .white.opacity(action.isEnabled ? 0.12 : 0.06),
                    lineWidth: 1
                )
        }
        .help(action.help)
        .accessibilityLabel(action.label)
        .accessibilityAddTraits(action.isSelectedRoute ? .isSelected : [])
        .accessibilityIdentifier("cinematic-plan-compass-action-\(action.identifier)")
    }

    private func compactLabel(
        for action: CinematicPlanCompassActionSurfaceDescriptor.Action
    ) -> String {
        switch action.sourceActionKind {
        case .showPlanOverlay:
            return "Show"
        case .focusImmediateRoute:
            return "Now"
        case .focusMidTermRoute:
            return "Mid"
        case .focusLongTermRoute:
            return "Long"
        case .copyFullPlanCompass:
            return "All"
        case .copySelectedRoute:
            return "Route"
        }
    }

    private func tint(
        for action: CinematicPlanCompassActionSurfaceDescriptor.Action
    ) -> Color {
        switch action.sourceActionKind {
        case .showPlanOverlay, .copyFullPlanCompass, .copySelectedRoute:
            return .cyan
        case .focusImmediateRoute:
            return .cyan
        case .focusMidTermRoute:
            return .mint
        case .focusLongTermRoute:
            return .indigo
        }
    }
}

private struct CinematicPlanCompassWaypointStrip: View {
    var plan: CinematicPlanCompassPlan
    var displayPlan: CinematicOverlayDisplayPlan

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(plan.historyStateIdentifier)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(displayPlan.hudStatusTextEmphasis))
                .lineLimit(1)
                .frame(width: 58, alignment: .leading)

            HStack(alignment: .center, spacing: 5) {
                ForEach(plan.completedWaypoints) { waypoint in
                    CinematicPlanCompassWaypointBead(
                        waypoint: waypoint,
                        overlayOpacity: displayPlan.overlayOpacity
                    )
                }
            }
            .frame(minHeight: 18, alignment: .leading)

            if plan.hiddenCompletedWaypointCount > 0 {
                Text("+\(plan.hiddenCompletedWaypointCount)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(displayPlan.hudStatusTextEmphasis))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.08 * displayPlan.overlayOpacity), in: Capsule())
                    .help("\(plan.hiddenCompletedWaypointCount) older completed iterations hidden")
            }

            Spacer(minLength: 0)
        }
        .frame(height: 20, alignment: .leading)
        .help(plan.completedWaypointCopyText)
        .accessibilityIdentifier("cinematic-plan-compass-history-\(plan.completedWaypointStripIdentifier)")
    }
}

private struct CinematicPlanCompassWaypointBead: View {
    var waypoint: CinematicPlanCompassPlan.CompletedWaypointDescriptor
    var overlayOpacity: Double

    private var isLatest: Bool {
        waypoint.stateIdentifier == "latest"
    }

    private var fillColor: Color {
        isLatest
            ? Color.cyan.opacity(0.72 * overlayOpacity)
            : Color.white.opacity(0.1 * overlayOpacity)
    }

    private var strokeColor: Color {
        isLatest
            ? Color.cyan.opacity(0.82)
            : Color.white.opacity(0.16)
    }

    var body: some View {
        let accessibilityID = "cinematic-" + waypoint.id + "-" + waypoint.exportIdentifier

        Text(waypoint.ordinalLabel)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundStyle(isLatest ? .black.opacity(0.82) : .white.opacity(0.72))
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .frame(width: 28, height: 17)
            .background(Capsule().fill(fillColor))
            .overlay {
                Capsule().stroke(strokeColor, lineWidth: 1)
            }
            .help(waypoint.copyText)
            .accessibilityIdentifier(accessibilityID)
    }
}

private struct CinematicPlanCompassSectionRow: View {
    var section: CinematicPlanCompassPlan.SectionDescriptor
    var isSelected: Bool
    var performAction: (CinematicPlanCompassCommandPlan.ActionKind) -> Void
    var displayPlan: CinematicOverlayDisplayPlan

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: section.systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(iconColor.opacity(section.isEmpty ? 0.48 : displayPlan.hudIconEmphasis))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(section.directionLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(section.isEmpty ? 0.62 : displayPlan.hudTitleEmphasis))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(section.label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(iconColor.opacity(section.isEmpty ? 0.5 : 0.88))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(iconColor.opacity(section.isEmpty ? 0.08 : 0.14), in: Capsule())

                    Spacer(minLength: 4)
                }

                Text(section.displayText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(section.isEmpty ? 0.52 : displayPlan.hudDetailTextEmphasis))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(section.metadataSummary)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(displayPlan.hudStatusTextEmphasis))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            .white.opacity(
                (isSelected ? 0.095 : (section.isEmpty ? 0.025 : 0.045)) * displayPlan.overlayOpacity
            ),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? iconColor.opacity(0.58) : .white.opacity(section.isEmpty ? 0.06 : 0.1))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            performAction(section.kind.planCompassFocusActionKind)
        }
        .help(section.copyText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("cinematic-\(section.rowIdentifier)-\(section.exportIdentifier)")
    }

    private var iconColor: Color {
        switch section.kind {
        case .immediate:
            return .cyan
        case .midTerm:
            return .mint
        case .longTerm:
            return .indigo
        }
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
    var artifactSourceReconciliationPlan: CinematicRunRecapShareArtifactSourceReconciliationPlan
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
                sourceReconciliationPlan: artifactSourceReconciliationPlan,
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
    var sourceReconciliationPlan: CinematicRunRecapShareArtifactSourceReconciliationPlan
    var tourPlan: CinematicRunRecapShareArtifactTourPlan
    var tint: Color
    var displayPlan: CinematicOverlayDisplayPlan
    @State private var feedback: String?
    @State private var feedbackStatus: CinematicRunRecapShareArtifactCleanupResult.Status?
    @State private var preservedFeedbackPlanIdentifier: String?
    @State private var sourceBadgeFeedback: String?
    @State private var preservedSourceBadgeIdentifier: String?

    var body: some View {
        let previewPlan = currentPreviewPlan
        let rollupPlan = currentRollupPlan
        let comparisonPlan = currentComparisonPlan
        let pinnedReferencePlan = currentPinnedReferencePlan
        let sourceBadgePlan = currentSourceBadgePlan
        let selectedExportPlan = subsetExportPlan(scope: .selected)
        let filteredExportPlan = subsetExportPlan(scope: .filtered)
        let tourExportPlan = tourSubsetExportPlan(tourPlan)
        let actionMenuPlan = actionMenuPlan(
            previewPlan: previewPlan,
            rollupPlan: rollupPlan,
            comparisonPlan: comparisonPlan,
            pinnedReferencePlan: pinnedReferencePlan,
            tourPlan: tourPlan,
            selectedExportPlan: selectedExportPlan,
            filteredExportPlan: filteredExportPlan,
            tourExportPlan: tourExportPlan
        )
        let commandPlan = CinematicRunRecapShareArtifactCommandPlanner.plan(actionMenuPlan: actionMenuPlan)

        VStack(alignment: .leading, spacing: 4) {
            rollupScanline(rollupPlan)
            sourceBadgeStrip(sourceBadgePlan)
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
                warningPulseFilterControl(previewPlan)

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

                actionMenu(actionMenuPlan, commandPlan: commandPlan)
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
        .focusedValue(
            \.cinematicRunRecapShareArtifactCommandDispatch,
            CinematicRunRecapShareArtifactCommandDispatch(
                plan: commandPlan,
                perform: performCommandAction
            )
        )
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
        .onChange(of: sourceReconciliationPlan.identifier) {
            let sourceBadgePlan = currentSourceBadgePlan
            if preservedSourceBadgeIdentifier == sourceBadgePlan.identifier {
                return
            }
            sourceBadgeFeedback = nil
            preservedSourceBadgeIdentifier = nil
        }
    }

    private var currentPreviewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan {
        CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: plan,
            selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText,
            warningPulseFilter: artifactLibraryContext.warningPulseFilter
        )
    }

    private var currentRollupPlan: CinematicRunRecapShareArtifactRollupPlan {
        CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: plan,
            selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText,
            warningPulseFilter: artifactLibraryContext.warningPulseFilter,
            sourceExportAuditPlan: currentSourceExportAuditPlan
        )
    }

    private var currentSourceBadgePlan: CinematicRunRecapShareArtifactSourceBadgePlan {
        CinematicRunRecapShareArtifactSourceBadgePlanner.plan(
            reconciliationPlan: sourceReconciliationPlan
        )
    }

    private var currentSourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan {
        CinematicRunRecapShareArtifactSourceExportAuditPlanner.plan(
            reconciliationPlan: sourceReconciliationPlan
        )
    }

    private var currentComparisonPlan: CinematicRunRecapShareArtifactComparisonPlan {
        CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: plan,
            selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText,
            targetMode: artifactLibraryContext.comparisonTargetMode,
            pinnedEntryIdentifiers: artifactLibraryContext.pinnedEntryIdentifiers,
            savedTourHoldEntryIdentifier: artifactLibraryContext.savedTourHoldEntryIdentifier,
            warningPulseFilter: artifactLibraryContext.warningPulseFilter,
            sourceExportAuditPlan: currentSourceExportAuditPlan
        )
    }

    private var currentPinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan {
        CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: plan,
            pinnedEntryIdentifiers: artifactLibraryContext.pinnedEntryIdentifiers,
            selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText,
            warningPulseFilter: artifactLibraryContext.warningPulseFilter,
            sourceExportAuditPlan: currentSourceExportAuditPlan
        )
    }

    private var currentActionMenuPlan: CinematicRunRecapShareArtifactActionMenuPlan {
        actionMenuPlan(
            previewPlan: currentPreviewPlan,
            rollupPlan: currentRollupPlan,
            comparisonPlan: currentComparisonPlan,
            pinnedReferencePlan: currentPinnedReferencePlan,
            tourPlan: tourPlan,
            selectedExportPlan: subsetExportPlan(scope: .selected),
            filteredExportPlan: subsetExportPlan(scope: .filtered),
            tourExportPlan: tourSubsetExportPlan(tourPlan)
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

    @ViewBuilder
    private func sourceBadgeStrip(
        _ sourceBadgePlan: CinematicRunRecapShareArtifactSourceBadgePlan
    ) -> some View {
        if sourceBadgePlan.isVisible {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: sourceBadgePlan.systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(sourceBadgeTint(sourceBadgePlan).opacity(0.82))
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 0) {
                    Text(sourceBadgePlan.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text(sourceBadgePlan.detail)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }

                Spacer(minLength: 4)

                if let sourceBadgeFeedback {
                    Text(sourceBadgeFeedback)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(sourceBadgeTint(sourceBadgePlan).opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Button {
                    copySourceBadge(sourceBadgePlan)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(sourceBadgePlan.copyText.isEmpty)
                .foregroundStyle(sourceBadgeTint(sourceBadgePlan).opacity(sourceBadgePlan.copyText.isEmpty ? 0.3 : 0.84))
                .help(sourceBadgePlan.help)
                .accessibilityLabel(sourceBadgePlan.copyLabel)
                .accessibilityIdentifier(sourceBadgePlan.copyAccessibilityIdentifier)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                sourceBadgeTint(sourceBadgePlan).opacity(sourceBadgePlan.severity == .info ? 0.055 : 0.08),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(sourceBadgeTint(sourceBadgePlan).opacity(sourceBadgePlan.severity == .info ? 0.12 : 0.22), lineWidth: 1)
            }
            .help(sourceBadgePlan.help)
            .accessibilityLabel(sourceBadgePlan.label)
            .accessibilityValue(sourceBadgePlan.detail)
            .accessibilityIdentifier(sourceBadgePlan.accessibilityIdentifier)
        }
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

            if let runtimeRouteCue = tourPlan.runtimeRouteCue {
                Text(runtimeRouteCue.compactCopy)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint.opacity(tourPlan.isAvailable ? 0.72 : 0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 42, maxWidth: 78, minHeight: 16)
                    .background(
                        tint.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .help(runtimeRouteCueHelp(runtimeRouteCue))
                    .accessibilityLabel("Runtime route \(runtimeRouteCue.compactCopy)")
                    .accessibilityIdentifier("cinematic-run-recap-artifact-library-tour-runtime-route-\(runtimeRouteCue.routeKindIdentifier)")
            }

            if tourPlan.isAvailable {
                Text(tourPlan.mutationTestingTreatment.compactCopy)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(mutationTreatmentColor(tourPlan).opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 46, maxWidth: 98, minHeight: 16)
                    .background(
                        mutationTreatmentColor(tourPlan).opacity(0.075),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .help(mutationTestingCueHelp(tourPlan))
                    .accessibilityLabel("Mutation cue \(tourPlan.mutationTestingTreatment.compactCopy)")
                    .accessibilityIdentifier("cinematic-run-recap-artifact-library-tour-mutation-\(tourPlan.mutationTestingCueStateIdentifier)")
            }

            if let warningPulseCue = tourPlan.warningPulseCue,
               tourPlan.warningPulseCueStateIdentifier == "active"
                || tourPlan.warningPulseCueStateIdentifier == "snoozed" {
                Text(warningPulseCue.compactCopy)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(warningPulseCueColor(tourPlan).opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 48, maxWidth: 104, minHeight: 16)
                    .background(
                        warningPulseCueColor(tourPlan).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .help(warningPulseCueHelp(tourPlan))
                    .accessibilityLabel("Warning pulse cue \(warningPulseCue.compactCopy)")
                    .accessibilityIdentifier("cinematic-run-recap-artifact-library-tour-warning-pulse-\(tourPlan.warningPulseCueStateIdentifier)")
            }

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
        .help(tourStripHelp(tourPlan))
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
        let pulseFilter = comparisonPlan.isWarningPulseFilterActive
            ? " | pulse \(comparisonPlan.warningPulseFilterIdentifier)"
            : ""
        return "\(mode) | \(comparisonPlan.targetDirectionIdentifier) | \(delta)\(promotedHold)\(search)\(pulseFilter)"
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
        let pulseFilter = pinnedReferencePlan.isWarningPulseFilterActive
            ? " | pulse \(pinnedReferencePlan.warningPulseFilterIdentifier)"
            : ""
        return "Pins \(pinnedReferencePlan.retainedPinnedEntryCount)/\(pinnedReferencePlan.pinnedEntryCount)\(search)\(pulseFilter)\(filtered)\(missing)"
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
        let pulseFilter = tourPlan.isWarningPulseFilterActive
            ? " | pulse \(tourPlan.warningPulseFilterIdentifier)"
            : ""
        return "Tour \(session) | \(tourPlan.selectionSourceIdentifier)\(hold)\(promotedHold)\(search)\(pulseFilter)"
    }

    private func tourStripHelp(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) -> String {
        var parts = [tourSummary(tourPlan)]
        if let runtimeRouteCue = tourPlan.runtimeRouteCue {
            parts.append("Runtime route: \(runtimeRouteCue.detailCopy). \(runtimeRouteCue.helpCopy)")
        }
        if tourPlan.isAvailable {
            parts.append("Mutation: \(tourPlan.mutationTestingCue?.detailCopy ?? tourPlan.mutationTestingTreatment.compactCopy). \(tourPlan.mutationTestingCue?.helpCopy ?? tourPlan.mutationTestingTreatment.helpCopy)")
        }
        if let warningPulseCue = tourPlan.warningPulseCue,
           tourPlan.warningPulseCueStateIdentifier == "active"
            || tourPlan.warningPulseCueStateIdentifier == "snoozed" {
            parts.append("Warning pulse: \(warningPulseCue.detailCopy). \(warningPulseCue.helpCopy)")
        }
        return boundedHelp(parts.joined(separator: " "))
    }

    private func runtimeRouteCueHelp(
        _ runtimeRouteCue: CinematicRunRecapShareArtifactRuntimeRouteCue
    ) -> String {
        boundedHelp("\(runtimeRouteCue.detailCopy). \(runtimeRouteCue.helpCopy)")
    }

    private func mutationTestingCueHelp(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) -> String {
        boundedHelp(
            [
                tourPlan.mutationTestingCue?.detailCopy,
                tourPlan.mutationTestingCue?.helpCopy,
                tourPlan.mutationTestingTreatment.helpCopy
            ]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " ")
        )
    }

    private func warningPulseCueHelp(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) -> String {
        boundedHelp(
            [
                tourPlan.warningPulseCue?.detailCopy,
                tourPlan.warningPulseCue?.helpCopy,
                tourPlan.warningPulseTreatment.helpCopy
            ]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " ")
        )
    }

    private func mutationTreatmentColor(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) -> Color {
        switch tourPlan.mutationTestingCueStateIdentifier {
        case "succeeded":
            return .green
        case "failed":
            return .red
        case "runtime-route-diverged":
            return .orange
        case "unknown":
            return .purple
        default:
            return .secondary
        }
    }

    private func warningPulseCueColor(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) -> Color {
        switch tourPlan.warningPulseCueStateIdentifier {
        case "active":
            return .orange
        case "snoozed":
            return .teal
        default:
            return .secondary
        }
    }

    private func warningPulseFilterTint(
        _ filter: CinematicRunRecapShareArtifactWarningPulseFilter
    ) -> Color {
        switch filter {
        case .active:
            return .orange
        case .snoozed:
            return .teal
        case .any:
            return .yellow
        case .all:
            return tint
        }
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
            return boundedHelp("Promote this retained tour hold to pinned comparison even though the current library filters hide it.")
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
            scope: scope,
            warningPulseFilter: artifactLibraryContext.warningPulseFilter,
            sourceExportAuditPlan: currentSourceExportAuditPlan
        )
    }

    private func tourSubsetExportPlan(
        _ tourPlan: CinematicRunRecapShareArtifactTourPlan
    ) -> CinematicRunRecapShareArtifactSubsetExportPlan {
        CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: plan,
            selectedEntryIdentifier: tourPlan.selectedEntryIdentifier,
            searchQuery: artifactLibraryContext.searchText,
            scope: .selected,
            warningPulseFilter: artifactLibraryContext.warningPulseFilter,
            sourceExportAuditPlan: currentSourceExportAuditPlan
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
            if previewPlan.isWarningPulseFilterActive {
                return "\(previewPlan.availabilityReason) | pulse \(previewPlan.warningPulseFilterIdentifier) \(previewPlan.warningPulseFilterMatchCount)/\(plan.entries.count)"
            }
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
        let pulseFilter = previewPlan.isWarningPulseFilterActive
            ? " | pulse \(previewPlan.warningPulseFilterIdentifier) \(previewPlan.warningPulseFilterMatchCount)"
            : ""
        return "\(previewPlan.titleSnippet) | \(previewPlan.statusSnippet)\(commit)\(search)\(pulseFilter)\(hidden)\(cleanup)\(warnings)"
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

    private func warningPulseFilterControl(
        _ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan
    ) -> some View {
        let currentFilter = artifactLibraryContext.warningPulseFilter
        let currentCount = warningPulseFilterCount(currentFilter, previewPlan: previewPlan)
        let currentIconName = currentFilter.isActive
            ? "exclamationmark.triangle.fill"
            : "exclamationmark.triangle"
        let currentLabel = "\(currentFilter.title) \(currentCount)"

        return HStack(spacing: 3) {
            Menu {
                ForEach(CinematicRunRecapShareArtifactWarningPulseFilter.allCases) { filter in
                    warningPulseFilterMenuButton(filter, previewPlan: previewPlan)
                }
            } label: {
                warningPulseFilterLabel(iconName: currentIconName, title: currentLabel)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .foregroundStyle(warningPulseFilterTint(currentFilter).opacity(currentFilter.isActive ? 0.84 : 0.56))
            .help(warningPulseFilterHelp(currentFilter, previewPlan: previewPlan))
            .accessibilityLabel("Warning pulse artifact filter")
            .accessibilityValue("\(currentFilter.title), \(currentCount)")
            .accessibilityIdentifier("cinematic-run-recap-artifact-library-warning-pulse-filter")

            if currentFilter.isActive {
                Button {
                    updateWarningPulseFilter(.all)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(warningPulseFilterTint(currentFilter).opacity(0.72))
                .help("Clear warning-pulse artifact filter")
                .accessibilityLabel("Clear warning pulse artifact filter")
                .accessibilityIdentifier("cinematic-run-recap-artifact-library-warning-pulse-filter-clear")
            }
        }
        .padding(.horizontal, 5)
        .frame(height: 22)
        .background(
            warningPulseFilterTint(currentFilter).opacity(currentFilter.isActive ? 0.075 : 0.04),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(warningPulseFilterTint(currentFilter).opacity(currentFilter.isActive ? 0.26 : 0.1), lineWidth: 1)
        }
    }

    private func warningPulseFilterMenuButton(
        _ filter: CinematicRunRecapShareArtifactWarningPulseFilter,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan
    ) -> some View {
        let title = warningPulseFilterMenuTitle(filter, previewPlan: previewPlan)
        let help = warningPulseFilterHelp(filter, previewPlan: previewPlan)
        let identifier = warningPulseFilterAccessibilityIdentifier(filter)

        return Button(title) {
            updateWarningPulseFilter(filter)
        }
        .help(help)
        .accessibilityIdentifier(identifier)
    }

    private func warningPulseFilterLabel(iconName: String, title: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 46)
        .frame(height: 22)
        .contentShape(Rectangle())
    }

    private func actionMenu(
        _ actionMenuPlan: CinematicRunRecapShareArtifactActionMenuPlan,
        commandPlan: CinematicRunRecapShareArtifactCommandPlan
    ) -> some View {
        Menu {
            ForEach(CinematicRunRecapShareArtifactActionMenuPlan.Section.allCases) { section in
                if !actionMenuPlan.actions(in: section).isEmpty {
                    Section {
                        ForEach(actionMenuPlan.actions(in: section)) { action in
                            Button {
                                performMenuAction(action)
                            } label: {
                                Label {
                                    actionMenuLabel(action, commandPlan: commandPlan)
                                } icon: {
                                    Image(systemName: action.systemImage)
                                }
                            }
                            .disabled(!action.isEnabled)
                            .help(action.help)
                            .accessibilityLabel(action.label)
                            .accessibilityIdentifier("cinematic-run-recap-artifact-library-menu-\(action.identifier)")
                        }
                    } header: {
                        Text(section.title)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(tint.opacity(0.86))
        .help("More recap artifact actions")
        .accessibilityLabel("More recap artifact actions")
        .accessibilityIdentifier("cinematic-run-recap-artifact-library-action-menu-\(actionMenuPlan.identifier)")
    }

    private func actionMenuLabel(
        _ action: CinematicRunRecapShareArtifactActionMenuPlan.Action,
        commandPlan: CinematicRunRecapShareArtifactCommandPlan
    ) -> some View {
        let shortcutHint = commandPlan.command(for: action.actionKind)?.shortcut.displayText ?? action.shortcutHint
        return HStack {
            Text(action.label)
            if let shortcutHint {
                Spacer()
                Text(shortcutHint)
                    .foregroundStyle(.secondary)
            }
        }
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

    private func warningPulseFilterHelp(
        _ filter: CinematicRunRecapShareArtifactWarningPulseFilter,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan
    ) -> String {
        let count = warningPulseFilterCount(filter, previewPlan: previewPlan)
        switch filter {
        case .all:
            return "Show all \(plan.entries.count) retained saved recap artifacts."
        case .any:
            return "Show \(count) saved recap artifact\(count == 1 ? "" : "s") with a diagnostics warning-pulse cue."
        case .active:
            return "Show \(count) saved recap artifact\(count == 1 ? "" : "s") with active diagnostics warning pulses."
        case .snoozed:
            return "Show \(count) saved recap artifact\(count == 1 ? "" : "s") with snoozed diagnostics warning pulses."
        }
    }

    private func warningPulseFilterMenuTitle(
        _ filter: CinematicRunRecapShareArtifactWarningPulseFilter,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan
    ) -> String {
        let count = warningPulseFilterCount(filter, previewPlan: previewPlan)
        return "\(filter.title) (\(count))"
    }

    private func warningPulseFilterAccessibilityIdentifier(
        _ filter: CinematicRunRecapShareArtifactWarningPulseFilter
    ) -> String {
        "cinematic-run-recap-artifact-library-warning-pulse-filter-\(filter.rawValue)"
    }

    private func warningPulseFilterCount(
        _ filter: CinematicRunRecapShareArtifactWarningPulseFilter,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan
    ) -> Int {
        switch filter {
        case .all:
            return plan.entries.count
        case .any:
            return previewPlan.warningPulseAnyCount
        case .active:
            return previewPlan.warningPulseActiveCount
        case .snoozed:
            return previewPlan.warningPulseSnoozedCount
        }
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

    private func actionMenuPlan(
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        rollupPlan: CinematicRunRecapShareArtifactRollupPlan,
        comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan,
        pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan,
        tourPlan: CinematicRunRecapShareArtifactTourPlan,
        selectedExportPlan: CinematicRunRecapShareArtifactSubsetExportPlan,
        filteredExportPlan: CinematicRunRecapShareArtifactSubsetExportPlan,
        tourExportPlan: CinematicRunRecapShareArtifactSubsetExportPlan
    ) -> CinematicRunRecapShareArtifactActionMenuPlan {
        CinematicRunRecapShareArtifactActionMenuPlanner.plan(
            previewPlan: previewPlan,
            rollupPlan: rollupPlan,
            comparisonPlan: comparisonPlan,
            pinnedReferencePlan: pinnedReferencePlan,
            tourPlan: tourPlan,
            selectedExportPlan: selectedExportPlan,
            filteredExportPlan: filteredExportPlan,
            historyPlan: plan,
            tourExportPlan: tourExportPlan
        )
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

    private func sourceBadgeTint(
        _ sourceBadgePlan: CinematicRunRecapShareArtifactSourceBadgePlan
    ) -> Color {
        switch sourceBadgePlan.tintIdentifier {
        case "teal":
            return .teal
        case "blue":
            return .blue
        case "orange":
            return .orange
        case "red":
            return .red
        case "yellow":
            return .yellow
        case "purple":
            return .purple
        default:
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

    private func performCommandAction(
        _ actionKind: CinematicRunRecapShareArtifactActionMenuPlan.ActionKind
    ) {
        guard let action = currentActionMenuPlan.actions.first(where: { $0.actionKind == actionKind }) else {
            return
        }
        performMenuAction(action)
    }

    private func performMenuAction(
        _ action: CinematicRunRecapShareArtifactActionMenuPlan.Action
    ) {
        guard action.isEnabled else { return }

        switch action.actionKind {
        case .navigatePrevious:
            selectArtifact(currentPreviewPlan.previousEntryIdentifier)
        case .navigateNext:
            selectArtifact(currentPreviewPlan.nextEntryIdentifier)
        case .revealSelected:
            revealSelectedArtifact()
        case .copySelectedExport:
            copySubsetExport(subsetExportPlan(scope: .selected))
        case .copyFilteredExport:
            copySubsetExport(subsetExportPlan(scope: .filtered))
        case .copyLibraryExport:
            copyExport()
        case .copyRollupExport:
            copyRollup(currentRollupPlan)
        case .copyComparisonExport:
            copyComparison(currentComparisonPlan)
        case .copyPinnedExport:
            copyPinnedExport(currentPinnedReferencePlan)
        case .copyTourExport:
            copyTourExport(tourPlan)
        case .cleanupOldArtifacts:
            cleanupArtifacts()
        case .toggleComparisonTargetMode:
            toggleComparisonTargetMode()
        case .toggleSelectedPin:
            toggleSelectedPin(currentPreviewPlan)
        case .toggleTourHold:
            holdOrReleaseCurrentTour(tourPlan.selectedEntryIdentifier)
        case .toggleSelectedTourHold:
            toggleTourHold(currentPreviewPlan.selectedEntryIdentifier)
        case .promoteTourHold:
            promoteTourHoldToPinnedReference(tourPlan)
        }
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

    private func copySourceBadge(
        _ sourceBadgePlan: CinematicRunRecapShareArtifactSourceBadgePlan
    ) {
        guard sourceBadgePlan.isVisible, !sourceBadgePlan.copyText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sourceBadgePlan.copyText, forType: .string)
        sourceBadgeFeedback = "Source copied"
        preservedSourceBadgeIdentifier = sourceBadgePlan.identifier
    }

    private func copyExport() {
        guard plan.isAvailable else { return }
        NSPasteboard.general.clearContents()
        let export = CinematicRunRecapShareArtifactSourceExportAuditPlanner.markdownExport(
            baseMarkdown: plan.combinedMarkdownExport,
            sourceExportAuditPlan: currentSourceExportAuditPlan,
            limit: CinematicRunRecapShareArtifactHistoryPlan.combinedMarkdownMaxCharacters
        )
        NSPasteboard.general.setString(export, forType: .string)
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
            searchQuery: artifactLibraryContext.searchText,
            warningPulseFilter: artifactLibraryContext.warningPulseFilter
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

    private func updateWarningPulseFilter(
        _ filter: CinematicRunRecapShareArtifactWarningPulseFilter
    ) {
        let nextFilter = artifactLibraryContext.warningPulseFilter == filter && filter != .all
            ? CinematicRunRecapShareArtifactWarningPulseFilter.all
            : filter
        let requestedContext = artifactLibraryContext.replacing(
            selectedEntryIdentifier: artifactLibraryContext.selectedEntryIdentifier,
            searchText: artifactLibraryContext.searchText,
            warningPulseFilter: nextFilter
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
    var selectedPlanCompassKind: PlanWorkflowOverview.Kind = .immediate
    var planCompassSceneFocusPlan: CinematicPlanCompassSceneFocusPlan = .none
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
                planCompassCommandSelectedKind: selectedPlanCompassKind,
                planCompassSceneFocusPlan: planCompassSceneFocusPlan,
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
                    CinematicDiagnosticsPopover(
                        summary: summary,
                        warningBundleHistory: project.cinematicDiagnosticsWarningBundleHistory,
                        warningPulseQuietingDescriptor:
                            project.cinematicDiagnosticsWarningPulseQuietingDescriptor,
                        onSnoozeWarningPulse: {
                            project.snoozeCinematicDiagnosticsWarningPulse()
                        },
                        onResumeWarningPulse: {
                            project.resumeCinematicDiagnosticsWarningPulse()
                        }
                    )
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
        .onChange(of: summary.attentionSummary) {
            recordDiagnosticsWarningBundle(summary)
        }
        .onAppear {
            recordDiagnosticsWarningBundle(summary)
        }
    }

    private func recordDiagnosticsWarningBundle(_ summary: CinematicDiagnosticsSummary) {
        project.recordCinematicDiagnosticsWarningBundle(summary.attentionSummary)
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
    var warningBundleHistory: CinematicDiagnosticsWarningBundleHistory
    var warningPulseQuietingDescriptor: CinematicDiagnosticsWarningPulseQuietingDescriptor?
    var onSnoozeWarningPulse: () -> Void
    var onResumeWarningPulse: () -> Void
    @State private var copied = false
    @State private var copiedWarningBundleHistory = false
    @State private var copiedWarningBundleHistoryRowID: String?
    @State private var copiedWarningPulseQuieting = false
    @State private var copiedNativeFeedbackHistory = false
    @State private var copiedTargetID: String?
    @State private var groupExpansion: [String: Bool] = [:]
    @FocusState private var focusedGroupID: String?

    private var warningPulseQuietingStatus:
        CinematicDiagnosticsWarningPulseQuietingStatusDescriptor
    {
        CinematicDiagnosticsWarningPulseQuietingStatusDescriptor(
            currentBundle: warningBundleHistory.currentUnresolvedBundle,
            quietingDescriptor: warningPulseQuietingDescriptor
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Diagnostics")
                    .font(.headline.weight(.semibold))

                Spacer()

                if summary.nativeFeedbackHistoryExport.isAvailable {
                    Button {
                        copyToPasteboard(summary.nativeFeedbackHistoryExport.copyText)
                        copied = false
                        copiedWarningBundleHistory = false
                        copiedWarningBundleHistoryRowID = nil
                        copiedWarningPulseQuieting = false
                        copiedNativeFeedbackHistory = true
                        copiedTargetID = nil
                    } label: {
                        Image(systemName: copiedNativeFeedbackHistory ? "checkmark" : "clock.arrow.circlepath")
                            .foregroundStyle(copiedNativeFeedbackHistory ? .green : .secondary)
                            .frame(width: 17, height: 17)
                    }
                    .disabled(!summary.nativeFeedbackHistoryExport.isAvailable)
                    .accessibilityLabel(summary.nativeFeedbackHistoryExport.copyLabel)
                    .help(summary.nativeFeedbackHistoryExport.copyHelp)
                }

                Button {
                    copyToPasteboard(summary.exportText)
                    copied = true
                    copiedWarningBundleHistory = false
                    copiedWarningBundleHistoryRowID = nil
                    copiedWarningPulseQuieting = false
                    copiedNativeFeedbackHistory = false
                    copiedTargetID = nil
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
        .onChange(of: summary) {
            copied = false
            copiedWarningBundleHistory = false
            copiedWarningBundleHistoryRowID = nil
            copiedWarningPulseQuieting = false
            copiedNativeFeedbackHistory = false
            copiedTargetID = nil
            resetExpansionDefaults()
        }
        .onChange(of: warningBundleHistory) {
            copiedWarningBundleHistory = false
            copiedWarningBundleHistoryRowID = nil
            copiedWarningPulseQuieting = false
        }
        .onChange(of: warningPulseQuietingDescriptor) {
            copiedWarningPulseQuieting = false
        }
        .onAppear {
            resetExpansionDefaults()
        }
    }

    @ViewBuilder
    private func attentionSummarySection(scrollProxy: ScrollViewProxy) -> some View {
        let warningRollup = warningBundleHistory.rollup
        if !summary.attentionSummary.isEmpty || warningRollup.isAvailable {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(summary.attentionSummary.isEmpty ? "Warning history" : "Warnings")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)

                    Spacer()

                    if warningRollup.isAvailable {
                        Button {
                            copyToPasteboard(warningRollup.copyText)
                            copied = false
                            copiedWarningBundleHistory = true
                            copiedWarningBundleHistoryRowID = nil
                            copiedWarningPulseQuieting = false
                            copiedNativeFeedbackHistory = false
                            copiedTargetID = nil
                        } label: {
                            Image(
                                systemName: copiedWarningBundleHistory
                                    ? "checkmark"
                                    : "exclamationmark.triangle"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(copiedWarningBundleHistory ? .green : .secondary)
                            .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(warningRollup.copyLabel)
                        .help(warningRollup.copyHelp)
                    }
                }

                ForEach(summary.attentionSummary.targets) { target in
                    HStack(alignment: .center, spacing: 6) {
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("Show \(target.label)")

                        Button {
                            copyToPasteboard(target.copyText)
                            copied = false
                            copiedWarningBundleHistory = false
                            copiedWarningBundleHistoryRowID = nil
                            copiedWarningPulseQuieting = false
                            copiedNativeFeedbackHistory = false
                            copiedTargetID = target.id
                        } label: {
                            Image(systemName: copiedTargetID == target.id ? "checkmark" : "doc.on.doc")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(copiedTargetID == target.id ? .green : .secondary)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy \(target.label) warning details")
                        .help("Copy \(target.label) warning details")
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

                if warningBundleHistory.currentUnresolvedBundle != nil {
                    warningPulseQuietingControl(warningPulseQuietingStatus)
                }

                if warningRollup.isAvailable {
                    warningBundleHistoryRollup(warningRollup)
                }
            }
        }
    }

    private func warningPulseQuietingControl(
        _ status: CinematicDiagnosticsWarningPulseQuietingStatusDescriptor
    ) -> some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: status.isSnoozed ? "moon.zzz.fill" : "dot.radiowaves.left.and.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(status.isSnoozed ? Color.secondary : Color.orange)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(status.detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if status.canResume {
                    onResumeWarningPulse()
                } else if status.canSnooze {
                    onSnoozeWarningPulse()
                }
                copiedWarningPulseQuieting = false
            } label: {
                Image(systemName: status.canResume ? "play.circle" : "moon.zzz")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(!status.canSnooze && !status.canResume)
            .accessibilityLabel(status.actionLabel)
            .help(status.actionHelp)

            Button {
                copyToPasteboard(status.copyText)
                copied = false
                copiedWarningBundleHistory = false
                copiedWarningBundleHistoryRowID = nil
                copiedWarningPulseQuieting = true
                copiedNativeFeedbackHistory = false
                copiedTargetID = nil
            } label: {
                Image(systemName: copiedWarningPulseQuieting ? "checkmark" : "doc.on.doc")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(copiedWarningPulseQuieting ? .green : .secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(status.copyText.isEmpty)
            .accessibilityLabel(status.copyLabel)
            .help(status.copyHelp)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .orange.opacity(status.isSnoozed ? 0.05 : 0.08),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.orange.opacity(status.isSnoozed ? 0.18 : 0.26))
        }
        .accessibilityIdentifier(status.id)
    }

    private func warningBundleHistoryRollup(
        _ rollup: CinematicDiagnosticsWarningBundleHistory.RollupDescriptor
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: rollup.stateIdentifier == "current-unresolved" ? "bolt.trianglebadge.exclamationmark" : "clock.arrow.circlepath")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                    .frame(width: 14)

                Text(rollup.stateLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(rollup.countsLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(rollup.stateDetail)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            ForEach(rollup.rows) { row in
                warningBundleHistoryRollupRow(row)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.orange.opacity(0.2))
        }
        .accessibilityIdentifier(rollup.id)
    }

    private func warningBundleHistoryRollupRow(
        _ row: CinematicDiagnosticsWarningBundleHistory.RollupDescriptor.RowDescriptor
    ) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: warningBundleHistoryRollupRowImage(for: row.kind))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange.opacity(0.82))
                .frame(width: 13)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(row.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(row.countLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(row.detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                copyToPasteboard(row.copyText)
                copied = false
                copiedWarningBundleHistory = false
                copiedWarningBundleHistoryRowID = row.id
                copiedWarningPulseQuieting = false
                copiedNativeFeedbackHistory = false
                copiedTargetID = nil
            } label: {
                Image(systemName: copiedWarningBundleHistoryRowID == row.id ? "checkmark" : "doc.on.doc")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(copiedWarningBundleHistoryRowID == row.id ? .green : .secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.copyLabel)
            .help(row.copyHelp)
        }
        .accessibilityIdentifier(row.id)
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
                    visualSmokeCheckRow(check)
                        .id(visualSmokeCheckAnchorID(for: check))
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
                .id(diagnosticsRowAnchorID(for: row.id))
            }
        }
    }

    private func visualSmokeCheckRow(
        _ check: CinematicVisualSmokeReport.Check
    ) -> some View {
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

                if let context = relatedDiagnosticsContext(for: check) {
                    Text(context)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        if let relatedGroupID = target.relatedGroupID {
            groupExpansion[relatedGroupID] = true
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            scrollProxy.scrollTo(target.targetAnchorID, anchor: .top)
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

    private func warningBundleHistoryRollupRowImage(
        for kind: CinematicDiagnosticsWarningBundleHistory.RollupDescriptor.RowDescriptor.Kind
    ) -> String {
        switch kind {
        case .recentBundle:
            return "clock.arrow.circlepath"
        case .warningIdentifierGroup:
            return "number"
        case .repeatedIdentifiers:
            return "repeat"
        case .targetAnchors:
            return "scope"
        case .relatedRowAnchors:
            return "link"
        }
    }

    private func visualSmokeCheckAnchorID(for check: CinematicVisualSmokeReport.Check) -> String {
        check.warningTarget?.targetAnchorID ?? "visual-smoke-check-\(check.id)"
    }

    private func diagnosticsRowAnchorID(for rowID: String) -> String {
        "diagnostics-row-\(rowID)"
    }

    private func relatedDiagnosticsContext(for check: CinematicVisualSmokeReport.Check) -> String? {
        guard let warningTarget = check.warningTarget,
              let relatedRow = summary.relatedRow(for: warningTarget)
        else {
            return nil
        }

        return "Related \(relatedRow.label): \(relatedRow.detail)"
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

private struct CinematicActivitySourceCueChip: View {
    var cue: CinematicActivitySourceCuePlan
    var displayPlan: CinematicOverlayDisplayPlan

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: cue.systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint.opacity(displayPlan.worldTextPillIconEmphasis))
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(cue.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(displayPlan.worldTextPillTextEmphasis))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(cue.activeStorageIdentifier)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(tint.opacity(0.84))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(tint.opacity(0.13 * displayPlan.overlayOpacity), in: Capsule())
                }

                Text(cue.detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(displayPlan.hudDetailTextEmphasis))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, CGFloat(displayPlan.worldTextPillHorizontalPadding))
        .padding(.vertical, CGFloat(displayPlan.worldTextPillVerticalPadding))
        .frame(maxWidth: CGFloat(displayPlan.worldTextMaxWidth), alignment: .leading)
        .background(
            .black.opacity(max(0.28, displayPlan.worldTextPillBackgroundOpacity) * displayPlan.overlayOpacity),
            in: RoundedRectangle(cornerRadius: CGFloat(displayPlan.worldTextPillCornerRadius))
        )
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(displayPlan.worldTextPillCornerRadius))
                .stroke(tint.opacity(max(0.18, displayPlan.worldTextPillStrokeOpacity)), lineWidth: 1)
        }
        .help(cue.helpText.isEmpty ? cue.copyText : cue.helpText)
        .accessibilityLabel("Activity source: \(cue.label)")
        .accessibilityValue(cue.detail)
        .accessibilityHint("Read-only activity-source status")
        .accessibilityIdentifier("cinematic-activity-source-cue-\(cue.identifier)")
    }

    private var tint: Color {
        switch cue.tintIdentifier {
        case "green":
            return .green
        case "blue":
            return .blue
        case "orange":
            return .orange
        case "red":
            return .red
        default:
            return .white
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

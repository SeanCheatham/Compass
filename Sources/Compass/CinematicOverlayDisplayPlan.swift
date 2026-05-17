import Foundation

enum CinematicOverlayDisplayMode: String, CaseIterable, Equatable {
    case full
    case compact
    case fallback
}

enum CinematicOverlayPill: String, CaseIterable, Equatable, Hashable, Identifiable {
    case quest
    case arena
    case activity

    var id: String { rawValue }
}

enum CinematicHUDProminence: String, CaseIterable, Equatable {
    case full
    case compact
    case minimal
}

struct CinematicNarrativeCueReadabilitySignals: Equatable {
    static let readableOpacityThreshold: Float = 0.38
    static let readableScaleThreshold: Float = 0.72
    static let readablePrimaryFontSizeThreshold: Float = 0.11
    static let readableBackingOpacityThreshold: Float = 0.1

    var hasQuestPlaque: Bool
    var hasArenaInscription: Bool
    var hasActivityBanner: Bool
    var readableCueCount: Int
    var minimumScale: Float
    var minimumOpacity: Float
    var minimumPrimaryFontSize: Float
    var minimumBackingOpacity: Float
    var hasReadableText: Bool
    var hasReadableLayout: Bool
    var identifier: String

    var isReadable: Bool {
        hasQuestPlaque
            && hasArenaInscription
            && hasActivityBanner
            && readableCueCount >= 3
            && hasReadableText
            && hasReadableLayout
            && minimumScale >= Self.readableScaleThreshold
            && minimumOpacity >= Self.readableOpacityThreshold
            && minimumPrimaryFontSize >= Self.readablePrimaryFontSizeThreshold
            && minimumBackingOpacity >= Self.readableBackingOpacityThreshold
    }

    static let unavailable = CinematicNarrativeCueReadabilitySignals(
        hasQuestPlaque: false,
        hasArenaInscription: false,
        hasActivityBanner: false,
        readableCueCount: 0,
        minimumScale: 0,
        minimumOpacity: 0,
        minimumPrimaryFontSize: 0,
        minimumBackingOpacity: 0,
        hasReadableText: false,
        hasReadableLayout: false
    )

    init(
        hasQuestPlaque: Bool,
        hasArenaInscription: Bool,
        hasActivityBanner: Bool,
        readableCueCount: Int,
        minimumScale: Float,
        minimumOpacity: Float,
        minimumPrimaryFontSize: Float,
        minimumBackingOpacity: Float,
        hasReadableText: Bool,
        hasReadableLayout: Bool
    ) {
        self.hasQuestPlaque = hasQuestPlaque
        self.hasArenaInscription = hasArenaInscription
        self.hasActivityBanner = hasActivityBanner
        self.readableCueCount = max(0, readableCueCount)
        self.minimumScale = max(0, minimumScale)
        self.minimumOpacity = max(0, minimumOpacity)
        self.minimumPrimaryFontSize = max(0, minimumPrimaryFontSize)
        self.minimumBackingOpacity = max(0, minimumBackingOpacity)
        self.hasReadableText = hasReadableText
        self.hasReadableLayout = hasReadableLayout
        identifier = [
            "quest:\(Self.flag(hasQuestPlaque))",
            "arena:\(Self.flag(hasArenaInscription))",
            "activity:\(Self.flag(hasActivityBanner))",
            "count:\(max(0, readableCueCount))",
            "scale:\(Self.fixed(max(0, minimumScale)))",
            "opacity:\(Self.fixed(max(0, minimumOpacity)))",
            "font:\(Self.fixed(max(0, minimumPrimaryFontSize)))",
            "backing:\(Self.fixed(max(0, minimumBackingOpacity)))",
            "text:\(Self.flag(hasReadableText))",
            "layout:\(Self.flag(hasReadableLayout))"
        ].joined(separator: "|")
    }

    init(plan: CinematicSceneNarrativeCuePlan) {
        let quest = Self.signal(for: plan.questPlaque)
        let arena = Self.signal(for: plan.arenaInscription)
        let activity = Self.signal(for: plan.activityBanner)
        let signals = [quest, arena, activity]

        self.init(
            hasQuestPlaque: quest.isVisibleText,
            hasArenaInscription: arena.isVisibleText,
            hasActivityBanner: activity.isVisibleText,
            readableCueCount: signals.filter(\.isVisibleText).count,
            minimumScale: signals.map(\.scale).min() ?? 0,
            minimumOpacity: signals.map(\.opacity).min() ?? 0,
            minimumPrimaryFontSize: signals.map(\.primaryFontSize).min() ?? 0,
            minimumBackingOpacity: signals.map(\.backingOpacity).min() ?? 0,
            hasReadableText: signals.allSatisfy(\.hasText),
            hasReadableLayout: signals.allSatisfy(\.hasLayout)
        )
    }

    private struct CueSignal {
        var isVisibleText: Bool
        var hasText: Bool
        var hasLayout: Bool
        var scale: Float
        var opacity: Float
        var primaryFontSize: Float
        var backingOpacity: Float
    }

    private static func signal(
        for descriptor: CinematicSceneNarrativeCuePlan.CueDescriptor
    ) -> CueSignal {
        let hasText = !descriptor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let layout = descriptor.layout
        let hasLayout = layout.plateSize.x > 0
            && layout.plateSize.y > 0
            && layout.primaryTextWidth > 0
            && layout.primaryFontSize > 0
        return CueSignal(
            isVisibleText: hasText && descriptor.visibility != .dim,
            hasText: hasText,
            hasLayout: hasLayout,
            scale: descriptor.scale,
            opacity: descriptor.opacity,
            primaryFontSize: layout.primaryFontSize,
            backingOpacity: layout.backingOpacity
        )
    }

    private static func flag(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private static func fixed(_ value: Float) -> String {
        String(format: "%.4f", Double(value))
    }
}

struct CinematicOverlayDisplayPlan: Equatable {
    static let gradientStrengthRange: ClosedRange<Double> = 0.18...0.58
    static let worldTextMaxWidthRange: ClosedRange<Double> = 240...430
    static let hudMaxWidthRange: ClosedRange<Double> = 360...620
    static let overlayOpacityRange: ClosedRange<Double> = 0.72...1
    static let pillLineLimitRange: ClosedRange<Int> = 1...2
    static let hudTitleLineLimitRange: ClosedRange<Int> = 1...2
    static let hudDetailLineLimitRange: ClosedRange<Int> = 1...3
    static let hudProfileLineLimitRange: ClosedRange<Int> = 1...2
    static let hudStatusLineLimitRange: ClosedRange<Int> = 1...2

    var identifier: String
    var mode: CinematicOverlayDisplayMode
    var visiblePills: [CinematicOverlayPill]
    var hudProminence: CinematicHUDProminence
    var gradientStrength: Double
    var worldTextMaxWidth: Double
    var hudMaxWidth: Double
    var pillLineLimit: Int
    var hudTitleLineLimit: Int
    var hudDetailLineLimit: Int
    var hudProfileLineLimit: Int
    var hudStatusLineLimit: Int
    var overlayOpacity: Double
    var reasonIdentifier: String
    var narrativeCueReadabilityIdentifier: String

    var modeIdentifier: String { mode.rawValue }
    var hudProminenceIdentifier: String { hudProminence.rawValue }
    var visiblePillIdentifiers: [String] { visiblePills.map(\.rawValue) }
    var showsWorldTextOverlay: Bool { !visiblePills.isEmpty }
    var showsHUDDetail: Bool { hudProminence != .minimal }
    var showsHUDProfiles: Bool { hudProminence == .full }

    init(
        mode: CinematicOverlayDisplayMode,
        visiblePills: [CinematicOverlayPill],
        hudProminence: CinematicHUDProminence,
        gradientStrength: Double,
        worldTextMaxWidth: Double,
        hudMaxWidth: Double,
        pillLineLimit: Int,
        hudTitleLineLimit: Int,
        hudDetailLineLimit: Int,
        hudProfileLineLimit: Int,
        hudStatusLineLimit: Int,
        overlayOpacity: Double,
        reasonIdentifier: String,
        narrativeCueReadability: CinematicNarrativeCueReadabilitySignals,
        phase: LoopPhase,
        isRunning: Bool,
        isAutoPlaying: Bool,
        isPaused: Bool,
        hasRepository: Bool,
        worldText: CinematicWorldText,
        briefing: CinematicBriefing,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings
    ) {
        self.mode = mode
        self.visiblePills = Self.uniquePills(visiblePills)
        self.hudProminence = hudProminence
        self.gradientStrength = Self.clamp(gradientStrength, to: Self.gradientStrengthRange)
        self.worldTextMaxWidth = Self.clamp(worldTextMaxWidth, to: Self.worldTextMaxWidthRange)
        self.hudMaxWidth = Self.clamp(hudMaxWidth, to: Self.hudMaxWidthRange)
        self.pillLineLimit = Self.clamp(pillLineLimit, to: Self.pillLineLimitRange)
        self.hudTitleLineLimit = Self.clamp(hudTitleLineLimit, to: Self.hudTitleLineLimitRange)
        self.hudDetailLineLimit = Self.clamp(hudDetailLineLimit, to: Self.hudDetailLineLimitRange)
        self.hudProfileLineLimit = Self.clamp(hudProfileLineLimit, to: Self.hudProfileLineLimitRange)
        self.hudStatusLineLimit = Self.clamp(hudStatusLineLimit, to: Self.hudStatusLineLimitRange)
        self.overlayOpacity = Self.clamp(overlayOpacity, to: Self.overlayOpacityRange)
        self.reasonIdentifier = reasonIdentifier
        narrativeCueReadabilityIdentifier = narrativeCueReadability.identifier
        identifier = [
            "mode:\(mode.rawValue)",
            "reason:\(reasonIdentifier)",
            "pills:\(self.visiblePills.map(\.rawValue).joined(separator: ","))",
            "hud:\(hudProminence.rawValue)",
            "gradient:\(Self.fixed(self.gradientStrength))",
            "widths:\(Self.fixed(self.worldTextMaxWidth))/\(Self.fixed(self.hudMaxWidth))",
            "lines:\(self.pillLineLimit)/\(self.hudTitleLineLimit)/\(self.hudDetailLineLimit)/\(self.hudProfileLineLimit)/\(self.hudStatusLineLimit)",
            "opacity:\(Self.fixed(self.overlayOpacity))",
            "phase:\(phase.rawValue)",
            "running:\(Self.flag(isRunning))",
            "auto:\(Self.flag(isAutoPlaying))",
            "paused:\(Self.flag(isPaused))",
            "repo:\(Self.flag(hasRepository))",
            "language:\(languageProfile.primaryLanguage.rawValue)",
            "activity:\(Self.activityIdentifier(activityProfile))",
            "influence:\(influenceSettings.cameraStyle.rawValue)|\(Self.fixed(influenceSettings.intensity))",
            "world:\(Self.copyIdentifier(worldText.questLabel, worldText.arenaCallout, worldText.activityCallout))",
            "briefing:\(Self.copyIdentifier(briefing.title, briefing.detail))",
            "readability:\(narrativeCueReadability.identifier)"
        ].joined(separator: "|")
    }

    private static func uniquePills(_ pills: [CinematicOverlayPill]) -> [CinematicOverlayPill] {
        var seen = Set<CinematicOverlayPill>()
        return pills.filter { seen.insert($0).inserted }
    }

    private static func activityIdentifier(_ profile: RepositoryActivityProfile) -> String {
        guard profile.isAvailable else { return "unavailable" }
        return "\(profile.pressureLevel.rawValue)-\(profile.pressureScore)"
    }

    private static func copyIdentifier(_ values: String...) -> String {
        values
            .map {
                $0
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .joined(separator: "/")
    }

    private static func flag(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private static func fixed(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

enum CinematicOverlayDisplayPlanner {
    static func plan(
        phase: LoopPhase,
        isRunning: Bool,
        isAutoPlaying: Bool,
        isPaused: Bool,
        hasRepository: Bool,
        worldText: CinematicWorldText,
        briefing: CinematicBriefing,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings,
        narrativeCueReadability: CinematicNarrativeCueReadabilitySignals
    ) -> CinematicOverlayDisplayPlan {
        let currentPhase: LoopPhase = isPaused ? .paused : phase
        let copyAvailable = hasRenderableCopy(worldText: worldText, briefing: briefing)
        let modeAndReason = displayMode(
            phase: currentPhase,
            isRunning: isRunning,
            isAutoPlaying: isAutoPlaying,
            hasRepository: hasRepository,
            copyAvailable: copyAvailable,
            activityProfile: activityProfile,
            narrativeCueReadability: narrativeCueReadability
        )
        let values = displayValues(
            mode: modeAndReason.mode,
            reasonIdentifier: modeAndReason.reason,
            phase: currentPhase,
            influenceSettings: influenceSettings
        )

        return CinematicOverlayDisplayPlan(
            mode: modeAndReason.mode,
            visiblePills: values.visiblePills,
            hudProminence: values.hudProminence,
            gradientStrength: values.gradientStrength,
            worldTextMaxWidth: values.worldTextMaxWidth,
            hudMaxWidth: values.hudMaxWidth,
            pillLineLimit: values.pillLineLimit,
            hudTitleLineLimit: values.hudTitleLineLimit,
            hudDetailLineLimit: values.hudDetailLineLimit,
            hudProfileLineLimit: values.hudProfileLineLimit,
            hudStatusLineLimit: values.hudStatusLineLimit,
            overlayOpacity: values.overlayOpacity,
            reasonIdentifier: modeAndReason.reason,
            narrativeCueReadability: narrativeCueReadability,
            phase: currentPhase,
            isRunning: isRunning,
            isAutoPlaying: isAutoPlaying,
            isPaused: isPaused,
            hasRepository: hasRepository,
            worldText: worldText,
            briefing: briefing,
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings
        )
    }

    static func narrativeCueReadabilitySignals(
        phase: LoopPhase,
        worldText: CinematicWorldText,
        briefing: CinematicBriefing,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicNarrativeCueReadabilitySignals {
        let languageMotif = CinematicMotif.language(for: languageProfile)
        let activityMotif = CinematicMotif.activity(for: activityProfile)
        let stageBeat = CinematicStageBeatPlanner.plan(
            phase: phase,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings
        )
        let setDressingPlan = CinematicSetDressingPlanner.plan(
            languageMotif: languageMotif,
            activityMotif: activityMotif,
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings
        )
        let stageEffectPlan = CinematicStageEffectPlanner.plan(
            beat: stageBeat,
            setDressingPlan: setDressingPlan,
            influenceSettings: influenceSettings
        )
        let stageAtmospherePlan = CinematicStageAtmospherePlanner.plan(
            beat: stageBeat,
            setDressingPlan: setDressingPlan,
            stageEffectTuning: stageEffectPlan.tuningMetadata,
            influenceSettings: influenceSettings
        )
        let stagePhasePolishPlan = CinematicStagePhasePolishPlanner.plan(
            beat: stageBeat,
            stageEffectTuning: stageEffectPlan.tuningMetadata,
            atmospherePlan: stageAtmospherePlan,
            activityMotif: activityMotif,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings
        )
        let narrativeCuePlan = CinematicSceneNarrativeCuePlanner.plan(
            worldText: worldText,
            briefing: briefing,
            stageBeat: stageBeat,
            stagePhasePolishPlan: stagePhasePolishPlan,
            languageMotif: languageMotif,
            activityMotif: activityMotif,
            influenceSettings: influenceSettings
        )

        return CinematicNarrativeCueReadabilitySignals(plan: narrativeCuePlan)
    }

    private struct ModeAndReason {
        var mode: CinematicOverlayDisplayMode
        var reason: String
    }

    private struct DisplayValues {
        var visiblePills: [CinematicOverlayPill]
        var hudProminence: CinematicHUDProminence
        var gradientStrength: Double
        var worldTextMaxWidth: Double
        var hudMaxWidth: Double
        var pillLineLimit: Int
        var hudTitleLineLimit: Int
        var hudDetailLineLimit: Int
        var hudProfileLineLimit: Int
        var hudStatusLineLimit: Int
        var overlayOpacity: Double
    }

    private static func displayMode(
        phase: LoopPhase,
        isRunning: Bool,
        isAutoPlaying: Bool,
        hasRepository: Bool,
        copyAvailable: Bool,
        activityProfile: RepositoryActivityProfile,
        narrativeCueReadability: CinematicNarrativeCueReadabilitySignals
    ) -> ModeAndReason {
        guard hasRepository else {
            return ModeAndReason(mode: .fallback, reason: "missing-repository")
        }
        guard copyAvailable else {
            return ModeAndReason(mode: .fallback, reason: "missing-overlay-copy")
        }
        if phase == .paused {
            return ModeAndReason(mode: .full, reason: "paused")
        }
        if !activityProfile.isAvailable {
            return ModeAndReason(mode: .full, reason: "activity-unavailable")
        }
        if phase == .idle || phase == .cancelled {
            return ModeAndReason(mode: .full, reason: phase.rawValue.lowercased())
        }
        guard compactEligiblePhases.contains(phase) || isRunning || isAutoPlaying else {
            return ModeAndReason(mode: .full, reason: "steady-readable")
        }
        guard narrativeCueReadability.isReadable else {
            return ModeAndReason(mode: .fallback, reason: "low-narrative-readability")
        }
        return ModeAndReason(mode: .compact, reason: "in-world-readable-cues")
    }

    private static func displayValues(
        mode: CinematicOverlayDisplayMode,
        reasonIdentifier: String,
        phase: LoopPhase,
        influenceSettings: CinematicInfluenceSettings
    ) -> DisplayValues {
        switch mode {
        case .compact:
            return compactDisplayValues(phase: phase, influenceSettings: influenceSettings)
        case .full:
            return DisplayValues(
                visiblePills: [.quest, .arena, .activity],
                hudProminence: .full,
                gradientStrength: 0.52,
                worldTextMaxWidth: 430,
                hudMaxWidth: 620,
                pillLineLimit: 1,
                hudTitleLineLimit: 2,
                hudDetailLineLimit: 2,
                hudProfileLineLimit: 1,
                hudStatusLineLimit: 1,
                overlayOpacity: 1
            )
        case .fallback:
            return DisplayValues(
                visiblePills: [.quest, .arena, .activity],
                hudProminence: .full,
                gradientStrength: reasonIdentifier == "missing-repository" ? 0.54 : 0.58,
                worldTextMaxWidth: 430,
                hudMaxWidth: 620,
                pillLineLimit: 2,
                hudTitleLineLimit: 2,
                hudDetailLineLimit: 3,
                hudProfileLineLimit: 2,
                hudStatusLineLimit: 2,
                overlayOpacity: 1
            )
        }
    }

    private static func compactDisplayValues(
        phase: LoopPhase,
        influenceSettings: CinematicInfluenceSettings
    ) -> DisplayValues {
        let intensity = CinematicInfluenceSettings.clampedIntensity(influenceSettings.intensity)
        let styleBias: Double
        switch influenceSettings.cameraStyle {
        case .steady:
            styleBias = -0.02
        case .follow:
            styleBias = 0
        case .dramatic:
            styleBias = 0.025
        }
        let gradient = 0.22 + intensity * 0.045 + styleBias
        let terminalPhase = phase == .succeeded || phase == .failed

        return DisplayValues(
            visiblePills: compactPills(for: phase),
            hudProminence: terminalPhase || phase == .planning ? .compact : .minimal,
            gradientStrength: gradient,
            worldTextMaxWidth: phase == .planning ? 310 : 286,
            hudMaxWidth: terminalPhase ? 470 : 398,
            pillLineLimit: 1,
            hudTitleLineLimit: 1,
            hudDetailLineLimit: 1,
            hudProfileLineLimit: 1,
            hudStatusLineLimit: 1,
            overlayOpacity: 0.82
        )
    }

    private static func compactPills(for phase: LoopPhase) -> [CinematicOverlayPill] {
        switch phase {
        case .planning:
            return [.quest]
        case .developing, .verifying, .succeeded, .failed:
            return [.activity]
        case .idle, .paused, .cancelled:
            return [.activity]
        }
    }

    private static var compactEligiblePhases: [LoopPhase] {
        [.planning, .developing, .verifying, .succeeded, .failed]
    }

    private static func hasRenderableCopy(
        worldText: CinematicWorldText,
        briefing: CinematicBriefing
    ) -> Bool {
        [
            worldText.questLabel,
            worldText.arenaCallout,
            worldText.activityCallout,
            briefing.title,
            briefing.detail
        ]
        .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

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
    static let worldTextPillBackgroundOpacityRange: ClosedRange<Double> = 0.18...0.46
    static let worldTextPillStrokeOpacityRange: ClosedRange<Double> = 0.05...0.15
    static let worldTextPillHorizontalPaddingRange: ClosedRange<Double> = 7...11
    static let worldTextPillVerticalPaddingRange: ClosedRange<Double> = 4...7
    static let worldTextPillCornerRadiusRange: ClosedRange<Double> = 5...8
    static let worldTextPillIconEmphasisRange: ClosedRange<Double> = 0.72...1
    static let worldTextPillTextEmphasisRange: ClosedRange<Double> = 0.72...0.94
    static let hudBackgroundOpacityRange: ClosedRange<Double> = 0.20...0.48
    static let hudStrokeOpacityRange: ClosedRange<Double> = 0.05...0.16
    static let hudHorizontalPaddingRange: ClosedRange<Double> = 10...16
    static let hudVerticalPaddingRange: ClosedRange<Double> = 8...14
    static let hudCornerRadiusRange: ClosedRange<Double> = 6...9
    static let hudIconEmphasisRange: ClosedRange<Double> = 0.72...1
    static let hudTitleEmphasisRange: ClosedRange<Double> = 0.82...1
    static let hudDetailTextEmphasisRange: ClosedRange<Double> = 0.62...0.86
    static let hudStatusTextEmphasisRange: ClosedRange<Double> = 0.70...0.92
    static let hudPhaseBackgroundOpacityRange: ClosedRange<Double> = 0.07...0.16
    static let hudAccentOpacityRange: ClosedRange<Double> = 0.70...1

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
    var chromeStyleIdentifier: String
    var worldTextPillBackgroundOpacity: Double
    var worldTextPillStrokeOpacity: Double
    var worldTextPillHorizontalPadding: Double
    var worldTextPillVerticalPadding: Double
    var worldTextPillCornerRadius: Double
    var worldTextPillIconEmphasis: Double
    var worldTextPillTextEmphasis: Double
    var hudBackgroundOpacity: Double
    var hudStrokeOpacity: Double
    var hudHorizontalPadding: Double
    var hudVerticalPadding: Double
    var hudCornerRadius: Double
    var hudIconEmphasis: Double
    var hudTitleEmphasis: Double
    var hudDetailTextEmphasis: Double
    var hudStatusTextEmphasis: Double
    var hudPhaseBackgroundOpacity: Double
    var hudAccentOpacity: Double
    var reasonIdentifier: String
    var narrativeCueReadabilityIdentifier: String
    var nativeFeedbackCueIdentifier: String
    var nativeFeedbackLifecycleIdentifier: String
    var nativeFeedbackBannerPolicyIdentifier: String
    var showsNativeFeedbackBanner: Bool

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
        chromeStyleName: String,
        worldTextPillBackgroundOpacity: Double,
        worldTextPillStrokeOpacity: Double,
        worldTextPillHorizontalPadding: Double,
        worldTextPillVerticalPadding: Double,
        worldTextPillCornerRadius: Double,
        worldTextPillIconEmphasis: Double,
        worldTextPillTextEmphasis: Double,
        hudBackgroundOpacity: Double,
        hudStrokeOpacity: Double,
        hudHorizontalPadding: Double,
        hudVerticalPadding: Double,
        hudCornerRadius: Double,
        hudIconEmphasis: Double,
        hudTitleEmphasis: Double,
        hudDetailTextEmphasis: Double,
        hudStatusTextEmphasis: Double,
        hudPhaseBackgroundOpacity: Double,
        hudAccentOpacity: Double,
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
        influenceSettings: CinematicInfluenceSettings,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan? = nil,
        nativeFeedbackLifecycleIdentifier: String? = nil
    ) {
        let nativeFeedbackPolicy = Self.nativeFeedbackBannerPolicy(
            for: nativeFeedbackCue,
            influenceSettings: influenceSettings
        )
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
        self.worldTextPillBackgroundOpacity = Self.clamp(
            worldTextPillBackgroundOpacity,
            to: Self.worldTextPillBackgroundOpacityRange
        )
        self.worldTextPillStrokeOpacity = Self.clamp(
            worldTextPillStrokeOpacity,
            to: Self.worldTextPillStrokeOpacityRange
        )
        self.worldTextPillHorizontalPadding = Self.clamp(
            worldTextPillHorizontalPadding,
            to: Self.worldTextPillHorizontalPaddingRange
        )
        self.worldTextPillVerticalPadding = Self.clamp(
            worldTextPillVerticalPadding,
            to: Self.worldTextPillVerticalPaddingRange
        )
        self.worldTextPillCornerRadius = Self.clamp(
            worldTextPillCornerRadius,
            to: Self.worldTextPillCornerRadiusRange
        )
        self.worldTextPillIconEmphasis = Self.clamp(
            worldTextPillIconEmphasis,
            to: Self.worldTextPillIconEmphasisRange
        )
        self.worldTextPillTextEmphasis = Self.clamp(
            worldTextPillTextEmphasis,
            to: Self.worldTextPillTextEmphasisRange
        )
        self.hudBackgroundOpacity = Self.clamp(hudBackgroundOpacity, to: Self.hudBackgroundOpacityRange)
        self.hudStrokeOpacity = Self.clamp(hudStrokeOpacity, to: Self.hudStrokeOpacityRange)
        self.hudHorizontalPadding = Self.clamp(hudHorizontalPadding, to: Self.hudHorizontalPaddingRange)
        self.hudVerticalPadding = Self.clamp(hudVerticalPadding, to: Self.hudVerticalPaddingRange)
        self.hudCornerRadius = Self.clamp(hudCornerRadius, to: Self.hudCornerRadiusRange)
        self.hudIconEmphasis = Self.clamp(hudIconEmphasis, to: Self.hudIconEmphasisRange)
        self.hudTitleEmphasis = Self.clamp(hudTitleEmphasis, to: Self.hudTitleEmphasisRange)
        self.hudDetailTextEmphasis = Self.clamp(hudDetailTextEmphasis, to: Self.hudDetailTextEmphasisRange)
        self.hudStatusTextEmphasis = Self.clamp(hudStatusTextEmphasis, to: Self.hudStatusTextEmphasisRange)
        self.hudPhaseBackgroundOpacity = Self.clamp(
            hudPhaseBackgroundOpacity,
            to: Self.hudPhaseBackgroundOpacityRange
        )
        self.hudAccentOpacity = Self.clamp(hudAccentOpacity, to: Self.hudAccentOpacityRange)
        self.chromeStyleIdentifier = Self.makeChromeStyleIdentifier(
            styleName: chromeStyleName,
            worldTextPillBackgroundOpacity: self.worldTextPillBackgroundOpacity,
            worldTextPillStrokeOpacity: self.worldTextPillStrokeOpacity,
            worldTextPillHorizontalPadding: self.worldTextPillHorizontalPadding,
            worldTextPillVerticalPadding: self.worldTextPillVerticalPadding,
            worldTextPillCornerRadius: self.worldTextPillCornerRadius,
            worldTextPillIconEmphasis: self.worldTextPillIconEmphasis,
            worldTextPillTextEmphasis: self.worldTextPillTextEmphasis,
            hudBackgroundOpacity: self.hudBackgroundOpacity,
            hudStrokeOpacity: self.hudStrokeOpacity,
            hudHorizontalPadding: self.hudHorizontalPadding,
            hudVerticalPadding: self.hudVerticalPadding,
            hudCornerRadius: self.hudCornerRadius,
            hudIconEmphasis: self.hudIconEmphasis,
            hudTitleEmphasis: self.hudTitleEmphasis,
            hudDetailTextEmphasis: self.hudDetailTextEmphasis,
            hudStatusTextEmphasis: self.hudStatusTextEmphasis,
            hudPhaseBackgroundOpacity: self.hudPhaseBackgroundOpacity,
            hudAccentOpacity: self.hudAccentOpacity
        )
        self.reasonIdentifier = reasonIdentifier
        narrativeCueReadabilityIdentifier = narrativeCueReadability.identifier
        nativeFeedbackCueIdentifier = nativeFeedbackCue?.identifier ?? "none"
        self.nativeFeedbackLifecycleIdentifier = nativeFeedbackLifecycleIdentifier
            ?? nativeFeedbackCue?.lifecycleIdentifier
            ?? "none"
        nativeFeedbackBannerPolicyIdentifier = nativeFeedbackPolicy.identifier
        showsNativeFeedbackBanner = nativeFeedbackPolicy.showsBanner
        identifier = [
            "mode:\(mode.rawValue)",
            "comfort:\(influenceSettings.comfortMode.rawValue)",
            "reason:\(reasonIdentifier)",
            "pills:\(self.visiblePills.map(\.rawValue).joined(separator: ","))",
            "hud:\(hudProminence.rawValue)",
            "chrome:\(self.chromeStyleIdentifier)",
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
            "influence:\(influenceSettings.cameraStyle.rawValue)|\(Self.fixed(influenceSettings.intensity))|\(influenceSettings.comfortMode.rawValue)",
            "world:\(Self.copyIdentifier(worldText.questLabel, worldText.arenaCallout, worldText.activityCallout))",
            "briefing:\(Self.copyIdentifier(briefing.title, briefing.detail))",
            "readability:\(narrativeCueReadability.identifier)",
            "native:\(nativeFeedbackCueIdentifier)",
            "native-lifecycle:\(self.nativeFeedbackLifecycleIdentifier)",
            "native-banner:\(nativeFeedbackBannerPolicyIdentifier)"
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

    private static func makeChromeStyleIdentifier(
        styleName: String,
        worldTextPillBackgroundOpacity: Double,
        worldTextPillStrokeOpacity: Double,
        worldTextPillHorizontalPadding: Double,
        worldTextPillVerticalPadding: Double,
        worldTextPillCornerRadius: Double,
        worldTextPillIconEmphasis: Double,
        worldTextPillTextEmphasis: Double,
        hudBackgroundOpacity: Double,
        hudStrokeOpacity: Double,
        hudHorizontalPadding: Double,
        hudVerticalPadding: Double,
        hudCornerRadius: Double,
        hudIconEmphasis: Double,
        hudTitleEmphasis: Double,
        hudDetailTextEmphasis: Double,
        hudStatusTextEmphasis: Double,
        hudPhaseBackgroundOpacity: Double,
        hudAccentOpacity: Double
    ) -> String {
        let name = styleName.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            name.isEmpty ? "unnamed" : name,
            "pill:bg\(fixed(worldTextPillBackgroundOpacity)):stroke\(fixed(worldTextPillStrokeOpacity)):pad\(fixed(worldTextPillHorizontalPadding))x\(fixed(worldTextPillVerticalPadding)):radius\(fixed(worldTextPillCornerRadius)):icon\(fixed(worldTextPillIconEmphasis)):text\(fixed(worldTextPillTextEmphasis))",
            "hud:bg\(fixed(hudBackgroundOpacity)):stroke\(fixed(hudStrokeOpacity)):pad\(fixed(hudHorizontalPadding))x\(fixed(hudVerticalPadding)):radius\(fixed(hudCornerRadius)):icon\(fixed(hudIconEmphasis)):title\(fixed(hudTitleEmphasis)):detail\(fixed(hudDetailTextEmphasis)):status\(fixed(hudStatusTextEmphasis)):phase\(fixed(hudPhaseBackgroundOpacity)):accent\(fixed(hudAccentOpacity))"
        ].joined(separator: "|")
    }

    private struct NativeFeedbackBannerPolicy {
        var identifier: String
        var showsBanner: Bool
    }

    private static func nativeFeedbackBannerPolicy(
        for cue: CinematicNativeFeedbackCuePlan?,
        influenceSettings: CinematicInfluenceSettings
    ) -> NativeFeedbackBannerPolicy {
        guard let cue else {
            return NativeFeedbackBannerPolicy(identifier: "none", showsBanner: false)
        }

        if influenceSettings.comfortMode == .quiet && !cue.isCriticalCinematicBanner {
            return NativeFeedbackBannerPolicy(identifier: "suppressed-quiet-noncritical", showsBanner: false)
        }

        return NativeFeedbackBannerPolicy(identifier: "visible", showsBanner: true)
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
        narrativeCueReadability: CinematicNarrativeCueReadabilitySignals,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan? = nil,
        nativeFeedbackLifecycleIdentifier: String? = nil
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
            chromeStyleName: values.chromeStyle.styleName,
            worldTextPillBackgroundOpacity: values.chromeStyle.worldTextPillBackgroundOpacity,
            worldTextPillStrokeOpacity: values.chromeStyle.worldTextPillStrokeOpacity,
            worldTextPillHorizontalPadding: values.chromeStyle.worldTextPillHorizontalPadding,
            worldTextPillVerticalPadding: values.chromeStyle.worldTextPillVerticalPadding,
            worldTextPillCornerRadius: values.chromeStyle.worldTextPillCornerRadius,
            worldTextPillIconEmphasis: values.chromeStyle.worldTextPillIconEmphasis,
            worldTextPillTextEmphasis: values.chromeStyle.worldTextPillTextEmphasis,
            hudBackgroundOpacity: values.chromeStyle.hudBackgroundOpacity,
            hudStrokeOpacity: values.chromeStyle.hudStrokeOpacity,
            hudHorizontalPadding: values.chromeStyle.hudHorizontalPadding,
            hudVerticalPadding: values.chromeStyle.hudVerticalPadding,
            hudCornerRadius: values.chromeStyle.hudCornerRadius,
            hudIconEmphasis: values.chromeStyle.hudIconEmphasis,
            hudTitleEmphasis: values.chromeStyle.hudTitleEmphasis,
            hudDetailTextEmphasis: values.chromeStyle.hudDetailTextEmphasis,
            hudStatusTextEmphasis: values.chromeStyle.hudStatusTextEmphasis,
            hudPhaseBackgroundOpacity: values.chromeStyle.hudPhaseBackgroundOpacity,
            hudAccentOpacity: values.chromeStyle.hudAccentOpacity,
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
            influenceSettings: influenceSettings,
            nativeFeedbackCue: nativeFeedbackCue,
            nativeFeedbackLifecycleIdentifier: nativeFeedbackLifecycleIdentifier
        )
    }

    static func narrativeCueReadabilitySignals(
        phase: LoopPhase,
        worldText: CinematicWorldText,
        briefing: CinematicBriefing,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan? = nil
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
            influenceSettings: influenceSettings,
            nativeFeedbackCue: nativeFeedbackCue
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
        var chromeStyle: ChromeStyleValues
    }

    private struct ChromeStyleValues {
        var styleName: String
        var worldTextPillBackgroundOpacity: Double
        var worldTextPillStrokeOpacity: Double
        var worldTextPillHorizontalPadding: Double
        var worldTextPillVerticalPadding: Double
        var worldTextPillCornerRadius: Double
        var worldTextPillIconEmphasis: Double
        var worldTextPillTextEmphasis: Double
        var hudBackgroundOpacity: Double
        var hudStrokeOpacity: Double
        var hudHorizontalPadding: Double
        var hudVerticalPadding: Double
        var hudCornerRadius: Double
        var hudIconEmphasis: Double
        var hudTitleEmphasis: Double
        var hudDetailTextEmphasis: Double
        var hudStatusTextEmphasis: Double
        var hudPhaseBackgroundOpacity: Double
        var hudAccentOpacity: Double
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
        let values: DisplayValues
        switch mode {
        case .compact:
            values = compactDisplayValues(phase: phase, influenceSettings: influenceSettings)
        case .full:
            values = DisplayValues(
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
                overlayOpacity: 1,
                chromeStyle: fullChromeStyle()
            )
        case .fallback:
            values = DisplayValues(
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
                overlayOpacity: 1,
                chromeStyle: fallbackChromeStyle()
            )
        }
        return comfortAdjustedDisplayValues(values, phase: phase, influenceSettings: influenceSettings)
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
            overlayOpacity: terminalPhase || phase == .planning ? 0.9 : 0.82,
            chromeStyle: compactChromeStyle(phase: phase)
        )
    }

    private static func compactChromeStyle(phase: LoopPhase) -> ChromeStyleValues {
        if phase == .planning || phase == .succeeded || phase == .failed {
            return ChromeStyleValues(
                styleName: "compact-readable",
                worldTextPillBackgroundOpacity: 0.28,
                worldTextPillStrokeOpacity: 0.08,
                worldTextPillHorizontalPadding: 9,
                worldTextPillVerticalPadding: 5,
                worldTextPillCornerRadius: 7,
                worldTextPillIconEmphasis: 0.9,
                worldTextPillTextEmphasis: 0.84,
                hudBackgroundOpacity: 0.30,
                hudStrokeOpacity: 0.08,
                hudHorizontalPadding: 12,
                hudVerticalPadding: 9,
                hudCornerRadius: 7,
                hudIconEmphasis: 0.9,
                hudTitleEmphasis: 0.93,
                hudDetailTextEmphasis: 0.72,
                hudStatusTextEmphasis: 0.8,
                hudPhaseBackgroundOpacity: 0.10,
                hudAccentOpacity: 0.82
            )
        }

        return ChromeStyleValues(
            styleName: "compact-active",
            worldTextPillBackgroundOpacity: 0.24,
            worldTextPillStrokeOpacity: 0.06,
            worldTextPillHorizontalPadding: 8,
            worldTextPillVerticalPadding: 4,
            worldTextPillCornerRadius: 6,
            worldTextPillIconEmphasis: 0.84,
            worldTextPillTextEmphasis: 0.76,
            hudBackgroundOpacity: 0.25,
            hudStrokeOpacity: 0.06,
            hudHorizontalPadding: 11,
            hudVerticalPadding: 8,
            hudCornerRadius: 7,
            hudIconEmphasis: 0.84,
            hudTitleEmphasis: 0.88,
            hudDetailTextEmphasis: 0.65,
            hudStatusTextEmphasis: 0.74,
            hudPhaseBackgroundOpacity: 0.08,
            hudAccentOpacity: 0.76
        )
    }

    private static func fullChromeStyle() -> ChromeStyleValues {
        ChromeStyleValues(
            styleName: "full-readable",
            worldTextPillBackgroundOpacity: 0.36,
            worldTextPillStrokeOpacity: 0.10,
            worldTextPillHorizontalPadding: 9,
            worldTextPillVerticalPadding: 6,
            worldTextPillCornerRadius: 7,
            worldTextPillIconEmphasis: 0.96,
            worldTextPillTextEmphasis: 0.88,
            hudBackgroundOpacity: 0.38,
            hudStrokeOpacity: 0.11,
            hudHorizontalPadding: 14,
            hudVerticalPadding: 12,
            hudCornerRadius: 8,
            hudIconEmphasis: 0.98,
            hudTitleEmphasis: 1,
            hudDetailTextEmphasis: 0.78,
            hudStatusTextEmphasis: 0.86,
            hudPhaseBackgroundOpacity: 0.12,
            hudAccentOpacity: 1
        )
    }

    private static func fallbackChromeStyle() -> ChromeStyleValues {
        ChromeStyleValues(
            styleName: "fallback-readable",
            worldTextPillBackgroundOpacity: 0.44,
            worldTextPillStrokeOpacity: 0.14,
            worldTextPillHorizontalPadding: 10,
            worldTextPillVerticalPadding: 7,
            worldTextPillCornerRadius: 8,
            worldTextPillIconEmphasis: 1,
            worldTextPillTextEmphasis: 0.92,
            hudBackgroundOpacity: 0.46,
            hudStrokeOpacity: 0.15,
            hudHorizontalPadding: 15,
            hudVerticalPadding: 13,
            hudCornerRadius: 8,
            hudIconEmphasis: 1,
            hudTitleEmphasis: 1,
            hudDetailTextEmphasis: 0.84,
            hudStatusTextEmphasis: 0.9,
            hudPhaseBackgroundOpacity: 0.15,
            hudAccentOpacity: 1
        )
    }

    private static func comfortAdjustedDisplayValues(
        _ values: DisplayValues,
        phase: LoopPhase,
        influenceSettings: CinematicInfluenceSettings
    ) -> DisplayValues {
        switch influenceSettings.comfortMode {
        case .standard:
            return values
        case .reducedMotion:
            return adjustedDisplayValues(
                values,
                suffix: "reduced-motion",
                gradientScale: 0.86,
                widthScale: 0.94,
                overlayScale: 0.94,
                chromeScale: 0.90,
                emphasisScale: 0.96,
                phase: phase
            )
        case .quiet:
            return adjustedDisplayValues(
                values,
                suffix: "quiet",
                gradientScale: 0.72,
                widthScale: 0.90,
                overlayScale: 0.86,
                chromeScale: 0.78,
                emphasisScale: 0.90,
                phase: phase
            )
        }
    }

    private static func adjustedDisplayValues(
        _ values: DisplayValues,
        suffix: String,
        gradientScale: Double,
        widthScale: Double,
        overlayScale: Double,
        chromeScale: Double,
        emphasisScale: Double,
        phase: LoopPhase
    ) -> DisplayValues {
        let terminalPhase = phase == .failed || phase == .succeeded
        let hudProminence: CinematicHUDProminence
        if suffix == "quiet", values.hudProminence == .full, !terminalPhase, phase != .paused {
            hudProminence = .compact
        } else {
            hudProminence = values.hudProminence
        }

        return DisplayValues(
            visiblePills: values.visiblePills,
            hudProminence: hudProminence,
            gradientStrength: values.gradientStrength * gradientScale,
            worldTextMaxWidth: values.worldTextMaxWidth * widthScale,
            hudMaxWidth: values.hudMaxWidth * widthScale,
            pillLineLimit: values.pillLineLimit,
            hudTitleLineLimit: values.hudTitleLineLimit,
            hudDetailLineLimit: values.hudDetailLineLimit,
            hudProfileLineLimit: values.hudProfileLineLimit,
            hudStatusLineLimit: values.hudStatusLineLimit,
            overlayOpacity: values.overlayOpacity * overlayScale,
            chromeStyle: adjustedChromeStyle(
                values.chromeStyle,
                suffix: suffix,
                chromeScale: chromeScale,
                emphasisScale: emphasisScale
            )
        )
    }

    private static func adjustedChromeStyle(
        _ style: ChromeStyleValues,
        suffix: String,
        chromeScale: Double,
        emphasisScale: Double
    ) -> ChromeStyleValues {
        ChromeStyleValues(
            styleName: "\(style.styleName)-\(suffix)",
            worldTextPillBackgroundOpacity: style.worldTextPillBackgroundOpacity * chromeScale,
            worldTextPillStrokeOpacity: style.worldTextPillStrokeOpacity * chromeScale,
            worldTextPillHorizontalPadding: style.worldTextPillHorizontalPadding,
            worldTextPillVerticalPadding: style.worldTextPillVerticalPadding,
            worldTextPillCornerRadius: style.worldTextPillCornerRadius,
            worldTextPillIconEmphasis: style.worldTextPillIconEmphasis * emphasisScale,
            worldTextPillTextEmphasis: style.worldTextPillTextEmphasis * emphasisScale,
            hudBackgroundOpacity: style.hudBackgroundOpacity * chromeScale,
            hudStrokeOpacity: style.hudStrokeOpacity * chromeScale,
            hudHorizontalPadding: style.hudHorizontalPadding,
            hudVerticalPadding: style.hudVerticalPadding,
            hudCornerRadius: style.hudCornerRadius,
            hudIconEmphasis: style.hudIconEmphasis * emphasisScale,
            hudTitleEmphasis: style.hudTitleEmphasis * emphasisScale,
            hudDetailTextEmphasis: style.hudDetailTextEmphasis * emphasisScale,
            hudStatusTextEmphasis: style.hudStatusTextEmphasis * emphasisScale,
            hudPhaseBackgroundOpacity: style.hudPhaseBackgroundOpacity * chromeScale,
            hudAccentOpacity: style.hudAccentOpacity * emphasisScale
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

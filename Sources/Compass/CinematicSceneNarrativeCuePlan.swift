import Foundation

enum CinematicNarrativeCueAnchor: String, CaseIterable, Equatable {
    case idleArchive = "idle-archive"
    case leftScoutPylon = "left-scout-pylon"
    case leftForgePylon = "left-forge-pylon"
    case leftSealPylon = "left-seal-pylon"
    case fractureGate = "fracture-gate"
    case victoryArch = "victory-arch"
    case arenaCenter = "arena-center"
    case arenaFront = "arena-front"
    case arenaRear = "arena-rear"
    case rightPylon = "right-pylon"
    case rightHistoryPylon = "right-history-pylon"
    case rightWarningPylon = "right-warning-pylon"
}

enum CinematicNarrativeCueVisibility: String, CaseIterable, Equatable {
    case dim
    case visible
    case featured
}

struct CinematicSceneNarrativeCuePlan: Equatable {
    static let cueScaleRange: ClosedRange<Float> = 0.58...1.34
    static let cueOpacityRange: ClosedRange<Float> = 0.18...0.92
    static let cueCadenceRange: ClosedRange<TimeInterval> = 1.35...6.4

    var identifier: String
    var stageBeatIdentifier: String
    var stagePhasePolishIdentifier: String
    var languageIdentifier: String
    var activityIdentifier: String
    var influenceIdentifier: String
    var questPlaque: CueDescriptor
    var arenaInscription: CueDescriptor
    var activityBanner: CueDescriptor

    struct CueDescriptor: Equatable {
        var stableID: String
        var text: String
        var secondaryText: String?
        var glyphIdentifier: String?
        var anchor: CinematicNarrativeCueAnchor
        var visibility: CinematicNarrativeCueVisibility
        var scale: Float
        var opacity: Float
        var lightFamily: CinematicStageLightFamily
        var tintFamily: CinematicStageLightFamily
        var cadence: TimeInterval

        var anchorIdentifier: String { anchor.rawValue }
        var visibilityIdentifier: String { visibility.rawValue }
        var lightFamilyIdentifier: String { lightFamily.rawValue }
        var tintFamilyIdentifier: String { tintFamily.rawValue }

        var identifier: String {
            [
                stableID,
                text,
                secondaryText ?? "none",
                glyphIdentifier ?? "none",
                anchor.rawValue,
                visibility.rawValue,
                "scale\(CinematicSceneNarrativeCuePlanner.fixed(scale))",
                "opacity\(CinematicSceneNarrativeCuePlanner.fixed(opacity))",
                "light\(lightFamily.rawValue)",
                "tint\(tintFamily.rawValue)",
                "cadence\(CinematicSceneNarrativeCuePlanner.fixed(cadence))"
            ].joined(separator: "|")
        }
    }
}

enum CinematicSceneNarrativeCuePlanner {
    static func plan(
        worldText: CinematicWorldText,
        briefing: CinematicBriefing,
        stageBeat: CinematicStageBeat,
        stagePhasePolishPlan: CinematicStagePhasePolishPlan,
        languageMotif: CinematicLanguageMotif,
        activityMotif: CinematicActivityMotif,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicSceneNarrativeCuePlan {
        let isIdleUnavailable = stageBeat.kind == .idle && activityMotif.eventKind == .unavailable
        let boundedWorldText = isIdleUnavailable ? CinematicWorldText.placeholder : worldText
        let boundedBriefing = isIdleUnavailable ? CinematicBriefing.placeholder : briefing
        let influenceIntensity = Float(CinematicInfluenceSettings.clampedIntensity(influenceSettings.intensity))
        let influenceFraction = influenceFraction(for: influenceSettings)
        let phaseEnergy = energy(
            stageBeat: stageBeat,
            phasePolish: stagePhasePolishPlan,
            activityMotif: activityMotif,
            isIdleUnavailable: isIdleUnavailable
        )
        let visibility = visibility(
            stageBeat: stageBeat,
            activityMotif: activityMotif,
            isIdleUnavailable: isIdleUnavailable
        )
        let questText = boundedWorldTextValue(
            boundedWorldText.questLabel,
            maxCharacters: CinematicWorldTextService.questLabelMaxCharacters,
            maxWords: CinematicWorldTextService.questLabelMaxWords,
            fallback: CinematicWorldText.placeholder.questLabel
        )
        let questSecondary = boundedBriefingTextValue(
            boundedBriefing.title,
            maxCharacters: CinematicBriefingService.titleMaxCharacters,
            fallback: CinematicBriefing.placeholder.title
        )
        let arenaText = boundedWorldTextValue(
            boundedWorldText.arenaCallout,
            maxCharacters: CinematicWorldTextService.arenaCalloutMaxCharacters,
            maxWords: CinematicWorldTextService.arenaCalloutMaxWords,
            fallback: CinematicWorldText.placeholder.arenaCallout
        )
        let activityText = boundedWorldTextValue(
            boundedWorldText.activityCallout,
            maxCharacters: CinematicWorldTextService.activityCalloutMaxCharacters,
            maxWords: CinematicWorldTextService.activityCalloutMaxWords,
            fallback: CinematicWorldText.placeholder.activityCallout
        )
        let questDescriptor = cueDescriptor(
            stableID: "narrative.quest.plaque",
            text: questText,
            secondaryText: questSecondary == questText ? nil : questSecondary,
            glyphIdentifier: languageMotif.sigilIdentifier,
            anchor: questAnchor(for: stageBeat, isIdleUnavailable: isIdleUnavailable),
            visibility: visibility,
            baseLightFamily: stagePhasePolishPlan.staffOrb.lightFamily,
            tintFamily: stageBeat.lightFamily,
            phaseEnergy: phaseEnergy,
            influenceIntensity: influenceIntensity,
            influenceFraction: influenceFraction,
            isIdleUnavailable: isIdleUnavailable
        )
        let arenaDescriptor = cueDescriptor(
            stableID: "narrative.arena.inscription",
            text: arenaText,
            secondaryText: nil,
            glyphIdentifier: stageBeat.arenaEffect.rawValue,
            anchor: arenaAnchor(for: stageBeat, isIdleUnavailable: isIdleUnavailable),
            visibility: visibility,
            baseLightFamily: stageBeat.lightFamily,
            tintFamily: stagePhasePolishPlan.portalBackdrop.lightFamily,
            phaseEnergy: phaseEnergy * 0.88,
            influenceIntensity: influenceIntensity,
            influenceFraction: influenceFraction,
            isIdleUnavailable: isIdleUnavailable
        )
        let activityDescriptor = cueDescriptor(
            stableID: "narrative.activity.banner",
            text: activityText,
            secondaryText: nil,
            glyphIdentifier: activityMotif.sigilIdentifier,
            anchor: activityAnchor(for: activityMotif, isIdleUnavailable: isIdleUnavailable),
            visibility: visibility,
            baseLightFamily: activityLightFamily(stageBeat: stageBeat, activityMotif: activityMotif),
            tintFamily: stagePhasePolishPlan.fractureRecovery.lightFamily,
            phaseEnergy: phaseEnergy + activityUrgency(for: activityMotif.eventKind) * 0.1,
            influenceIntensity: influenceIntensity,
            influenceFraction: influenceFraction,
            isIdleUnavailable: isIdleUnavailable
        )
        let influenceIdentifier = [
            influenceSettings.cameraStyle.rawValue,
            fixed(influenceIntensity),
            fixed(influenceFraction)
        ].joined(separator: "|")
        let identifier = [
            "beat:\(stageBeat.identifier)",
            "phase-polish:\(stagePhasePolishPlan.identifier)",
            "language:\(languageMotif.sigilIdentifier)",
            "activity:\(activityMotif.sigilIdentifier)",
            "quest:\(questDescriptor.identifier)",
            "arena:\(arenaDescriptor.identifier)",
            "banner:\(activityDescriptor.identifier)",
            "influence:\(influenceIdentifier)"
        ].joined(separator: "||")

        return CinematicSceneNarrativeCuePlan(
            identifier: identifier,
            stageBeatIdentifier: stageBeat.identifier,
            stagePhasePolishIdentifier: stagePhasePolishPlan.identifier,
            languageIdentifier: languageMotif.sigilIdentifier,
            activityIdentifier: activityMotif.sigilIdentifier,
            influenceIdentifier: influenceIdentifier,
            questPlaque: questDescriptor,
            arenaInscription: arenaDescriptor,
            activityBanner: activityDescriptor
        )
    }

    static func fixed(_ value: Float) -> String {
        String(format: "%.4f", Double(value))
    }

    static func fixed(_ value: TimeInterval) -> String {
        String(format: "%.4f", value)
    }

    private static func cueDescriptor(
        stableID: String,
        text: String,
        secondaryText: String?,
        glyphIdentifier: String?,
        anchor: CinematicNarrativeCueAnchor,
        visibility: CinematicNarrativeCueVisibility,
        baseLightFamily: CinematicStageLightFamily,
        tintFamily: CinematicStageLightFamily,
        phaseEnergy: Float,
        influenceIntensity: Float,
        influenceFraction: Float,
        isIdleUnavailable: Bool
    ) -> CinematicSceneNarrativeCuePlan.CueDescriptor {
        let visibilityBoost: Float
        switch visibility {
        case .dim:
            visibilityBoost = 0
        case .visible:
            visibilityBoost = 0.12
        case .featured:
            visibilityBoost = 0.22
        }
        let scale = isIdleUnavailable
            ? CinematicSceneNarrativeCuePlan.cueScaleRange.lowerBound
            : clamp(
                0.78 + phaseEnergy * 0.22 + influenceFraction * 0.12 + visibilityBoost,
                to: CinematicSceneNarrativeCuePlan.cueScaleRange
            )
        let opacity = isIdleUnavailable
            ? 0.24
            : clamp(
                0.42 + phaseEnergy * 0.28 + influenceFraction * 0.08 + visibilityBoost,
                to: CinematicSceneNarrativeCuePlan.cueOpacityRange
            )
        let cadence = isIdleUnavailable
            ? CinematicSceneNarrativeCuePlan.cueCadenceRange.upperBound
            : clamp(
                4.8 - TimeInterval(phaseEnergy * 1.4 + influenceIntensity * 0.75 + visibilityBoost),
                to: CinematicSceneNarrativeCuePlan.cueCadenceRange
            )

        return CinematicSceneNarrativeCuePlan.CueDescriptor(
            stableID: stableID,
            text: text,
            secondaryText: secondaryText,
            glyphIdentifier: glyphIdentifier,
            anchor: anchor,
            visibility: visibility,
            scale: scale,
            opacity: opacity,
            lightFamily: isIdleUnavailable ? .lifecycle : baseLightFamily,
            tintFamily: isIdleUnavailable ? .lifecycle : tintFamily,
            cadence: cadence
        )
    }

    private static func questAnchor(
        for beat: CinematicStageBeat,
        isIdleUnavailable: Bool
    ) -> CinematicNarrativeCueAnchor {
        guard !isIdleUnavailable else { return .idleArchive }
        switch beat.kind {
        case .planning:
            return .leftScoutPylon
        case .developing:
            return .leftForgePylon
        case .verifying:
            return .leftSealPylon
        case .succeeded:
            return .victoryArch
        case .failed:
            return .fractureGate
        case .idle, .paused, .cancelled:
            return .idleArchive
        }
    }

    private static func arenaAnchor(
        for beat: CinematicStageBeat,
        isIdleUnavailable: Bool
    ) -> CinematicNarrativeCueAnchor {
        guard !isIdleUnavailable else { return .arenaCenter }
        switch beat.arenaEffect {
        case .charge, .activityPulse, .historyChains:
            return .arenaFront
        case .seal, .victory:
            return .arenaRear
        case .none:
            return .arenaCenter
        }
    }

    private static func activityAnchor(
        for motif: CinematicActivityMotif,
        isIdleUnavailable: Bool
    ) -> CinematicNarrativeCueAnchor {
        guard !isIdleUnavailable else { return .idleArchive }
        switch motif.eventKind {
        case .commit, .success, .recovery:
            return .rightHistoryPylon
        case .dirty, .conflicted, .failure:
            return .rightWarningPylon
        case .clean, .unavailable:
            return .rightPylon
        }
    }

    private static func visibility(
        stageBeat: CinematicStageBeat,
        activityMotif: CinematicActivityMotif,
        isIdleUnavailable: Bool
    ) -> CinematicNarrativeCueVisibility {
        if isIdleUnavailable {
            return .dim
        }
        switch (stageBeat.kind, activityMotif.eventKind) {
        case (.succeeded, _), (.failed, _), (_, .conflicted), (_, .failure), (_, .success), (_, .recovery):
            return .featured
        default:
            return .visible
        }
    }

    private static func activityLightFamily(
        stageBeat: CinematicStageBeat,
        activityMotif: CinematicActivityMotif
    ) -> CinematicStageLightFamily {
        if let accent = stageBeat.activityAccent {
            return accent.lightFamily
        }
        switch activityMotif.eventKind {
        case .unavailable, .clean:
            return .lifecycle
        case .dirty:
            return .pressure
        case .conflicted, .failure:
            return .failure
        case .commit:
            return .git
        case .success, .recovery:
            return .verify
        }
    }

    private static func energy(
        stageBeat: CinematicStageBeat,
        phasePolish: CinematicStagePhasePolishPlan,
        activityMotif: CinematicActivityMotif,
        isIdleUnavailable: Bool
    ) -> Float {
        guard !isIdleUnavailable else { return 0 }
        let phaseBase: Float
        switch stageBeat.kind {
        case .idle, .paused, .cancelled:
            phaseBase = 0.08
        case .planning:
            phaseBase = 0.24
        case .developing:
            phaseBase = 0.48
        case .verifying:
            phaseBase = 0.58
        case .succeeded:
            phaseBase = 0.78
        case .failed:
            phaseBase = 0.9
        }

        return clamp(
            phaseBase * 0.34
                + phasePolish.wizardPose.poseIntensity * 0.22
                + phasePolish.staffOrb.emission * 0.18
                + phasePolish.portalBackdrop.portalAperture * 0.1
                + phasePolish.fractureRecovery.fractureOpacity * 0.08
                + phasePolish.fractureRecovery.healingOpacity * 0.08
                + activityUrgency(for: activityMotif.eventKind) * 0.12,
            to: 0...1
        )
    }

    private static func activityUrgency(for eventKind: CinematicActivityEventKind) -> Float {
        switch eventKind {
        case .unavailable:
            return 0
        case .clean:
            return 0.08
        case .commit:
            return 0.24
        case .success:
            return 0.36
        case .recovery:
            return 0.48
        case .dirty:
            return 0.58
        case .conflicted:
            return 0.86
        case .failure:
            return 0.92
        }
    }

    private static func influenceFraction(for settings: CinematicInfluenceSettings) -> Float {
        let clamped = Float(CinematicInfluenceSettings.clampedIntensity(settings.intensity))
        let styleBias: Float
        switch settings.cameraStyle {
        case .steady:
            styleBias = -0.12
        case .follow:
            styleBias = 0
        case .dramatic:
            styleBias = 0.14
        }
        return clamp(0.48 + clamped * 0.38 + styleBias, to: 0...1)
    }

    private static func boundedWorldTextValue(
        _ text: String,
        maxCharacters: Int,
        maxWords: Int,
        fallback: String
    ) -> String {
        boundedTextValue(
            text,
            maxCharacters: maxCharacters,
            maxWords: maxWords,
            fallback: fallback
        )
    }

    private static func boundedBriefingTextValue(
        _ text: String,
        maxCharacters: Int,
        fallback: String
    ) -> String {
        boundedTextValue(
            text,
            maxCharacters: maxCharacters,
            maxWords: nil,
            fallback: fallback
        )
    }

    private static func boundedTextValue(
        _ text: String,
        maxCharacters: Int,
        maxWords: Int?,
        fallback: String
    ) -> String {
        let clean = safeDisplayText(text)
        let source = clean.isEmpty ? fallback : clean
        let wordLimited = limitWords(source, maxWords: maxWords)
        let fitted = CinematicBriefingService.fittedPlainText(wordLimited, maxCharacters: maxCharacters)
        return fitted.isEmpty ? fallback : fitted
    }

    private static func safeDisplayText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutURLs = normalized
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"www\.\S+"#, with: "", options: .regularExpression)
        let filtered = withoutURLs.reduce(into: "") { partial, character in
            if !"`{}[]#*_\"".contains(character) {
                partial.append(character)
            }
        }
        return filtered
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :;,.|- \n\t"))
    }

    private static func limitWords(_ text: String, maxWords: Int?) -> String {
        guard let maxWords, maxWords > 0 else { return text }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > maxWords else { return text }
        return words.prefix(maxWords).joined(separator: " ")
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: TimeInterval, to range: ClosedRange<TimeInterval>) -> TimeInterval {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

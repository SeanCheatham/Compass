import Foundation

struct CinematicSetDressingPlan: Equatable {
    static let pedestalCountRange = 3...6
    static let shardCountRange = 4...9
    static let flameLightIntensityRange: ClosedRange<Float> = 120...360
    static let flameOpacityRange: ClosedRange<Float> = 0.68...0.96
    static let flameScaleRange: ClosedRange<Float> = 0.58...1.08
    static let flameHeightScaleRange: ClosedRange<Float> = 1.18...1.68
    static let rimOpacityRange: ClosedRange<Float> = 0.42...0.82
    static let shardEmissionOpacityRange: ClosedRange<Float> = 0.14...0.56
    static let shardOpacityRange: ClosedRange<Float> = 0.46...0.86
    static let runeIntensityRange: ClosedRange<Float> = 0.55...1.35
    static let segmentRadiusScaleRange: ClosedRange<Float> = 0.82...1.34
    static let sigilCoreScaleRange: ClosedRange<Float> = 0.72...1.28
    static let flamePulseRateRange: ClosedRange<Float> = 2.8...6.2
    static let flamePulseAmplitudeRange: ClosedRange<Float> = 0.06...0.2
    static let shardBobRateRange: ClosedRange<Float> = 0.72...1.85
    static let shardBobAmplitudeRange: ClosedRange<Float> = 0.04...0.16
    static let shardRotationStepRange: ClosedRange<Float> = 0.003...0.018
    static let activityTintBlendRange: ClosedRange<Float> = 0...0.42

    var identifier: String
    var languageArchitecture: LanguageArchitecture
    var activityMarker: ActivityMarker
    var pedestalFlames: PedestalFlameAccents
    var floatingShards: FloatingShardIntensity
    var runeIntensity: RuneIntensity
    var animationCadence: AnimationCadence
    var materialTextureVariants: MaterialTextureVariants
    var ambientSpawnCadence: TimeInterval
    var ambientEnemyLimit: Int
    var activityLightBoost: Float

    struct LanguageArchitecture: Equatable {
        var identifier: String
        var languageIdentifier: String
        var sigilIdentifier: String
        var styleIdentifier: String
        var architectureIdentifier: String
        var pedestalLayoutIdentifier: String
        var shardFormationIdentifier: String
    }

    struct ActivityMarker: Equatable {
        var identifier: String
        var eventKindIdentifier: String
        var pressureLevelIdentifier: String
        var sigilIdentifier: String
        var styleIdentifier: String
        var tintSourceIdentifier: String?
        var transitionSpellIdentifier: String?
        var ambientOverrideIdentifier: String?
        var ambientSpellIdentifier: String
        var usesCommitAmbient: Bool
        var usesSuccessAmbient: Bool
        var shouldShakeOnTransition: Bool
    }

    struct PedestalFlameAccents: Equatable {
        var identifier: String
        var pedestalCount: Int
        var flameLightIntensity: Float
        var flameOpacity: Float
        var rimOpacity: Float
        var flameXZScale: Float
        var flameHeightScale: Float
        var activityTintFraction: Float
        var materialVariantIdentifier: String
    }

    struct FloatingShardIntensity: Equatable {
        var identifier: String
        var shardCount: Int
        var opacity: Float
        var emissionOpacity: Float
        var scale: Float
        var activityTintFraction: Float
        var materialVariantIdentifier: String
    }

    struct RuneIntensity: Equatable {
        var identifier: String
        var languageBaseRadius: Float
        var activityBaseRadius: Float
        var segmentRadiusScale: Float
        var segmentOpacityScale: Float
        var coreScale: Float
        var activityPulseScale: Float
    }

    struct AnimationCadence: Equatable {
        var identifier: String
        var flamePulseRate: Float
        var flamePulseAmplitude: Float
        var shardBobRate: Float
        var shardBobAmplitude: Float
        var shardRotationStep: Float
        var activityPulseDuration: TimeInterval
    }

    struct MaterialTextureVariants: Equatable {
        var identifier: String
        var backdropTextureAsset: CinematicTextureAsset
        var arenaTextureAsset: CinematicTextureAsset
        var pedestalMaterialIdentifier: String
        var flameMaterialIdentifier: String
        var shardMaterialIdentifier: String
        var runeMaterialIdentifier: String

        var backdropTextureName: String {
            backdropTextureAsset.textureName
        }

        var arenaTextureName: String {
            arenaTextureAsset.textureName
        }

        var textureRoleCoverageIdentifier: String {
            CinematicTextureAssetCatalog.textureRoleCoverageIdentifier(
                backdrop: backdropTextureAsset,
                arena: arenaTextureAsset
            )
        }

        var usesFallbackTextureAsset: Bool {
            backdropTextureAsset.usesFallback || arenaTextureAsset.usesFallback
        }
    }
}

enum CinematicTextureAssetRole: String, CaseIterable, Equatable {
    case backdrop
    case arena
}

struct CinematicTextureAsset: Equatable {
    var role: CinematicTextureAssetRole
    var routeIdentifier: String
    var requestedTextureName: String
    var textureName: String
    var fallbackTextureName: String
    var usesFallback: Bool
    var identifier: String
}

enum CinematicTextureAssetCatalog {
    static let identifierMaxCharacters = 72

    private static let generatedBackdropTextureNames: Set<String> = Set(
        CinematicLanguageSigilStyle.allCases.map { generatedBackdropTextureName(for: $0) }
    )
    private static let fallbackBackdropTextureNames: Set<String> = [
        "void-arches",
        "void-arches-v2"
    ]
    private static let backdropTextureNames = generatedBackdropTextureNames.union(fallbackBackdropTextureNames)
    private static let arenaTextureNames: Set<String> = [
        "arena-runes",
        "arena-runes-v2",
        "arena-runes-v3"
    ]

    static var bundledTextureNames: Set<String> {
        backdropTextureNames.union(arenaTextureNames)
    }

    static var generatedBackdropNames: Set<String> {
        generatedBackdropTextureNames
    }

    static var backdropFallbackNames: Set<String> {
        fallbackBackdropTextureNames
    }

    static func backdropAsset(for style: CinematicLanguageSigilStyle) -> CinematicTextureAsset {
        return asset(
            role: .backdrop,
            routeIdentifier: "language.\(style.rawValue)",
            requestedTextureName: generatedBackdropTextureName(for: style)
        )
    }

    static func generatedBackdropTextureName(for style: CinematicLanguageSigilStyle) -> String {
        switch style {
        case .swiftComet:
            return "swift-comet-backdrop"
        case .scriptCircuit:
            return "script-circuit-backdrop"
        case .pythonCoil:
            return "python-coil-backdrop"
        case .goCurrent:
            return "go-current-backdrop"
        case .rustGear:
            return "rust-gear-backdrop"
        case .markdownRune:
            return "markdown-rune-backdrop"
        case .polyglotPrism:
            return "polyglot-prism-backdrop"
        case .unknownGate:
            return "unknown-gate-backdrop"
        }
    }

    static func arenaAsset(for kind: CinematicActivityEventKind) -> CinematicTextureAsset {
        let textureName: String
        switch kind {
        case .conflicted, .failure:
            textureName = "arena-runes-v3"
        case .dirty:
            textureName = "arena-runes-v3"
        case .commit:
            textureName = "arena-runes-v2"
        case .success, .recovery:
            textureName = "arena-runes-v2"
        case .clean, .unavailable:
            textureName = "arena-runes-v3"
        }

        return asset(
            role: .arena,
            routeIdentifier: "activity.\(kind.rawValue)",
            requestedTextureName: textureName
        )
    }

    static func textureRoleCoverageIdentifier(
        backdrop: CinematicTextureAsset,
        arena: CinematicTextureAsset
    ) -> String {
        [
            "backdrop:\(backdrop.routeIdentifier)=\(backdrop.textureName)",
            "arena:\(arena.routeIdentifier)=\(arena.textureName)"
        ].joined(separator: "|")
    }

    static func expectedRouteIdentifiers(for role: CinematicTextureAssetRole) -> Set<String> {
        switch role {
        case .backdrop:
            return Set(CinematicLanguageSigilStyle.allCases.map { backdropAsset(for: $0).routeIdentifier })
        case .arena:
            return Set(CinematicActivityEventKind.allCases.map { arenaAsset(for: $0).routeIdentifier })
        }
    }

    static func recognizes(_ textureName: String, role: CinematicTextureAssetRole) -> Bool {
        recognizedTextureNames(for: role).contains(textureName)
    }

    static func recognizesBundledTextureName(_ textureName: String) -> Bool {
        bundledTextureNames.contains(textureName)
    }

    static func isGeneratedBackdropTextureName(_ textureName: String) -> Bool {
        generatedBackdropTextureNames.contains(textureName)
    }

    static func isPackagedResourceAvailable(
        _ textureName: String,
        role: CinematicTextureAssetRole
    ) -> Bool {
        guard recognizes(textureName, role: role) else { return false }
        return packagedResourceURL(for: textureName) != nil
    }

    static func isPackagedResourceAvailable(for asset: CinematicTextureAsset) -> Bool {
        isPackagedResourceAvailable(asset.textureName, role: asset.role)
    }

    private static func asset(
        role: CinematicTextureAssetRole,
        routeIdentifier: String,
        requestedTextureName: String
    ) -> CinematicTextureAsset {
        let requested = requestedTextureName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallbackTextureName(for: role)
        let recognizedNames = recognizedTextureNames(for: role)
        let textureName = recognizedNames.contains(requested) ? requested : fallback
        let usesFallback = textureName != requested
        let identifier = boundedIdentifier(
            [
                "texture",
                role.rawValue,
                routeIdentifier,
                textureName,
                usesFallback ? "fallback" : "direct"
            ].joined(separator: ".")
        )

        return CinematicTextureAsset(
            role: role,
            routeIdentifier: routeIdentifier,
            requestedTextureName: requested,
            textureName: textureName,
            fallbackTextureName: fallback,
            usesFallback: usesFallback,
            identifier: identifier
        )
    }

    private static func recognizedTextureNames(for role: CinematicTextureAssetRole) -> Set<String> {
        switch role {
        case .backdrop:
            return backdropTextureNames
        case .arena:
            return arenaTextureNames
        }
    }

    private static func fallbackTextureName(for role: CinematicTextureAssetRole) -> String {
        switch role {
        case .backdrop:
            return "void-arches"
        case .arena:
            return "arena-runes"
        }
    }

    private static func packagedResourceURL(for textureName: String) -> URL? {
        Bundle.module.url(
            forResource: textureName,
            withExtension: "png",
            subdirectory: "Cinematic"
        ) ?? Bundle.module.url(forResource: textureName, withExtension: "png")
    }

    private static func boundedIdentifier(_ identifier: String) -> String {
        guard identifier.count > identifierMaxCharacters else { return identifier }

        let prefixLimit = max(1, identifierMaxCharacters - 3)
        return String(identifier.prefix(prefixLimit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

enum CinematicSetDressingPlanner {
    static func plan(
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicSetDressingPlan {
        plan(
            languageMotif: CinematicMotif.language(for: languageProfile),
            activityMotif: CinematicMotif.activity(for: activityProfile),
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings
        )
    }

    static func plan(
        languageMotif: CinematicLanguageMotif,
        activityMotif: CinematicActivityMotif,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicSetDressingPlan {
        let pressureFraction = pressureFraction(for: activityProfile)
        let influenceFraction = influenceFraction(for: influenceSettings)
        let eventUrgency = eventUrgency(for: activityMotif.eventKind)
        let energy = clamp(
            0.34 + pressureFraction * 0.26 + influenceFraction * 0.22 + eventUrgency * 0.28,
            to: 0...1
        )
        let tintFraction = clamp(
            Float(CinematicMotif.activityTintBlend) + eventUrgency * 0.13 + influenceFraction * 0.05,
            to: CinematicSetDressingPlan.activityTintBlendRange
        )
        let architecture = languageArchitecture(
            motif: languageMotif,
            profile: languageProfile
        )
        let marker = activityMarker(
            motif: activityMotif,
            profile: activityProfile,
            languageAmbient: languageMotif.ambientSpell
        )
        let variants = materialTextureVariants(
            languageStyle: languageMotif.style,
            activityKind: activityMotif.eventKind
        )
        let pedestalCount = clamp(
            basePedestalCount(for: languageMotif.style) + pedestalActivityBonus(for: activityMotif.eventKind),
            to: CinematicSetDressingPlan.pedestalCountRange
        )
        let shardCount = clamp(
            baseShardCount(for: languageMotif.style) + shardActivityBonus(for: activityProfile),
            to: CinematicSetDressingPlan.shardCountRange
        )
        let pedestalFlames = CinematicSetDressingPlan.PedestalFlameAccents(
            identifier: [
                "pedestals:\(pedestalCount)",
                "light:\(fixed(lerp(150, 330, energy)))",
                "tint:\(fixed(tintFraction))",
                variants.pedestalMaterialIdentifier,
                variants.flameMaterialIdentifier
            ].joined(separator: "|"),
            pedestalCount: pedestalCount,
            flameLightIntensity: clamp(lerp(150, 330, energy), to: CinematicSetDressingPlan.flameLightIntensityRange),
            flameOpacity: clamp(lerp(0.72, 0.93, energy), to: CinematicSetDressingPlan.flameOpacityRange),
            rimOpacity: clamp(lerp(0.48, 0.76, energy), to: CinematicSetDressingPlan.rimOpacityRange),
            flameXZScale: clamp(lerp(0.66, 0.96, energy), to: CinematicSetDressingPlan.flameScaleRange),
            flameHeightScale: clamp(lerp(1.22, 1.58, energy), to: CinematicSetDressingPlan.flameHeightScaleRange),
            activityTintFraction: tintFraction,
            materialVariantIdentifier: variants.flameMaterialIdentifier
        )
        let floatingShards = CinematicSetDressingPlan.FloatingShardIntensity(
            identifier: [
                "shards:\(shardCount)",
                "emission:\(fixed(lerp(0.18, 0.5, energy)))",
                "tint:\(fixed(tintFraction))",
                variants.shardMaterialIdentifier
            ].joined(separator: "|"),
            shardCount: shardCount,
            opacity: clamp(lerp(0.52, 0.8, energy), to: CinematicSetDressingPlan.shardOpacityRange),
            emissionOpacity: clamp(lerp(0.18, 0.5, energy), to: CinematicSetDressingPlan.shardEmissionOpacityRange),
            scale: clamp(lerp(0.9, 1.18, energy), to: 0.82...1.24),
            activityTintFraction: tintFraction,
            materialVariantIdentifier: variants.shardMaterialIdentifier
        )
        let runeIntensity = CinematicSetDressingPlan.RuneIntensity(
            identifier: [
                "rune:\(fixed(lerp(0.68, 1.22, energy)))",
                "segments:\(fixed(lerp(0.9, 1.28, energy)))",
                variants.runeMaterialIdentifier
            ].joined(separator: "|"),
            languageBaseRadius: clamp(lerp(0.58, 0.72, energy), to: 0.5...0.78),
            activityBaseRadius: clamp(lerp(0.52, 0.66, energy), to: 0.48...0.72),
            segmentRadiusScale: clamp(lerp(0.9, 1.28, energy), to: CinematicSetDressingPlan.segmentRadiusScaleRange),
            segmentOpacityScale: clamp(lerp(0.82, 1.2, energy), to: 0.72...1.28),
            coreScale: clamp(lerp(0.84, 1.18, energy), to: CinematicSetDressingPlan.sigilCoreScaleRange),
            activityPulseScale: clamp(lerp(0.82, 1.24, energy), to: CinematicSetDressingPlan.runeIntensityRange)
        )
        let animationCadence = CinematicSetDressingPlan.AnimationCadence(
            identifier: [
                "flame:\(fixed(lerp(3.25, 5.7, energy)))",
                "shard:\(fixed(lerp(0.82, 1.56, energy)))",
                "pulse:\(fixed(lerp(1.08, 0.7, energy)))"
            ].joined(separator: "|"),
            flamePulseRate: clamp(lerp(3.25, 5.7, energy), to: CinematicSetDressingPlan.flamePulseRateRange),
            flamePulseAmplitude: clamp(lerp(0.08, 0.17, energy), to: CinematicSetDressingPlan.flamePulseAmplitudeRange),
            shardBobRate: clamp(lerp(0.82, 1.56, energy), to: CinematicSetDressingPlan.shardBobRateRange),
            shardBobAmplitude: clamp(lerp(0.055, 0.13, energy), to: CinematicSetDressingPlan.shardBobAmplitudeRange),
            shardRotationStep: clamp(lerp(0.0045, 0.012, energy), to: CinematicSetDressingPlan.shardRotationStepRange),
            activityPulseDuration: TimeInterval(clamp(lerp(1.08, 0.7, energy), to: 0.56...1.24))
        )
        let ambientSpawnCadence = CinematicTuning.ambientSpawnCadence(
            activityProfile: activityProfile,
            settings: influenceSettings
        )
        let ambientEnemyLimit = CinematicTuning.ambientEnemyLimit(
            activityProfile: activityProfile,
            settings: influenceSettings
        )
        let activityLightBoost = CinematicTuning.activityLightBoost(
            activityProfile: activityProfile,
            settings: influenceSettings
        )

        let identifier = [
            architecture.identifier,
            marker.identifier,
            pedestalFlames.identifier,
            floatingShards.identifier,
            runeIntensity.identifier,
            animationCadence.identifier,
            variants.identifier,
            "ambient:\(fixed(ambientSpawnCadence))",
            "limit:\(ambientEnemyLimit)",
            "light:\(fixed(activityLightBoost))"
        ].joined(separator: "||")

        return CinematicSetDressingPlan(
            identifier: identifier,
            languageArchitecture: architecture,
            activityMarker: marker,
            pedestalFlames: pedestalFlames,
            floatingShards: floatingShards,
            runeIntensity: runeIntensity,
            animationCadence: animationCadence,
            materialTextureVariants: variants,
            ambientSpawnCadence: ambientSpawnCadence,
            ambientEnemyLimit: ambientEnemyLimit,
            activityLightBoost: activityLightBoost
        )
    }

    private static func languageArchitecture(
        motif: CinematicLanguageMotif,
        profile: RepositoryLanguageProfile
    ) -> CinematicSetDressingPlan.LanguageArchitecture {
        let architectureIdentifier: String
        let pedestalLayoutIdentifier: String
        let shardFormationIdentifier: String

        switch motif.style {
        case .swiftComet:
            architectureIdentifier = "comet-spires"
            pedestalLayoutIdentifier = "cardinal-forge"
            shardFormationIdentifier = "tailwind"
        case .scriptCircuit:
            architectureIdentifier = "circuit-gantry"
            pedestalLayoutIdentifier = "paired-relays"
            shardFormationIdentifier = "bus-trace"
        case .pythonCoil:
            architectureIdentifier = "coil-observatory"
            pedestalLayoutIdentifier = "spiral-wells"
            shardFormationIdentifier = "helix"
        case .goCurrent:
            architectureIdentifier = "current-channel"
            pedestalLayoutIdentifier = "balanced-flow"
            shardFormationIdentifier = "stream"
        case .rustGear:
            architectureIdentifier = "gear-foundry"
            pedestalLayoutIdentifier = "six-point-anvil"
            shardFormationIdentifier = "gear-teeth"
        case .markdownRune:
            architectureIdentifier = "tablet-archive"
            pedestalLayoutIdentifier = "quiet-triad"
            shardFormationIdentifier = "page-tabs"
        case .polyglotPrism:
            architectureIdentifier = "prism-yard"
            pedestalLayoutIdentifier = "facet-ring"
            shardFormationIdentifier = "split-spectrum"
        case .unknownGate:
            architectureIdentifier = "quiet-gate"
            pedestalLayoutIdentifier = "low-beacons"
            shardFormationIdentifier = "distant-watch"
        }

        let languageIdentifier = profile.primaryLanguage.rawValue
        return CinematicSetDressingPlan.LanguageArchitecture(
            identifier: [
                "language:\(languageIdentifier)",
                motif.sigilIdentifier,
                motif.styleIdentifier,
                architectureIdentifier,
                pedestalLayoutIdentifier,
                shardFormationIdentifier
            ].joined(separator: "|"),
            languageIdentifier: languageIdentifier,
            sigilIdentifier: motif.sigilIdentifier,
            styleIdentifier: motif.styleIdentifier,
            architectureIdentifier: architectureIdentifier,
            pedestalLayoutIdentifier: pedestalLayoutIdentifier,
            shardFormationIdentifier: shardFormationIdentifier
        )
    }

    private static func activityMarker(
        motif: CinematicActivityMotif,
        profile: RepositoryActivityProfile,
        languageAmbient: SpellSchool
    ) -> CinematicSetDressingPlan.ActivityMarker {
        let tintSourceIdentifier = motif.tintSource?.setDressingIdentifier
        let transitionSpellIdentifier = motif.transitionSpell?.setDressingIdentifier
        let ambientOverrideIdentifier = motif.ambientOverride?.setDressingIdentifier
        let ambientSpellIdentifier = motif.ambientSpell(
            languageAmbient: languageAmbient,
            spawnIndex: 0
        ).setDressingIdentifier
        let pressureLevelIdentifier = profile.pressureLevel.rawValue
        let identifier = [
            motif.sigilIdentifier,
            motif.styleIdentifier,
            motif.eventKind.rawValue,
            pressureLevelIdentifier,
            tintSourceIdentifier ?? "none",
            transitionSpellIdentifier ?? "none",
            ambientOverrideIdentifier ?? "none",
            ambientSpellIdentifier
        ].joined(separator: "|")

        return CinematicSetDressingPlan.ActivityMarker(
            identifier: identifier,
            eventKindIdentifier: motif.eventKind.rawValue,
            pressureLevelIdentifier: pressureLevelIdentifier,
            sigilIdentifier: motif.sigilIdentifier,
            styleIdentifier: motif.styleIdentifier,
            tintSourceIdentifier: tintSourceIdentifier,
            transitionSpellIdentifier: transitionSpellIdentifier,
            ambientOverrideIdentifier: ambientOverrideIdentifier,
            ambientSpellIdentifier: ambientSpellIdentifier,
            usesCommitAmbient: motif.usesCommitAmbient,
            usesSuccessAmbient: motif.usesSuccessAmbient,
            shouldShakeOnTransition: motif.shouldShakeOnTransition
        )
    }

    private static func materialTextureVariants(
        languageStyle: CinematicLanguageSigilStyle,
        activityKind: CinematicActivityEventKind
    ) -> CinematicSetDressingPlan.MaterialTextureVariants {
        let languageVariant: String
        switch languageStyle {
        case .swiftComet:
            languageVariant = "comet-alloy"
        case .scriptCircuit:
            languageVariant = "circuit-glass"
        case .pythonCoil:
            languageVariant = "coil-ceramic"
        case .goCurrent:
            languageVariant = "current-stone"
        case .rustGear:
            languageVariant = "oxidized-iron"
        case .markdownRune:
            languageVariant = "etched-slate"
        case .polyglotPrism:
            languageVariant = "prism-basalt"
        case .unknownGate:
            languageVariant = "dim-basalt"
        }

        let arenaTextureAsset = CinematicTextureAssetCatalog.arenaAsset(for: activityKind)
        let backdropTextureAsset = CinematicTextureAssetCatalog.backdropAsset(for: languageStyle)
        let runeMaterialIdentifier: String
        switch activityKind {
        case .conflicted, .failure:
            runeMaterialIdentifier = "fracture-runes"
        case .dirty:
            runeMaterialIdentifier = "pressure-runes"
        case .commit:
            runeMaterialIdentifier = "history-runes"
        case .success, .recovery:
            runeMaterialIdentifier = "seal-runes"
        case .clean, .unavailable:
            runeMaterialIdentifier = "quiet-runes"
        }

        let identifier = [
            backdropTextureAsset.identifier,
            arenaTextureAsset.identifier,
            languageVariant,
            runeMaterialIdentifier
        ].joined(separator: "|")

        return CinematicSetDressingPlan.MaterialTextureVariants(
            identifier: identifier,
            backdropTextureAsset: backdropTextureAsset,
            arenaTextureAsset: arenaTextureAsset,
            pedestalMaterialIdentifier: "\(languageVariant)-pedestal",
            flameMaterialIdentifier: "\(languageVariant)-flame",
            shardMaterialIdentifier: "\(languageVariant)-shard",
            runeMaterialIdentifier: runeMaterialIdentifier
        )
    }

    private static func basePedestalCount(for style: CinematicLanguageSigilStyle) -> Int {
        switch style {
        case .rustGear:
            return 6
        case .pythonCoil, .polyglotPrism:
            return 5
        case .swiftComet, .scriptCircuit, .goCurrent:
            return 4
        case .markdownRune, .unknownGate:
            return 3
        }
    }

    private static func pedestalActivityBonus(for kind: CinematicActivityEventKind) -> Int {
        switch kind {
        case .conflicted, .failure, .success:
            return 1
        case .unavailable, .clean, .dirty, .commit, .recovery:
            return 0
        }
    }

    private static func baseShardCount(for style: CinematicLanguageSigilStyle) -> Int {
        switch style {
        case .scriptCircuit, .rustGear:
            return 7
        case .swiftComet, .pythonCoil, .polyglotPrism:
            return 6
        case .goCurrent:
            return 5
        case .markdownRune, .unknownGate:
            return 4
        }
    }

    private static func shardActivityBonus(for profile: RepositoryActivityProfile) -> Int {
        guard !profile.isEmpty else { return 0 }
        switch profile.pressureLevel {
        case .clean:
            return profile.successStreak > 1 || profile.recentCommitCount > 0 ? 1 : 0
        case .light:
            return 1
        case .moderate, .heavy:
            return 2
        }
    }

    private static func pressureFraction(for profile: RepositoryActivityProfile) -> Float {
        guard !profile.isEmpty else { return 0 }
        switch profile.pressureLevel {
        case .clean:
            return profile.successStreak > 1 || profile.recentCommitCount > 0 ? 0.18 : 0.08
        case .light:
            return 0.34
        case .moderate:
            return 0.66
        case .heavy:
            return 1
        }
    }

    private static func influenceFraction(for settings: CinematicInfluenceSettings) -> Float {
        let intensity = Float(CinematicInfluenceSettings.clampedIntensity(settings.intensity))
        let styleFloor: Float
        switch settings.cameraStyle {
        case .steady:
            styleFloor = 0.12
        case .follow:
            styleFloor = 0.42
        case .dramatic:
            styleFloor = 0.76
        }
        return clamp(styleFloor + intensity * 0.24, to: 0...1)
    }

    private static func eventUrgency(for kind: CinematicActivityEventKind) -> Float {
        switch kind {
        case .unavailable:
            return 0
        case .clean:
            return 0.08
        case .commit:
            return 0.3
        case .success, .recovery:
            return 0.36
        case .dirty:
            return 0.56
        case .conflicted, .failure:
            return 1
        }
    }

    private static func lerp(_ start: Float, _ end: Float, _ t: Float) -> Float {
        start + (end - start) * t
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func fixed(_ value: TimeInterval) -> String {
        fixed(Float(value))
    }

    private static func fixed(_ value: Float) -> String {
        String(format: "%.4f", value)
    }
}

extension SpellSchool {
    var setDressingIdentifier: String {
        switch self {
        case .scan:
            return "scan"
        case .shell:
            return "shell"
        case .edit:
            return "edit"
        case .git:
            return "git"
        case .verify:
            return "verify"
        case .insight:
            return "insight"
        case .lifecycle:
            return "lifecycle"
        case .pressure:
            return "pressure"
        case .failure:
            return "failure"
        }
    }
}

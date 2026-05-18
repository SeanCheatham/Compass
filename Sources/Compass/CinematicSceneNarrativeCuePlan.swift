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
    static let cueAnchorXRange: ClosedRange<Float> = -6.2...6.2
    static let cueAnchorYRange: ClosedRange<Float> = 0.08...2.45
    static let cueAnchorZRange: ClosedRange<Float> = -4.85...4.45
    static let cuePlateWidthRange: ClosedRange<Float> = 2.18...4.08
    static let cuePlateHeightRange: ClosedRange<Float> = 0.3...0.72
    static let cueTextWidthRange: ClosedRange<Float> = 1.44...3.52
    static let cueFontSizeRange: ClosedRange<Float> = 0.058...0.212
    static let cueBackingOpacityRange: ClosedRange<Float> = 0.08...0.42
    static let cueOffsetXRange: ClosedRange<Float> = -1.82...1.82
    static let cueOffsetYRange: ClosedRange<Float> = -0.24...0.18
    static let cueLayerZRange: ClosedRange<Float> = -0.052...0.092
    static let cuePlateDepthRange: ClosedRange<Float> = 0.012...0.052

    var identifier: String
    var stageBeatIdentifier: String
    var stagePhasePolishIdentifier: String
    var languageIdentifier: String
    var activityIdentifier: String
    var influenceIdentifier: String
    var nativeFeedbackCueIdentifier: String
    var nativeFeedbackLifecycleIdentifier: String
    var nativeFeedbackSourceIdentifier: String
    var nativeFeedbackStyleIdentifier: String
    var nativeFeedbackMilestoneIdentifier: String
    var nativeFeedbackAffectedDescriptorIdentifiers: [String]
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
        var layout: LayoutDescriptor
        var plaqueTreatment: PlaqueTreatmentDescriptor

        var anchorIdentifier: String { anchor.rawValue }
        var visibilityIdentifier: String { visibility.rawValue }
        var lightFamilyIdentifier: String { lightFamily.rawValue }
        var tintFamilyIdentifier: String { tintFamily.rawValue }
        var plaqueTreatmentIdentifier: String { plaqueTreatment.identifier }
        var plaqueTreatmentAccentIdentifier: String { plaqueTreatment.accentIdentifier }
        var plaqueTreatmentRouteIdentifier: String { plaqueTreatment.routeIdentifier }
        var plaqueTreatmentRenderRecipeIdentifier: String { plaqueTreatment.renderRecipe.identifier }
        var plaqueTreatmentRenderPrimitiveIdentifiers: [String] {
            plaqueTreatment.renderRecipe.primitiveIdentifiers
        }
        var plaqueTreatmentRenderPrimitiveCount: Int { plaqueTreatment.renderRecipe.primitiveCount }

        init(
            stableID: String,
            text: String,
            secondaryText: String?,
            glyphIdentifier: String?,
            anchor: CinematicNarrativeCueAnchor,
            visibility: CinematicNarrativeCueVisibility,
            scale: Float,
            opacity: Float,
            lightFamily: CinematicStageLightFamily,
            tintFamily: CinematicStageLightFamily,
            cadence: TimeInterval,
            layout: LayoutDescriptor? = nil,
            plaqueTreatment: PlaqueTreatmentDescriptor = .none
        ) {
            self.stableID = stableID
            self.text = text
            self.secondaryText = secondaryText
            self.glyphIdentifier = glyphIdentifier
            self.anchor = anchor
            self.visibility = visibility
            self.scale = scale
            self.opacity = opacity
            self.lightFamily = lightFamily
            self.tintFamily = tintFamily
            self.cadence = cadence
            self.layout = layout ?? Self.fallbackLayout(anchor: anchor, opacity: opacity)
            self.plaqueTreatment = plaqueTreatment
        }

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
                "cadence\(CinematicSceneNarrativeCuePlanner.fixed(cadence))",
                "layout{\(layout.identifier)}",
                "treatment{\(plaqueTreatment.identifier)}"
            ].joined(separator: "|")
        }

        struct PlaqueTreatmentDescriptor: Equatable {
            enum Accent: String, CaseIterable, Equatable {
                case none
                case verifySeal = "verify-seal"
                case warningRails = "warning-rails"
                case failureFracture = "failure-fracture"
                case retryBraces = "retry-braces"
            }

            enum RenderPrimitive: String, CaseIterable, Equatable {
                case railTop = "rail.top"
                case railBottom = "rail.bottom"
                case sealLeft = "seal.left"
                case sealRight = "seal.right"
                case warningLeft = "warning.left"
                case warningRight = "warning.right"
                case fractureDiagonalA = "fracture.diagonal.a"
                case fractureDiagonalB = "fracture.diagonal.b"
                case retryBraceLeft = "retry.brace.left"
                case retryBraceRight = "retry.brace.right"
                case retryCross = "retry.cross"

                var identifier: String { rawValue }
            }

            struct RenderRecipe: Equatable {
                static let primitiveCountRange: ClosedRange<Int> = 0...6
                static let primitiveIdentifierMaxCharacters = 32

                var primitives: [RenderPrimitive]

                var primitiveIdentifiers: [String] {
                    primitives.map(\.identifier)
                }

                var primitiveCount: Int {
                    primitives.count
                }

                var identifier: String {
                    primitiveIdentifiers.isEmpty ? "none" : primitiveIdentifiers.joined(separator: ",")
                }

                init(primitives: [RenderPrimitive]) {
                    self.primitives = Array(primitives.prefix(Self.primitiveCountRange.upperBound))
                }
            }

            static let none = PlaqueTreatmentDescriptor(
                accent: .none,
                routeIdentifier: "none",
                emissionBoost: 0,
                edgeRailOpacity: 0,
                braceOpacity: 0,
                fractureOpacity: 0,
                pulseScale: 1
            )

            var accent: Accent
            var routeIdentifier: String
            var emissionBoost: Float
            var edgeRailOpacity: Float
            var braceOpacity: Float
            var fractureOpacity: Float
            var pulseScale: Float

            var accentIdentifier: String { accent.rawValue }
            var renderRecipe: RenderRecipe { Self.renderRecipe(for: accent) }

            var identifier: String {
                let recipe = renderRecipe
                return [
                    accent.rawValue,
                    "route:\(routeIdentifier)",
                    "emit\(CinematicSceneNarrativeCuePlanner.fixed(emissionBoost))",
                    "rails\(CinematicSceneNarrativeCuePlanner.fixed(edgeRailOpacity))",
                    "braces\(CinematicSceneNarrativeCuePlanner.fixed(braceOpacity))",
                    "fracture\(CinematicSceneNarrativeCuePlanner.fixed(fractureOpacity))",
                    "pulse\(CinematicSceneNarrativeCuePlanner.fixed(pulseScale))",
                    "primitives:\(recipe.identifier)",
                    "primitive-count:\(recipe.primitiveCount)"
                ].joined(separator: "|")
            }

            init(
                accent: Accent,
                routeIdentifier: String,
                emissionBoost: Float,
                edgeRailOpacity: Float,
                braceOpacity: Float,
                fractureOpacity: Float,
                pulseScale: Float
            ) {
                self.accent = accent
                self.routeIdentifier = routeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "none"
                    : routeIdentifier
                self.emissionBoost = Self.clamp(emissionBoost, to: 0...0.42)
                self.edgeRailOpacity = Self.clamp(edgeRailOpacity, to: 0...0.9)
                self.braceOpacity = Self.clamp(braceOpacity, to: 0...0.9)
                self.fractureOpacity = Self.clamp(fractureOpacity, to: 0...0.9)
                self.pulseScale = Self.clamp(pulseScale, to: 0.96...1.12)
            }

            private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
                min(max(value, range.lowerBound), range.upperBound)
            }

            private static func renderRecipe(for accent: Accent) -> RenderRecipe {
                switch accent {
                case .verifySeal:
                    return RenderRecipe(primitives: [
                        .railTop,
                        .railBottom,
                        .sealLeft,
                        .sealRight
                    ])
                case .warningRails:
                    return RenderRecipe(primitives: [
                        .railTop,
                        .railBottom,
                        .warningLeft,
                        .warningRight
                    ])
                case .failureFracture:
                    return RenderRecipe(primitives: [
                        .railTop,
                        .railBottom,
                        .fractureDiagonalA,
                        .fractureDiagonalB
                    ])
                case .retryBraces:
                    return RenderRecipe(primitives: [
                        .railTop,
                        .railBottom,
                        .retryBraceLeft,
                        .retryBraceRight,
                        .retryCross
                    ])
                case .none:
                    return RenderRecipe(primitives: [])
                }
            }
        }

        struct LayoutDescriptor: Equatable {
            enum FacingMode: String, CaseIterable, Equatable {
                case arenaCamera = "arena-camera"
                case floorInscription = "floor-inscription"
            }

            enum GlyphSide: String, CaseIterable, Equatable {
                case none
                case leading
                case trailing
            }

            var anchorPosition: SIMD3<Float>
            var facingMode: FacingMode
            var plateSize: SIMD2<Float>
            var primaryTextWidth: Float
            var secondaryTextWidth: Float
            var primaryFontSize: Float
            var secondaryFontSize: Float
            var backingOpacity: Float
            var glyphSide: GlyphSide
            var glyphOffset: SIMD3<Float>
            var plateDepth: Float
            var plateZOffset: Float
            var primaryTextOffset: SIMD3<Float>
            var secondaryTextOffset: SIMD3<Float>

            var facingModeIdentifier: String { facingMode.rawValue }
            var glyphSideIdentifier: String { glyphSide.rawValue }

            var identifier: String {
                [
                    "pos\(Self.vectorIdentifier(anchorPosition))",
                    "face\(facingMode.rawValue)",
                    "plate\(CinematicSceneNarrativeCuePlanner.fixed(plateSize.x))x\(CinematicSceneNarrativeCuePlanner.fixed(plateSize.y))",
                    "text\(CinematicSceneNarrativeCuePlanner.fixed(primaryTextWidth))/\(CinematicSceneNarrativeCuePlanner.fixed(secondaryTextWidth))",
                    "font\(CinematicSceneNarrativeCuePlanner.fixed(primaryFontSize))/\(CinematicSceneNarrativeCuePlanner.fixed(secondaryFontSize))",
                    "back\(CinematicSceneNarrativeCuePlanner.fixed(backingOpacity))",
                    "glyph\(glyphSide.rawValue)@\(Self.vectorIdentifier(glyphOffset))",
                    "depth\(CinematicSceneNarrativeCuePlanner.fixed(plateDepth))@\(CinematicSceneNarrativeCuePlanner.fixed(plateZOffset))",
                    "primary@\(Self.vectorIdentifier(primaryTextOffset))",
                    "secondary@\(Self.vectorIdentifier(secondaryTextOffset))"
                ].joined(separator: "|")
            }

            init(
                anchorPosition: SIMD3<Float>,
                facingMode: FacingMode,
                plateSize: SIMD2<Float>,
                primaryTextWidth: Float,
                secondaryTextWidth: Float,
                primaryFontSize: Float,
                secondaryFontSize: Float,
                backingOpacity: Float,
                glyphSide: GlyphSide,
                glyphOffset: SIMD3<Float>,
                plateDepth: Float,
                plateZOffset: Float,
                primaryTextOffset: SIMD3<Float>,
                secondaryTextOffset: SIMD3<Float>
            ) {
                self.anchorPosition = [
                    Self.clamp(anchorPosition.x, to: CinematicSceneNarrativeCuePlan.cueAnchorXRange),
                    Self.clamp(anchorPosition.y, to: CinematicSceneNarrativeCuePlan.cueAnchorYRange),
                    Self.clamp(anchorPosition.z, to: CinematicSceneNarrativeCuePlan.cueAnchorZRange)
                ]
                self.facingMode = facingMode
                self.plateSize = [
                    Self.clamp(plateSize.x, to: CinematicSceneNarrativeCuePlan.cuePlateWidthRange),
                    Self.clamp(plateSize.y, to: CinematicSceneNarrativeCuePlan.cuePlateHeightRange)
                ]
                self.primaryTextWidth = Self.clamp(primaryTextWidth, to: CinematicSceneNarrativeCuePlan.cueTextWidthRange)
                self.secondaryTextWidth = Self.clamp(secondaryTextWidth, to: CinematicSceneNarrativeCuePlan.cueTextWidthRange)
                self.primaryFontSize = Self.clamp(primaryFontSize, to: CinematicSceneNarrativeCuePlan.cueFontSizeRange)
                self.secondaryFontSize = Self.clamp(secondaryFontSize, to: CinematicSceneNarrativeCuePlan.cueFontSizeRange)
                self.backingOpacity = Self.clamp(backingOpacity, to: CinematicSceneNarrativeCuePlan.cueBackingOpacityRange)
                self.glyphSide = glyphSide
                self.glyphOffset = [
                    Self.clamp(glyphOffset.x, to: CinematicSceneNarrativeCuePlan.cueOffsetXRange),
                    Self.clamp(glyphOffset.y, to: CinematicSceneNarrativeCuePlan.cueOffsetYRange),
                    Self.clamp(glyphOffset.z, to: CinematicSceneNarrativeCuePlan.cueLayerZRange)
                ]
                self.plateDepth = Self.clamp(plateDepth, to: CinematicSceneNarrativeCuePlan.cuePlateDepthRange)
                self.plateZOffset = Self.clamp(plateZOffset, to: CinematicSceneNarrativeCuePlan.cueLayerZRange)
                self.primaryTextOffset = [
                    Self.clamp(primaryTextOffset.x, to: CinematicSceneNarrativeCuePlan.cueOffsetXRange),
                    Self.clamp(primaryTextOffset.y, to: CinematicSceneNarrativeCuePlan.cueOffsetYRange),
                    Self.clamp(primaryTextOffset.z, to: CinematicSceneNarrativeCuePlan.cueLayerZRange)
                ]
                self.secondaryTextOffset = [
                    Self.clamp(secondaryTextOffset.x, to: CinematicSceneNarrativeCuePlan.cueOffsetXRange),
                    Self.clamp(secondaryTextOffset.y, to: CinematicSceneNarrativeCuePlan.cueOffsetYRange),
                    Self.clamp(secondaryTextOffset.z, to: CinematicSceneNarrativeCuePlan.cueLayerZRange)
                ]
            }

            private static func vectorIdentifier(_ value: SIMD3<Float>) -> String {
                [
                    CinematicSceneNarrativeCuePlanner.fixed(value.x),
                    CinematicSceneNarrativeCuePlanner.fixed(value.y),
                    CinematicSceneNarrativeCuePlanner.fixed(value.z)
                ].joined(separator: ",")
            }

            private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
                min(max(value, range.lowerBound), range.upperBound)
            }
        }

        private static func fallbackLayout(
            anchor: CinematicNarrativeCueAnchor,
            opacity: Float
        ) -> LayoutDescriptor {
            let isFloor = anchor == .arenaCenter || anchor == .arenaFront || anchor == .arenaRear
            return LayoutDescriptor(
                anchorPosition: isFloor ? [0, 0.13, 0.72] : [0, 1.1, 2.8],
                facingMode: isFloor ? .floorInscription : .arenaCamera,
                plateSize: isFloor ? [3.0, 0.34] : [2.6, 0.52],
                primaryTextWidth: isFloor ? 2.24 : 1.92,
                secondaryTextWidth: isFloor ? 2.06 : 1.74,
                primaryFontSize: isFloor ? 0.17 : 0.136,
                secondaryFontSize: 0.068,
                backingOpacity: max(0.1, opacity * (isFloor ? 0.2 : 0.34)),
                glyphSide: .none,
                glyphOffset: [0, 0, isFloor ? 0.032 : 0.04],
                plateDepth: isFloor ? 0.018 : 0.036,
                plateZOffset: isFloor ? -0.0104 : -0.0208,
                primaryTextOffset: [0, isFloor ? -0.034 : -0.026, isFloor ? 0.024 : 0.03],
                secondaryTextOffset: [0, -0.13, isFloor ? 0.028 : 0.034]
            )
        }
    }
}

enum CinematicSceneNarrativeCuePlanner {
    private typealias PlaqueTreatmentDescriptor = CinematicSceneNarrativeCuePlan.CueDescriptor.PlaqueTreatmentDescriptor

    static func plan(
        worldText: CinematicWorldText,
        briefing: CinematicBriefing,
        stageBeat: CinematicStageBeat,
        stagePhasePolishPlan: CinematicStagePhasePolishPlan,
        languageMotif: CinematicLanguageMotif,
        activityMotif: CinematicActivityMotif,
        influenceSettings: CinematicInfluenceSettings,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan? = nil
    ) -> CinematicSceneNarrativeCuePlan {
        let isIdleUnavailable = stageBeat.kind == .idle && activityMotif.eventKind == .unavailable
        let usesNativeFeedbackCue = nativeFeedbackCue != nil
        let usesIdleFallback = isIdleUnavailable && !usesNativeFeedbackCue
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
        let nativeCue = nativeFeedbackCue.map { nativeFeedbackCueDescriptorPlan(for: $0) }
        let questDescriptor = cueDescriptor(
            slot: .questPlaque,
            stableID: "narrative.quest.plaque",
            text: nativeCue?.questPlaqueText ?? questText,
            secondaryText: nativeCue?.questPlaqueSecondaryText ?? (questSecondary == questText ? nil : questSecondary),
            glyphIdentifier: nativeCue?.glyphIdentifier ?? languageMotif.sigilIdentifier,
            anchor: nativeCue?.questPlaqueAnchor ?? questAnchor(for: stageBeat, isIdleUnavailable: usesIdleFallback),
            visibility: nativeCue?.visibility ?? visibility,
            baseLightFamily: nativeCue?.lightFamily ?? stagePhasePolishPlan.staffOrb.lightFamily,
            tintFamily: nativeCue?.tintFamily ?? stageBeat.lightFamily,
            phaseEnergy: nativeCue?.phaseEnergy ?? phaseEnergy,
            influenceIntensity: influenceIntensity,
            influenceFraction: influenceFraction,
            isIdleUnavailable: usesIdleFallback,
            plaqueTreatment: nativeCue?.plaqueTreatment ?? .none
        )
        let arenaDescriptor = cueDescriptor(
            slot: .arenaInscription,
            stableID: "narrative.arena.inscription",
            text: nativeCue?.arenaInscriptionText ?? arenaText,
            secondaryText: nil,
            glyphIdentifier: nativeCue?.glyphIdentifier ?? stageBeat.arenaEffect.rawValue,
            anchor: nativeCue?.arenaInscriptionAnchor ?? arenaAnchor(for: stageBeat, isIdleUnavailable: usesIdleFallback),
            visibility: nativeCue?.visibility ?? visibility,
            baseLightFamily: nativeCue?.lightFamily ?? stageBeat.lightFamily,
            tintFamily: nativeCue?.tintFamily ?? stagePhasePolishPlan.portalBackdrop.lightFamily,
            phaseEnergy: nativeCue.map { $0.phaseEnergy * 0.94 } ?? (phaseEnergy * 0.88),
            influenceIntensity: influenceIntensity,
            influenceFraction: influenceFraction,
            isIdleUnavailable: usesIdleFallback,
            plaqueTreatment: nativeCue?.plaqueTreatment ?? .none
        )
        let activityDescriptor = cueDescriptor(
            slot: .activityBanner,
            stableID: "narrative.activity.banner",
            text: nativeCue?.activityBannerText ?? activityText,
            secondaryText: nil,
            glyphIdentifier: nativeCue?.glyphIdentifier ?? activityMotif.sigilIdentifier,
            anchor: nativeCue?.activityBannerAnchor ?? activityAnchor(for: activityMotif, isIdleUnavailable: usesIdleFallback),
            visibility: nativeCue?.visibility ?? visibility,
            baseLightFamily: nativeCue?.lightFamily ?? activityLightFamily(stageBeat: stageBeat, activityMotif: activityMotif),
            tintFamily: nativeCue?.tintFamily ?? stagePhasePolishPlan.fractureRecovery.lightFamily,
            phaseEnergy: nativeCue?.phaseEnergy ?? (phaseEnergy + activityUrgency(for: activityMotif.eventKind) * 0.1),
            influenceIntensity: influenceIntensity,
            influenceFraction: influenceFraction,
            isIdleUnavailable: usesIdleFallback,
            plaqueTreatment: nativeCue?.plaqueTreatment ?? .none
        )
        let influenceIdentifier = [
            influenceSettings.cameraStyle.rawValue,
            fixed(influenceIntensity),
            fixed(influenceFraction)
        ].joined(separator: "|")
        var identifierParts = [
            "beat:\(stageBeat.identifier)",
            "phase-polish:\(stagePhasePolishPlan.identifier)",
            "language:\(languageMotif.sigilIdentifier)",
            "activity:\(activityMotif.sigilIdentifier)",
            "quest:\(questDescriptor.identifier)",
            "arena:\(arenaDescriptor.identifier)",
            "banner:\(activityDescriptor.identifier)",
            "influence:\(influenceIdentifier)"
        ]
        if let nativeFeedbackCue {
            identifierParts.append("native-feedback:\(nativeFeedbackCue.identifier)")
            identifierParts.append("native-lifecycle:\(nativeFeedbackCue.lifecycleIdentifier)")
        }
        let identifier = identifierParts.joined(separator: "||")

        return CinematicSceneNarrativeCuePlan(
            identifier: identifier,
            stageBeatIdentifier: stageBeat.identifier,
            stagePhasePolishIdentifier: stagePhasePolishPlan.identifier,
            languageIdentifier: languageMotif.sigilIdentifier,
            activityIdentifier: activityMotif.sigilIdentifier,
            influenceIdentifier: influenceIdentifier,
            nativeFeedbackCueIdentifier: nativeFeedbackCue?.identifier ?? "none",
            nativeFeedbackLifecycleIdentifier: nativeFeedbackCue?.lifecycleIdentifier ?? "none",
            nativeFeedbackSourceIdentifier: nativeFeedbackCue?.sourceIdentifier ?? "none",
            nativeFeedbackStyleIdentifier: nativeFeedbackCue?.styleIdentifier ?? "none",
            nativeFeedbackMilestoneIdentifier: nativeFeedbackCue?.milestoneIdentifier ?? "none",
            nativeFeedbackAffectedDescriptorIdentifiers: nativeCue?.affectedDescriptorIdentifiers ?? [],
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
        slot: NarrativeCueSlot,
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
        isIdleUnavailable: Bool,
        plaqueTreatment: CinematicSceneNarrativeCuePlan.CueDescriptor.PlaqueTreatmentDescriptor = .none
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
        let layout = cueLayoutDescriptor(
            slot: slot,
            anchor: anchor,
            visibility: visibility,
            opacity: opacity,
            phaseEnergy: phaseEnergy,
            influenceFraction: influenceFraction,
            hasSecondary: secondaryText?.isEmpty == false,
            hasGlyph: glyphIdentifier?.isEmpty == false,
            isIdleUnavailable: isIdleUnavailable
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
            cadence: cadence,
            layout: layout,
            plaqueTreatment: plaqueTreatment
        )
    }

    private enum NarrativeCueSlot {
        case questPlaque
        case arenaInscription
        case activityBanner
    }

    private struct NativeFeedbackCueDescriptorPlan {
        var questPlaqueText: String
        var questPlaqueSecondaryText: String
        var arenaInscriptionText: String
        var activityBannerText: String
        var glyphIdentifier: String
        var questPlaqueAnchor: CinematicNarrativeCueAnchor
        var arenaInscriptionAnchor: CinematicNarrativeCueAnchor
        var activityBannerAnchor: CinematicNarrativeCueAnchor
        var visibility: CinematicNarrativeCueVisibility
        var lightFamily: CinematicStageLightFamily
        var tintFamily: CinematicStageLightFamily
        var phaseEnergy: Float
        var plaqueTreatment: CinematicSceneNarrativeCuePlan.CueDescriptor.PlaqueTreatmentDescriptor
        var affectedDescriptorIdentifiers: [String]
    }

    private struct NativeFeedbackTreatment {
        var plaqueLabel: String
        var inscriptionLabel: String
        var bannerLabel: String
        var questPlaqueAnchor: CinematicNarrativeCueAnchor
        var arenaInscriptionAnchor: CinematicNarrativeCueAnchor
        var activityBannerAnchor: CinematicNarrativeCueAnchor
        var lightFamily: CinematicStageLightFamily
        var tintFamily: CinematicStageLightFamily
        var phaseEnergy: Float
        var plaqueTreatment: CinematicSceneNarrativeCuePlan.CueDescriptor.PlaqueTreatmentDescriptor
    }

    private static func nativeFeedbackCueDescriptorPlan(
        for cue: CinematicNativeFeedbackCuePlan
    ) -> NativeFeedbackCueDescriptorPlan {
        let treatment = nativeFeedbackTreatment(for: cue)
        let glyphIdentifier = cue.systemImage.isEmpty ? "native-feedback" : cue.systemImage
        let runCueMetadata = nativeFeedbackRunCueMetadata(for: cue)
        let sourceCopy = nativeFeedbackSourceCopy(for: cue, runCueMetadata: runCueMetadata)

        let questPlaqueText = boundedWorldTextValue(
            "\(treatment.plaqueLabel): \(cue.title)",
            maxCharacters: CinematicWorldTextService.questLabelMaxCharacters,
            maxWords: CinematicWorldTextService.questLabelMaxWords,
            fallback: treatment.plaqueLabel
        )
        let questPlaqueSecondaryText = boundedBriefingTextValue(
            "\(cue.status) | \(sourceCopy)",
            maxCharacters: CinematicBriefingService.titleMaxCharacters,
            fallback: cue.status
        )
        let arenaInscriptionText = boundedWorldTextValue(
            [
                treatment.inscriptionLabel,
                nativeFeedbackSystemImageCopy(glyphIdentifier),
                nativeFeedbackArenaMetadata(for: cue, runCueMetadata: runCueMetadata)
            ].joined(separator: " "),
            maxCharacters: CinematicWorldTextService.arenaCalloutMaxCharacters,
            maxWords: CinematicWorldTextService.arenaCalloutMaxWords,
            fallback: treatment.inscriptionLabel
        )
        let activityBannerText = boundedWorldTextValue(
            [
                treatment.bannerLabel,
                runCueMetadata,
                cue.detail
            ].compactMap { $0 }.joined(separator: ": "),
            maxCharacters: CinematicWorldTextService.activityCalloutMaxCharacters,
            maxWords: CinematicWorldTextService.activityCalloutMaxWords,
            fallback: treatment.bannerLabel
        )

        return NativeFeedbackCueDescriptorPlan(
            questPlaqueText: questPlaqueText,
            questPlaqueSecondaryText: questPlaqueSecondaryText,
            arenaInscriptionText: arenaInscriptionText,
            activityBannerText: activityBannerText,
            glyphIdentifier: glyphIdentifier,
            questPlaqueAnchor: treatment.questPlaqueAnchor,
            arenaInscriptionAnchor: treatment.arenaInscriptionAnchor,
            activityBannerAnchor: treatment.activityBannerAnchor,
            visibility: .featured,
            lightFamily: treatment.lightFamily,
            tintFamily: treatment.tintFamily,
            phaseEnergy: treatment.phaseEnergy,
            plaqueTreatment: treatment.plaqueTreatment,
            affectedDescriptorIdentifiers: [
                "narrative.quest.plaque",
                "narrative.arena.inscription",
                "narrative.activity.banner"
            ]
        )
    }

    private static func nativeFeedbackTreatment(
        for cue: CinematicNativeFeedbackCuePlan
    ) -> NativeFeedbackTreatment {
        if cue.milestone == .verifyStarted {
            return NativeFeedbackTreatment(
                plaqueLabel: "Verify seal",
                inscriptionLabel: "Seal",
                bannerLabel: "Verify started",
                questPlaqueAnchor: .leftSealPylon,
                arenaInscriptionAnchor: .arenaRear,
                activityBannerAnchor: .rightHistoryPylon,
                lightFamily: .verify,
                tintFamily: .verify,
                phaseEnergy: 0.78,
                plaqueTreatment: nativeFeedbackPlaqueTreatment(for: cue, accent: .verifySeal)
            )
        }

        switch cue.style {
        case .failure:
            let accent: PlaqueTreatmentDescriptor.Accent = cue.milestone == .developRetrying
                ? .retryBraces
                : .failureFracture
            return NativeFeedbackTreatment(
                plaqueLabel: accent == .retryBraces ? "Retry braces" : "Failure anchor",
                inscriptionLabel: "Failure rune",
                bannerLabel: accent == .retryBraces ? "Retry run" : "Failure run",
                questPlaqueAnchor: .fractureGate,
                arenaInscriptionAnchor: .fractureGate,
                activityBannerAnchor: .rightWarningPylon,
                lightFamily: .failure,
                tintFamily: .failure,
                phaseEnergy: 0.96,
                plaqueTreatment: nativeFeedbackPlaqueTreatment(for: cue, accent: accent)
            )
        case .warning:
            return NativeFeedbackTreatment(
                plaqueLabel: "Warning anchor",
                inscriptionLabel: "Warning rune",
                bannerLabel: "Recovery run",
                questPlaqueAnchor: .rightWarningPylon,
                arenaInscriptionAnchor: .fractureGate,
                activityBannerAnchor: .rightWarningPylon,
                lightFamily: .pressure,
                tintFamily: .failure,
                phaseEnergy: 0.86,
                plaqueTreatment: nativeFeedbackPlaqueTreatment(for: cue, accent: .warningRails)
            )
        case .verify:
            return NativeFeedbackTreatment(
                plaqueLabel: "Verify seal",
                inscriptionLabel: "Seal",
                bannerLabel: "Verify cue",
                questPlaqueAnchor: .leftSealPylon,
                arenaInscriptionAnchor: .arenaRear,
                activityBannerAnchor: .rightHistoryPylon,
                lightFamily: .verify,
                tintFamily: .verify,
                phaseEnergy: 0.74,
                plaqueTreatment: nativeFeedbackPlaqueTreatment(for: cue, accent: .verifySeal)
            )
        case .success:
            return NativeFeedbackTreatment(
                plaqueLabel: "Success arch",
                inscriptionLabel: "Victory",
                bannerLabel: "Success cue",
                questPlaqueAnchor: .victoryArch,
                arenaInscriptionAnchor: .victoryArch,
                activityBannerAnchor: .rightHistoryPylon,
                lightFamily: .verify,
                tintFamily: .git,
                phaseEnergy: 0.82,
                plaqueTreatment: nativeFeedbackPlaqueTreatment(for: cue, accent: .none)
            )
        case .develop:
            let accent: PlaqueTreatmentDescriptor.Accent = cue.milestone == .developRetrying
                ? .retryBraces
                : .none
            return NativeFeedbackTreatment(
                plaqueLabel: accent == .retryBraces ? "Retry braces" : "Develop forge",
                inscriptionLabel: "Forge",
                bannerLabel: accent == .retryBraces ? "Retry cue" : "Develop cue",
                questPlaqueAnchor: .leftForgePylon,
                arenaInscriptionAnchor: .arenaFront,
                activityBannerAnchor: .rightPylon,
                lightFamily: .edit,
                tintFamily: .shell,
                phaseEnergy: 0.64,
                plaqueTreatment: nativeFeedbackPlaqueTreatment(for: cue, accent: accent)
            )
        case .plan:
            return NativeFeedbackTreatment(
                plaqueLabel: "Plan scout",
                inscriptionLabel: "Scout",
                bannerLabel: "Plan cue",
                questPlaqueAnchor: .leftScoutPylon,
                arenaInscriptionAnchor: .arenaFront,
                activityBannerAnchor: .rightPylon,
                lightFamily: .scan,
                tintFamily: .insight,
                phaseEnergy: 0.48,
                plaqueTreatment: nativeFeedbackPlaqueTreatment(for: cue, accent: .none)
            )
        case .paused:
            return NativeFeedbackTreatment(
                plaqueLabel: "Paused gate",
                inscriptionLabel: "Gate",
                bannerLabel: "Paused cue",
                questPlaqueAnchor: .idleArchive,
                arenaInscriptionAnchor: .arenaCenter,
                activityBannerAnchor: .rightPylon,
                lightFamily: .lifecycle,
                tintFamily: .lifecycle,
                phaseEnergy: 0.38,
                plaqueTreatment: nativeFeedbackPlaqueTreatment(for: cue, accent: .none)
            )
        case .idle:
            return NativeFeedbackTreatment(
                plaqueLabel: "Idle archive",
                inscriptionLabel: "Archive",
                bannerLabel: "Idle cue",
                questPlaqueAnchor: .idleArchive,
                arenaInscriptionAnchor: .arenaCenter,
                activityBannerAnchor: .idleArchive,
                lightFamily: .lifecycle,
                tintFamily: .lifecycle,
                phaseEnergy: 0.28,
                plaqueTreatment: nativeFeedbackPlaqueTreatment(for: cue, accent: .none)
            )
        }
    }

    private static func nativeFeedbackPlaqueTreatment(
        for cue: CinematicNativeFeedbackCuePlan,
        accent: PlaqueTreatmentDescriptor.Accent
    ) -> PlaqueTreatmentDescriptor {
        guard accent != .none else { return .none }

        let routeIdentifier = [
            cue.milestoneIdentifier,
            cue.styleIdentifier,
            cue.runCueKind?.rawValue
        ].compactMap { $0 }.joined(separator: ".")

        switch accent {
        case .verifySeal:
            return PlaqueTreatmentDescriptor(
                accent: accent,
                routeIdentifier: routeIdentifier,
                emissionBoost: 0.08,
                edgeRailOpacity: 0.44,
                braceOpacity: 0.16,
                fractureOpacity: 0,
                pulseScale: 1.02
            )
        case .warningRails:
            return PlaqueTreatmentDescriptor(
                accent: accent,
                routeIdentifier: routeIdentifier,
                emissionBoost: 0.14,
                edgeRailOpacity: 0.62,
                braceOpacity: 0.28,
                fractureOpacity: 0.18,
                pulseScale: 1.04
            )
        case .failureFracture:
            return PlaqueTreatmentDescriptor(
                accent: accent,
                routeIdentifier: routeIdentifier,
                emissionBoost: 0.24,
                edgeRailOpacity: 0.72,
                braceOpacity: 0.54,
                fractureOpacity: 0.62,
                pulseScale: 1.08
            )
        case .retryBraces:
            return PlaqueTreatmentDescriptor(
                accent: accent,
                routeIdentifier: routeIdentifier,
                emissionBoost: 0.2,
                edgeRailOpacity: 0.66,
                braceOpacity: 0.74,
                fractureOpacity: 0.36,
                pulseScale: 1.06
            )
        case .none:
            return .none
        }
    }

    private static func nativeFeedbackRunCueMetadata(
        for cue: CinematicNativeFeedbackCuePlan
    ) -> String? {
        guard let kind = cue.runCueKind else { return nil }
        if let sessionNumber = cue.runCueSessionNumber {
            return "run \(sessionNumber) \(kind.rawValue)"
        }
        return "run \(kind.rawValue)"
    }

    private static func nativeFeedbackSourceCopy(
        for cue: CinematicNativeFeedbackCuePlan,
        runCueMetadata: String?
    ) -> String {
        [
            cue.styleIdentifier,
            cue.sourceIdentifier,
            runCueMetadata
        ].compactMap { $0 }.joined(separator: " ")
    }

    private static func nativeFeedbackArenaMetadata(
        for cue: CinematicNativeFeedbackCuePlan,
        runCueMetadata: String?
    ) -> String {
        if let kind = cue.runCueKind {
            return kind.rawValue
        }
        return runCueMetadata ?? cue.milestoneIdentifier
    }

    private static func nativeFeedbackSystemImageCopy(_ systemImage: String) -> String {
        systemImage
            .split(separator: ".")
            .first
            .map(String.init)
            ?? "symbol"
    }

    private static func cueLayoutDescriptor(
        slot: NarrativeCueSlot,
        anchor: CinematicNarrativeCueAnchor,
        visibility: CinematicNarrativeCueVisibility,
        opacity: Float,
        phaseEnergy: Float,
        influenceFraction: Float,
        hasSecondary: Bool,
        hasGlyph: Bool,
        isIdleUnavailable: Bool
    ) -> CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor {
        let visibilityFraction: Float
        switch visibility {
        case .dim:
            visibilityFraction = 0
        case .visible:
            visibilityFraction = 0.48
        case .featured:
            visibilityFraction = 1
        }

        let position = cueAnchorPosition(for: anchor, slot: slot)
        let facingMode: CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor.FacingMode = slot == .arenaInscription
            ? .floorInscription
            : .arenaCamera
        let glyphSide = glyphSide(for: slot, hasGlyph: hasGlyph)

        let plateWidth: Float
        let plateHeight: Float
        let primaryFontSize: Float
        let secondaryFontSize: Float
        let backingOpacity: Float
        let plateDepth: Float
        let textXOffset: Float
        let primaryYOffset: Float
        let secondaryYOffset: Float

        switch slot {
        case .questPlaque:
            plateWidth = isIdleUnavailable
                ? 2.58
                : 2.78 + visibilityFraction * 0.2 + influenceFraction * 0.14
            plateHeight = hasSecondary ? 0.62 + visibilityFraction * 0.035 : 0.52
            primaryFontSize = 0.132 + visibilityFraction * 0.014 + influenceFraction * 0.006
            secondaryFontSize = 0.07 + visibilityFraction * 0.004
            backingOpacity = isIdleUnavailable
                ? 0.16
                : 0.17 + opacity * 0.17 + phaseEnergy * 0.035 + visibilityFraction * 0.026
            plateDepth = 0.038
            textXOffset = glyphSide == .leading ? 0.18 : 0
            primaryYOffset = hasSecondary ? 0.074 : -0.026
            secondaryYOffset = -0.152
        case .arenaInscription:
            plateWidth = isIdleUnavailable
                ? 3.0
                : 3.34 + visibilityFraction * 0.2 + influenceFraction * 0.12
            plateHeight = 0.34 + visibilityFraction * 0.025
            primaryFontSize = 0.166 + visibilityFraction * 0.016 + influenceFraction * 0.006
            secondaryFontSize = 0.064
            backingOpacity = isIdleUnavailable
                ? 0.1
                : 0.085 + opacity * 0.08 + phaseEnergy * 0.024 + visibilityFraction * 0.016
            plateDepth = 0.018
            textXOffset = glyphSide == .leading ? 0.2 : 0
            primaryYOffset = -0.034
            secondaryYOffset = -0.13
        case .activityBanner:
            plateWidth = isIdleUnavailable
                ? 2.48
                : 2.62 + visibilityFraction * 0.18 + influenceFraction * 0.16
            plateHeight = 0.42 + visibilityFraction * 0.035
            primaryFontSize = 0.128 + visibilityFraction * 0.013 + influenceFraction * 0.006
            secondaryFontSize = 0.064
            backingOpacity = isIdleUnavailable
                ? 0.15
                : 0.15 + opacity * 0.19 + phaseEnergy * 0.04 + visibilityFraction * 0.03
            plateDepth = 0.036
            textXOffset = glyphSide == .trailing ? -0.18 : 0
            primaryYOffset = -0.024
            secondaryYOffset = -0.13
        }

        let horizontalTextInset: Float
        switch slot {
        case .questPlaque:
            horizontalTextInset = hasGlyph ? 0.78 : 0.46
        case .arenaInscription:
            horizontalTextInset = hasGlyph ? 0.86 : 0.42
        case .activityBanner:
            horizontalTextInset = hasGlyph ? 0.74 : 0.42
        }
        let secondaryTextInset: Float = hasGlyph ? horizontalTextInset + 0.18 : 0.58
        let textDepth: Float = slot == .arenaInscription ? 0.024 : 0.03
        let glyphDepth: Float = slot == .arenaInscription ? 0.032 : 0.04

        return CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor(
            anchorPosition: position,
            facingMode: facingMode,
            plateSize: [plateWidth, plateHeight],
            primaryTextWidth: plateWidth - horizontalTextInset,
            secondaryTextWidth: plateWidth - secondaryTextInset,
            primaryFontSize: primaryFontSize,
            secondaryFontSize: secondaryFontSize,
            backingOpacity: backingOpacity,
            glyphSide: glyphSide,
            glyphOffset: glyphOffset(
                side: glyphSide,
                plateWidth: plateWidth,
                plateHeight: plateHeight,
                depth: glyphDepth
            ),
            plateDepth: plateDepth,
            plateZOffset: -plateDepth * 0.58,
            primaryTextOffset: [textXOffset, primaryYOffset, textDepth],
            secondaryTextOffset: [textXOffset, secondaryYOffset, textDepth + 0.004]
        )
    }

    private static func cueAnchorPosition(
        for anchor: CinematicNarrativeCueAnchor,
        slot: NarrativeCueSlot
    ) -> SIMD3<Float> {
        if slot == .arenaInscription {
            switch anchor {
            case .arenaFront:
                return [0, 0.13, 3.12]
            case .arenaRear:
                return [0, 0.13, -3.32]
            case .arenaCenter, .idleArchive:
                return [0, 0.13, 0.72]
            case .fractureGate:
                return [-1.15, 0.13, -2.72]
            case .victoryArch:
                return [0, 0.13, -3.45]
            case .leftScoutPylon, .leftForgePylon, .leftSealPylon:
                return [-1.2, 0.13, 1.15]
            case .rightPylon, .rightHistoryPylon, .rightWarningPylon:
                return [1.2, 0.13, 1.15]
            }
        }

        if slot == .activityBanner {
            switch anchor {
            case .idleArchive:
                return [5.05, 1.16, 3.22]
            case .rightPylon, .arenaCenter, .arenaFront:
                return [5.18, 1.28, 1.74]
            case .rightHistoryPylon, .arenaRear, .victoryArch:
                return [5.32, 1.42, -0.62]
            case .rightWarningPylon, .fractureGate:
                return [5.08, 1.54, -3.02]
            case .leftScoutPylon:
                return [5.05, 1.28, 1.74]
            case .leftForgePylon:
                return [5.24, 1.4, -0.62]
            case .leftSealPylon:
                return [5.05, 1.52, -2.82]
            }
        }

        switch anchor {
        case .idleArchive:
            return [-5.05, 1.08, 3.22]
        case .leftScoutPylon, .rightPylon:
            return [-5.12, 1.16, 1.58]
        case .leftForgePylon, .rightHistoryPylon:
            return [-5.38, 1.2, -0.34]
        case .leftSealPylon, .rightWarningPylon:
            return [-5.02, 1.3, -2.46]
        case .fractureGate:
            return [-3.94, 1.58, -4.04]
        case .victoryArch:
            return [0, 2.08, -4.58]
        case .arenaCenter:
            return [-4.8, 1.18, 0.9]
        case .arenaFront:
            return [-4.95, 1.2, 2.18]
        case .arenaRear:
            return [-4.55, 1.28, -2.18]
        }
    }

    private static func glyphSide(
        for slot: NarrativeCueSlot,
        hasGlyph: Bool
    ) -> CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor.GlyphSide {
        guard hasGlyph else { return .none }
        switch slot {
        case .questPlaque, .arenaInscription:
            return .leading
        case .activityBanner:
            return .trailing
        }
    }

    private static func glyphOffset(
        side: CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor.GlyphSide,
        plateWidth: Float,
        plateHeight: Float,
        depth: Float
    ) -> SIMD3<Float> {
        let inset = min(0.36, max(0.24, plateHeight * 0.72))
        switch side {
        case .none:
            return [0, 0, depth]
        case .leading:
            return [-plateWidth / 2 + inset, 0, depth]
        case .trailing:
            return [plateWidth / 2 - inset, 0, depth]
        }
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

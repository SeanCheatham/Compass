import Foundation

struct CinematicDiagnosticsReport: Equatable {
    var identifier: String
    var repoName: String
    var phase: String
    var immediateTitle: String
    var completedCount: Int
    var planCompass: CinematicPlanCompassPlan?
    var influenceIdentifier: String
    var languageMotif: LanguageMotifSnapshot
    var activityMotif: ActivityMotifSnapshot
    var nativeFeedback: NativeFeedbackSnapshot
    var nativeFeedbackDelivery: NativeFeedbackDeliverySnapshot
    var recoveryCue: RecoveryCueSnapshot
    var stageBeat: StageBeatSnapshot
    var stageEffect: StageEffectSnapshot
    var stageAtmosphere: StageAtmosphereSnapshot
    var stagePhasePolish: StagePhasePolishSnapshot
    var narrativeCue: NarrativeCueSnapshot
    var overlayDisplay: OverlayDisplaySnapshot
    var worldText: WorldTextSnapshot
    var briefing: BriefingSnapshot
    var cameraTuning: CameraTuningSnapshot
    var activityTuning: ActivityTuningSnapshot
    var setDressing: SetDressingSnapshot
    var commitConstellation: CommitConstellationSnapshot
    var idleStoryCycle: IdleStoryCycleSnapshot
    var timelineFocus: TimelineFocusSnapshot
    var runRecap: RunRecapSnapshot
    var runRecapShare: RunRecapShareSnapshot
    var runRecapShareArtifact: RunRecapShareArtifactSnapshot
    var runRecapShareArtifactHistory: RunRecapShareArtifactHistorySnapshot
    var runRecapShareArtifactRollup: RunRecapShareArtifactRollupSnapshot
    var runRecapShareArtifactComparison: RunRecapShareArtifactComparisonSnapshot
    var runRecapShareArtifactPins: RunRecapShareArtifactPinnedReferenceSnapshot
    var runRecapShareArtifactTour: RunRecapShareArtifactTourSnapshot
    var runRecapShareArtifactPreview: RunRecapShareArtifactPreviewSnapshot
    var runRecapShareArtifactCommands: RunRecapShareArtifactCommandSnapshot
    var runRecapSceneFocus: RunRecapSceneFocusSnapshot
    var runRecapEndCard: RunRecapEndCardSnapshot
    var cameraSnapshots: [CameraSnapshot]

    struct LanguageMotifSnapshot: Equatable {
        var identifier: String
        var language: RepositoryLanguage
        var sigilIdentifier: String
        var styleIdentifier: String
        var ambientSpellIdentifier: String
        var phaseBlend: Double
    }

    struct ActivityMotifSnapshot: Equatable {
        var identifier: String
        var eventKindIdentifier: String
        var sigilIdentifier: String
        var styleIdentifier: String
        var tintSourceIdentifier: String?
        var transitionSpellIdentifier: String?
        var ambientOverrideIdentifier: String?
        var usesCommitAmbient: Bool
        var usesSuccessAmbient: Bool
        var shouldShakeOnTransition: Bool
    }

    struct NativeFeedbackSnapshot: Equatable {
        var identifier: String
        var cueIdentifier: String
        var lifecycleIdentifier: String
        var lifecycleStateIdentifier: String
        var lifecycleActiveCueIdentifier: String
        var lifecycleRecentArchiveIdentifiers: [String]
        var lifecycleRecentArchiveCount: Int
        var lifecycleActiveHistoryEntry: NativeFeedbackHistoryEntrySnapshot?
        var lifecycleArchiveHistoryEntries: [NativeFeedbackHistoryEntrySnapshot]
        var lifecycleHistoryEntryCount: Int
        var sourceIdentifier: String
        var styleIdentifier: String
        var milestoneIdentifier: String
        var affectedNarrativeDescriptorIdentifiers: [String]
    }

    struct NativeFeedbackHistoryEntrySnapshot: Equatable {
        var identifier: String
        var cueIdentifier: String
        var lifecycleIdentifier: String
        var sequence: Int
        var stateIdentifier: String
        var reasonIdentifier: String?
        var milestoneIdentifier: String
        var sourceIdentifier: String?
        var styleIdentifier: String?
        var displayDuration: TimeInterval
    }

    struct RecoveryCueSnapshot: Equatable {
        var identifier: String
        var selectedCueIdentifier: String?
        var sessionNumber: Int?
        var kindIdentifier: String
        var severityIdentifier: String?
        var label: String?
        var detail: String?
        var systemImage: String?
        var visualIdentifier: String
        var treatmentIdentifier: String
        var lightFamilyIdentifier: String
        var fractureLightFamilyIdentifier: String
        var symbolIdentifier: String?
        var phaseLightIntensity: Float
        var intensity: Float
        var postureIdentifier: String
        var arenaEffectIdentifier: String
        var fractureOpacity: Float
        var fractureSpread: Float
        var healingOpacity: Float
        var shouldShakeCamera: Bool
        var cameraShakeIdentifier: String?
    }

    struct StageBeatSnapshot: Equatable {
        var identifier: String
        var phaseIdentifier: String
        var kindIdentifier: String
        var cameraShotIdentifier: String
        var lightFamilyIdentifier: String
        var arenaEffectIdentifier: String
        var phaseLightIntensity: Float
        var shouldShakeCamera: Bool
        var shouldRunVictorySurge: Bool
        var shouldRunHistoryChains: Bool
        var activityAccentIdentifier: String
        var activityEventKindIdentifier: String?
        var activityLightFamilyIdentifier: String?
        var activityArenaEffectIdentifier: String?
    }

    struct StageEffectSnapshot: Equatable {
        var identifier: String
        var phaseEffectIdentifier: String
        var phaseSourceIdentifier: String
        var phaseArenaEffectIdentifier: String
        var activityEffectIdentifier: String?
        var activitySourceIdentifier: String?
        var activityArenaEffectIdentifier: String?
        var recoveryEffectIdentifier: String?
        var recoverySourceIdentifier: String?
        var recoveryArenaEffectIdentifier: String?
        var arenaRingIdentifiers: [String]
        var phaseLightPulseIdentifiers: [String]
        var sparkBurstIdentifiers: [String]
        var historyTrailIdentifiers: [String]
        var victoryCadenceIdentifier: String?
        var cameraShakeIdentifiers: [String]
        var arenaRingCount: Int
        var phaseLightPulseCount: Int
        var sparkBurstCount: Int
        var historyTrailCount: Int
        var tuningIdentifier: String
        var recoveryCueIdentifier: String
        var recoveryCueKindIdentifier: String
        var pressureLevelIdentifier: String
        var pressureFraction: Float
        var energy: Float
        var influenceStyleIdentifier: String
        var influenceIntensity: Float
        var influenceFraction: Float
        var activityLightBoost: Float
        var activityLightBoostFraction: Float
        var runePulseScale: Float
        var activityPulseDuration: TimeInterval
        var ringDurationScale: Float
        var ringScaleMultiplier: Float
        var ringOpacityMultiplier: Float
        var colorAlphaMultiplier: Float
        var pulseIntensityMultiplier: Float
        var pulseDurationMultiplier: Float
        var sparkBirthRateMultiplier: Float
        var historyTrailTargetCount: Int
        var cameraShakeMultiplier: Float
        var cameraShakeDurationMultiplier: Float
        var victoryCadenceMultiplier: Float
    }

    struct StageAtmosphereSnapshot: Equatable {
        var identifier: String
        var beatIdentifier: String
        var phaseIdentifier: String
        var activityIdentifier: String
        var pressureLevelIdentifier: String
        var influenceStyleIdentifier: String
        var influenceIntensity: Float
        var pressureFraction: Float
        var influenceFraction: Float
        var energy: Float
        var pressureHaloIdentifier: String
        var pressureHaloRadius: Float
        var pressureHaloOpacity: Float
        var pressureHaloScale: Float
        var pressureHaloColorAlpha: Float
        var atmosphericPulseIdentifier: String
        var atmosphericPulseCadence: TimeInterval
        var atmosphericPulseAmplitude: Float
        var atmosphericPulseOpacity: Float
        var pressureLightingIdentifier: String
        var phaseLightPressureBoost: Float
        var rimLightPressureBoost: Float
        var pressureLightColorAlpha: Float
        var backdropTintIdentifier: String
        var backdropTintRed: Float
        var backdropTintGreen: Float
        var backdropTintBlue: Float
        var backdropTintOpacity: Float
        var backdropTintBlendFraction: Float
        var floorTintIdentifier: String
        var floorTintRed: Float
        var floorTintGreen: Float
        var floorTintBlue: Float
        var floorTintOpacity: Float
        var floorTintBlendFraction: Float
    }

    struct StagePhasePolishSnapshot: Equatable {
        var identifier: String
        var beatIdentifier: String
        var stageEffectTuningIdentifier: String
        var atmosphereIdentifier: String
        var phaseIdentifier: String
        var activityIdentifier: String
        var recoveryCueIdentifier: String
        var recoveryCueKindIdentifier: String
        var influenceIdentifier: String
        var postureIdentifier: String
        var wizardPoseIdentifier: String
        var poseIntensity: Float
        var staffOrbIdentifier: String
        var staffOrbLightFamilyIdentifier: String
        var staffOrbScale: Float
        var staffOrbEmission: Float
        var staffOrbPulseAmplitude: Float
        var sigilEmphasisIdentifier: String
        var sigilOrbitRadius: Float
        var sigilSealEmphasis: Float
        var sigilVictoryEmphasis: Float
        var sigilPulseAmplitude: Float
        var portalBackdropIdentifier: String
        var portalLightFamilyIdentifier: String
        var portalAperture: Float
        var portalScale: Float
        var portalOpacity: Float
        var backdropAperture: Float
        var backdropOpacityBoost: Float
        var fractureRecoveryIdentifier: String
        var fractureLightFamilyIdentifier: String
        var fractureOpacity: Float
        var fractureSpread: Float
        var healingOpacity: Float
        var cadenceIdentifier: String
        var poseCadence: TimeInterval
        var orbPulseCadence: TimeInterval
        var sigilOrbitCadence: TimeInterval
        var fractureCadence: TimeInterval
    }

    struct NarrativeCueSnapshot: Equatable {
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
        var questPlaque: NarrativeCueDescriptorSnapshot
        var arenaInscription: NarrativeCueDescriptorSnapshot
        var activityBanner: NarrativeCueDescriptorSnapshot
    }

    struct OverlayDisplaySnapshot: Equatable {
        var identifier: String
        var modeIdentifier: String
        var visiblePillIdentifiers: [String]
        var hudProminenceIdentifier: String
        var chromeStyleIdentifier: String
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
        var nativeFeedbackCueIdentifier: String
        var nativeFeedbackLifecycleIdentifier: String
        var nativeFeedbackBannerPolicyIdentifier: String
        var showsNativeFeedbackBanner: Bool
    }

    struct NarrativeCueDescriptorSnapshot: Equatable {
        var identifier: String
        var stableID: String
        var text: String
        var secondaryText: String?
        var glyphIdentifier: String?
        var anchorIdentifier: String
        var visibilityIdentifier: String
        var scale: Float
        var opacity: Float
        var lightFamilyIdentifier: String
        var tintFamilyIdentifier: String
        var cadence: TimeInterval
        var plaqueTreatmentIdentifier: String
        var plaqueTreatmentAccentIdentifier: String
        var plaqueTreatmentRouteIdentifier: String
        var plaqueTreatmentRenderRecipeIdentifier: String
        var plaqueTreatmentRenderPrimitiveIdentifiers: [String]
        var plaqueTreatmentRenderPrimitiveCount: Int
        var layout: NarrativeCueLayoutSnapshot
    }

    struct NarrativeCueLayoutSnapshot: Equatable {
        var identifier: String
        var anchorPosition: SIMD3<Float>
        var facingModeIdentifier: String
        var plateWidth: Float
        var plateHeight: Float
        var primaryTextWidth: Float
        var secondaryTextWidth: Float
        var primaryFontSize: Float
        var secondaryFontSize: Float
        var backingOpacity: Float
        var glyphSideIdentifier: String
        var glyphOffset: SIMD3<Float>
        var plateDepth: Float
        var plateZOffset: Float
        var primaryTextOffset: SIMD3<Float>
        var secondaryTextOffset: SIMD3<Float>
    }

    struct WorldTextSnapshot: Equatable {
        var identifier: String
        var questLabel: String
        var arenaCallout: String
        var activityCallout: String
    }

    struct BriefingSnapshot: Equatable {
        var identifier: String
        var title: String
        var detail: String
    }

    struct CameraTuningSnapshot: Equatable {
        var identifier: String
        var orbitScale: Float
        var pullbackScale: Float
        var heightOffset: Float
        var followResponsiveness: Float
        var followFieldOfView: Float
        var driftScale: Float
        var shakeScale: Float
    }

    struct ActivityTuningSnapshot: Equatable {
        var identifier: String
        var pressureLevelIdentifier: String
        var ambientSpawnCadence: TimeInterval
        var ambientEnemyLimit: Int
        var activityLightBoost: Float
        var activityPressureScale: Float
    }

    struct SetDressingSnapshot: Equatable {
        var identifier: String
        var languageArchitectureIdentifier: String
        var activityMarkerIdentifier: String
        var pedestalLayoutIdentifier: String
        var shardFormationIdentifier: String
        var pedestalSlotCount: Int
        var shardSlotCount: Int
        var layoutGeometryCoverageIdentifier: String
        var layoutGeometryIsBounded: Bool
        var pedestalCount: Int
        var flameLightIntensity: Float
        var flameOpacity: Float
        var rimOpacity: Float
        var shardCount: Int
        var shardEmissionOpacity: Float
        var runeIntensityIdentifier: String
        var animationCadenceIdentifier: String
        var flamePulseRate: Float
        var shardBobRate: Float
        var ambientSpawnCadence: TimeInterval
        var ambientEnemyLimit: Int
        var activityLightBoost: Float
        var materialTextureVariantIdentifier: String
        var backdropTextureAssetIdentifier: String
        var arenaTextureAssetIdentifier: String
        var backdropTextureRouteIdentifier: String
        var arenaTextureRouteIdentifier: String
        var textureRoleCoverageIdentifier: String
        var runeMaterialIdentifier: String
        var runeMaterialTreatmentIdentifier: String
        var runeFloorEmissionOpacity: Float
        var runeSegmentOpacityScale: Float
        var arenaAccentOpacityScale: Float
        var backdropTextureName: String
        var arenaTextureName: String
        var usesFallbackTextureAsset: Bool
    }

    struct CommitConstellationSnapshot: Equatable {
        var identifier: String
        var count: Int
        var newestSubject: String?
        var nodeIdentifiers: [String]
        var branchIdentifiers: [String]
        var focusIdentifier: String
        var focusShotIdentifier: String
        var focusLookTarget: SIMD3<Float>
        var usesFallbackFocus: Bool
    }

    struct IdleStoryCycleSnapshot: Equatable {
        var identifier: String
        var isActive: Bool
        var phaseIdentifier: String
        var sourceDescriptorIdentifier: String
        var targetKindIdentifier: String
        var cadence: TimeInterval
        var cameraTreatmentIdentifier: String
        var anchorTreatmentIdentifier: String
        var choreographyIdentifier: String
        var dwellDuration: TimeInterval
        var transitionDurationScale: Double
        var cameraPressureIdentifier: String
        var targetBias: Float
        var comfortDamping: Float
        var shakeHintIdentifier: String
        var pulseHintIdentifier: String
        var suppressionReason: String
        var phaseCopy: String
        var descriptorIdentifier: String
        var cycleSlot: Int
        var phaseIndex: Int
        var diagnosticsWarningBundleIdentifier: String
        var diagnosticsWarningSequence: Int
        var diagnosticsWarningCaptureCount: Int
        var diagnosticsWarningTargetCount: Int
        var diagnosticsWarningWarningCount: Int
        var diagnosticsWarningTargetIdentifiers: [String]
        var diagnosticsWarningIdentifiers: [String]
        var diagnosticsWarningRepeatedIdentifiers: [String]
        var diagnosticsWarningTargetAnchors: [String]
        var diagnosticsWarningRelatedRowAnchors: [String]
    }

    struct TimelineFocusSnapshot: Equatable {
        var identifier: String
        var selectedBeatID: String?
        var isActive: Bool
        var kindIdentifier: String
        var descriptorIdentifier: String
        var label: String?
        var cameraShotIdentifier: String
        var lookTarget: SIMD3<Float>?
        var lightFamilyIdentifier: String
        var arenaEffectIdentifier: String
        var phaseLightIntensity: Float
        var commitNodeIdentifier: String?
        var recoveryTreatmentIdentifier: String?
        var recoveryVisualIdentifier: String?
        var usesFallbackTarget: Bool
    }

    struct RunRecapSnapshot: Equatable {
        var identifier: String
        var availabilityIdentifier: String
        var isAvailable: Bool
        var sessionNumber: Int?
        var title: String
        var detail: String
        var status: String
        var statusIdentifier: String
        var styleIdentifier: String
        var colorIdentifier: String
        var systemImage: String
        var latestCompletedSummary: String
        var newestCommitHighlight: String?
        var completedCount: Int
        var commitHighlightCount: Int
        var eventChipCount: Int
        var eventChipIdentifiers: [String]
        var sourceIdentifier: String?
        var flavorStateIdentifier: String
        var flavorIdentifier: String?
        var flavorSourceIdentifier: String?
        var titleSourceIdentifier: String
    }

    struct RunRecapShareSnapshot: Equatable {
        var identifier: String
        var availabilityIdentifier: String
        var availabilityReason: String
        var isAvailable: Bool
        var recapIdentifier: String
        var recapFocusIdentifier: String?
        var endCardIdentifier: String?
        var title: String
        var detail: String
        var status: String
        var commitHighlight: String?
        var eventSummaries: [String]
        var eventSummaryCount: Int
        var visualDescriptorTokens: [String]
        var visualDescriptorTokenCount: Int
        var text: String
        var textLength: Int
    }

    struct RunRecapShareArtifactSnapshot: Equatable {
        var identifier: String
        var isAvailable: Bool
        var availabilityReason: String
        var sessionNumber: Int?
        var filename: String
        var shareIdentifier: String
        var recapIdentifier: String
        var recapFocusIdentifier: String?
        var endCardIdentifier: String?
        var title: String
        var status: String
        var detail: String
        var commitHighlight: String?
        var eventSummaryCount: Int
        var visualDescriptorTokenCount: Int
        var markdownLength: Int
    }

    struct RunRecapShareArtifactHistorySnapshot: Equatable {
        var identifier: String
        var isAvailable: Bool
        var availabilityReason: String
        var retentionLimit: Int
        var totalCount: Int
        var hiddenCount: Int
        var cleanupCandidateCount: Int
        var hiddenCleanupCandidateCount: Int
        var cleanupCandidateIdentifiers: [String]
        var latestSessionNumber: Int?
        var latestFilename: String?
        var exportIdentifier: String
        var exportMarkdownLength: Int
        var warningCount: Int
        var hiddenWarningCount: Int
        var warningIdentifiers: [String]
        var warningStateIdentifier: String
        var lastCleanupResultIdentifier: String
        var lastCleanupResultStatus: String
    }

    struct RunRecapShareArtifactRollupStatusBucketSnapshot: Equatable {
        var identifier: String
        var label: String
        var count: Int
    }

    struct RunRecapShareArtifactRollupSnapshot: Equatable {
        var identifier: String
        var exportIdentifier: String
        var isAvailable: Bool
        var availabilityReason: String
        var isSearchActive: Bool
        var searchQuerySnippet: String
        var searchQueryFingerprint: String
        var noMatchAvailabilityReason: String?
        var retainedEntryCount: Int
        var totalCount: Int
        var hiddenCount: Int
        var matchingEntryCount: Int
        var unfilteredVisibleCount: Int
        var selectedEntryIdentifier: String?
        var selectedFallbackEntryIdentifier: String?
        var selectedFallbackReasonIdentifier: String
        var sessionRangeLabel: String
        var newestEntryIdentifier: String?
        var newestSessionNumber: Int?
        var newestFilename: String?
        var oldestEntryIdentifier: String?
        var oldestSessionNumber: Int?
        var oldestFilename: String?
        var statusBuckets: [RunRecapShareArtifactRollupStatusBucketSnapshot]
        var statusBucketSummary: String
        var cleanupCandidateCount: Int
        var hiddenCleanupCandidateCount: Int
        var cleanupCandidateIdentifiers: [String]
        var warningStateIdentifier: String
        var warningCount: Int
        var hiddenWarningCount: Int
        var warningIdentifiers: [String]
        var hasWarnings: Bool
        var insightText: String
        var exportTextLength: Int
        var copyLabel: String
        var copyHelp: String
    }

    struct RunRecapShareArtifactSubsetExportSnapshot: Equatable {
        var identifier: String
        var exportIdentifier: String
        var scopeIdentifier: String
        var isAvailable: Bool
        var availabilityReason: String
        var isSearchActive: Bool
        var searchQuerySnippet: String
        var searchQueryFingerprint: String
        var noMatchAvailabilityReason: String?
        var retainedEntryCount: Int
        var totalCount: Int
        var hiddenCount: Int
        var selectedCount: Int
        var filteredCount: Int
        var exportEntryCount: Int
        var unfilteredVisibleCount: Int
        var selectedEntryIdentifier: String?
        var selectedFallbackEntryIdentifier: String?
        var selectedFallbackReasonIdentifier: String
        var exportedEntryIdentifiers: [String]
        var warningStateIdentifier: String
        var warningCount: Int
        var hiddenWarningCount: Int
        var warningIdentifiers: [String]
        var hasWarnings: Bool
        var markdownLength: Int
        var copyLabel: String
        var copyHelp: String
    }

    struct RunRecapShareArtifactComparisonSnapshot: Equatable {
        var identifier: String
        var exportIdentifier: String
        var isAvailable: Bool
        var availabilityReason: String
        var isSearchActive: Bool
        var searchQuerySnippet: String
        var searchQueryFingerprint: String
        var noMatchAvailabilityReason: String?
        var retainedEntryCount: Int
        var totalCount: Int
        var hiddenCount: Int
        var matchingEntryCount: Int
        var unfilteredVisibleCount: Int
        var selectedEntryIdentifier: String?
        var selectedFallbackEntryIdentifier: String?
        var selectedFallbackReasonIdentifier: String
        var compareEntryIdentifier: String?
        var targetModeIdentifier: String
        var targetDirectionIdentifier: String
        var pinnedTargetEntryIdentifier: String?
        var pinnedTargetStateIdentifier: String
        var pinnedTargetUnavailableReasonIdentifier: String?
        var promotedHoldStateIdentifier: String
        var requestedSavedTourHoldEntryIdentifier: String?
        var retainedSavedTourHoldEntryIdentifier: String?
        var filteredSavedTourHoldEntryIdentifier: String?
        var requestedPinnedEntryIdentifiers: [String]
        var retainedPinnedEntryIdentifiers: [String]
        var missingPinnedEntryIdentifiers: [String]
        var filteredPinnedEntryIdentifiers: [String]
        var pinnedEntryCount: Int
        var retainedPinnedEntryCount: Int
        var missingPinnedEntryCount: Int
        var filteredPinnedEntryCount: Int
        var sessionDelta: Int?
        var selectedSessionNumber: Int?
        var compareSessionNumber: Int?
        var selectedFilename: String?
        var compareFilename: String?
        var selectedTitleSnippet: String?
        var compareTitleSnippet: String?
        var selectedStatusSnippet: String?
        var compareStatusSnippet: String?
        var selectedCommitSnippet: String?
        var compareCommitSnippet: String?
        var selectedBodyPreviewText: String?
        var compareBodyPreviewText: String?
        var cleanupCandidateCount: Int
        var hiddenCleanupCandidateCount: Int
        var cleanupCandidateIdentifiers: [String]
        var warningStateIdentifier: String
        var warningCount: Int
        var hiddenWarningCount: Int
        var warningIdentifiers: [String]
        var hasWarnings: Bool
        var exportTextLength: Int
        var copyLabel: String
        var copyHelp: String
    }

    struct RunRecapShareArtifactPinnedReferenceEntrySnapshot: Equatable {
        var identifier: String
        var sessionNumber: Int
        var filename: String
        var titleSnippet: String
        var statusSnippet: String
        var commitSnippet: String?
        var isQuickSelectable: Bool
    }

    struct RunRecapShareArtifactPinnedReferenceSnapshot: Equatable {
        var identifier: String
        var exportIdentifier: String
        var isAvailable: Bool
        var availabilityReason: String
        var isSearchActive: Bool
        var searchQuerySnippet: String
        var searchQueryFingerprint: String
        var noMatchAvailabilityReason: String?
        var retainedEntryCount: Int
        var totalCount: Int
        var hiddenCount: Int
        var matchingEntryCount: Int
        var unfilteredVisibleCount: Int
        var selectedEntryIdentifier: String?
        var selectedEntryIsPinned: Bool
        var selectedPinStateIdentifier: String
        var requestedPinnedEntryIdentifiers: [String]
        var retainedPinnedEntryIdentifiers: [String]
        var missingPinnedEntryIdentifiers: [String]
        var filteredPinnedEntryIdentifiers: [String]
        var quickSelectEntryIdentifiers: [String]
        var pinnedEntryCount: Int
        var retainedPinnedEntryCount: Int
        var missingPinnedEntryCount: Int
        var filteredPinnedEntryCount: Int
        var quickSelectEntryCount: Int
        var references: [RunRecapShareArtifactPinnedReferenceEntrySnapshot]
        var warningStateIdentifier: String
        var warningCount: Int
        var hiddenWarningCount: Int
        var warningIdentifiers: [String]
        var hasWarnings: Bool
        var exportTextLength: Int
        var copyLabel: String
        var copyHelp: String
    }

    struct RunRecapShareArtifactTourSnapshot: Equatable {
        var identifier: String
        var isAvailable: Bool
        var availabilityReason: String
        var stateIdentifier: String
        var selectionSourceIdentifier: String
        var savedTourHoldStateIdentifier: String
        var requestedSavedTourHoldEntryIdentifier: String?
        var retainedSavedTourHoldEntryIdentifier: String?
        var filteredSavedTourHoldEntryIdentifier: String?
        var isSearchActive: Bool
        var searchQuerySnippet: String
        var searchQueryFingerprint: String
        var noMatchAvailabilityReason: String?
        var retainedEntryCount: Int
        var totalCount: Int
        var hiddenCount: Int
        var matchingEntryCount: Int
        var unfilteredVisibleCount: Int
        var selectedEntryIdentifier: String?
        var selectedOrdinal: Int?
        var entryCount: Int
        var rotationSeed: Int
        var sessionNumber: Int?
        var filename: String?
        var titleSnippet: String
        var statusSnippet: String
        var commitSnippet: String?
        var bodyPreviewText: String
        var sessionText: String
        var requestedPinnedEntryIdentifiers: [String]
        var retainedPinnedEntryIdentifiers: [String]
        var missingPinnedEntryIdentifiers: [String]
        var filteredPinnedEntryIdentifiers: [String]
        var pinnedEntryCount: Int
        var retainedPinnedEntryCount: Int
        var missingPinnedEntryCount: Int
        var filteredPinnedEntryCount: Int
        var warningStateIdentifier: String
        var warningCount: Int
        var hiddenWarningCount: Int
        var warningIdentifiers: [String]
        var hasWarnings: Bool
        var shouldDisplay: Bool
    }

    struct RunRecapShareArtifactPreviewSnapshot: Equatable {
        var identifier: String
        var isAvailable: Bool
        var availabilityReason: String
        var isSearchActive: Bool
        var searchQuerySnippet: String
        var searchQueryFingerprint: String
        var matchCount: Int
        var unfilteredVisibleCount: Int
        var noMatchAvailabilityReason: String?
        var selectedEntryIdentifier: String?
        var selectedFallbackEntryIdentifier: String?
        var selectedFallbackReasonIdentifier: String
        var previousEntryIdentifier: String?
        var nextEntryIdentifier: String?
        var selectedIndex: Int?
        var selectedOrdinal: Int?
        var entryCount: Int
        var sessionNumber: Int?
        var filename: String?
        var titleSnippet: String
        var statusSnippet: String
        var commitSnippet: String?
        var pathSnippet: String
        var bodyPreviewText: String
        var markdownLength: Int
        var warningStateIdentifier: String
        var warningCount: Int
        var hasWarnings: Bool
        var selectedExport: RunRecapShareArtifactSubsetExportSnapshot
        var filteredExport: RunRecapShareArtifactSubsetExportSnapshot
    }

    struct RunRecapShareArtifactCommandSectionSnapshot: Equatable {
        var sectionIdentifier: String
        var commandCount: Int
        var enabledCommandCount: Int
        var disabledCommandCount: Int
    }

    struct RunRecapShareArtifactCommandSnapshot: Equatable {
        var identifier: String
        var commandPlanIdentifier: String
        var sourceActionMenuIdentifier: String
        var sourceHistoryIdentifier: String
        var sourcePreviewIdentifier: String
        var sourceRollupIdentifier: String
        var sourceComparisonIdentifier: String
        var sourcePinsIdentifier: String
        var sourceTourIdentifier: String
        var sourceSelectedExportIdentifier: String
        var sourceFilteredExportIdentifier: String
        var actionCount: Int
        var commandCount: Int
        var enabledCommandCount: Int
        var disabledCommandCount: Int
        var sectionCount: Int
        var sections: [RunRecapShareArtifactCommandSectionSnapshot]
        var shortcutIdentifiers: [String]
        var disabledActionKindIdentifiers: [String]
        var omittedActionKindIdentifiers: [String]
        var appLevelShortcutCollisionStateIdentifier: String
        var appLevelShortcutIdentifiers: [String]
        var appLevelShortcutCollisionIdentifiers: [String]
        var historyAvailabilityReason: String
        var previewNoMatchAvailabilityReason: String?
        var selectedExportAvailabilityReason: String
        var filteredExportAvailabilityReason: String
        var rollupAvailabilityReason: String
        var comparisonAvailabilityReason: String
        var comparisonPromotedHoldStateIdentifier: String
        var pinsAvailabilityReason: String
        var missingPinnedEntryCount: Int
        var filteredPinnedEntryCount: Int
        var tourAvailabilityReason: String
        var tourSavedHoldStateIdentifier: String
        var tourFilteredSavedHoldEntryIdentifier: String?
        var tourNoMatchAvailabilityReason: String?
    }

    struct RunRecapSceneFocusSnapshot: Equatable {
        var identifier: String
        var isActive: Bool
        var descriptorIdentifier: String
        var recapIdentifier: String
        var terminalBeatID: String?
        var terminalStatusIdentifier: String
        var terminalStyleIdentifier: String
        var cameraShotIdentifier: String
        var lookTarget: SIMD3<Float>?
        var lightFamilyIdentifier: String
        var arenaEffectIdentifier: String
        var phaseLightIntensity: Float
        var commitNodeIdentifier: String?
        var fallbackTargetIdentifier: String?
        var usesFallbackTarget: Bool
    }

    struct RunRecapEndCardSnapshot: Equatable {
        var identifier: String
        var isActive: Bool
        var descriptorIdentifier: String
        var recapIdentifier: String
        var title: String
        var detail: String
        var status: String
        var titleSourceIdentifier: String
        var flavorStateIdentifier: String
        var flavorIdentifier: String?
        var flavorSourceIdentifier: String?
        var styleIdentifier: String
        var colorIdentifier: String
        var anchorIdentifier: String
        var scale: Float
        var cadence: TimeInterval
        var lightFamilyIdentifier: String
        var tintFamilyIdentifier: String
        var glyphIdentifier: String
        var layoutIdentifier: String
        var plateWidth: Float
        var plateHeight: Float
        var plaqueTreatmentIdentifier: String
        var plaqueTreatmentAccentIdentifier: String
        var plaqueTreatmentRouteIdentifier: String
        var plaqueTreatmentRenderRecipeIdentifier: String
        var plaqueTreatmentRenderPrimitiveIdentifiers: [String]
        var plaqueTreatmentRenderPrimitiveCount: Int
        var hasPinnedComparisonCue: Bool
        var pinnedComparisonCueIdentifier: String?
        var pinnedComparisonCueComparisonIdentifier: String?
        var pinnedComparisonCueComparisonExportIdentifier: String?
        var pinnedComparisonCueModeIdentifier: String
        var pinnedComparisonCueStateIdentifier: String
        var pinnedComparisonCueNoMatchStateIdentifier: String
        var pinnedComparisonCueTargetDirectionIdentifier: String
        var pinnedComparisonCueSelectedEntryIdentifier: String?
        var pinnedComparisonCueTargetEntryIdentifier: String?
        var pinnedComparisonCueSelectedSessionNumber: Int?
        var pinnedComparisonCueTargetSessionNumber: Int?
        var pinnedComparisonCueDeltaLabel: String
        var pinnedComparisonCuePinnedEntryCount: Int
        var pinnedComparisonCueRetainedPinnedEntryCount: Int
        var pinnedComparisonCueMissingPinnedEntryCount: Int
        var pinnedComparisonCueFilteredPinnedEntryCount: Int
        var pinnedComparisonCuePromotedHoldStateIdentifier: String
        var pinnedComparisonCuePromotedHoldEntryIdentifier: String?
        var pinnedComparisonCueWarningStateIdentifier: String
        var pinnedComparisonCueGlyphIdentifier: String
        var pinnedComparisonCueRailTreatmentIdentifier: String
        var pinnedComparisonCueLabel: String
        var pinnedComparisonCueDetail: String
        var pinnedComparisonCueLabelLength: Int
        var pinnedComparisonCueDetailLength: Int
        var pinnedComparisonCueDeltaLabelLength: Int
        var titleLength: Int
        var detailLength: Int
        var statusLength: Int
    }

    struct CameraSnapshot: Equatable {
        var identifier: String
        var shotIdentifier: String
        var position: SIMD3<Float>
        var fieldOfView: Float
        var transitionDuration: TimeInterval
    }
}

struct CinematicVisualSmokeReport: Equatable {
    static let labelMaxCharacters = 32
    static let detailMaxCharacters = 120
    static let warningIdentifierMaxCharacters = 72

    var status: Status
    var warningIdentifiers: [String]
    var checks: [Check]

    enum Status: String, Equatable {
        case pass
        case warning
    }

    struct Check: Identifiable, Equatable {
        var id: String
        var label: String
        var status: Status
        var warningIdentifier: String?
        var warningTarget: WarningTarget?
        var detail: String

        struct WarningTarget: Equatable {
            var id: String
            var targetGroupID: String
            var targetAnchorID: String
            var relatedGroupID: String?
            var relatedRowID: String?
            var label: String
            var detail: String
        }
    }

    init(reports: [CinematicDiagnosticsReport]) {
        let checks = Self.makeChecks(reports: reports)
        self.checks = checks
        warningIdentifiers = checks.compactMap(\.warningIdentifier)
        status = warningIdentifiers.isEmpty ? .pass : .warning
    }

    static func representative() -> CinematicVisualSmokeReport {
        let settingsSamples = [
            CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0),
            CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity),
            CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        ]
        let reports = settingsSamples.flatMap {
            CinematicDiagnostics.representativeSmokeMatrix(influenceSettings: $0)
        }
        let nativeFeedbackReports = CinematicDiagnostics.representativeNativeFeedbackSmokeReports()
        let idleStoryReports = CinematicDiagnostics.representativeIdleStoryCycleSmokeReports()
        let savedArtifactTourReports = CinematicDiagnostics.representativeSavedRecapArtifactTourSmokeReports()
        let pinnedCueReports = CinematicDiagnostics.representativePinnedComparisonCueSmokeReports()
        let recapArtifactCommandReports = CinematicDiagnostics.representativeRunRecapArtifactCommandSmokeReports()
        return CinematicVisualSmokeReport(
            reports: reports + nativeFeedbackReports + idleStoryReports + savedArtifactTourReports
                + pinnedCueReports + recapArtifactCommandReports
        )
    }

    private static func makeChecks(reports: [CinematicDiagnosticsReport]) -> [Check] {
        [
            runRecapArtifactCommandAvailabilityCheck(reports: reports),
            narrativeCueReadabilityCheck(reports: reports),
            overlayFallbackUsageCheck(reports: reports),
            chromeStrengthCheck(reports: reports),
            textBoundsCheck(reports: reports),
            assetAvailabilityCheck(reports: reports),
            textureRoleCoverageCheck(reports: reports),
            languageLayoutCoverageCheck(reports: reports),
            activityMaterialTreatmentCoverageCheck(reports: reports),
            cameraPhaseCoverageCheck(reports: reports),
            pressureInfluenceSpreadCheck(reports: reports),
            recoveryCueCoverageCheck(reports: reports),
            nativeFeedbackCueCoverageCheck(reports: reports),
            nativeFeedbackTreatmentCoverageCheck(reports: reports),
            idleStoryCycleCoverageCheck(reports: reports),
            runRecapSavedArtifactTourCoverageCheck(reports: reports),
            timelineFocusCoverageCheck(reports: reports),
            runRecapSceneFocusCoverageCheck(reports: reports),
            runRecapEndCardCoverageCheck(reports: reports),
            runRecapPinnedComparisonCueCoverageCheck(reports: reports)
        ]
    }

    private static func runRecapArtifactCommandAvailabilityCheck(
        reports: [CinematicDiagnosticsReport]
    ) -> Check {
        let snapshots = reports.map(\.runRecapShareArtifactCommands)
        guard !snapshots.isEmpty else {
            return check(
                id: "run-recap-artifact-command-availability",
                label: "Recap command availability",
                isPassing: false,
                warningIdentifier: "visual-smoke.recap-artifact-commands",
                detail: "no representative reports available"
            )
        }

        let expectedSections = Set(CinematicRunRecapShareArtifactActionMenuPlan.Section.allCases.map(\.rawValue))
        let expectedShortcuts = Set(recapArtifactCommandShortcutIdentifiers())
        let expectedAppLevelShortcuts = Set(recapArtifactAppLevelShortcutIdentifiers())
        let noMatchDisabledActionKinds: Set<String> = [
            "navigatePrevious",
            "navigateNext",
            "revealSelected",
            "copySelectedExport",
            "copyFilteredExport",
            "copyRollupExport",
            "copyComparisonExport"
        ]
        let unavailableDisabledActionKinds: Set<String> = [
            "copyLibraryExport",
            "copySelectedExport"
        ]

        let boundedCount = reports.filter(runRecapShareArtifactCommandsCopyIsBounded).count
        let countIntegrityCount = snapshots.filter { snapshot in
            snapshot.actionCount <= CinematicRunRecapShareArtifactActionMenuPlan.actionLimit
                && snapshot.commandCount <= CinematicRunRecapShareArtifactCommandPlan.commandLimit
                && snapshot.enabledCommandCount + snapshot.disabledCommandCount == snapshot.commandCount
                && snapshot.commandCount + snapshot.omittedActionKindIdentifiers.count == snapshot.actionCount
        }.count
        let sectionCoverageCount = snapshots.filter { snapshot in
            let sectionIdentifiers = Set(snapshot.sections.map(\.sectionIdentifier))
            let sectionCommandCount = snapshot.sections.reduce(0) { $0 + $1.commandCount }
            let sectionEnabledCount = snapshot.sections.reduce(0) { $0 + $1.enabledCommandCount }
            let sectionDisabledCount = snapshot.sections.reduce(0) { $0 + $1.disabledCommandCount }
            return sectionIdentifiers == expectedSections
                && snapshot.sectionCount == expectedSections.count
                && sectionCommandCount == snapshot.commandCount
                && sectionEnabledCount == snapshot.enabledCommandCount
                && sectionDisabledCount == snapshot.disabledCommandCount
        }.count
        let shortcutCoverageCount = snapshots.filter { snapshot in
            Set(snapshot.shortcutIdentifiers) == expectedShortcuts
                && snapshot.shortcutIdentifiers.count == snapshot.commandCount
                && snapshot.shortcutIdentifiers.count == Set(snapshot.shortcutIdentifiers).count
        }.count
        let cleanupOmissionCount = snapshots.filter {
            $0.omittedActionKindIdentifiers == ["cleanupOldArtifacts"]
        }.count
        let cleanupActiveOmitted = reports.contains {
            $0.runRecapShareArtifactHistory.cleanupCandidateCount > 0
                && $0.runRecapShareArtifactCommands.omittedActionKindIdentifiers.contains("cleanupOldArtifacts")
        }
        let collisionClearCount = snapshots.filter { snapshot in
            snapshot.appLevelShortcutCollisionStateIdentifier == "clear"
                && snapshot.appLevelShortcutCollisionIdentifiers.isEmpty
                && Set(snapshot.appLevelShortcutIdentifiers) == expectedAppLevelShortcuts
        }.count
        let correlatedCount = snapshots.filter { snapshot in
            !snapshot.commandPlanIdentifier.isEmpty
                && !snapshot.sourceActionMenuIdentifier.isEmpty
                && snapshot.commandPlanIdentifier != snapshot.sourceActionMenuIdentifier
                && snapshot.commandCount + snapshot.omittedActionKindIdentifiers.count == snapshot.actionCount
        }.count
        let hasAvailable = snapshots.contains {
            $0.historyAvailabilityReason == "available"
                && $0.previewNoMatchAvailabilityReason == nil
                && $0.enabledCommandCount > 0
        }
        let hasUnavailable = snapshots.contains { snapshot in
            snapshot.historyAvailabilityReason != "available"
                && unavailableDisabledActionKinds.isSubset(of: Set(snapshot.disabledActionKindIdentifiers))
        }
        let hasNoMatch = snapshots.contains { snapshot in
            snapshot.previewNoMatchAvailabilityReason == "no-matching-recap-share-artifacts"
                && noMatchDisabledActionKinds.isSubset(of: Set(snapshot.disabledActionKindIdentifiers))
        }
        let hasStalePin = snapshots.contains { $0.missingPinnedEntryCount > 0 }
        let hasFilteredPin = snapshots.contains { $0.filteredPinnedEntryCount > 0 }
        let hasFilteredHold = snapshots.contains {
            $0.tourSavedHoldStateIdentifier == "filtered-hold"
                && $0.tourFilteredSavedHoldEntryIdentifier != nil
        }
        let hasPromotedHold = snapshots.contains {
            $0.comparisonPromotedHoldStateIdentifier == "retained-promoted-hold-target"
        }
        let hasFilteredPromotedHold = snapshots.contains {
            $0.comparisonPromotedHoldStateIdentifier == "filtered-promoted-hold-target"
        }

        let isPassing = hasAvailable
            && hasUnavailable
            && hasNoMatch
            && hasStalePin
            && hasFilteredPin
            && hasFilteredHold
            && hasPromotedHold
            && hasFilteredPromotedHold
            && cleanupActiveOmitted
            && boundedCount == reports.count
            && countIntegrityCount == snapshots.count
            && sectionCoverageCount == snapshots.count
            && shortcutCoverageCount == snapshots.count
            && cleanupOmissionCount == snapshots.count
            && collisionClearCount == snapshots.count
            && correlatedCount == snapshots.count

        return check(
            id: "run-recap-artifact-command-availability",
            label: "Recap command availability",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.recap-artifact-commands",
            detail: [
                hasAvailable ? "available" : "available-missing",
                hasUnavailable ? "unavailable" : "unavailable-missing",
                hasNoMatch ? "no-match" : "no-match-missing",
                hasStalePin && hasFilteredPin ? "stale-pin" : "stale-pin-missing",
                hasFilteredHold ? "filtered-hold" : "filtered-hold-missing",
                hasPromotedHold && hasFilteredPromotedHold ? "promoted-hold" : "promoted-hold-missing",
                cleanupActiveOmitted ? "cleanup-omitted" : "cleanup-missing",
                collisionClearCount == snapshots.count ? "collisions clear" : "collisions \(snapshots.count - collisionClearCount)",
                "bounded \(boundedCount)/\(reports.count)",
                "correlated \(correlatedCount)/\(snapshots.count)"
            ].joined(separator: " "),
            warningTarget: Check.WarningTarget(
                id: "visual-smoke-check-run-recap-artifact-command-availability",
                targetGroupID: "visual-smoke",
                targetAnchorID: "visual-smoke-check-run-recap-artifact-command-availability",
                relatedGroupID: "repository-context",
                relatedRowID: "run-recap-share-artifact-commands",
                label: "Recap command availability",
                detail: "Recap artifact command availability warning"
            )
        )
    }

    private static func narrativeCueReadabilityCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let total = reports.count
        guard total > 0 else {
            return check(
                id: "narrative-cue-readability",
                label: "Narrative cue readability",
                isPassing: false,
                warningIdentifier: "visual-smoke.no-reports",
                detail: "no representative reports available"
            )
        }

        let compactReports = reports.filter { $0.overlayDisplay.modeIdentifier == "compact" }
        let metrics = compactReports.map(readabilityMetrics)
        let readableCount = metrics.filter(\.isReadable).count
        let minimumScale = metrics.map(\.minimumScale).min() ?? 0
        let minimumOpacity = metrics.map(\.minimumOpacity).min() ?? 0
        let minimumFontSize = metrics.map(\.minimumPrimaryFontSize).min() ?? 0
        let minimumBackingOpacity = metrics.map(\.minimumBackingOpacity).min() ?? 0
        let isPassing = !compactReports.isEmpty && readableCount == compactReports.count

        return check(
            id: "narrative-cue-readability",
            label: "Narrative cue readability",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.narrative-readability",
            detail: [
                "compact readable \(readableCount)/\(compactReports.count)",
                "reports \(total)",
                "scale \(fixed(minimumScale))",
                "opacity \(fixed(minimumOpacity))",
                "font \(fixed(minimumFontSize))",
                "backing \(fixed(minimumBackingOpacity))"
            ].joined(separator: " | ")
        )
    }

    private static func overlayFallbackUsageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let modes = Set(reports.map(\.overlayDisplay.modeIdentifier))
        let reasons = Set(reports.map(\.overlayDisplay.reasonIdentifier))
        let requiredModes: Set<String> = ["compact", "full", "fallback"]
        let requiredReasons: Set<String> = [
            "in-world-readable-cues",
            "activity-unavailable",
            "missing-repository"
        ]
        let missingModes = requiredModes.subtracting(modes).sorted()
        let missingReasons = requiredReasons.subtracting(reasons).sorted()
        let isPassing = !reports.isEmpty && missingModes.isEmpty && missingReasons.isEmpty
        let fallbackReasons = reasons.filter { reason in
            reports.contains {
                $0.overlayDisplay.modeIdentifier == "fallback"
                    && $0.overlayDisplay.reasonIdentifier == reason
            }
        }
        .sorted()

        return check(
            id: "overlay-fallback-usage",
            label: "Overlay fallback",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.overlay-coverage",
            detail: [
                "modes \(joined(modes))",
                "fallback \(fallbackReasons.isEmpty ? "none" : joined(fallbackReasons))",
                missingModes.isEmpty ? nil : "missing modes \(missingModes.joined(separator: ","))",
                missingReasons.isEmpty ? nil : "missing reasons \(missingReasons.joined(separator: ","))"
            ].compactMap { $0 }.joined(separator: " | ")
        )
    }

    private static func chromeStrengthCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let styleNames = Set(reports.map { chromeStyleName($0.overlayDisplay.chromeStyleIdentifier) })
        let compactGradients = gradients(for: "compact", in: reports)
        let fullGradients = gradients(for: "full", in: reports)
        let fallbackGradients = gradients(for: "fallback", in: reports)
        let modes = Set(reports.map(\.overlayDisplay.modeIdentifier))
        let hasExpectedModes = ["compact", "full", "fallback"].allSatisfy(modes.contains)
        let stylesMatchModes = reports.allSatisfy { report in
            let styleName = chromeStyleName(report.overlayDisplay.chromeStyleIdentifier)
            switch report.overlayDisplay.modeIdentifier {
            case "compact":
                return styleName.hasPrefix("compact-")
            case "full":
                return styleName.hasPrefix("full-")
            case "fallback":
                return styleName.hasPrefix("fallback-")
            default:
                return false
            }
        }
        let strengthOrdering = compactGradients.maxValue < fullGradients.minValue
            && fullGradients.maxValue <= fallbackGradients.minValue
        let isPassing = !reports.isEmpty
            && !styleNames.contains("")
            && hasExpectedModes
            && stylesMatchModes
            && strengthOrdering

        return check(
            id: "chrome-strength",
            label: "Chrome strength",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.chrome-strength",
            detail: [
                "styles \(joined(styleNames))",
                "gradients c\(range(compactGradients))/f\(range(fullGradients))/b\(range(fallbackGradients))"
            ].joined(separator: " | ")
        )
    }

    private static func textBoundsCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let boundedCount = reports.filter(textIsBounded).count
        let isPassing = !reports.isEmpty && boundedCount == reports.count

        return check(
            id: "text-bounds",
            label: "Text bounds",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.text-bounds",
            detail: "\(boundedCount)/\(reports.count) reports fit world, briefing, and cue copy limits"
        )
    }

    private static func assetAvailabilityCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let availableCount = reports.filter(assetsAreAvailable).count
        let backdropTextures = Set(reports.map(\.setDressing.backdropTextureName))
        let arenaTextures = Set(reports.map(\.setDressing.arenaTextureName))
        let generatedBackdropTextures = Set(
            backdropTextures.filter(CinematicTextureAssetCatalog.isGeneratedBackdropTextureName)
        )
        let generatedArenaTextures = Set(
            arenaTextures.filter(CinematicTextureAssetCatalog.isGeneratedArenaTextureName)
        )
        let packagedGeneratedBackdrops = Set(
            generatedBackdropTextures.filter {
                CinematicTextureAssetCatalog.isPackagedResourceAvailable($0, role: .backdrop)
            }
        )
        let packagedGeneratedArenas = Set(
            generatedArenaTextures.filter {
                CinematicTextureAssetCatalog.isPackagedResourceAvailable($0, role: .arena)
            }
        )
        let isPassing = !reports.isEmpty && availableCount == reports.count

        return check(
            id: "asset-availability",
            label: "Asset availability",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.asset-availability",
            detail: [
                "assets \(availableCount)/\(reports.count)",
                "gen backdrops \(generatedBackdropTextures.count)/\(CinematicTextureAssetCatalog.generatedBackdropNames.count)",
                "gen arenas \(generatedArenaTextures.count)/\(CinematicTextureAssetCatalog.generatedArenaNames.count)",
                "packaged backdrops \(packagedGeneratedBackdrops.count)/\(generatedBackdropTextures.count)",
                "packaged arenas \(packagedGeneratedArenas.count)/\(generatedArenaTextures.count)"
            ].joined(separator: " | ")
        )
    }

    private static func textureRoleCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedBackdropRoutes = CinematicTextureAssetCatalog.expectedRouteIdentifiers(for: .backdrop)
        let expectedArenaRoutes = CinematicTextureAssetCatalog.expectedRouteIdentifiers(for: .arena)
        let backdropRoutes = Set(reports.map(\.setDressing.backdropTextureRouteIdentifier))
        let arenaRoutes = Set(reports.map(\.setDressing.arenaTextureRouteIdentifier))
        let generatedBackdropRoutes = Set(reports.compactMap { report in
            CinematicTextureAssetCatalog.isGeneratedBackdropTextureName(report.setDressing.backdropTextureName)
                ? report.setDressing.backdropTextureRouteIdentifier
                : nil
        })
        let generatedArenaRoutes = Set(reports.compactMap { report in
            CinematicTextureAssetCatalog.isGeneratedArenaTextureName(report.setDressing.arenaTextureName)
                ? report.setDressing.arenaTextureRouteIdentifier
                : nil
        })
        let directRouteCount = reports.filter { !$0.setDressing.usesFallbackTextureAsset }.count
        let isPassing = !reports.isEmpty
            && backdropRoutes.isSuperset(of: expectedBackdropRoutes)
            && generatedBackdropRoutes.isSuperset(of: expectedBackdropRoutes)
            && arenaRoutes.isSuperset(of: expectedArenaRoutes)
            && generatedArenaRoutes.isSuperset(of: expectedArenaRoutes)
            && directRouteCount == reports.count

        return check(
            id: "texture-role-coverage",
            label: "Texture role coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.texture-role-coverage",
            detail: [
                "backdrop \(backdropRoutes.intersection(expectedBackdropRoutes).count)/\(expectedBackdropRoutes.count)",
                "gen backdrop \(generatedBackdropRoutes.intersection(expectedBackdropRoutes).count)/\(expectedBackdropRoutes.count)",
                "arena \(arenaRoutes.intersection(expectedArenaRoutes).count)/\(expectedArenaRoutes.count)",
                "gen arena \(generatedArenaRoutes.intersection(expectedArenaRoutes).count)/\(expectedArenaRoutes.count)",
                "direct \(directRouteCount)/\(reports.count)"
            ].joined(separator: " | ")
        )
    }

    private static func languageLayoutCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedPedestalLayouts = CinematicSetDressingGeometryCatalog.expectedPedestalLayoutIdentifiers
        let expectedShardFormations = CinematicSetDressingGeometryCatalog.expectedShardFormationIdentifiers
        let pedestalLayouts = Set(reports.map(\.setDressing.pedestalLayoutIdentifier))
        let shardFormations = Set(reports.map(\.setDressing.shardFormationIdentifier))
        let completePedestalReports = reports.filter {
            $0.setDressing.pedestalSlotCount == CinematicSetDressingPlan.pedestalCountRange.upperBound
        }.count
        let completeShardReports = reports.filter {
            $0.setDressing.shardSlotCount == CinematicSetDressingPlan.shardCountRange.upperBound
        }.count
        let boundedReports = reports.filter(\.setDressing.layoutGeometryIsBounded).count
        let isPassing = !reports.isEmpty
            && pedestalLayouts.isSuperset(of: expectedPedestalLayouts)
            && shardFormations.isSuperset(of: expectedShardFormations)
            && completePedestalReports == reports.count
            && completeShardReports == reports.count
            && boundedReports == reports.count

        return check(
            id: "language-layout-coverage",
            label: "Language layout coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.language-layout-coverage",
            detail: [
                "pedestals \(pedestalLayouts.intersection(expectedPedestalLayouts).count)/\(expectedPedestalLayouts.count)",
                "shards \(shardFormations.intersection(expectedShardFormations).count)/\(expectedShardFormations.count)",
                "slot maps \(completePedestalReports)/\(completeShardReports)",
                "bounds \(boundedReports)/\(reports.count)"
            ].joined(separator: " | ")
        )
    }

    private static func activityMaterialTreatmentCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedMaterials = CinematicRuneMaterialTreatmentCatalog.expectedRuneMaterialIdentifiers
        let expectedTreatments = CinematicRuneMaterialTreatmentCatalog.expectedTreatmentIdentifiers
        let materials = Set(reports.map(\.setDressing.runeMaterialIdentifier))
        let treatments = Set(reports.map(\.setDressing.runeMaterialTreatmentIdentifier))
        let treatmentValuesInBounds = reports.filter { report in
            CinematicSetDressingPlan.runeFloorEmissionOpacityRange.contains(report.setDressing.runeFloorEmissionOpacity)
                && CinematicSetDressingPlan.runeSegmentOpacityScaleRange.contains(report.setDressing.runeSegmentOpacityScale)
                && CinematicSetDressingPlan.arenaAccentOpacityScaleRange.contains(report.setDressing.arenaAccentOpacityScale)
        }.count
        let isPassing = !reports.isEmpty
            && materials.isSuperset(of: expectedMaterials)
            && treatments.isSuperset(of: expectedTreatments)
            && treatmentValuesInBounds == reports.count

        return check(
            id: "activity-material-treatment",
            label: "Activity material treatment",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.activity-material-treatment",
            detail: [
                "materials \(materials.intersection(expectedMaterials).count)/\(expectedMaterials.count)",
                "treatments \(treatments.intersection(expectedTreatments).count)/\(expectedTreatments.count)",
                "bounds \(treatmentValuesInBounds)/\(reports.count)"
            ].joined(separator: " | ")
        )
    }

    private static func cameraPhaseCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedShots = Set(CinematicCameraShot.allCases.map(\.identifier))
        let expectedEvents = Set(CinematicActivityEventKind.allCases.map(\.rawValue))
        let expectedActivityCaseIDs = Set(CinematicDiagnostics.representativeActivityCases().map(\.identifier))
        let completeCameraReports = reports.filter {
            Set($0.cameraSnapshots.map(\.shotIdentifier)) == expectedShots
        }.count
        let phases = Set(reports.map(\.phase))
        let shotCoverage = Set(reports.flatMap { $0.cameraSnapshots.map(\.shotIdentifier) })
        let eventCoverage = Set(reports.map(\.activityMotif.eventKindIdentifier))
        let activityCaseCoverage = Set(reports.compactMap(activityCaseIdentifier))
        let isPassing = !reports.isEmpty
            && completeCameraReports == reports.count
            && shotCoverage == expectedShots
            && eventCoverage.isSuperset(of: expectedEvents)
            && activityCaseCoverage.isSuperset(of: expectedActivityCaseIDs)

        return check(
            id: "camera-phase-coverage",
            label: "Camera/phase coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.camera-phase-coverage",
            detail: [
                "shots \(shotCoverage.count)/\(expectedShots.count)",
                "complete \(completeCameraReports)/\(reports.count)",
                "phases \(phases.count)",
                "activity cases \(activityCaseCoverage.count)/\(expectedActivityCaseIDs.count)"
            ].joined(separator: " | ")
        )
    }

    private static func pressureInfluenceSpreadCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedPressure = Set(["clean", "light", "moderate", "heavy"])
        let effectPressure = Set(reports.map(\.stageEffect.pressureLevelIdentifier))
        let atmospherePressure = Set(reports.map(\.stageAtmosphere.pressureLevelIdentifier))
        let activityPressure = Set(reports.map(\.activityTuning.pressureLevelIdentifier))
        let influenceStyles = Set(reports.map(\.stageEffect.influenceStyleIdentifier))
        let pressureFractions = reports.map(\.stageEffect.pressureFraction)
        let influenceFractions = reports.map(\.stageEffect.influenceFraction)
        let pressureRange = valueRange(pressureFractions)
        let influenceRange = valueRange(influenceFractions)
        let isPassing = !reports.isEmpty
            && effectPressure.isSuperset(of: expectedPressure)
            && atmospherePressure.isSuperset(of: expectedPressure)
            && activityPressure.isSuperset(of: expectedPressure)
            && influenceStyles == Set(CinematicInfluenceSettings.CameraStyle.allCases.map(\.rawValue))
            && pressureRange.hasSpread
            && influenceRange.hasSpread

        return check(
            id: "pressure-influence-spread",
            label: "Pressure/influence spread",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.pressure-influence-spread",
            detail: [
                "pressure \(joined(effectPressure)) \(range(pressureRange))",
                "influence \(joined(influenceStyles)) \(range(influenceRange))"
            ].joined(separator: " | ")
        )
    }

    private static func recoveryCueCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedKinds = Set(["none", "failedVerify", "dirtyWorktree", "promotionFailed"])
        let expectedTreatments = Set(["none", "verify-failure", "dirty-cleanup", "promotion-branch"])
        let kinds = Set(reports.map(\.recoveryCue.kindIdentifier))
        let treatments = Set(reports.map(\.recoveryCue.treatmentIdentifier))
        let lights = Set(reports.map(\.recoveryCue.lightFamilyIdentifier))
        let symbols = Set(reports.compactMap(\.recoveryCue.symbolIdentifier))
        let cueReports = reports.filter { $0.recoveryCue.kindIdentifier != "none" }
        let distinctEffects = Set(cueReports.compactMap(\.stageEffect.recoveryArenaEffectIdentifier))
        let isPassing = !reports.isEmpty
            && kinds.isSuperset(of: expectedKinds)
            && treatments.isSuperset(of: expectedTreatments)
            && lights.isSuperset(of: ["edit", "failure", "git"])
            && symbols.isSuperset(of: ["verify-fracture-seal", "edit-amber-cleanup", "git-failure-branch"])
            && distinctEffects.isSuperset(of: ["charge", "activity-pulse", "history-chains"])

        return check(
            id: "recovery-cue-coverage",
            label: "Recovery cue coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.recovery-cue-coverage",
            detail: [
                "kinds \(joined(kinds))",
                "effects \(joined(distinctEffects))"
            ].joined(separator: " | ")
        )
    }

    private static func nativeFeedbackCueCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let activeReports = reports.filter {
            $0.nativeFeedback.cueIdentifier != "none"
                && $0.nativeFeedback.lifecycleStateIdentifier == "active"
        }
        let expectedStyles = Set(["verify", "warning", "failure"])
        let styles = Set(activeReports.map(\.nativeFeedback.styleIdentifier))
        let sourceFamilies = Set(activeReports.compactMap(nativeFeedbackSourceFamily))
        let affectedDescriptors = Set(activeReports.flatMap(\.nativeFeedback.affectedNarrativeDescriptorIdentifiers))
        let expectedDescriptors = Set([
            "narrative.quest.plaque",
            "narrative.arena.inscription",
            "narrative.activity.banner"
        ])
        let anchorRoutes = Set(activeReports.flatMap(nativeFeedbackAnchorRouteIdentifiers))
        let expectedAnchorRoutes = Set(["seal", "warning", "fracture"])
        let visibleBannerReports = activeReports.filter {
            $0.overlayDisplay.showsNativeFeedbackBanner
                && $0.overlayDisplay.nativeFeedbackBannerPolicyIdentifier == "visible"
        }.count
        let consistentActiveReports = activeReports.filter(nativeFeedbackActiveRoutesAreConsistent).count
        let expiredArchivedReports = reports.filter(nativeFeedbackExpiredLifecycleIsArchived).count

        let isPassing = !activeReports.isEmpty
            && styles.isSuperset(of: expectedStyles)
            && sourceFamilies.isSuperset(of: ["native", "run-cue"])
            && affectedDescriptors.isSuperset(of: expectedDescriptors)
            && anchorRoutes.isSuperset(of: expectedAnchorRoutes)
            && visibleBannerReports == activeReports.count
            && consistentActiveReports == activeReports.count
            && expiredArchivedReports > 0

        return check(
            id: "native-feedback-cue-coverage",
            label: "Native feedback coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.native-feedback-cue-coverage",
            detail: [
                "active \(activeReports.count)",
                "styles \(styles.intersection(expectedStyles).count)/\(expectedStyles.count)",
                "sources \(joined(sourceFamilies))",
                "desc \(affectedDescriptors.intersection(expectedDescriptors).count)/\(expectedDescriptors.count)",
                "routes \(joined(anchorRoutes))",
                "visible \(visibleBannerReports)/\(activeReports.count)",
                "life \(consistentActiveReports)/\(activeReports.count)",
                "expired \(expiredArchivedReports)"
            ].joined(separator: "|")
        )
    }

    private static func nativeFeedbackTreatmentCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let activeReports = reports.filter {
            $0.nativeFeedback.cueIdentifier != "none"
                && $0.nativeFeedback.lifecycleStateIdentifier == "active"
        }
        let expectedPairs = nativeFeedbackTreatmentExpectations
        let expectedAccents = Set(expectedPairs.map(\.accentIdentifier))
        let expectedRoutes = Set(expectedPairs.map(\.routeIdentifier))
        let expectedPairIdentifiers = Set(expectedPairs.map(\.pairIdentifier))
        let observedAccents = Set(activeReports.map(\.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier))
        let observedRoutes = Set(activeReports.map(\.narrativeCue.questPlaque.plaqueTreatmentRouteIdentifier))
        let observedPairIdentifiers = Set(activeReports.compactMap(nativeFeedbackTreatmentPairIdentifier))
        let expectedReportCount = activeReports.filter(nativeFeedbackTreatmentMatchesExpectedPair).count
        let consistentSurfaceCount = activeReports.filter(nativeFeedbackTreatmentSurfacesMatch).count
        let meaningfulParameterCount = activeReports.filter(nativeFeedbackTreatmentParametersAreMeaningful).count
        let primitiveSetCount = activeReports.filter(nativeFeedbackTreatmentPrimitivesMatchExpected).count

        let isPassing = !activeReports.isEmpty
            && observedAccents.isSuperset(of: expectedAccents)
            && observedRoutes.isSuperset(of: expectedRoutes)
            && observedPairIdentifiers.isSuperset(of: expectedPairIdentifiers)
            && expectedReportCount == activeReports.count
            && consistentSurfaceCount == activeReports.count
            && meaningfulParameterCount == activeReports.count
            && primitiveSetCount == activeReports.count

        return check(
            id: "native-feedback-treatment-coverage",
            label: "Native feedback treatment",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.native-feedback-treatment-coverage",
            detail: [
                "active \(activeReports.count)",
                "accents \(observedAccents.intersection(expectedAccents).count)/\(expectedAccents.count)",
                "routes \(observedRoutes.intersection(expectedRoutes).count)/\(expectedRoutes.count)",
                "pairs \(observedPairIdentifiers.intersection(expectedPairIdentifiers).count)/\(expectedPairIdentifiers.count)",
                "surfaces \(consistentSurfaceCount)/\(activeReports.count)",
                "params \(meaningfulParameterCount)/\(activeReports.count)",
                "prims \(primitiveSetCount)/\(activeReports.count)"
            ].joined(separator: "|")
        )
    }

    private static func idleStoryCycleCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedPhases = Set(
            CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases.map(\.rawValue)
        )
        let activeReports = reports.filter(\.idleStoryCycle.isActive)
        let emptyCount = reports.filter { !$0.idleStoryCycle.isActive }.count
        let phases = Set(activeReports.map(\.idleStoryCycle.phaseIdentifier))
        let sourceRouteCount = activeReports.filter {
            $0.idleStoryCycle.sourceDescriptorIdentifier != "none"
                && !$0.idleStoryCycle.sourceDescriptorIdentifier.isEmpty
        }.count
        let cameraTreatmentCount = activeReports.filter {
            $0.idleStoryCycle.cameraTreatmentIdentifier != "none"
        }.count
        let anchorTreatmentCount = activeReports.filter {
            $0.idleStoryCycle.anchorTreatmentIdentifier != "none"
        }.count
        let choreographyRouteCount = activeReports.filter {
            $0.idleStoryCycle.choreographyIdentifier != "none"
                && !$0.idleStoryCycle.choreographyIdentifier.isEmpty
        }.count
        let cameraPressureCount = activeReports.filter {
            $0.idleStoryCycle.cameraPressureIdentifier != "none"
                && !$0.idleStoryCycle.cameraPressureIdentifier.isEmpty
        }.count
        let boundedCopyCount = activeReports.filter {
            !$0.idleStoryCycle.phaseCopy.isEmpty
                && $0.idleStoryCycle.phaseCopy.count <= CinematicIdleStoryCyclePlan.phaseCopyMaxCharacters
        }.count
        let cadenceCount = activeReports.filter {
            CinematicIdleStoryCyclePlan.cadenceRange.contains($0.idleStoryCycle.cadence)
        }.count
        let dwellCount = activeReports.filter {
            CinematicIdleStoryCyclePlan.dwellDurationRange.contains($0.idleStoryCycle.dwellDuration)
        }.count
        let transitionScaleCount = activeReports.filter {
            CinematicIdleStoryCyclePlan.transitionDurationScaleRange.contains(
                $0.idleStoryCycle.transitionDurationScale
            )
        }.count
        let targetBiasCount = activeReports.filter {
            CinematicIdleStoryCyclePlan.targetBiasRange.contains($0.idleStoryCycle.targetBias)
        }.count
        let comfortDampingCount = activeReports.filter {
            CinematicIdleStoryCyclePlan.comfortDampingRange.contains($0.idleStoryCycle.comfortDamping)
        }.count
        let distinctChoreographyCount = Set(activeReports.map(\.idleStoryCycle.choreographyIdentifier)).count
        let distinctCameraPressureCount = Set(activeReports.map(\.idleStoryCycle.cameraPressureIdentifier)).count
        let distinctTimingCount = Set(
            activeReports.map {
                [
                    fixed($0.idleStoryCycle.cadence),
                    fixed($0.idleStoryCycle.dwellDuration),
                    fixed($0.idleStoryCycle.transitionDurationScale),
                    fixed($0.idleStoryCycle.targetBias)
                ].joined(separator: "/")
            }
        ).count
        let orderedPhaseDetail = CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases
            .map(\.rawValue)
            .filter(phases.contains)
            .joined(separator: "/")
        let featuredPhaseDetail = [
            "commit-constellation",
            "timeline-focus",
            "native-feedback-plaque",
            "diagnostics-warning-pulse"
        ].filter(phases.contains).joined(separator: "/")
        let expectedDistinctRoutes = expectedPhases.count
        let isPassing = !reports.isEmpty
            && !activeReports.isEmpty
            && emptyCount > 0
            && phases.isSuperset(of: expectedPhases)
            && sourceRouteCount == activeReports.count
            && cameraTreatmentCount == activeReports.count
            && anchorTreatmentCount == activeReports.count
            && choreographyRouteCount == activeReports.count
            && cameraPressureCount == activeReports.count
            && boundedCopyCount == activeReports.count
            && cadenceCount == activeReports.count
            && dwellCount == activeReports.count
            && transitionScaleCount == activeReports.count
            && targetBiasCount == activeReports.count
            && comfortDampingCount == activeReports.count
            && distinctChoreographyCount >= expectedDistinctRoutes
            && distinctCameraPressureCount >= expectedDistinctRoutes
            && distinctTimingCount >= expectedDistinctRoutes
        let detail = isPassing
            ? [
                "routes \(sourceRouteCount)/\(activeReports.count)",
                "phases \(phases.count)/\(expectedPhases.count)",
                featuredPhaseDetail,
                "c\(distinctChoreographyCount)",
                "t\(distinctTimingCount)",
                "p\(distinctCameraPressureCount)"
            ].joined(separator: " ")
            : [
                "routes \(sourceRouteCount)/\(activeReports.count)",
                "choreo \(distinctChoreographyCount)/\(expectedDistinctRoutes)",
                "timing \(distinctTimingCount)/\(expectedDistinctRoutes)",
                "pressure \(distinctCameraPressureCount)/\(expectedDistinctRoutes)",
                "phases \(orderedPhaseDetail)"
            ].joined(separator: " ")

        return check(
            id: "idle-story-cycle-coverage",
            label: "Idle story cycle",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.idle-story-cycle",
            detail: detail
        )
    }

    private static func runRecapSavedArtifactTourCoverageCheck(
        reports: [CinematicDiagnosticsReport]
    ) -> Check {
        let displayReports = reports.filter(\.runRecapShareArtifactTour.shouldDisplay)
        let activeIdleTourReports = reports.filter {
            $0.idleStoryCycle.phaseIdentifier == "saved-recap-artifact-tour"
        }
        let states = Set(displayReports.map(\.runRecapShareArtifactTour.stateIdentifier))
        let sources = Set(displayReports.map(\.runRecapShareArtifactTour.selectionSourceIdentifier))
        let holdStates = Set(displayReports.map(\.runRecapShareArtifactTour.savedTourHoldStateIdentifier))
        let noMatchCount = displayReports.filter {
            $0.runRecapShareArtifactTour.noMatchAvailabilityReason == "no-matching-recap-share-artifacts"
        }.count
        let warningCount = displayReports.filter(\.runRecapShareArtifactTour.hasWarnings).count
        let boundedCount = reports.filter(runRecapSavedArtifactTourIsBounded).count
        let idleRouteCount = activeIdleTourReports.filter {
            $0.idleStoryCycle.sourceDescriptorIdentifier != "none"
                && $0.idleStoryCycle.targetKindIdentifier.contains("saved-recap-artifact")
                && $0.idleStoryCycle.cameraPressureIdentifier == "archive-tour"
        }.count
        let isPassing = !reports.isEmpty
            && !displayReports.isEmpty
            && !activeIdleTourReports.isEmpty
            && sources.isSuperset(of: ["recent", "pinned", "held"])
            && states.isSuperset(of: [
                "recent",
                "pinned",
                "held",
                "filtered-pin",
                "filtered-hold",
                "no-match",
                "missing-pin",
                "missing-hold",
                "recent-warning"
            ])
            && holdStates.isSuperset(of: ["none", "held", "filtered-hold", "missing-hold"])
            && noMatchCount > 0
            && warningCount > 0
            && boundedCount == reports.count
            && idleRouteCount == activeIdleTourReports.count
        return check(
            id: "run-recap-saved-artifact-tour",
            label: "Saved artifact tour",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.saved-artifact-tour",
            detail: [
                "recent",
                "pinned",
                "held",
                "filtered-pin",
                "filtered-hold",
                "no-match \(noMatchCount)",
                "missing-pin",
                "missing-hold",
                "warnings \(warningCount)",
                "bounded \(boundedCount)/\(reports.count)"
            ].joined(separator: " ")
        )
    }

    private static func timelineFocusCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let expectedKinds = Set(["none", "plan", "develop", "verify", "outcome", "commit", "recovery", "failed-verify"])
        let kinds = Set(reports.map(\.timelineFocus.kindIdentifier))
        let shots = Set(reports.map(\.timelineFocus.cameraShotIdentifier))
        let lights = Set(reports.map(\.timelineFocus.lightFamilyIdentifier))
        let recoveryTreatments = Set(reports.compactMap(\.timelineFocus.recoveryTreatmentIdentifier))
        let commitNodeCount = reports.compactMap(\.timelineFocus.commitNodeIdentifier).count
        let fallbackCount = reports.filter(\.timelineFocus.usesFallbackTarget).count
        let isPassing = !reports.isEmpty
            && kinds.isSuperset(of: expectedKinds)
            && shots.isSuperset(of: ["none", "wide", "cast-prep", "overhead", "victory", "commit-constellation", "failure"])
            && lights.isSuperset(of: ["none", "scan", "shell", "verify", "git", "failure"])
            && recoveryTreatments.isSuperset(of: ["verify-failure", "dirty-cleanup", "promotion-branch"])
            && commitNodeCount > 0

        return check(
            id: "timeline-focus-coverage",
            label: "Timeline focus coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.timeline-focus-coverage",
            detail: [
                "kinds \(joined(kinds))",
                "shots \(joined(shots))",
                "recovery \(joined(recoveryTreatments))",
                "commit nodes \(commitNodeCount)",
                "fallbacks \(fallbackCount)"
            ].joined(separator: " | ")
        )
    }

    private static func runRecapSceneFocusCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let activeReports = reports.filter(\.runRecapSceneFocus.isActive)
        let emptyCount = reports.filter { !$0.runRecapSceneFocus.isActive }.count
        let styles = Set(activeReports.map(\.runRecapSceneFocus.terminalStyleIdentifier))
        let shots = Set(activeReports.map(\.runRecapSceneFocus.cameraShotIdentifier))
        let lights = Set(activeReports.map(\.runRecapSceneFocus.lightFamilyIdentifier))
        let effects = Set(activeReports.map(\.runRecapSceneFocus.arenaEffectIdentifier))
        let descriptorCount = Set(activeReports.map(\.runRecapSceneFocus.descriptorIdentifier)).count
        let commitNodeCount = activeReports.compactMap(\.runRecapSceneFocus.commitNodeIdentifier).count
        let fallbackCount = activeReports.filter(\.runRecapSceneFocus.usesFallbackTarget).count
        let lookTargetCount = activeReports.compactMap(\.runRecapSceneFocus.lookTarget).count
        let isPassing = !reports.isEmpty
            && !activeReports.isEmpty
            && emptyCount > 0
            && styles.isSuperset(of: ["success", "failure", "warning"])
            && shots.isSuperset(of: ["victory", "failure", "wide"])
            && lights.isSuperset(of: ["verify", "failure", "pressure"])
            && effects.isSuperset(of: ["victory", "charge", "activity-pulse"])
            && descriptorCount > 0
            && commitNodeCount > 0
            && fallbackCount > 0
            && lookTargetCount == activeReports.count

        return check(
            id: "run-recap-focus-coverage",
            label: "Run recap focus coverage",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.run-recap-focus-coverage",
            detail: [
                "active \(activeReports.count)",
                "empty \(emptyCount)",
                "styles \(slashJoined(styles))",
                "shots \(slashJoined(shots))",
                "l/e \(lights.count)/\(effects.count)",
                "commit nodes \(commitNodeCount) fallbacks \(fallbackCount)"
            ].joined(separator: " ")
        )
    }

    private static func runRecapEndCardCoverageCheck(reports: [CinematicDiagnosticsReport]) -> Check {
        let activeReports = reports.filter(\.runRecapEndCard.isActive)
        let emptyCount = reports.filter { !$0.runRecapEndCard.isActive }.count
        let styles = Set(activeReports.map(\.runRecapEndCard.styleIdentifier))
        let titleSources = Set(activeReports.map(\.runRecapEndCard.titleSourceIdentifier))
        let flavorStates = Set(activeReports.map(\.runRecapEndCard.flavorStateIdentifier))
        let anchors = Set(activeReports.map(\.runRecapEndCard.anchorIdentifier))
        let treatments = Set(activeReports.map(\.runRecapEndCard.plaqueTreatmentAccentIdentifier))
        let glyphs = Set(activeReports.map(\.runRecapEndCard.glyphIdentifier))
        let boundedCount = reports.filter(runRecapEndCardCopyIsBounded).count
        let isPassing = !reports.isEmpty
            && !activeReports.isEmpty
            && emptyCount > 0
            && styles.isSuperset(of: ["success", "failure", "warning"])
            && titleSources.isSuperset(of: ["deterministic", "generated"])
            && flavorStates.isSuperset(of: ["deterministic", "applied"])
            && anchors.isSuperset(of: ["victory-arch", "fracture-gate", "right-warning-pylon"])
            && treatments.isSuperset(of: ["verify-seal", "failure-fracture", "warning-rails"])
            && glyphs.isSuperset(of: ["recap.success.seal", "recap.failure.fracture", "recap.warning.rails"])
            && boundedCount == reports.count

        return check(
            id: "run-recap-end-card-coverage",
            label: "Run recap end card",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.run-recap-end-card",
            detail: [
                "active \(activeReports.count) empty \(emptyCount)",
                "bounded \(boundedCount)/\(reports.count)",
                "styles \(slashJoined(styles))",
                "titles \(slashJoined(titleSources))",
                "flavors \(slashJoined(flavorStates))",
                "treat \(treatments.count)"
            ].joined(separator: " ")
        )
    }

    private static func runRecapPinnedComparisonCueCoverageCheck(
        reports: [CinematicDiagnosticsReport]
    ) -> Check {
        let activeEndCardReports = reports.filter(\.runRecapEndCard.isActive)
        let activeCueReports = activeEndCardReports.filter(\.runRecapEndCard.hasPinnedComparisonCue)
        let inactiveCueCount = activeEndCardReports.filter {
            $0.runRecapEndCard.pinnedComparisonCueStateIdentifier == "inactive"
        }.count
        let states = Set(activeEndCardReports.map(\.runRecapEndCard.pinnedComparisonCueStateIdentifier))
        let noMatchStates = Set(activeEndCardReports.map(\.runRecapEndCard.pinnedComparisonCueNoMatchStateIdentifier))
        let modes = Set(activeEndCardReports.map(\.runRecapEndCard.pinnedComparisonCueModeIdentifier))
        let glyphs = Set(activeCueReports.map(\.runRecapEndCard.pinnedComparisonCueGlyphIdentifier))
        let rails = Set(activeCueReports.map(\.runRecapEndCard.pinnedComparisonCueRailTreatmentIdentifier))
        let boundedCount = reports.filter(runRecapEndCardPinnedComparisonCueIsBounded).count
        let isPassing = !reports.isEmpty
            && !activeCueReports.isEmpty
            && inactiveCueCount > 0
            && modes.contains("pinned_reference")
            && states.isSuperset(of: [
                "inactive",
                "visible-pinned-target",
                "filtered-pinned-target",
                "selected-only-pinned-recap-share-artifact",
                "no-selected-recap-share-artifact",
                "pinned-recap-share-artifacts-missing"
            ])
            && noMatchStates.contains("no-matching-recap-share-artifacts")
            && glyphs.isSuperset(of: [
                "pin.bridge.active",
                "pin.bridge.filtered",
                "hold.pin.bridge.active",
                "hold.pin.bridge.filtered"
            ])
            && rails.isSuperset(of: [
                "pin-bridge-rail",
                "filtered-pin-rail",
                "promoted-hold-rail",
                "filtered-promoted-hold-rail"
            ])
            && boundedCount == reports.count

        return check(
            id: "run-recap-pinned-comparison-cue",
            label: "Pinned comparison cue",
            isPassing: isPassing,
            warningIdentifier: "visual-smoke.run-recap-pinned-cue",
            detail: [
                "active\(activeCueReports.count)",
                "inactive\(inactiveCueCount)",
                states.contains("selected-only-pinned-recap-share-artifact") ? "selected-only" : "selected-only-missing",
                noMatchStates.contains("no-matching-recap-share-artifacts") ? "no-match" : "no-match-missing",
                states.contains("pinned-recap-share-artifacts-missing") ? "stale" : "stale-missing",
                states.contains("filtered-pinned-target") ? "filtered-pin" : "filtered-pin-missing",
                glyphs.contains("hold.pin.bridge.active") ? "promoted-hold" : "promoted-hold-missing",
                glyphs.contains("hold.pin.bridge.filtered")
                    ? "filtered-promoted-hold"
                    : "filtered-promoted-hold-missing",
                "bounded \(boundedCount)/\(reports.count)"
            ].joined(separator: " ")
        )
    }

    private struct ReadabilityMetrics {
        var isReadable: Bool
        var minimumScale: Float
        var minimumOpacity: Float
        var minimumPrimaryFontSize: Float
        var minimumBackingOpacity: Float
    }

    private struct NumericRange {
        var minValue: Float
        var maxValue: Float

        var hasSpread: Bool {
            maxValue > minValue
        }
    }

    private struct NativeFeedbackTreatmentExpectation {
        var sourceIdentifier: String
        var accentIdentifier: String
        var routeIdentifier: String
        var primitiveIdentifiers: [String]

        var pairIdentifier: String {
            "\(accentIdentifier)/\(routeIdentifier)"
        }

        var primitiveSetIdentifier: String {
            primitiveIdentifiers.isEmpty ? "none" : primitiveIdentifiers.joined(separator: ",")
        }
    }

    private struct NativeFeedbackTreatmentParameters {
        var accentIdentifier: String
        var routeIdentifier: String
        var emissionBoost: Float
        var edgeRailOpacity: Float
        var braceOpacity: Float
        var fractureOpacity: Float
        var pulseScale: Float

        var valuesAreBounded: Bool {
            (Float(0)...Float(0.42)).contains(emissionBoost)
                && (Float(0)...Float(0.9)).contains(edgeRailOpacity)
                && (Float(0)...Float(0.9)).contains(braceOpacity)
                && (Float(0)...Float(0.9)).contains(fractureOpacity)
                && (Float(0.96)...Float(1.12)).contains(pulseScale)
        }

        init?(_ identifier: String) {
            let pieces = identifier.split(separator: "|").map(String.init)
            guard let accentIdentifier = pieces.first,
                  accentIdentifier != "none",
                  let routePiece = pieces.first(where: { $0.hasPrefix("route:") })
            else {
                return nil
            }

            func tokenValue(_ prefix: String) -> Float? {
                guard let piece = pieces.first(where: { $0.hasPrefix(prefix) }) else {
                    return nil
                }
                return Float(String(piece.dropFirst(prefix.count)))
            }

            let routeIdentifier = String(routePiece.dropFirst("route:".count))
            guard !routeIdentifier.isEmpty,
                  routeIdentifier != "none",
                  let emissionBoost = tokenValue("emit"),
                  let edgeRailOpacity = tokenValue("rails"),
                  let braceOpacity = tokenValue("braces"),
                  let fractureOpacity = tokenValue("fracture"),
                  let pulseScale = tokenValue("pulse")
            else {
                return nil
            }

            self.accentIdentifier = accentIdentifier
            self.routeIdentifier = routeIdentifier
            self.emissionBoost = emissionBoost
            self.edgeRailOpacity = edgeRailOpacity
            self.braceOpacity = braceOpacity
            self.fractureOpacity = fractureOpacity
            self.pulseScale = pulseScale
        }

        func hasMeaningfulValues(for accentIdentifier: String) -> Bool {
            guard valuesAreBounded,
                  self.accentIdentifier == accentIdentifier,
                  emissionBoost > 0,
                  edgeRailOpacity > 0,
                  braceOpacity > 0,
                  pulseScale > 1
            else {
                return false
            }

            switch accentIdentifier {
            case "verify-seal":
                return fractureOpacity == 0
            case "warning-rails", "failure-fracture", "retry-braces":
                return fractureOpacity > 0
            default:
                return false
            }
        }
    }

    private static let nativeFeedbackTreatmentExpectations = [
        NativeFeedbackTreatmentExpectation(
            sourceIdentifier: "native:verifyStarted",
            accentIdentifier: "verify-seal",
            routeIdentifier: "verifyStarted.verify",
            primitiveIdentifiers: ["rail.top", "rail.bottom", "seal.left", "seal.right"]
        ),
        NativeFeedbackTreatmentExpectation(
            sourceIdentifier: "run-cue:11:dirtyWorktree",
            accentIdentifier: "warning-rails",
            routeIdentifier: "developRetrying.warning.dirtyWorktree",
            primitiveIdentifiers: ["rail.top", "rail.bottom", "warning.left", "warning.right"]
        ),
        NativeFeedbackTreatmentExpectation(
            sourceIdentifier: "native:postChecksFailed",
            accentIdentifier: "failure-fracture",
            routeIdentifier: "postChecksFailed.failure",
            primitiveIdentifiers: ["rail.top", "rail.bottom", "fracture.diagonal.a", "fracture.diagonal.b"]
        ),
        NativeFeedbackTreatmentExpectation(
            sourceIdentifier: "run-cue:7:failedVerify",
            accentIdentifier: "retry-braces",
            routeIdentifier: "developRetrying.failure.failedVerify",
            primitiveIdentifiers: ["rail.top", "rail.bottom", "retry.brace.left", "retry.brace.right", "retry.cross"]
        )
    ]

    private static func recapArtifactCommandShortcutIdentifiers() -> [String] {
        recapArtifactCommandActionKinds.compactMap {
            CinematicRunRecapShareArtifactCommandPlanner.shortcut(for: $0)?.identifier
        }
    }

    private static func recapArtifactAppLevelShortcutIdentifiers() -> [String] {
        typealias Shortcut = CinematicRunRecapShareArtifactCommandPlan.Shortcut
        return [
            Shortcut(key: .o, modifiers: [.command]),
            Shortcut(key: .r, modifiers: [.command]),
            Shortcut(key: .returnKey, modifiers: [.command])
        ].map(\.identifier)
    }

    private static let recapArtifactCommandActionKinds: [CinematicRunRecapShareArtifactActionMenuPlan.ActionKind] = [
        .navigatePrevious,
        .navigateNext,
        .revealSelected,
        .copySelectedExport,
        .copyFilteredExport,
        .copyLibraryExport,
        .copyRollupExport,
        .copyComparisonExport,
        .copyPinnedExport,
        .copyTourExport,
        .toggleComparisonTargetMode,
        .toggleSelectedPin,
        .toggleTourHold,
        .toggleSelectedTourHold,
        .promoteTourHold
    ]

    private static func readabilityMetrics(_ report: CinematicDiagnosticsReport) -> ReadabilityMetrics {
        let descriptors = narrativeCueDescriptors(report)
        let minimumScale = descriptors.map(\.scale).min() ?? 0
        let minimumOpacity = descriptors.map(\.opacity).min() ?? 0
        let minimumPrimaryFontSize = descriptors.map(\.layout.primaryFontSize).min() ?? 0
        let minimumBackingOpacity = descriptors.map(\.layout.backingOpacity).min() ?? 0
        let hasReadableText = descriptors.allSatisfy {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.visibilityIdentifier != "dim"
        }
        let hasReadableLayout = descriptors.allSatisfy {
            $0.layout.plateWidth > 0
                && $0.layout.plateHeight > 0
                && $0.layout.primaryTextWidth > 0
                && $0.layout.primaryFontSize > 0
        }
        let isReadable = descriptors.count == 3
            && hasReadableText
            && hasReadableLayout
            && minimumScale >= CinematicNarrativeCueReadabilitySignals.readableScaleThreshold
            && minimumOpacity >= CinematicNarrativeCueReadabilitySignals.readableOpacityThreshold
            && minimumPrimaryFontSize >= CinematicNarrativeCueReadabilitySignals.readablePrimaryFontSizeThreshold
            && minimumBackingOpacity >= CinematicNarrativeCueReadabilitySignals.readableBackingOpacityThreshold

        return ReadabilityMetrics(
            isReadable: isReadable,
            minimumScale: minimumScale,
            minimumOpacity: minimumOpacity,
            minimumPrimaryFontSize: minimumPrimaryFontSize,
            minimumBackingOpacity: minimumBackingOpacity
        )
    }

    private static func narrativeCueDescriptors(
        _ report: CinematicDiagnosticsReport
    ) -> [CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot] {
        [
            report.narrativeCue.questPlaque,
            report.narrativeCue.arenaInscription,
            report.narrativeCue.activityBanner
        ]
    }

    private static func textIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        string(report.worldText.questLabel, maxCharacters: CinematicWorldTextService.questLabelMaxCharacters)
            && string(report.worldText.arenaCallout, maxCharacters: CinematicWorldTextService.arenaCalloutMaxCharacters)
            && string(report.worldText.activityCallout, maxCharacters: CinematicWorldTextService.activityCalloutMaxCharacters)
            && wordCount(report.worldText.questLabel) <= CinematicWorldTextService.questLabelMaxWords
            && wordCount(report.worldText.arenaCallout) <= CinematicWorldTextService.arenaCalloutMaxWords
            && wordCount(report.worldText.activityCallout) <= CinematicWorldTextService.activityCalloutMaxWords
            && string(report.briefing.title, maxCharacters: CinematicBriefingService.titleMaxCharacters)
            && string(report.briefing.detail, maxCharacters: CinematicBriefingService.detailMaxCharacters)
            && cueTextIsBounded(
                report.narrativeCue.questPlaque,
                maxCharacters: CinematicWorldTextService.questLabelMaxCharacters,
                maxWords: CinematicWorldTextService.questLabelMaxWords
            )
            && cueTextIsBounded(
                report.narrativeCue.arenaInscription,
                maxCharacters: CinematicWorldTextService.arenaCalloutMaxCharacters,
                maxWords: CinematicWorldTextService.arenaCalloutMaxWords
            )
            && cueTextIsBounded(
                report.narrativeCue.activityBanner,
                maxCharacters: CinematicWorldTextService.activityCalloutMaxCharacters,
                maxWords: CinematicWorldTextService.activityCalloutMaxWords
            )
            && (report.narrativeCue.questPlaque.secondaryText?.count ?? 0)
                <= CinematicBriefingService.titleMaxCharacters
            && runRecapShareCopyIsBounded(report)
            && runRecapShareArtifactCopyIsBounded(report)
            && runRecapShareArtifactHistoryCopyIsBounded(report)
            && runRecapShareArtifactRollupCopyIsBounded(report)
            && runRecapShareArtifactComparisonCopyIsBounded(report)
            && runRecapShareArtifactPinsCopyIsBounded(report)
            && runRecapShareArtifactTourCopyIsBounded(report)
            && runRecapShareArtifactPreviewCopyIsBounded(report)
            && runRecapShareArtifactCommandsCopyIsBounded(report)
            && runRecapEndCardCopyIsBounded(report)
    }

    private static func runRecapShareCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapShare
        return string(snapshot.identifier, maxCharacters: CinematicRunRecapSharePlan.identifierMaxCharacters)
            && string(snapshot.title, maxCharacters: CinematicRunRecapPlan.titleLimit)
            && string(snapshot.detail, maxCharacters: CinematicRunRecapPlan.detailLimit)
            && string(snapshot.status, maxCharacters: CinematicRunRecapPlan.statusLimit)
            && string(snapshot.text, maxCharacters: CinematicRunRecapSharePlan.textMaxCharacters)
            && snapshot.textLength == snapshot.text.count
            && snapshot.eventSummaryCount == snapshot.eventSummaries.count
            && snapshot.eventSummaryCount <= CinematicRunRecapSharePlan.eventSummaryLimit
            && snapshot.eventSummaries.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapSharePlan.eventSummaryMaxCharacters)
            }
            && snapshot.visualDescriptorTokenCount == snapshot.visualDescriptorTokens.count
            && snapshot.visualDescriptorTokenCount <= CinematicRunRecapSharePlan.visualDescriptorTokenLimit
            && snapshot.visualDescriptorTokens.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapSharePlan.visualDescriptorTokenMaxCharacters)
            }
    }

    private static func runRecapShareArtifactCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapShareArtifact
        return string(snapshot.identifier, maxCharacters: CinematicRunRecapShareArtifactPlan.identifierMaxCharacters)
            && string(snapshot.filename, maxCharacters: CinematicRunRecapShareArtifactPlan.filenameMaxCharacters)
            && string(snapshot.title, maxCharacters: CinematicRunRecapPlan.titleLimit)
            && string(snapshot.detail, maxCharacters: CinematicRunRecapPlan.detailLimit)
            && string(snapshot.status, maxCharacters: CinematicRunRecapPlan.statusLimit)
            && snapshot.markdownLength <= CinematicRunRecapShareArtifactPlan.markdownMaxCharacters
    }

    private static func runRecapShareArtifactHistoryCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapShareArtifactHistory
        return string(
            snapshot.identifier,
            maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
        )
            && string(
                snapshot.exportIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            )
            && (snapshot.latestFilename?.count ?? 0)
                <= CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
            && snapshot.exportMarkdownLength
                <= CinematicRunRecapShareArtifactHistoryPlan.combinedMarkdownMaxCharacters
            && snapshot.warningIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.cleanupCandidateIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && string(
                snapshot.lastCleanupResultIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactCleanupResult.identifierMaxCharacters
            )
    }

    private static func runRecapShareArtifactRollupCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapShareArtifactRollup
        return string(
            snapshot.identifier,
            maxCharacters: CinematicRunRecapShareArtifactRollupPlan.identifierMaxCharacters
        )
            && string(
                snapshot.exportIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactRollupPlan.identifierMaxCharacters
            )
            && string(
                snapshot.searchQuerySnippet,
                maxCharacters: CinematicRunRecapShareArtifactRollupPlan.searchQuerySnippetMaxCharacters
            )
            && snapshot.searchQueryFingerprint.count
                <= CinematicRunRecapShareArtifactRollupPlan.identifierMaxCharacters
            && (snapshot.noMatchAvailabilityReason?.count ?? 0)
                <= CinematicRunRecapShareArtifactRollupPlan.snippetMaxCharacters
            && (snapshot.selectedEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.selectedFallbackEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && snapshot.selectedFallbackReasonIdentifier.count
                <= CinematicRunRecapShareArtifactRollupPlan.snippetMaxCharacters
            && (snapshot.newestEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.oldestEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.newestFilename?.count ?? 0)
                <= CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
            && (snapshot.oldestFilename?.count ?? 0)
                <= CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
            && string(
                snapshot.sessionRangeLabel,
                maxCharacters: CinematicRunRecapShareArtifactRollupPlan.snippetMaxCharacters
            )
            && snapshot.statusBuckets.allSatisfy {
                string($0.identifier, maxCharacters: CinematicRunRecapShareArtifactRollupPlan.snippetMaxCharacters)
                    && string($0.label, maxCharacters: CinematicRunRecapShareArtifactRollupPlan.snippetMaxCharacters)
            }
            && string(
                snapshot.statusBucketSummary,
                maxCharacters: CinematicRunRecapShareArtifactRollupPlan.statusBucketSummaryMaxCharacters
            )
            && snapshot.cleanupCandidateIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.warningIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && string(
                snapshot.insightText,
                maxCharacters: CinematicRunRecapShareArtifactRollupPlan.insightTextMaxCharacters
            )
            && snapshot.exportTextLength
                <= CinematicRunRecapShareArtifactRollupPlan.exportTextMaxCharacters
            && string(
                snapshot.copyLabel,
                maxCharacters: CinematicRunRecapShareArtifactRollupPlan.copyLabelMaxCharacters
            )
            && string(
                snapshot.copyHelp,
                maxCharacters: CinematicRunRecapShareArtifactRollupPlan.copyHelpMaxCharacters
            )
    }

    private static func runRecapShareArtifactComparisonCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapShareArtifactComparison
        return string(
            snapshot.identifier,
            maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.identifierMaxCharacters
        )
            && string(
                snapshot.exportIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.identifierMaxCharacters
            )
            && string(
                snapshot.searchQuerySnippet,
                maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.searchQuerySnippetMaxCharacters
            )
            && snapshot.searchQueryFingerprint.count
                <= CinematicRunRecapShareArtifactComparisonPlan.identifierMaxCharacters
            && (snapshot.noMatchAvailabilityReason?.count ?? 0)
                <= CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            && (snapshot.selectedEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.selectedFallbackEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && snapshot.selectedFallbackReasonIdentifier.count
                <= CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            && (snapshot.compareEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && string(
                snapshot.targetModeIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            )
            && string(
                snapshot.targetDirectionIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            )
            && (snapshot.pinnedTargetEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && string(
                snapshot.pinnedTargetStateIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            )
            && (snapshot.pinnedTargetUnavailableReasonIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            && string(
                snapshot.promotedHoldStateIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            )
            && (snapshot.requestedSavedTourHoldEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.retainedSavedTourHoldEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.filteredSavedTourHoldEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && snapshot.requestedPinnedEntryIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.retainedPinnedEntryIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.missingPinnedEntryIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.filteredPinnedEntryIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && (snapshot.selectedFilename?.count ?? 0)
                <= CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
            && (snapshot.compareFilename?.count ?? 0)
                <= CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
            && (snapshot.selectedTitleSnippet?.count ?? 0)
                <= CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            && (snapshot.compareTitleSnippet?.count ?? 0)
                <= CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            && (snapshot.selectedStatusSnippet?.count ?? 0)
                <= CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            && (snapshot.compareStatusSnippet?.count ?? 0)
                <= CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            && (snapshot.selectedCommitSnippet?.count ?? 0)
                <= CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            && (snapshot.compareCommitSnippet?.count ?? 0)
                <= CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            && (snapshot.selectedBodyPreviewText?.count ?? 0)
                <= CinematicRunRecapShareArtifactComparisonPlan.bodyPreviewMaxCharacters
            && (snapshot.compareBodyPreviewText?.count ?? 0)
                <= CinematicRunRecapShareArtifactComparisonPlan.bodyPreviewMaxCharacters
            && snapshot.cleanupCandidateIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.warningIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.exportTextLength
                <= CinematicRunRecapShareArtifactComparisonPlan.exportTextMaxCharacters
            && string(
                snapshot.copyLabel,
                maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.copyLabelMaxCharacters
            )
            && string(
                snapshot.copyHelp,
                maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.copyHelpMaxCharacters
            )
    }

    private static func runRecapShareArtifactPinsCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapShareArtifactPins
        return string(
            snapshot.identifier,
            maxCharacters: CinematicRunRecapShareArtifactPinnedReferencePlan.identifierMaxCharacters
        )
            && string(
                snapshot.exportIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactPinnedReferencePlan.identifierMaxCharacters
            )
            && string(
                snapshot.searchQuerySnippet,
                maxCharacters: CinematicRunRecapShareArtifactPinnedReferencePlan.searchQuerySnippetMaxCharacters
            )
            && snapshot.searchQueryFingerprint.count
                <= CinematicRunRecapShareArtifactPinnedReferencePlan.identifierMaxCharacters
            && (snapshot.noMatchAvailabilityReason?.count ?? 0)
                <= CinematicRunRecapShareArtifactPinnedReferencePlan.snippetMaxCharacters
            && (snapshot.selectedEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && snapshot.selectedPinStateIdentifier.count
                <= CinematicRunRecapShareArtifactPinnedReferencePlan.snippetMaxCharacters
            && snapshot.requestedPinnedEntryIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.retainedPinnedEntryIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.missingPinnedEntryIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.filteredPinnedEntryIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.quickSelectEntryIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.references.allSatisfy { reference in
                string(
                    reference.identifier,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
                    && reference.filename.count <= CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
                    && string(
                        reference.titleSnippet,
                        maxCharacters: CinematicRunRecapShareArtifactPinnedReferencePlan.snippetMaxCharacters
                    )
                    && string(
                        reference.statusSnippet,
                        maxCharacters: CinematicRunRecapShareArtifactPinnedReferencePlan.snippetMaxCharacters
                    )
                    && (reference.commitSnippet?.count ?? 0)
                        <= CinematicRunRecapShareArtifactPinnedReferencePlan.snippetMaxCharacters
            }
            && snapshot.warningIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.exportTextLength
                <= CinematicRunRecapShareArtifactPinnedReferencePlan.exportTextMaxCharacters
            && string(
                snapshot.copyLabel,
                maxCharacters: CinematicRunRecapShareArtifactPinnedReferencePlan.copyLabelMaxCharacters
            )
            && string(
                snapshot.copyHelp,
                maxCharacters: CinematicRunRecapShareArtifactPinnedReferencePlan.copyHelpMaxCharacters
            )
    }

    private static func runRecapShareArtifactTourCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapShareArtifactTour
        return string(
            snapshot.identifier,
            maxCharacters: CinematicRunRecapShareArtifactTourPlan.identifierMaxCharacters
        )
            && string(
                snapshot.stateIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
            )
            && string(
                snapshot.selectionSourceIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
            )
            && string(
                snapshot.savedTourHoldStateIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
            )
            && (snapshot.requestedSavedTourHoldEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.retainedSavedTourHoldEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.filteredSavedTourHoldEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && string(
                snapshot.searchQuerySnippet,
                maxCharacters: CinematicRunRecapShareArtifactTourPlan.searchQuerySnippetMaxCharacters
            )
            && snapshot.searchQueryFingerprint.count
                <= CinematicRunRecapShareArtifactTourPlan.identifierMaxCharacters
            && (snapshot.noMatchAvailabilityReason?.count ?? 0)
                <= CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
            && (snapshot.selectedEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.filename?.count ?? 0)
                <= CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
            && string(
                snapshot.titleSnippet,
                maxCharacters: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
            )
            && string(
                snapshot.statusSnippet,
                maxCharacters: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
            )
            && (snapshot.commitSnippet?.count ?? 0)
                <= CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
            && string(
                snapshot.bodyPreviewText,
                maxCharacters: CinematicRunRecapShareArtifactTourPlan.bodyPreviewMaxCharacters
            )
            && string(
                snapshot.sessionText,
                maxCharacters: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
            )
            && snapshot.requestedPinnedEntryIdentifiers.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters)
            }
            && snapshot.retainedPinnedEntryIdentifiers.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters)
            }
            && snapshot.missingPinnedEntryIdentifiers.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters)
            }
            && snapshot.filteredPinnedEntryIdentifiers.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters)
            }
            && snapshot.warningIdentifiers.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters)
            }
    }

    private static func runRecapShareArtifactPreviewCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapShareArtifactPreview
        return string(
            snapshot.identifier,
            maxCharacters: CinematicRunRecapShareArtifactPreviewBrowserPlan.identifierMaxCharacters
        )
            && string(
                snapshot.searchQuerySnippet,
                maxCharacters: CinematicRunRecapShareArtifactPreviewBrowserPlan.searchQuerySnippetMaxCharacters
            )
            && snapshot.searchQueryFingerprint.count
                <= CinematicRunRecapShareArtifactPreviewBrowserPlan.identifierMaxCharacters
            && (snapshot.noMatchAvailabilityReason?.count ?? 0)
                <= CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
            && (snapshot.selectedEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.selectedFallbackEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && snapshot.selectedFallbackReasonIdentifier.count
                <= CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
            && (snapshot.previousEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.nextEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.filename?.count ?? 0)
                <= CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
            && string(
                snapshot.titleSnippet,
                maxCharacters: CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
            )
            && string(
                snapshot.statusSnippet,
                maxCharacters: CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
            )
            && (snapshot.commitSnippet?.count ?? 0)
                <= CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
            && string(
                snapshot.pathSnippet,
                maxCharacters: CinematicRunRecapShareArtifactPreviewBrowserPlan.pathSnippetMaxCharacters
            )
            && string(
                snapshot.bodyPreviewText,
                maxCharacters: CinematicRunRecapShareArtifactPreviewBrowserPlan.bodyPreviewMaxCharacters
            )
            && runRecapShareArtifactSubsetExportCopyIsBounded(snapshot.selectedExport)
            && runRecapShareArtifactSubsetExportCopyIsBounded(snapshot.filteredExport)
    }

    private static func runRecapShareArtifactCommandsCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapShareArtifactCommands
        return string(
            snapshot.identifier,
            maxCharacters: CinematicRunRecapShareArtifactCommandPlan.identifierMaxCharacters
        )
            && string(
                snapshot.commandPlanIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactCommandPlan.identifierMaxCharacters
            )
            && string(
                snapshot.sourceActionMenuIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactActionMenuPlan.identifierMaxCharacters
            )
            && string(
                snapshot.sourceHistoryIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            )
            && string(
                snapshot.sourcePreviewIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactPreviewBrowserPlan.identifierMaxCharacters
            )
            && string(
                snapshot.sourceRollupIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactRollupPlan.identifierMaxCharacters
            )
            && string(
                snapshot.sourceComparisonIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.identifierMaxCharacters
            )
            && string(
                snapshot.sourcePinsIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactPinnedReferencePlan.identifierMaxCharacters
            )
            && string(
                snapshot.sourceTourIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactTourPlan.identifierMaxCharacters
            )
            && string(
                snapshot.sourceSelectedExportIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters
            )
            && string(
                snapshot.sourceFilteredExportIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters
            )
            && snapshot.actionCount <= CinematicRunRecapShareArtifactActionMenuPlan.actionLimit
            && snapshot.commandCount <= CinematicRunRecapShareArtifactCommandPlan.commandLimit
            && snapshot.enabledCommandCount <= snapshot.commandCount
            && snapshot.disabledCommandCount <= snapshot.commandCount
            && snapshot.enabledCommandCount + snapshot.disabledCommandCount == snapshot.commandCount
            && snapshot.sectionCount == snapshot.sections.count
            && snapshot.sectionCount <= CinematicRunRecapShareArtifactActionMenuPlan.Section.allCases.count
            && snapshot.sections.allSatisfy { section in
                string(
                    section.sectionIdentifier,
                    maxCharacters: CinematicRunRecapShareArtifactCommandPlan.identifierMaxCharacters
                )
                    && section.enabledCommandCount <= section.commandCount
                    && section.disabledCommandCount <= section.commandCount
                    && section.enabledCommandCount + section.disabledCommandCount == section.commandCount
            }
            && snapshot.shortcutIdentifiers.count <= CinematicRunRecapShareArtifactCommandPlan.commandLimit
            && snapshot.shortcutIdentifiers.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapShareArtifactCommandPlan.identifierMaxCharacters)
            }
            && snapshot.disabledActionKindIdentifiers.count
                <= CinematicRunRecapShareArtifactActionMenuPlan.actionLimit
            && snapshot.disabledActionKindIdentifiers.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapShareArtifactCommandPlan.identifierMaxCharacters)
            }
            && snapshot.omittedActionKindIdentifiers.count
                <= CinematicRunRecapShareArtifactActionMenuPlan.actionLimit
            && snapshot.omittedActionKindIdentifiers.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapShareArtifactCommandPlan.identifierMaxCharacters)
            }
            && snapshot.appLevelShortcutIdentifiers.count == 3
            && snapshot.appLevelShortcutIdentifiers.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapShareArtifactCommandPlan.identifierMaxCharacters)
            }
            && snapshot.appLevelShortcutCollisionIdentifiers.count <= snapshot.appLevelShortcutIdentifiers.count
            && snapshot.appLevelShortcutCollisionIdentifiers.allSatisfy {
                string($0, maxCharacters: CinematicRunRecapShareArtifactCommandPlan.identifierMaxCharacters)
            }
            && string(
                snapshot.appLevelShortcutCollisionStateIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactCommandPlan.identifierMaxCharacters
            )
            && string(
                snapshot.historyAvailabilityReason,
                maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
            )
            && (snapshot.previewNoMatchAvailabilityReason?.count ?? 0)
                <= CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
            && string(
                snapshot.selectedExportAvailabilityReason,
                maxCharacters: CinematicRunRecapShareArtifactSubsetExportPlan.snippetMaxCharacters
            )
            && string(
                snapshot.filteredExportAvailabilityReason,
                maxCharacters: CinematicRunRecapShareArtifactSubsetExportPlan.snippetMaxCharacters
            )
            && string(
                snapshot.rollupAvailabilityReason,
                maxCharacters: CinematicRunRecapShareArtifactRollupPlan.snippetMaxCharacters
            )
            && string(
                snapshot.comparisonAvailabilityReason,
                maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            )
            && string(
                snapshot.comparisonPromotedHoldStateIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
            )
            && string(
                snapshot.pinsAvailabilityReason,
                maxCharacters: CinematicRunRecapShareArtifactPinnedReferencePlan.snippetMaxCharacters
            )
            && string(
                snapshot.tourAvailabilityReason,
                maxCharacters: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
            )
            && string(
                snapshot.tourSavedHoldStateIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
            )
            && (snapshot.tourFilteredSavedHoldEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.tourNoMatchAvailabilityReason?.count ?? 0)
                <= CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
    }

    private static func runRecapShareArtifactSubsetExportCopyIsBounded(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareArtifactSubsetExportSnapshot
    ) -> Bool {
        string(
            snapshot.identifier,
            maxCharacters: CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters
        )
            && string(
                snapshot.exportIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters
            )
            && string(
                snapshot.scopeIdentifier,
                maxCharacters: CinematicRunRecapShareArtifactSubsetExportPlan.snippetMaxCharacters
            )
            && string(
                snapshot.searchQuerySnippet,
                maxCharacters: CinematicRunRecapShareArtifactSubsetExportPlan.searchQuerySnippetMaxCharacters
            )
            && snapshot.searchQueryFingerprint.count
                <= CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters
            && (snapshot.noMatchAvailabilityReason?.count ?? 0)
                <= CinematicRunRecapShareArtifactSubsetExportPlan.snippetMaxCharacters
            && (snapshot.selectedEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && (snapshot.selectedFallbackEntryIdentifier ?? "").count
                <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            && snapshot.selectedFallbackReasonIdentifier.count
                <= CinematicRunRecapShareArtifactSubsetExportPlan.snippetMaxCharacters
            && snapshot.exportedEntryIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.warningIdentifiers.allSatisfy {
                string(
                    $0,
                    maxCharacters: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                )
            }
            && snapshot.markdownLength
                <= CinematicRunRecapShareArtifactSubsetExportPlan.markdownMaxCharacters
            && string(
                snapshot.copyLabel,
                maxCharacters: CinematicRunRecapShareArtifactSubsetExportPlan.labelMaxCharacters
            )
            && string(
                snapshot.copyHelp,
                maxCharacters: CinematicRunRecapShareArtifactSubsetExportPlan.helpMaxCharacters
            )
    }

    private static func runRecapEndCardCopyIsBounded(_ report: CinematicDiagnosticsReport) -> Bool {
        let snapshot = report.runRecapEndCard
        guard snapshot.isActive else {
            return snapshot.titleLength == 0
                && snapshot.detailLength == 0
                && snapshot.statusLength == 0
        }

        return string(snapshot.title, maxCharacters: CinematicRunRecapEndCardPlan.titleMaxCharacters)
            && string(snapshot.detail, maxCharacters: CinematicRunRecapEndCardPlan.detailMaxCharacters)
            && string(snapshot.status, maxCharacters: CinematicRunRecapEndCardPlan.statusMaxCharacters)
            && snapshot.titleLength == snapshot.title.count
            && snapshot.detailLength == snapshot.detail.count
            && snapshot.statusLength == snapshot.status.count
            && (!snapshot.hasPinnedComparisonCue
                || (
                    string(
                        snapshot.pinnedComparisonCueLabel,
                        maxCharacters: CinematicRunRecapEndCardPlan.pinnedComparisonLabelMaxCharacters
                    )
                    && string(
                        snapshot.pinnedComparisonCueDetail,
                        maxCharacters: CinematicRunRecapEndCardPlan.pinnedComparisonDetailMaxCharacters
                    )
                    && string(
                        snapshot.pinnedComparisonCueDeltaLabel,
                        maxCharacters: CinematicRunRecapEndCardPlan.pinnedComparisonDeltaLabelMaxCharacters
                    )
                    && string(
                        snapshot.pinnedComparisonCuePromotedHoldStateIdentifier,
                        maxCharacters: CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
                    )
                    && (snapshot.pinnedComparisonCuePromotedHoldEntryIdentifier ?? "").count
                        <= CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
                    && snapshot.pinnedComparisonCueLabelLength == snapshot.pinnedComparisonCueLabel.count
                    && snapshot.pinnedComparisonCueDetailLength == snapshot.pinnedComparisonCueDetail.count
                    && snapshot.pinnedComparisonCueDeltaLabelLength == snapshot.pinnedComparisonCueDeltaLabel.count
                ))
    }

    private static func runRecapEndCardPinnedComparisonCueIsBounded(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        runRecapEndCardCopyIsBounded(report)
    }

    private static func runRecapSavedArtifactTourIsBounded(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        runRecapShareArtifactTourCopyIsBounded(report)
    }

    private static func cueTextIsBounded(
        _ descriptor: CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot,
        maxCharacters: Int,
        maxWords: Int
    ) -> Bool {
        string(descriptor.text, maxCharacters: maxCharacters)
            && wordCount(descriptor.text) <= maxWords
    }

    private static func assetsAreAvailable(_ report: CinematicDiagnosticsReport) -> Bool {
        let identifiersArePresent = [
            report.setDressing.identifier,
            report.setDressing.languageArchitectureIdentifier,
            report.setDressing.activityMarkerIdentifier,
            report.setDressing.pedestalLayoutIdentifier,
            report.setDressing.shardFormationIdentifier,
            report.setDressing.layoutGeometryCoverageIdentifier,
            report.setDressing.runeIntensityIdentifier,
            report.setDressing.animationCadenceIdentifier,
            report.setDressing.materialTextureVariantIdentifier,
            report.setDressing.backdropTextureAssetIdentifier,
            report.setDressing.arenaTextureAssetIdentifier,
            report.setDressing.backdropTextureRouteIdentifier,
            report.setDressing.arenaTextureRouteIdentifier,
            report.setDressing.textureRoleCoverageIdentifier,
            report.setDressing.runeMaterialIdentifier,
            report.setDressing.runeMaterialTreatmentIdentifier,
            report.setDressing.backdropTextureName,
            report.setDressing.arenaTextureName
        ]
        .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let textureNamesAreRecognized = CinematicTextureAssetCatalog.recognizes(
            report.setDressing.backdropTextureName,
            role: .backdrop
        ) && CinematicTextureAssetCatalog.recognizes(
            report.setDressing.arenaTextureName,
            role: .arena
        )
        let backdropTextureIsPackaged = CinematicTextureAssetCatalog.isPackagedResourceAvailable(
            report.setDressing.backdropTextureName,
            role: .backdrop
        )
        let arenaTextureIsPackaged = CinematicTextureAssetCatalog.isPackagedResourceAvailable(
            report.setDressing.arenaTextureName,
            role: .arena
        )

        return identifiersArePresent
            && textureNamesAreRecognized
            && backdropTextureIsPackaged
            && arenaTextureIsPackaged
    }

    private static func activityCaseIdentifier(_ report: CinematicDiagnosticsReport) -> String? {
        if report.overlayDisplay.reasonIdentifier == "missing-repository" {
            return "missing-repository"
        }
        switch report.activityMotif.eventKindIdentifier {
        case "unavailable":
            return "unavailable"
        case "clean":
            return "clean"
        case "dirty":
            switch report.stageEffect.pressureLevelIdentifier {
            case "light":
                return "dirty-light"
            case "moderate":
                return "dirty-moderate"
            case "heavy":
                return "dirty-heavy"
            default:
                return nil
            }
        case "conflicted":
            return "conflicted"
        case "commit":
            return "commit"
        case "success":
            return "success"
        case "recovery":
            return "recovery"
        case "failure":
            return "failure"
        default:
            return nil
        }
    }

    private static func nativeFeedbackSourceFamily(_ report: CinematicDiagnosticsReport) -> String? {
        let source = report.nativeFeedback.sourceIdentifier
        if source.hasPrefix("native:") {
            return "native"
        }
        if source.hasPrefix("run-cue:") {
            return "run-cue"
        }
        return nil
    }

    private static func nativeFeedbackAnchorRouteIdentifiers(
        _ report: CinematicDiagnosticsReport
    ) -> [String] {
        [
            nativeFeedbackAnchorRouteIdentifier(report.narrativeCue.questPlaque.anchorIdentifier),
            nativeFeedbackAnchorRouteIdentifier(report.narrativeCue.arenaInscription.anchorIdentifier),
            nativeFeedbackAnchorRouteIdentifier(report.narrativeCue.activityBanner.anchorIdentifier)
        ].compactMap { $0 }
    }

    private static func nativeFeedbackAnchorRouteIdentifier(_ anchorIdentifier: String) -> String? {
        switch anchorIdentifier {
        case "left-seal-pylon", "arena-rear":
            return "seal"
        case "right-warning-pylon":
            return "warning"
        case "fracture-gate":
            return "fracture"
        default:
            return nil
        }
    }

    private static func nativeFeedbackTreatmentPairIdentifier(
        _ report: CinematicDiagnosticsReport
    ) -> String? {
        let descriptor = report.narrativeCue.questPlaque
        guard descriptor.plaqueTreatmentAccentIdentifier != "none",
              descriptor.plaqueTreatmentRouteIdentifier != "none"
        else {
            return nil
        }

        return "\(descriptor.plaqueTreatmentAccentIdentifier)/\(descriptor.plaqueTreatmentRouteIdentifier)"
    }

    private static func nativeFeedbackTreatmentMatchesExpectedPair(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        guard let expectation = nativeFeedbackTreatmentExpectations.first(where: {
            $0.sourceIdentifier == report.nativeFeedback.sourceIdentifier
        }) else {
            return false
        }

        return narrativeCueDescriptors(report).allSatisfy {
            $0.plaqueTreatmentAccentIdentifier == expectation.accentIdentifier
                && $0.plaqueTreatmentRouteIdentifier == expectation.routeIdentifier
        }
    }

    private static func nativeFeedbackTreatmentSurfacesMatch(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        let descriptors = narrativeCueDescriptors(report)
        let treatmentIdentifiers = Set(descriptors.map(\.plaqueTreatmentIdentifier))
        let accentIdentifiers = Set(descriptors.map(\.plaqueTreatmentAccentIdentifier))
        let routeIdentifiers = Set(descriptors.map(\.plaqueTreatmentRouteIdentifier))

        return descriptors.count == 3
            && treatmentIdentifiers.count == 1
            && accentIdentifiers.count == 1
            && routeIdentifiers.count == 1
            && !treatmentIdentifiers.contains("none")
            && !accentIdentifiers.contains("none")
            && !routeIdentifiers.contains("none")
            && descriptors.allSatisfy {
                !$0.plaqueTreatmentIdentifier.isEmpty
                    && $0.identifier.contains($0.plaqueTreatmentIdentifier)
            }
    }

    private static func nativeFeedbackTreatmentParametersAreMeaningful(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        narrativeCueDescriptors(report).allSatisfy { descriptor in
            guard let parameters = NativeFeedbackTreatmentParameters(descriptor.plaqueTreatmentIdentifier) else {
                return false
            }

            return parameters.routeIdentifier == descriptor.plaqueTreatmentRouteIdentifier
                && parameters.hasMeaningfulValues(for: descriptor.plaqueTreatmentAccentIdentifier)
        }
    }

    private static func nativeFeedbackTreatmentPrimitivesMatchExpected(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        guard let expectation = nativeFeedbackTreatmentExpectations.first(where: {
            $0.sourceIdentifier == report.nativeFeedback.sourceIdentifier
        }) else {
            return false
        }

        let descriptors = narrativeCueDescriptors(report)
        let expectedPrimitiveCount = expectation.primitiveIdentifiers.count
        let expectedRecipeIdentifier = expectation.primitiveSetIdentifier

        return descriptors.count == 3
            && descriptors.allSatisfy { descriptor in
                descriptor.plaqueTreatmentRenderRecipeIdentifier == expectedRecipeIdentifier
                    && descriptor.plaqueTreatmentRenderPrimitiveIdentifiers == expectation.primitiveIdentifiers
                    && descriptor.plaqueTreatmentRenderPrimitiveCount == expectedPrimitiveCount
                    && descriptor.plaqueTreatmentIdentifier.contains("primitives:\(expectedRecipeIdentifier)")
                    && descriptor.plaqueTreatmentIdentifier.contains("primitive-count:\(expectedPrimitiveCount)")
            }
    }

    private static func nativeFeedbackActiveRoutesAreConsistent(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        report.nativeFeedback.lifecycleStateIdentifier == "active"
            && report.nativeFeedback.lifecycleActiveCueIdentifier == report.nativeFeedback.cueIdentifier
            && report.nativeFeedback.cueIdentifier == report.narrativeCue.nativeFeedbackCueIdentifier
            && report.nativeFeedback.cueIdentifier == report.overlayDisplay.nativeFeedbackCueIdentifier
            && report.nativeFeedback.sourceIdentifier == report.narrativeCue.nativeFeedbackSourceIdentifier
            && report.nativeFeedback.styleIdentifier == report.narrativeCue.nativeFeedbackStyleIdentifier
            && report.nativeFeedback.milestoneIdentifier == report.narrativeCue.nativeFeedbackMilestoneIdentifier
            && report.nativeFeedback.affectedNarrativeDescriptorIdentifiers
                == report.narrativeCue.nativeFeedbackAffectedDescriptorIdentifiers
            && report.nativeFeedback.lifecycleIdentifier == report.overlayDisplay.nativeFeedbackLifecycleIdentifier
            && report.narrativeCue.nativeFeedbackLifecycleIdentifier != "none"
    }

    private static func nativeFeedbackExpiredLifecycleIsArchived(
        _ report: CinematicDiagnosticsReport
    ) -> Bool {
        report.nativeFeedback.cueIdentifier == "none"
            && report.nativeFeedback.lifecycleStateIdentifier == "expired"
            && report.nativeFeedback.lifecycleActiveCueIdentifier == "none"
            && report.nativeFeedback.lifecycleRecentArchiveCount > 0
            && report.narrativeCue.nativeFeedbackCueIdentifier == "none"
            && report.overlayDisplay.nativeFeedbackCueIdentifier == "none"
            && report.nativeFeedback.lifecycleIdentifier == report.overlayDisplay.nativeFeedbackLifecycleIdentifier
            && !report.overlayDisplay.showsNativeFeedbackBanner
            && report.overlayDisplay.nativeFeedbackBannerPolicyIdentifier == "none"
    }

    private static func gradients(
        for mode: String,
        in reports: [CinematicDiagnosticsReport]
    ) -> NumericRange {
        valueRange(
            reports
                .filter { $0.overlayDisplay.modeIdentifier == mode }
                .map { Float($0.overlayDisplay.gradientStrength) }
        )
    }

    private static func valueRange(_ values: [Float]) -> NumericRange {
        NumericRange(minValue: values.min() ?? 0, maxValue: values.max() ?? 0)
    }

    private static func range(_ range: NumericRange) -> String {
        "\(fixed(range.minValue))...\(fixed(range.maxValue))"
    }

    private static func chromeStyleName(_ identifier: String) -> String {
        identifier.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
    }

    private static func joined<S: Sequence>(_ values: S) -> String where S.Element == String {
        let sortedValues = values.sorted()
        return sortedValues.isEmpty ? "none" : sortedValues.joined(separator: ",")
    }

    private static func slashJoined<S: Sequence>(_ values: S) -> String where S.Element == String {
        let sortedValues = values.sorted()
        return sortedValues.isEmpty ? "none" : sortedValues.joined(separator: "/")
    }

    private static func string(_ text: String, maxCharacters: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxCharacters
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func check(
        id: String,
        label: String,
        isPassing: Bool,
        warningIdentifier: String,
        detail: String,
        warningTarget: Check.WarningTarget? = nil
    ) -> Check {
        Check(
            id: bounded(id, limit: warningIdentifierMaxCharacters),
            label: bounded(label, limit: labelMaxCharacters),
            status: isPassing ? .pass : .warning,
            warningIdentifier: isPassing
                ? nil
                : bounded(warningIdentifier, limit: warningIdentifierMaxCharacters),
            warningTarget: isPassing ? nil : warningTarget.map(boundedWarningTarget),
            detail: bounded(detail, limit: detailMaxCharacters)
        )
    }

    private static func boundedWarningTarget(_ target: Check.WarningTarget) -> Check.WarningTarget {
        Check.WarningTarget(
            id: bounded(target.id, limit: warningIdentifierMaxCharacters),
            targetGroupID: bounded(target.targetGroupID, limit: warningIdentifierMaxCharacters),
            targetAnchorID: bounded(target.targetAnchorID, limit: warningIdentifierMaxCharacters),
            relatedGroupID: target.relatedGroupID.map { bounded($0, limit: warningIdentifierMaxCharacters) },
            relatedRowID: target.relatedRowID.map { bounded($0, limit: warningIdentifierMaxCharacters) },
            label: bounded(target.label, limit: labelMaxCharacters),
            detail: bounded(target.detail, limit: detailMaxCharacters)
        )
    }

    private static func fixed(_ value: Float) -> String {
        String(format: "%.2f", Double(value))
    }

    private static func fixed(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "-" }
        guard normalized.count > limit else { return normalized }

        let prefixLimit = max(1, limit - 3)
        let prefix = normalized.prefix(prefixLimit)
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

struct CinematicDiagnosticsSummary: Equatable {
    static let maxRows = 49
    static let labelMaxCharacters = 32
    static let detailMaxCharacters = 512
    static let headerDetailMaxCharacters = 128
    static let visualSmokeCountMaxCharacters = 24
    static let attentionSummaryMaxTargets = 4
    static let attentionSummaryMaxVisibleWarnings = 3
    static let attentionSummaryDetailMaxCharacters = 256
    static let attentionTargetCopyMaxCharacters = 1_200
    static let attentionTargetCopyRelatedDetailMaxCharacters = 360
    static let nativeFeedbackHistoryExportCopyMaxCharacters = 1_600
    static let nativeFeedbackHistoryExportEntryMaxCharacters = 320

    var rows: [Row]
    var sections: [Section]
    var visualSmoke: VisualSmokeSection
    var plaqueTreatmentLegend: PlaqueTreatmentLegend
    var attentionSummary: AttentionSummary
    var nativeFeedbackHistoryExport: NativeFeedbackHistoryExport
    var exportText: String

    struct Row: Identifiable, Equatable {
        var id: String
        var label: String
        var detail: String
    }

    enum AttentionState: String, Equatable {
        case normal
        case warning
    }

    struct PresentationMetadata: Equatable {
        var headerDetail: String
        var defaultExpanded: Bool
        var attentionState: AttentionState
        var warningIdentifiers: [String]

        var needsAttention: Bool {
            attentionState == .warning || !warningIdentifiers.isEmpty
        }
    }

    struct Section: Identifiable, Equatable {
        var id: String
        var label: String
        var rows: [Row]
        var presentation: PresentationMetadata

        var rowCountLabel: String {
            rows.count == 1 ? "1 row" : "\(rows.count) rows"
        }
    }

    struct VisualSmokeSection: Identifiable, Equatable {
        var id: String
        var label: String
        var status: CinematicVisualSmokeReport.Status
        var statusLabel: String
        var warningCount: Int
        var warningCountLabel: String
        var warningBadgeLabel: String
        var help: String
        var warningIdentifiers: [String]
        var checks: [CinematicVisualSmokeReport.Check]
        var presentation: PresentationMetadata

        var checkCountLabel: String {
            checks.count == 1 ? "1 check" : "\(checks.count) checks"
        }
    }

    struct PlaqueTreatmentLegend: Identifiable, Equatable {
        var id: String
        var label: String
        var status: CinematicVisualSmokeReport.Status
        var statusLabel: String
        var detail: String
        var warningIdentifier: String?
        var rows: [Row]
        var presentation: PresentationMetadata

        var rowCountLabel: String {
            rows.count == 1 ? "1 recipe" : "\(rows.count) recipes"
        }
    }

    struct AttentionSummary: Equatable {
        var targets: [AttentionTarget]

        var isEmpty: Bool {
            targets.isEmpty
        }
    }

    struct AttentionTarget: Identifiable, Equatable {
        var id: String
        var targetGroupID: String
        var targetAnchorID: String
        var relatedGroupID: String?
        var relatedRowID: String?
        var label: String
        var detail: String
        var warningCount: Int
        var visibleWarningIdentifiers: [String]
        var copyText: String
    }

    struct NativeFeedbackHistoryExport: Identifiable, Equatable {
        var id: String
        var rowID: String
        var activeCount: Int
        var archivedCount: Int
        var omittedCount: Int
        var entries: [Entry]
        var copyText: String

        var isAvailable: Bool {
            !entries.isEmpty && !copyText.isEmpty
        }

        var copyLabel: String {
            isAvailable ? "Copy native history" : "No native history"
        }

        var copyHelp: String {
            guard isAvailable else { return "No native feedback cue history to copy" }
            return "Copy native feedback history: active \(activeCount), archived \(archivedCount), omitted \(omittedCount)"
        }

        struct Entry: Identifiable, Equatable {
            var id: String { identifier }

            var identifier: String
            var sequence: Int
            var stateIdentifier: String
            var reasonIdentifier: String?
            var milestoneIdentifier: String
            var sourceIdentifier: String?
            var styleIdentifier: String?
            var displayDuration: TimeInterval
            var lifecycleIdentifier: String
            var copyLine: String
        }
    }

    private struct PlaqueTreatmentLegendEntry {
        var accentIdentifier: String
        var routeIdentifier: String
        var renderRecipeIdentifier: String
        var primitiveIdentifiers: [String]
        var primitiveCount: Int
    }

    private struct SectionDefinition {
        var id: String
        var label: String
        var rowIDs: Set<String>
        var rowIDPrefixes: [String] = []

        func contains(_ row: Row) -> Bool {
            rowIDs.contains(row.id) || rowIDPrefixes.contains { row.id.hasPrefix($0) }
        }
    }

    private static let sectionDefinitions: [SectionDefinition] = [
        SectionDefinition(
            id: "repository-context",
            label: "Repository/context",
            rowIDs: [
                "repository",
                "immediate",
                "plan-compass-immediate",
                "plan-compass-mid-term",
                "plan-compass-long-term",
                "commit-constellation",
                "idle-story-cycle",
                "timeline-focus",
                "run-recap",
                "run-recap-share",
                "run-recap-share-artifact",
                "run-recap-share-artifact-history",
                "run-recap-share-artifact-rollup",
                "run-recap-share-artifact-comparison",
                "run-recap-share-artifact-pins",
                "run-recap-share-artifact-tour",
                "run-recap-share-artifact-preview",
                "run-recap-share-artifact-commands",
                "run-recap-focus",
                "run-recap-end-card"
            ]
        ),
        SectionDefinition(
            id: "motifs",
            label: "Motifs",
            rowIDs: ["language-motif", "activity-motif"]
        ),
        SectionDefinition(
            id: "stage-motion-effects",
            label: "Stage motion/effects",
            rowIDs: [
                "recovery-cue",
                "stage-beat",
                "stage-effect",
                "effect-rings",
                "effect-pulses",
                "effect-history",
                "stage-atmosphere",
                "atmosphere-tints",
                "phase-polish"
            ]
        ),
        SectionDefinition(
            id: "narrative-overlay",
            label: "Narrative/overlay",
            rowIDs: [
                "narrative-cues",
                "narrative-layout",
                "overlay-display",
                "native-feedback-history",
                "native-feedback-delivery",
                "world-quest",
                "world-arena",
                "world-activity"
            ]
        ),
        SectionDefinition(
            id: "assets-textures",
            label: "Assets/textures",
            rowIDs: ["set-dressing", "textures"]
        ),
        SectionDefinition(
            id: "tuning",
            label: "Tuning",
            rowIDs: [
                "effect-tuning",
                "activity-tuning",
                "camera-tuning",
                "camera-follow"
            ]
        ),
        SectionDefinition(
            id: "camera-shots",
            label: "Camera shots",
            rowIDs: [],
            rowIDPrefixes: ["camera-shot-"]
        )
    ]

    private static let collapsedByDefaultSectionIDs: Set<String> = [
        "stage-motion-effects",
        "camera-shots"
    ]

    init(report: CinematicDiagnosticsReport, visualSmoke: CinematicVisualSmokeReport = .representative()) {
        let rows = Self.makeRows(report: report)
        self.rows = Array(rows.prefix(Self.maxRows))
        sections = Self.makeSections(rows: self.rows)
        self.visualSmoke = Self.makeVisualSmokeSection(visualSmoke)
        plaqueTreatmentLegend = Self.makePlaqueTreatmentLegend(visualSmoke: self.visualSmoke)
        nativeFeedbackHistoryExport = Self.makeNativeFeedbackHistoryExport(report.nativeFeedback)
        attentionSummary = Self.makeAttentionSummary(
            report: report,
            sections: sections,
            visualSmoke: self.visualSmoke,
            plaqueTreatmentLegend: plaqueTreatmentLegend
        )
        exportText = Self.makeExportText(
            report: report,
            attentionSummary: attentionSummary,
            sections: sections,
            visualSmoke: self.visualSmoke,
            plaqueTreatmentLegend: plaqueTreatmentLegend
        )
    }

    private static func makeRows(report: CinematicDiagnosticsReport) -> [Row] {
        var rows: [Row] = [
            row(
                id: "repository",
                label: "Repository",
                detail: [
                    report.repoName,
                    report.phase,
                    completedLabel(report.completedCount)
                ].joined(separator: " | ")
            ),
            row(id: "immediate", label: "Immediate", detail: report.immediateTitle),
        ]

        if let planCompass = report.planCompass {
            rows.append(
                contentsOf: planCompass.sections.map { section in
                    row(
                        id: section.rowIdentifier,
                        label: section.directionLabel,
                        detail: planCompassDetail(section)
                    )
                }
            )
        }

        rows.append(contentsOf: [
            row(
                id: "commit-constellation",
                label: "Commit constellation",
                detail: commitConstellationDetail(report.commitConstellation)
            ),
            row(
                id: "idle-story-cycle",
                label: "Idle story cycle",
                detail: idleStoryCycleDetail(report.idleStoryCycle)
            ),
            row(
                id: "timeline-focus",
                label: "Timeline focus",
                detail: timelineFocusDetail(report.timelineFocus)
            ),
            row(
                id: "run-recap",
                label: "Run recap",
                detail: runRecapDetail(report.runRecap)
            ),
            row(
                id: "run-recap-share",
                label: "Run recap share",
                detail: runRecapShareDetail(report.runRecapShare)
            ),
            row(
                id: "run-recap-share-artifact",
                label: "Recap share artifact",
                detail: runRecapShareArtifactDetail(report.runRecapShareArtifact)
            ),
            row(
                id: "run-recap-share-artifact-history",
                label: "Recap artifact library",
                detail: runRecapShareArtifactHistoryDetail(report.runRecapShareArtifactHistory)
            ),
            row(
                id: "run-recap-share-artifact-rollup",
                label: "Recap artifact rollup",
                detail: runRecapShareArtifactRollupDetail(report.runRecapShareArtifactRollup)
            ),
            row(
                id: "run-recap-share-artifact-comparison",
                label: "Recap artifact compare",
                detail: runRecapShareArtifactComparisonDetail(report.runRecapShareArtifactComparison)
            ),
            row(
                id: "run-recap-share-artifact-pins",
                label: "Recap artifact pins",
                detail: runRecapShareArtifactPinsDetail(report.runRecapShareArtifactPins)
            ),
            row(
                id: "run-recap-share-artifact-tour",
                label: "Recap artifact tour",
                detail: runRecapShareArtifactTourDetail(report.runRecapShareArtifactTour)
            ),
            row(
                id: "run-recap-share-artifact-preview",
                label: "Recap artifact preview",
                detail: runRecapShareArtifactPreviewDetail(report.runRecapShareArtifactPreview)
            ),
            row(
                id: "run-recap-share-artifact-commands",
                label: "Recap artifact commands",
                detail: runRecapShareArtifactCommandsDetail(report.runRecapShareArtifactCommands)
            ),
            row(
                id: "run-recap-focus",
                label: "Run recap focus",
                detail: runRecapSceneFocusDetail(report.runRecapSceneFocus)
            ),
            row(
                id: "run-recap-end-card",
                label: "Run recap end card",
                detail: runRecapEndCardDetail(report.runRecapEndCard)
            ),
            row(
                id: "language-motif",
                label: "Language motif",
                detail: [
                    report.languageMotif.language.displayName,
                    report.languageMotif.sigilIdentifier,
                    report.languageMotif.styleIdentifier,
                    "ambient \(report.languageMotif.ambientSpellIdentifier)",
                    "blend \(fixed(report.languageMotif.phaseBlend))"
                ].joined(separator: " | ")
            ),
            row(
                id: "activity-motif",
                label: "Activity motif",
                detail: [
                    report.activityMotif.eventKindIdentifier,
                    report.activityMotif.sigilIdentifier,
                    report.activityMotif.styleIdentifier,
                    optionalIdentifier("tint", report.activityMotif.tintSourceIdentifier),
                    optionalIdentifier("transition", report.activityMotif.transitionSpellIdentifier),
                    optionalIdentifier("ambient", report.activityMotif.ambientOverrideIdentifier),
                    report.activityMotif.shouldShakeOnTransition ? "shake" : nil
                ].compactMap { $0 }.joined(separator: " | ")
            ),
            row(
                id: "recovery-cue",
                label: "Recovery cue",
                detail: [
                    report.recoveryCue.kindIdentifier,
                    "treatment \(report.recoveryCue.treatmentIdentifier)",
                    "light \(report.recoveryCue.lightFamilyIdentifier)",
                    "symbol \(report.recoveryCue.symbolIdentifier ?? "none")",
                    "intensity \(fixed(report.recoveryCue.intensity))",
                    "fracture \(fixed(report.recoveryCue.fractureOpacity))",
                    "heal \(fixed(report.recoveryCue.healingOpacity))",
                    report.recoveryCue.shouldShakeCamera ? "shake" : nil
                ].compactMap { $0 }.joined(separator: " | ")
            ),
            row(
                id: "stage-beat",
                label: "Stage beat",
                detail: [
                    report.stageBeat.kindIdentifier,
                    "shot \(report.stageBeat.cameraShotIdentifier)",
                    "light \(report.stageBeat.lightFamilyIdentifier)",
                    "effect \(report.stageBeat.arenaEffectIdentifier)",
                    "intensity \(fixed(report.stageBeat.phaseLightIntensity))",
                    optionalIdentifier("activity", report.stageBeat.activityEventKindIdentifier),
                    optionalIdentifier("accent", report.stageBeat.activityAccentIdentifier),
                    report.stageBeat.shouldShakeCamera ? "shake" : nil,
                    report.stageBeat.shouldRunVictorySurge ? "victory" : nil,
                    report.stageBeat.shouldRunHistoryChains ? "history" : nil
                ].compactMap { $0 }.joined(separator: " | ")
            ),
            row(
                id: "stage-effect",
                label: "Stage effect",
                detail: [
                    "phase \(report.stageEffect.phaseSourceIdentifier)/\(report.stageEffect.phaseArenaEffectIdentifier)",
                    report.stageEffect.activitySourceIdentifier.flatMap { source in
                        report.stageEffect.activityArenaEffectIdentifier.map { "activity \(source)/\($0)" }
                    },
                    report.stageEffect.recoverySourceIdentifier.flatMap { source in
                        report.stageEffect.recoveryArenaEffectIdentifier.map { "recovery \(source)/\($0)" }
                    },
                    "rings \(report.stageEffect.arenaRingCount)",
                    "pulses \(report.stageEffect.phaseLightPulseCount)",
                    "sparks \(report.stageEffect.sparkBurstCount)",
                    "history \(report.stageEffect.historyTrailCount)",
                    optionalIdentifier("victory", report.stageEffect.victoryCadenceIdentifier),
                    report.stageEffect.cameraShakeIdentifiers.isEmpty
                        ? nil
                        : "camera \(report.stageEffect.cameraShakeIdentifiers.joined(separator: ","))"
                ].compactMap { $0 }.joined(separator: " | ")
            ),
            row(
                id: "effect-tuning",
                label: "Effect tuning",
                detail: [
                    "pressure \(report.stageEffect.pressureLevelIdentifier) \(fixed(report.stageEffect.pressureFraction))",
                    "energy \(fixed(report.stageEffect.energy))",
                    "influence \(report.stageEffect.influenceStyleIdentifier) \(fixed(report.stageEffect.influenceIntensity))/\(fixed(report.stageEffect.influenceFraction))",
                    "light \(fixed(report.stageEffect.activityLightBoost))/\(fixed(report.stageEffect.activityLightBoostFraction))",
                    "rune \(fixed(report.stageEffect.runePulseScale))",
                    "cadence \(fixed(report.stageEffect.activityPulseDuration))s",
                    "ring \(fixed(report.stageEffect.ringScaleMultiplier))/\(fixed(report.stageEffect.ringDurationScale))/\(fixed(report.stageEffect.ringOpacityMultiplier))",
                    "alpha \(fixed(report.stageEffect.colorAlphaMultiplier))",
                    "pulse \(fixed(report.stageEffect.pulseIntensityMultiplier))/\(fixed(report.stageEffect.pulseDurationMultiplier))",
                    "spark \(fixed(report.stageEffect.sparkBirthRateMultiplier))",
                    "trails \(report.stageEffect.historyTrailTargetCount)",
                    "shake \(fixed(report.stageEffect.cameraShakeMultiplier))/\(fixed(report.stageEffect.cameraShakeDurationMultiplier))",
                    "victory \(fixed(report.stageEffect.victoryCadenceMultiplier))"
                ].joined(separator: " | ")
            ),
            row(
                id: "effect-rings",
                label: "Effect rings",
                detail: report.stageEffect.arenaRingIdentifiers.isEmpty
                    ? "none"
                    : report.stageEffect.arenaRingIdentifiers.joined(separator: " | ")
            ),
            row(
                id: "effect-pulses",
                label: "Effect pulses",
                detail: effectPulseDetail(report.stageEffect)
            ),
            row(
                id: "effect-history",
                label: "Effect history",
                detail: report.stageEffect.historyTrailIdentifiers.isEmpty
                    ? "none"
                    : report.stageEffect.historyTrailIdentifiers.joined(separator: " | ")
            ),
            row(
                id: "stage-atmosphere",
                label: "Atmosphere",
                detail: [
                    "pressure \(report.stageAtmosphere.pressureLevelIdentifier) \(fixed(report.stageAtmosphere.pressureFraction))",
                    "energy \(fixed(report.stageAtmosphere.energy))",
                    "influence \(report.stageAtmosphere.influenceStyleIdentifier) \(fixed(report.stageAtmosphere.influenceIntensity))/\(fixed(report.stageAtmosphere.influenceFraction))",
                    "halo \(report.stageAtmosphere.pressureHaloIdentifier)",
                    "pulse \(report.stageAtmosphere.atmosphericPulseIdentifier)",
                    "light \(report.stageAtmosphere.pressureLightingIdentifier)"
                ].joined(separator: " | ")
            ),
            row(
                id: "atmosphere-tints",
                label: "Atmosphere tints",
                detail: [
                    "backdrop \(report.stageAtmosphere.backdropTintIdentifier)",
                    "floor \(report.stageAtmosphere.floorTintIdentifier)"
                ].joined(separator: " | ")
            ),
            row(
                id: "phase-polish",
                label: "Phase polish",
                detail: [
                    report.stagePhasePolish.postureIdentifier,
                    "recovery \(report.stagePhasePolish.recoveryCueKindIdentifier)",
                    "pose \(fixed(report.stagePhasePolish.poseIntensity))",
                    "orb \(report.stagePhasePolish.staffOrbLightFamilyIdentifier) \(fixed(report.stagePhasePolish.staffOrbScale))/\(fixed(report.stagePhasePolish.staffOrbEmission))",
                    "sigil \(fixed(report.stagePhasePolish.sigilSealEmphasis))/\(fixed(report.stagePhasePolish.sigilOrbitRadius))",
                    "victory \(fixed(report.stagePhasePolish.sigilVictoryEmphasis))",
                    "portal \(fixed(report.stagePhasePolish.portalAperture))",
                    "backdrop \(fixed(report.stagePhasePolish.backdropAperture))",
                    "fracture \(fixed(report.stagePhasePolish.fractureOpacity))",
                    "heal \(fixed(report.stagePhasePolish.healingOpacity))",
                    "cadence \(report.stagePhasePolish.cadenceIdentifier)"
                ].joined(separator: " | ")
            ),
            row(
                id: "narrative-cues",
                label: "Narrative cues",
                detail: narrativeCueDetail(report.narrativeCue)
            ),
            row(
                id: "narrative-layout",
                label: "Narrative layout",
                detail: narrativeLayoutDetail(report.narrativeCue)
            ),
            row(
                id: "overlay-display",
                label: "Overlay display",
                detail: overlayDisplayDetail(report.overlayDisplay)
            ),
            row(
                id: "native-feedback-history",
                label: "Native feedback history",
                detail: nativeFeedbackHistoryDetail(report.nativeFeedback)
            ),
            row(
                id: "native-feedback-delivery",
                label: "Native feedback delivery",
                detail: nativeFeedbackDeliveryDetail(report.nativeFeedbackDelivery)
            ),
            row(id: "world-quest", label: "World quest", detail: report.worldText.questLabel),
            row(id: "world-arena", label: "World arena", detail: report.worldText.arenaCallout),
            row(id: "world-activity", label: "World activity", detail: report.worldText.activityCallout),
            row(
                id: "set-dressing",
                label: "Set dressing",
                detail: [
                    report.setDressing.languageArchitectureIdentifier,
                    report.setDressing.activityMarkerIdentifier,
                    "layout \(report.setDressing.layoutGeometryCoverageIdentifier)",
                    report.setDressing.layoutGeometryIsBounded ? "layout bounded" : "layout out-of-bounds",
                    "runes \(report.setDressing.runeIntensityIdentifier)",
                    "rune material \(report.setDressing.runeMaterialIdentifier)",
                    "material \(report.setDressing.runeMaterialTreatmentIdentifier)",
                    "cadence \(report.setDressing.animationCadenceIdentifier)"
                ].joined(separator: " | ")
            ),
            row(
                id: "textures",
                label: "Textures",
                detail: [
                    report.setDressing.materialTextureVariantIdentifier,
                    report.setDressing.backdropTextureAssetIdentifier,
                    report.setDressing.arenaTextureAssetIdentifier,
                    "routes \(report.setDressing.textureRoleCoverageIdentifier)",
                    report.setDressing.backdropTextureName,
                    report.setDressing.arenaTextureName,
                    CinematicTextureAssetCatalog.isGeneratedBackdropTextureName(
                        report.setDressing.backdropTextureName
                    ) ? "backdrop generated" : "backdrop fallback",
                    CinematicTextureAssetCatalog.isGeneratedArenaTextureName(
                        report.setDressing.arenaTextureName
                    ) ? "arena generated" : "arena fallback",
                    CinematicTextureAssetCatalog.isPackagedResourceAvailable(
                        report.setDressing.backdropTextureName,
                        role: .backdrop
                    ) ? "backdrop packaged" : "backdrop missing",
                    CinematicTextureAssetCatalog.isPackagedResourceAvailable(
                        report.setDressing.arenaTextureName,
                        role: .arena
                    ) ? "arena packaged" : "arena missing",
                    report.setDressing.usesFallbackTextureAsset ? "fallback" : "direct"
                ].joined(separator: " | ")
            ),
            row(
                id: "activity-tuning",
                label: "Activity tuning",
                detail: [
                    report.activityTuning.pressureLevelIdentifier,
                    "spawn \(fixed(report.activityTuning.ambientSpawnCadence))s",
                    "limit \(report.activityTuning.ambientEnemyLimit)",
                    "light \(fixed(report.activityTuning.activityLightBoost))",
                    "scale \(fixed(report.activityTuning.activityPressureScale))"
                ].joined(separator: " | ")
            ),
            row(
                id: "camera-tuning",
                label: "Camera tuning",
                detail: [
                    report.cameraTuning.identifier,
                    "orbit \(fixed(report.cameraTuning.orbitScale))",
                    "pullback \(fixed(report.cameraTuning.pullbackScale))",
                    "height \(fixed(report.cameraTuning.heightOffset))"
                ].joined(separator: " | ")
            ),
            row(
                id: "camera-follow",
                label: "Camera follow",
                detail: [
                    "fov \(fixed(report.cameraTuning.followFieldOfView))",
                    "response \(fixed(report.cameraTuning.followResponsiveness))",
                    "drift \(fixed(report.cameraTuning.driftScale))",
                    "shake \(fixed(report.cameraTuning.shakeScale))"
                ].joined(separator: " | ")
            )
        ])

        rows.append(contentsOf: report.cameraSnapshots.map { snapshot in
            row(
                id: "camera-shot-\(snapshot.shotIdentifier)",
                label: "Shot \(snapshot.shotIdentifier)",
                detail: [
                    snapshot.identifier,
                    "pos \(position(snapshot.position))",
                    "fov \(fixed(snapshot.fieldOfView))",
                    "transition \(fixed(snapshot.transitionDuration))s"
                ].joined(separator: " | ")
            )
        })

        return rows
    }

    private static func makeSections(rows: [Row]) -> [Section] {
        var matchedRowIDs = Set<String>()
        var sections = sectionDefinitions.compactMap { definition -> Section? in
            let sectionRows = rows.filter(definition.contains)
            guard !sectionRows.isEmpty else { return nil }

            matchedRowIDs.formUnion(sectionRows.map(\.id))
            return Section(
                id: definition.id,
                label: bounded(definition.label, limit: labelMaxCharacters),
                rows: sectionRows,
                presentation: sectionPresentation(
                    id: definition.id,
                    rowCount: sectionRows.count
                )
            )
        }

        let unmatchedRows = rows.filter { !matchedRowIDs.contains($0.id) }
        if !unmatchedRows.isEmpty {
            sections.append(
                Section(
                    id: "other",
                    label: bounded("Other", limit: labelMaxCharacters),
                    rows: unmatchedRows,
                    presentation: sectionPresentation(
                        id: "other",
                        rowCount: unmatchedRows.count
                    )
                )
            )
        }

        return sections
    }

    private static func sectionPresentation(id: String, rowCount: Int) -> PresentationMetadata {
        PresentationMetadata(
            headerDetail: bounded(
                rowCountCopy(rowCount, singular: "row", plural: "rows"),
                limit: headerDetailMaxCharacters
            ),
            defaultExpanded: !collapsedByDefaultSectionIDs.contains(id),
            attentionState: .normal,
            warningIdentifiers: []
        )
    }

    var defaultExpandedGroupStates: [String: Bool] {
        var states = Dictionary(uniqueKeysWithValues: sections.map { section in
            (section.id, section.presentation.defaultExpanded)
        })
        states[visualSmoke.id] = visualSmoke.presentation.defaultExpanded
        states[plaqueTreatmentLegend.id] = plaqueTreatmentLegend.presentation.defaultExpanded
        return states
    }

    func row(id: String) -> Row? {
        rows.first { $0.id == id }
    }

    func relatedRow(for target: CinematicVisualSmokeReport.Check.WarningTarget) -> Row? {
        target.relatedRowID.flatMap { row(id: $0) }
    }

    private static func makeAttentionSummary(
        report: CinematicDiagnosticsReport,
        sections: [Section],
        visualSmoke: VisualSmokeSection,
        plaqueTreatmentLegend: PlaqueTreatmentLegend
    ) -> AttentionSummary {
        let rowsByID = Dictionary(
            uniqueKeysWithValues: sections.flatMap(\.rows).map { ($0.id, $0) }
        )
        let warningCheckTargets = visualSmoke.checks.compactMap { check in
            warningCheckAttentionTarget(
                check: check,
                report: report,
                rowsByID: rowsByID
            )
        }
        let groupTargets = [
            attentionTarget(
                id: visualSmoke.id,
                targetGroupID: visualSmoke.id,
                targetAnchorID: visualSmoke.id,
                relatedGroupID: nil,
                relatedRowID: nil,
                label: visualSmoke.label,
                detail: [
                    visualSmoke.checkCountLabel,
                    visualSmoke.statusLabel
                ].joined(separator: " | "),
                presentation: visualSmoke.presentation
            ),
            attentionTarget(
                id: plaqueTreatmentLegend.id,
                targetGroupID: plaqueTreatmentLegend.id,
                targetAnchorID: plaqueTreatmentLegend.id,
                relatedGroupID: nil,
                relatedRowID: nil,
                label: plaqueTreatmentLegend.label,
                detail: [
                    plaqueTreatmentLegend.rowCountLabel,
                    plaqueTreatmentLegend.statusLabel
                ].joined(separator: " | "),
                presentation: plaqueTreatmentLegend.presentation
            )
        ]
        .compactMap { $0 }
        let targets = (warningCheckTargets + groupTargets).prefix(attentionSummaryMaxTargets)

        return AttentionSummary(targets: Array(targets))
    }

    private static func warningCheckAttentionTarget(
        check: CinematicVisualSmokeReport.Check,
        report: CinematicDiagnosticsReport,
        rowsByID: [String: Row]
    ) -> AttentionTarget? {
        guard check.status == .warning, let warningTarget = check.warningTarget else {
            return nil
        }

        let relatedRow = warningTarget.relatedRowID.flatMap { rowsByID[$0] }
        let detail: String
        if check.id == "run-recap-artifact-command-availability" {
            detail = runRecapCommandAvailabilityAttentionDetail(
                report.runRecapShareArtifactCommands
            )
        } else {
            detail = relatedRow.map { "\(check.detail) | \($0.detail)" } ?? check.detail
        }

        return AttentionTarget(
            id: warningTarget.id,
            targetGroupID: warningTarget.targetGroupID,
            targetAnchorID: warningTarget.targetAnchorID,
            relatedGroupID: warningTarget.relatedGroupID,
            relatedRowID: warningTarget.relatedRowID,
            label: bounded(warningTarget.label, limit: labelMaxCharacters),
            detail: bounded(detail, limit: attentionSummaryDetailMaxCharacters),
            warningCount: 1,
            visibleWarningIdentifiers: check.warningIdentifier.map { [$0] } ?? [],
            copyText: attentionTargetCopyText(
                label: warningTarget.label,
                targetGroupID: warningTarget.targetGroupID,
                targetAnchorID: warningTarget.targetAnchorID,
                visibleWarningIdentifiers: check.warningIdentifier.map { [$0] } ?? [],
                detail: detail,
                relatedRow: relatedRow
            )
        )
    }

    private static func attentionTarget(
        id: String,
        targetGroupID: String,
        targetAnchorID: String,
        relatedGroupID: String?,
        relatedRowID: String?,
        label: String,
        detail: String,
        presentation: PresentationMetadata
    ) -> AttentionTarget? {
        guard presentation.needsAttention else {
            return nil
        }

        let warningCount = presentation.warningIdentifiers.isEmpty ? 1 : presentation.warningIdentifiers.count
        return AttentionTarget(
            id: bounded(id, limit: CinematicVisualSmokeReport.warningIdentifierMaxCharacters),
            targetGroupID: targetGroupID,
            targetAnchorID: targetAnchorID,
            relatedGroupID: relatedGroupID,
            relatedRowID: relatedRowID,
            label: bounded(label, limit: labelMaxCharacters),
            detail: bounded(detail, limit: attentionSummaryDetailMaxCharacters),
            warningCount: warningCount,
            visibleWarningIdentifiers: Array(
                presentation.warningIdentifiers.prefix(attentionSummaryMaxVisibleWarnings)
            ),
            copyText: attentionTargetCopyText(
                label: label,
                targetGroupID: targetGroupID,
                targetAnchorID: targetAnchorID,
                visibleWarningIdentifiers: Array(
                    presentation.warningIdentifiers.prefix(attentionSummaryMaxVisibleWarnings)
                ),
                detail: detail,
                relatedRow: nil
            )
        )
    }

    private static func attentionTargetCopyText(
        label: String,
        targetGroupID: String,
        targetAnchorID: String,
        visibleWarningIdentifiers: [String],
        detail: String,
        relatedRow: Row?
    ) -> String {
        let warnings = visibleWarningIdentifiers.isEmpty
            ? "none"
            : visibleWarningIdentifiers.joined(separator: ", ")
        var lines = [
            "Cinematic diagnostics warning target",
            "Label: \(bounded(label, limit: labelMaxCharacters))",
            "Target anchor: \(bounded(targetAnchorID, limit: CinematicVisualSmokeReport.warningIdentifierMaxCharacters))",
            "Target group: \(bounded(targetGroupID, limit: CinematicVisualSmokeReport.warningIdentifierMaxCharacters))",
            "Warnings: \(bounded(warnings, limit: detailMaxCharacters))",
            "Detail: \(bounded(detail, limit: attentionSummaryDetailMaxCharacters))"
        ]

        if let relatedRow {
            lines.append(
                [
                    "Related row:",
                    bounded(relatedRow.id, limit: CinematicVisualSmokeReport.warningIdentifierMaxCharacters),
                    "(\(bounded(relatedRow.label, limit: labelMaxCharacters)))"
                ].joined(separator: " ")
            )
            lines.append(
                "Related detail: \(bounded(relatedRow.detail, limit: attentionTargetCopyRelatedDetailMaxCharacters))"
            )
        }

        return bounded(
            lines.joined(separator: "\n"),
            limit: attentionTargetCopyMaxCharacters
        )
    }

    private static func makeVisualSmokeSection(
        _ report: CinematicVisualSmokeReport
    ) -> VisualSmokeSection {
        let warningCount = report.warningIdentifiers.count
        let checkCountLabel = report.checks.count == 1 ? "1 check" : "\(report.checks.count) checks"
        let warningIdentifiers = report.warningIdentifiers
        let presentation = PresentationMetadata(
            headerDetail: bounded(
                [
                    checkCountLabel,
                    warningHeaderDetail(warningIdentifiers)
                ].joined(separator: " | "),
                limit: headerDetailMaxCharacters
            ),
            defaultExpanded: !warningIdentifiers.isEmpty,
            attentionState: warningIdentifiers.isEmpty ? .normal : .warning,
            warningIdentifiers: warningIdentifiers
        )

        return VisualSmokeSection(
            id: "visual-smoke",
            label: bounded("Visual smoke", limit: labelMaxCharacters),
            status: report.status,
            statusLabel: bounded(visualSmokeStatusLabel(for: report.status), limit: labelMaxCharacters),
            warningCount: warningCount,
            warningCountLabel: bounded(
                warningCountCopy(for: warningCount),
                limit: visualSmokeCountMaxCharacters
            ),
            warningBadgeLabel: bounded(
                warningBadgeCopy(for: warningCount),
                limit: visualSmokeCountMaxCharacters
            ),
            help: bounded(
                visualSmokeHelp(status: report.status, warningIdentifiers: report.warningIdentifiers),
                limit: detailMaxCharacters
            ),
            warningIdentifiers: warningIdentifiers,
            checks: report.checks,
            presentation: presentation
        )
    }

    private static func makePlaqueTreatmentLegend(
        visualSmoke: VisualSmokeSection
    ) -> PlaqueTreatmentLegend {
        let treatmentCheck = visualSmoke.checks.first { $0.id == "native-feedback-treatment-coverage" }
        let status = treatmentCheck?.status ?? .warning
        let statusLabel = visualSmokeStatusLabel(for: status)
        let warningIdentifier = treatmentCheck?.warningIdentifier
        let detail = warningIdentifier.map { "smoke \(status.rawValue) \($0)" }
            ?? "smoke \(status.rawValue)"
        let entries = plaqueTreatmentLegendEntries(
            reports: CinematicDiagnostics.representativeNativeFeedbackSmokeReports()
        )
        let rows = entries.map { entry in
            row(
                id: "plaque-treatment-\(entry.accentIdentifier)",
                label: entry.accentIdentifier,
                detail: plaqueTreatmentLegendDetail(entry)
            )
        }
        let warningIdentifiers = warningIdentifier.map { [$0] } ?? []
        let rowCountLabel = rows.count == 1 ? "1 recipe" : "\(rows.count) recipes"
        let presentation = PresentationMetadata(
            headerDetail: bounded(
                [
                    rowCountLabel,
                    statusLabel,
                    warningHeaderDetail(warningIdentifiers)
                ].joined(separator: " | "),
                limit: headerDetailMaxCharacters
            ),
            defaultExpanded: status == .warning || !warningIdentifiers.isEmpty,
            attentionState: status == .warning || !warningIdentifiers.isEmpty ? .warning : .normal,
            warningIdentifiers: warningIdentifiers
        )

        return PlaqueTreatmentLegend(
            id: "plaque-treatment-legend",
            label: bounded("Plaque treatments", limit: labelMaxCharacters),
            status: status,
            statusLabel: bounded(statusLabel, limit: labelMaxCharacters),
            detail: bounded(detail, limit: detailMaxCharacters),
            warningIdentifier: warningIdentifier,
            rows: rows,
            presentation: presentation
        )
    }

    private static func makeExportText(
        report: CinematicDiagnosticsReport,
        attentionSummary: AttentionSummary,
        sections: [Section],
        visualSmoke: VisualSmokeSection,
        plaqueTreatmentLegend: PlaqueTreatmentLegend
    ) -> String {
        var lines = [
            "Cinematic Diagnostics",
            "Report: \(bounded(report.identifier, limit: detailMaxCharacters))"
        ]

        if !attentionSummary.targets.isEmpty {
            lines.append(
                "Warning summary (\(rowCountCopy(attentionSummary.targets.count, singular: "target", plural: "targets")))"
            )
            lines.append(contentsOf: attentionSummary.targets.map { target in
                let visibleWarnings = target.visibleWarningIdentifiers.isEmpty
                    ? "no visible warning identifiers"
                    : target.visibleWarningIdentifiers.joined(separator: ", ")
                let anchor = target.targetAnchorID == target.id ? "" : " | anchor \(target.targetAnchorID)"
                let related = target.relatedRowID.map { " | related \($0)" } ?? ""
                return "\(target.label) -> \(target.id) (\(warningCountCopy(for: target.warningCount))): \(target.detail)\(anchor)\(related) | \(visibleWarnings)"
            })
        }

        for section in sections {
            lines.append("\(section.label) (\(section.rowCountLabel))")
            lines.append(contentsOf: section.rows.map { "\($0.label): \($0.detail)" })
        }

        lines.append(
            "Visual smoke (\(visualSmoke.status.rawValue), \(visualSmoke.checks.count) checks)"
        )
        lines.append(contentsOf: visualSmoke.checks.map { check in
            let warning = check.warningIdentifier.map { " | warning \($0)" } ?? ""
            return "\(check.label): \(check.status.rawValue) | \(check.detail)\(warning)"
        })

        lines.append(
            "\(plaqueTreatmentLegend.label) (\(plaqueTreatmentLegend.status.rawValue), \(plaqueTreatmentLegend.rowCountLabel)): \(plaqueTreatmentLegend.detail)"
        )
        lines.append(contentsOf: plaqueTreatmentLegend.rows.map { "\($0.label): \($0.detail)" })

        return lines.joined(separator: "\n")
    }

    private static func warningCountCopy(for count: Int) -> String {
        switch count {
        case 0:
            return "No warnings"
        case 1:
            return "1 warning"
        default:
            return "\(count) warnings"
        }
    }

    private static func warningBadgeCopy(for count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    private static func rowCountCopy(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }

    private static func warningHeaderDetail(_ warningIdentifiers: [String]) -> String {
        guard !warningIdentifiers.isEmpty else {
            return "No warnings"
        }

        let visibleWarnings = warningIdentifiers.prefix(2).joined(separator: ", ")
        if warningIdentifiers.count <= 2 {
            return "\(warningCountCopy(for: warningIdentifiers.count)) | \(visibleWarnings)"
        }

        return "\(warningCountCopy(for: warningIdentifiers.count)) | \(visibleWarnings) +\(warningIdentifiers.count - 2)"
    }

    private static func visualSmokeHelp(
        status: CinematicVisualSmokeReport.Status,
        warningIdentifiers: [String]
    ) -> String {
        switch status {
        case .pass:
            return "Visual smoke checks passing"
        case .warning:
            let warnings = warningIdentifiers.isEmpty
                ? "warnings unavailable"
                : warningIdentifiers.joined(separator: ", ")
            return "Visual smoke warning: \(warningCountCopy(for: warningIdentifiers.count)) (\(warnings))"
        }
    }

    private static func visualSmokeStatusLabel(for status: CinematicVisualSmokeReport.Status) -> String {
        switch status {
        case .pass:
            return "Passing"
        case .warning:
            return "Warning"
        }
    }

    private static func row(id: String, label: String, detail: String) -> Row {
        Row(
            id: id,
            label: bounded(label, limit: labelMaxCharacters),
            detail: bounded(detail, limit: detailMaxCharacters)
        )
    }

    private static func optionalIdentifier(_ label: String, _ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return "\(label) \(identifier)"
    }

    private static func identifierListDetail(_ label: String, _ identifiers: [String]) -> String? {
        guard !identifiers.isEmpty else { return nil }
        return "\(label) \(bounded(identifiers.joined(separator: ","), limit: 160))"
    }

    private static func plaqueTreatmentLegendEntries(
        reports: [CinematicDiagnosticsReport]
    ) -> [PlaqueTreatmentLegendEntry] {
        let entries = reports
            .filter {
                $0.nativeFeedback.cueIdentifier != "none"
                    && $0.nativeFeedback.lifecycleStateIdentifier == "active"
            }
            .flatMap(narrativeCueDescriptors)
            .filter { $0.plaqueTreatmentAccentIdentifier != "none" }
            .reduce(into: [String: PlaqueTreatmentLegendEntry]()) { entries, descriptor in
                let accent = descriptor.plaqueTreatmentAccentIdentifier
                guard entries[accent] == nil else { return }
                entries[accent] = PlaqueTreatmentLegendEntry(
                    accentIdentifier: accent,
                    routeIdentifier: descriptor.plaqueTreatmentRouteIdentifier,
                    renderRecipeIdentifier: descriptor.plaqueTreatmentRenderRecipeIdentifier,
                    primitiveIdentifiers: descriptor.plaqueTreatmentRenderPrimitiveIdentifiers,
                    primitiveCount: descriptor.plaqueTreatmentRenderPrimitiveCount
                )
            }

        return entries.values.sorted { lhs, rhs in
            plaqueTreatmentLegendOrder(lhs.accentIdentifier)
                < plaqueTreatmentLegendOrder(rhs.accentIdentifier)
        }
    }

    private static func plaqueTreatmentLegendDetail(_ entry: PlaqueTreatmentLegendEntry) -> String {
        let primitiveIdentifiers = entry.primitiveIdentifiers.isEmpty
            ? "none"
            : entry.primitiveIdentifiers.joined(separator: ",")
        return [
            "accent \(entry.accentIdentifier)",
            "route \(entry.routeIdentifier)",
            "recipe \(entry.renderRecipeIdentifier)",
            "primitives \(entry.primitiveCount) \(primitiveIdentifiers)"
        ].joined(separator: " | ")
    }

    private static func plaqueTreatmentLegendOrder(_ accentIdentifier: String) -> Int {
        switch accentIdentifier {
        case "verify-seal":
            return 0
        case "warning-rails":
            return 1
        case "failure-fracture":
            return 2
        case "retry-braces":
            return 3
        default:
            return 100
        }
    }

    private static func narrativeCueDescriptors(
        _ report: CinematicDiagnosticsReport
    ) -> [CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot] {
        [
            report.narrativeCue.questPlaque,
            report.narrativeCue.arenaInscription,
            report.narrativeCue.activityBanner
        ]
    }

    private static func effectPulseDetail(_ snapshot: CinematicDiagnosticsReport.StageEffectSnapshot) -> String {
        let values = [
            snapshot.phaseLightPulseIdentifiers.isEmpty
                ? nil
                : "light \(snapshot.phaseLightPulseIdentifiers.joined(separator: ","))",
            snapshot.sparkBurstIdentifiers.isEmpty
                ? nil
                : "sparks \(snapshot.sparkBurstIdentifiers.joined(separator: ","))",
            snapshot.cameraShakeIdentifiers.isEmpty
                ? nil
                : "camera \(snapshot.cameraShakeIdentifiers.joined(separator: ","))",
            optionalIdentifier("victory", snapshot.victoryCadenceIdentifier)
        ].compactMap { $0 }

        return values.isEmpty ? "none" : values.joined(separator: " | ")
    }

    private static func narrativeCueDetail(_ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot) -> String {
        var details = [String]()
        if let nativeDetail = nativeFeedbackNarrativeDetail(snapshot) {
            details.append(nativeDetail)
        }
        details.append(contentsOf: [
            narrativeCueDescriptorDetail("quest", snapshot.questPlaque),
            narrativeCueDescriptorDetail("arena", snapshot.arenaInscription),
            narrativeCueDescriptorDetail("activity", snapshot.activityBanner)
        ])
        return details.joined(separator: " | ")
    }

    private static func narrativeLayoutDetail(_ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot) -> String {
        [
            narrativeCueLayoutDescriptorDetail("quest", snapshot.questPlaque.layout),
            narrativeCueLayoutDescriptorDetail("arena", snapshot.arenaInscription.layout),
            narrativeCueLayoutDescriptorDetail("activity", snapshot.activityBanner.layout)
        ].joined(separator: " | ")
    }

    private static func overlayDisplayDetail(_ snapshot: CinematicDiagnosticsReport.OverlayDisplaySnapshot) -> String {
        let details = [
            "mode \(snapshot.modeIdentifier)",
            "reason \(snapshot.reasonIdentifier)",
            "pills \(snapshot.visiblePillIdentifiers.isEmpty ? "none" : snapshot.visiblePillIdentifiers.joined(separator: ","))",
            "hud \(snapshot.hudProminenceIdentifier)",
            snapshot.nativeFeedbackCueIdentifier == "none" ? nil : "native \(snapshot.nativeFeedbackCueIdentifier)",
            snapshot.nativeFeedbackLifecycleIdentifier == "none"
                ? nil
                : "native-lifecycle \(snapshot.nativeFeedbackLifecycleIdentifier)",
            "native-banner \(snapshot.nativeFeedbackBannerPolicyIdentifier)",
            "chrome \(snapshot.chromeStyleIdentifier)",
            "gradient \(fixed(snapshot.gradientStrength))",
            "width \(fixed(snapshot.worldTextMaxWidth))/\(fixed(snapshot.hudMaxWidth))",
            "lines \(snapshot.pillLineLimit)/\(snapshot.hudTitleLineLimit)/\(snapshot.hudDetailLineLimit)/\(snapshot.hudProfileLineLimit)/\(snapshot.hudStatusLineLimit)",
            "opacity \(fixed(snapshot.overlayOpacity))"
        ].compactMap { $0 }
        return details.joined(separator: " | ")
    }

    private static func nativeFeedbackHistoryDetail(
        _ snapshot: CinematicDiagnosticsReport.NativeFeedbackSnapshot
    ) -> String {
        let entries = nativeFeedbackHistoryEntries(snapshot)
        guard !entries.isEmpty else { return "none" }
        return entries
            .map(nativeFeedbackHistoryEntryDetail)
            .joined(separator: " | ")
    }

    private static func makeNativeFeedbackHistoryExport(
        _ snapshot: CinematicDiagnosticsReport.NativeFeedbackSnapshot
    ) -> NativeFeedbackHistoryExport {
        let historyEntries = nativeFeedbackHistoryEntries(snapshot)
        let entries = historyEntries.map(nativeFeedbackHistoryExportEntry)
        let activeCount = entries.filter { $0.stateIdentifier == "active" }.count
        let archivedCount = entries.filter { $0.stateIdentifier == "archived" }.count
        let maxSequence = entries.map(\.sequence).max() ?? 0
        let omittedCount = max(0, maxSequence - entries.count)
        let copyText = nativeFeedbackHistoryExportCopyText(
            entries: entries,
            activeCount: activeCount,
            archivedCount: archivedCount,
            omittedCount: omittedCount
        )

        return NativeFeedbackHistoryExport(
            id: "native-feedback-history-export",
            rowID: "native-feedback-history",
            activeCount: activeCount,
            archivedCount: archivedCount,
            omittedCount: omittedCount,
            entries: entries,
            copyText: copyText
        )
    }

    private static func nativeFeedbackHistoryEntries(
        _ snapshot: CinematicDiagnosticsReport.NativeFeedbackSnapshot
    ) -> [CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot] {
        [snapshot.lifecycleActiveHistoryEntry].compactMap { $0 }
            + snapshot.lifecycleArchiveHistoryEntries
    }

    private static func nativeFeedbackHistoryExportEntry(
        _ entry: CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot
    ) -> NativeFeedbackHistoryExport.Entry {
        NativeFeedbackHistoryExport.Entry(
            identifier: entry.identifier,
            sequence: entry.sequence,
            stateIdentifier: entry.stateIdentifier,
            reasonIdentifier: entry.reasonIdentifier,
            milestoneIdentifier: entry.milestoneIdentifier,
            sourceIdentifier: entry.sourceIdentifier,
            styleIdentifier: entry.styleIdentifier,
            displayDuration: entry.displayDuration,
            lifecycleIdentifier: entry.lifecycleIdentifier,
            copyLine: bounded(
                nativeFeedbackHistoryEntryDetail(entry),
                limit: nativeFeedbackHistoryExportEntryMaxCharacters
            )
        )
    }

    private static func nativeFeedbackHistoryExportCopyText(
        entries: [NativeFeedbackHistoryExport.Entry],
        activeCount: Int,
        archivedCount: Int,
        omittedCount: Int
    ) -> String {
        guard !entries.isEmpty else { return "" }

        let lines = [
            "Native feedback history",
            "Row: native-feedback-history",
            "Counts: active \(activeCount) | archived \(archivedCount) | omitted \(omittedCount)",
            "Entries:"
        ] + entries.map(\.copyLine)

        return boundedMultiline(
            lines.joined(separator: "\n"),
            limit: nativeFeedbackHistoryExportCopyMaxCharacters
        )
    }

    private static func nativeFeedbackDeliveryDetail(
        _ snapshot: NativeFeedbackDeliverySnapshot
    ) -> String {
        [
            "mode \(snapshot.mode.rawValue)",
            snapshot.notificationModeIdentifier,
            snapshot.speechModeIdentifier,
            "support \(snapshot.notificationSupportIdentifier)",
            "authorization \(snapshot.authorizationRequestStateIdentifier)",
            "notification-status \(snapshot.notificationAuthorizationStatusIdentifier)",
            "notification-allowed \(snapshot.notificationsAllowed ? "true" : "false")",
            "dedupe \(snapshot.recentDedupeCount)",
            "last \(snapshot.lastAttemptedMilestoneIdentifier)/\(snapshot.lastAttemptResultIdentifier)",
            "speech \(snapshot.speechStateIdentifier)"
        ].joined(separator: " | ")
    }

    private static func nativeFeedbackHistoryEntryDetail(
        _ entry: CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot
    ) -> String {
        [
            "#\(entry.sequence)",
            stateAndReasonDetail(entry),
            "milestone \(entry.milestoneIdentifier)",
            entry.sourceIdentifier.map { "source \($0)" },
            entry.styleIdentifier.map { "style \($0)" },
            "duration \(fixed(entry.displayDuration))s",
            "lifecycle \(entry.lifecycleIdentifier)"
        ].compactMap { $0 }.joined(separator: " ")
    }

    private static func stateAndReasonDetail(
        _ entry: CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot
    ) -> String {
        if let reason = entry.reasonIdentifier {
            return "\(entry.stateIdentifier)/\(reason)"
        }
        return entry.stateIdentifier
    }

    private static func nativeFeedbackNarrativeDetail(
        _ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot
    ) -> String? {
        guard snapshot.nativeFeedbackCueIdentifier != "none" else { return nil }
        let affected = snapshot.nativeFeedbackAffectedDescriptorIdentifiers.isEmpty
            ? "none"
            : snapshot.nativeFeedbackAffectedDescriptorIdentifiers.joined(separator: ",")
        let treatments = nativeFeedbackPlaqueTreatmentAccents(snapshot)
        let primitiveSets = nativeFeedbackPlaqueTreatmentPrimitiveSets(snapshot)
        return [
            "native",
            "source \(snapshot.nativeFeedbackSourceIdentifier)",
            "style \(snapshot.nativeFeedbackStyleIdentifier)",
            "milestone \(snapshot.nativeFeedbackMilestoneIdentifier)",
            "lifecycle \(snapshot.nativeFeedbackLifecycleIdentifier)",
            "treatments \(treatments.isEmpty ? "none" : treatments.joined(separator: ","))",
            "primitives \(primitiveSets.isEmpty ? "none" : primitiveSets.joined(separator: ","))",
            "affects \(affected)"
        ].joined(separator: " ")
    }

    private static func nativeFeedbackPlaqueTreatmentAccents(
        _ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot
    ) -> [String] {
        Array(
            Set([
                snapshot.questPlaque.plaqueTreatmentAccentIdentifier,
                snapshot.arenaInscription.plaqueTreatmentAccentIdentifier,
                snapshot.activityBanner.plaqueTreatmentAccentIdentifier
            ].filter { $0 != "none" })
        ).sorted()
    }

    private static func nativeFeedbackPlaqueTreatmentPrimitiveSets(
        _ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot
    ) -> [String] {
        Array(
            Set([
                snapshot.questPlaque.plaqueTreatmentRenderRecipeIdentifier,
                snapshot.arenaInscription.plaqueTreatmentRenderRecipeIdentifier,
                snapshot.activityBanner.plaqueTreatmentRenderRecipeIdentifier
            ].filter { $0 != "none" })
        ).sorted()
    }

    private static func commitConstellationDetail(
        _ snapshot: CinematicDiagnosticsReport.CommitConstellationSnapshot
    ) -> String {
        [
            "count \(snapshot.count)",
            optionalIdentifier("newest", snapshot.newestSubject),
            snapshot.nodeIdentifiers.isEmpty ? "nodes none" : "nodes \(snapshot.nodeIdentifiers.joined(separator: ","))",
            snapshot.branchIdentifiers.isEmpty ? "branches none" : "branches \(snapshot.branchIdentifiers.joined(separator: ","))",
            "focus \(snapshot.focusIdentifier)",
            "shot \(snapshot.focusShotIdentifier)",
            "look \(position(snapshot.focusLookTarget))",
            snapshot.usesFallbackFocus ? "fallback focus" : nil
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func idleStoryCycleDetail(
        _ snapshot: CinematicDiagnosticsReport.IdleStoryCycleSnapshot
    ) -> String {
        guard snapshot.isActive else {
            return "empty \(snapshot.suppressionReason)"
        }

        return [
            "active",
            "phase \(snapshot.phaseIdentifier)",
            snapshot.diagnosticsWarningBundleIdentifier == "none"
                ? nil
                : "warning-bundle \(bounded(snapshot.diagnosticsWarningBundleIdentifier, limit: 72))",
            snapshot.diagnosticsWarningBundleIdentifier == "none"
                ? nil
                : "warning-captures \(snapshot.diagnosticsWarningCaptureCount)",
            snapshot.diagnosticsWarningBundleIdentifier == "none"
                ? nil
                : "warning-targets \(snapshot.diagnosticsWarningTargetCount)",
            snapshot.diagnosticsWarningBundleIdentifier == "none"
                ? nil
                : "warning-count \(snapshot.diagnosticsWarningWarningCount)",
            identifierListDetail("warning ids", snapshot.diagnosticsWarningIdentifiers),
            identifierListDetail("repeated warnings", snapshot.diagnosticsWarningRepeatedIdentifiers),
            identifierListDetail("target ids", snapshot.diagnosticsWarningTargetIdentifiers),
            identifierListDetail("target anchors", snapshot.diagnosticsWarningTargetAnchors),
            identifierListDetail("related rows", snapshot.diagnosticsWarningRelatedRowAnchors),
            "choreo \(bounded(snapshot.choreographyIdentifier, limit: 80))",
            "source \(bounded(snapshot.sourceDescriptorIdentifier, limit: 80))",
            "target \(snapshot.targetKindIdentifier)",
            "cadence \(fixed(snapshot.cadence))",
            "dwell \(fixed(snapshot.dwellDuration))",
            "transition \(fixed(snapshot.transitionDurationScale))",
            "camera \(bounded(snapshot.cameraTreatmentIdentifier, limit: 96))",
            "pressure \(snapshot.cameraPressureIdentifier)",
            "anchor \(snapshot.anchorTreatmentIdentifier)",
            "bias \(fixed(snapshot.targetBias))",
            "damping \(fixed(snapshot.comfortDamping))",
            "shake \(snapshot.shakeHintIdentifier)",
            "pulse \(snapshot.pulseHintIdentifier)",
            "slot \(snapshot.cycleSlot)",
            "index \(snapshot.phaseIndex)",
            "suppression \(snapshot.suppressionReason)",
            "copy \(bounded(snapshot.phaseCopy, limit: 96))",
            "id \(bounded(snapshot.descriptorIdentifier, limit: 140))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func timelineFocusDetail(
        _ snapshot: CinematicDiagnosticsReport.TimelineFocusSnapshot
    ) -> String {
        guard snapshot.isActive else {
            return "none"
        }

        return [
            snapshot.selectedBeatID.map { "beat \($0)" },
            "kind \(snapshot.kindIdentifier)",
            snapshot.label.map { "label \($0)" },
            "shot \(snapshot.cameraShotIdentifier)",
            snapshot.lookTarget.map { "look \(position($0))" },
            "light \(snapshot.lightFamilyIdentifier)",
            "effect \(snapshot.arenaEffectIdentifier)",
            "phase \(fixed(snapshot.phaseLightIntensity))",
            optionalIdentifier("node", snapshot.commitNodeIdentifier),
            optionalIdentifier("recovery", snapshot.recoveryTreatmentIdentifier),
            snapshot.usesFallbackTarget ? "fallback target" : nil
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func planCompassDetail(
        _ section: CinematicPlanCompassPlan.SectionDescriptor
    ) -> String {
        section.diagnosticsDetail
    }

    private static func runRecapDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapSnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityIdentifier)"
        return [
            availability,
            snapshot.sessionNumber.map { "session \($0)" },
            "title \(snapshot.title)",
            "detail \(snapshot.detail)",
            "status \(snapshot.status)",
            "terminal \(snapshot.statusIdentifier)",
            "style \(snapshot.styleIdentifier)/\(snapshot.colorIdentifier)",
            "flavor \(snapshot.flavorStateIdentifier)",
            "title-source \(snapshot.titleSourceIdentifier)",
            "completed \(snapshot.completedCount)",
            "commits \(snapshot.commitHighlightCount)",
            "events \(snapshot.eventChipCount)",
            "image \(snapshot.systemImage)",
            snapshot.flavorIdentifier.map { "flavor-id \(bounded($0, limit: 96))" },
            snapshot.flavorSourceIdentifier.map { "flavor-source \(bounded($0, limit: 96))" },
            snapshot.sourceIdentifier.map { "source \(bounded($0, limit: 96))" },
            optionalIdentifier("newest", snapshot.newestCommitHighlight),
            snapshot.eventChipIdentifiers.isEmpty
                ? "chips none"
                : "chips \(snapshot.eventChipIdentifiers.joined(separator: ","))",
            "id \(bounded(snapshot.identifier, limit: 180))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapShareDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareSnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityReason)"
        return [
            availability,
            "share \(bounded(snapshot.identifier, limit: 64))",
            "recap \(bounded(snapshot.recapIdentifier, limit: 40))",
            "focus \(bounded(snapshot.recapFocusIdentifier ?? "none", limit: 40))",
            "end-card \(bounded(snapshot.endCardIdentifier ?? "none", limit: 40))",
            "copy \(snapshot.textLength) chars",
            "events \(snapshot.eventSummaryCount)",
            snapshot.visualDescriptorTokens.isEmpty
                ? "visual none"
                : "visual \(bounded(snapshot.visualDescriptorTokens.joined(separator: ","), limit: 260))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapShareArtifactDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareArtifactSnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityReason)"
        return [
            availability,
            snapshot.sessionNumber.map { "session \($0)" },
            "file \(snapshot.filename)",
            "artifact \(bounded(snapshot.identifier, limit: 74))",
            "share \(bounded(snapshot.shareIdentifier, limit: 42))",
            "recap \(bounded(snapshot.recapIdentifier, limit: 42))",
            "focus \(bounded(snapshot.recapFocusIdentifier ?? "none", limit: 42))",
            "end-card \(bounded(snapshot.endCardIdentifier ?? "none", limit: 42))",
            "copy \(snapshot.markdownLength) chars",
            "events \(snapshot.eventSummaryCount)",
            "visual \(snapshot.visualDescriptorTokenCount)",
            optionalIdentifier("commit", snapshot.commitHighlight)
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapShareArtifactHistoryDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareArtifactHistorySnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityReason)"
        return [
            availability,
            "total \(snapshot.totalCount)",
            "hidden \(snapshot.hiddenCount)",
            "retention \(snapshot.retentionLimit)",
            "cleanup candidates \(snapshot.cleanupCandidateCount)",
            snapshot.hiddenCleanupCandidateCount > 0 ? "hidden cleanup \(snapshot.hiddenCleanupCandidateCount)" : nil,
            snapshot.cleanupCandidateIdentifiers.isEmpty
                ? nil
                : "cleanup ids \(bounded(snapshot.cleanupCandidateIdentifiers.joined(separator: ","), limit: 120))",
            "warnings \(snapshot.warningCount)",
            "warning state \(snapshot.warningStateIdentifier)",
            snapshot.hiddenWarningCount > 0 ? "hidden warnings \(snapshot.hiddenWarningCount)" : nil,
            snapshot.warningIdentifiers.isEmpty
                ? nil
                : "warning ids \(bounded(snapshot.warningIdentifiers.joined(separator: ","), limit: 120))",
            "last cleanup \(snapshot.lastCleanupResultStatus) \(bounded(snapshot.lastCleanupResultIdentifier, limit: 54))",
            snapshot.latestSessionNumber.map { "latest session \($0)" },
            snapshot.latestFilename.map { "latest file \(bounded($0, limit: 72))" },
            "export \(bounded(snapshot.exportIdentifier, limit: 54))",
            "copy \(snapshot.exportMarkdownLength) chars",
            "id \(bounded(snapshot.identifier, limit: 54))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapShareArtifactRollupDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareArtifactRollupSnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityReason)"
        return [
            availability,
            snapshot.isSearchActive
                ? "search \(snapshot.searchQuerySnippet) \(snapshot.searchQueryFingerprint)"
                : "search none",
            "matches \(snapshot.matchingEntryCount)/\(snapshot.unfilteredVisibleCount)",
            "retained \(snapshot.retainedEntryCount)/\(snapshot.totalCount)",
            "hidden \(snapshot.hiddenCount)",
            snapshot.noMatchAvailabilityReason.map { "no-match \($0)" },
            "range \(snapshot.sessionRangeLabel)",
            "buckets \(snapshot.statusBucketSummary)",
            snapshot.newestSessionNumber.map { "newest S\($0)" },
            snapshot.newestFilename.map { "newest file \(bounded($0, limit: 72))" },
            snapshot.oldestSessionNumber.map { "oldest S\($0)" },
            snapshot.oldestFilename.map { "oldest file \(bounded($0, limit: 72))" },
            "cleanup candidates \(snapshot.cleanupCandidateCount)",
            snapshot.hiddenCleanupCandidateCount > 0 ? "hidden cleanup \(snapshot.hiddenCleanupCandidateCount)" : nil,
            "warning state \(snapshot.warningStateIdentifier)",
            "warnings \(snapshot.warningCount)",
            snapshot.hiddenWarningCount > 0 ? "hidden warnings \(snapshot.hiddenWarningCount)" : nil,
            snapshot.warningIdentifiers.isEmpty
                ? nil
                : "warning ids \(bounded(snapshot.warningIdentifiers.joined(separator: ","), limit: 120))",
            "copy \(snapshot.exportTextLength) chars",
            "export \(bounded(snapshot.exportIdentifier, limit: 54))",
            "id \(bounded(snapshot.identifier, limit: 54))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapShareArtifactComparisonDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareArtifactComparisonSnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityReason)"
        return [
            availability,
            snapshot.isSearchActive
                ? "search \(snapshot.searchQuerySnippet) \(snapshot.searchQueryFingerprint)"
                : "search none",
            "matches \(snapshot.matchingEntryCount)/\(snapshot.unfilteredVisibleCount)",
            snapshot.noMatchAvailabilityReason.map { "no-match \($0)" },
            "mode \(snapshot.targetModeIdentifier)",
            snapshot.selectedSessionNumber.map { "selected S\($0)" },
            snapshot.selectedFilename.map { "selected file \(bounded($0, limit: 72))" },
            snapshot.compareSessionNumber.map { "target S\($0)" },
            snapshot.compareFilename.map { "target file \(bounded($0, limit: 72))" },
            "direction \(snapshot.targetDirectionIdentifier)",
            snapshot.pinnedTargetEntryIdentifier.map { "pinned target \(bounded($0, limit: 54))" },
            "pinned state \(snapshot.pinnedTargetStateIdentifier)",
            snapshot.pinnedTargetUnavailableReasonIdentifier.map { "pinned unavailable \($0)" },
            "promoted hold \(snapshot.promotedHoldStateIdentifier)",
            snapshot.requestedSavedTourHoldEntryIdentifier.map {
                "promoted held id \(bounded($0, limit: 54))"
            },
            snapshot.retainedSavedTourHoldEntryIdentifier.map {
                "retained promoted hold \(bounded($0, limit: 54))"
            },
            snapshot.filteredSavedTourHoldEntryIdentifier.map {
                "filtered promoted hold \(bounded($0, limit: 54))"
            },
            "pins \(snapshot.pinnedEntryCount)",
            "retained pins \(snapshot.retainedPinnedEntryCount)",
            "missing pins \(snapshot.missingPinnedEntryCount)",
            "filtered pins \(snapshot.filteredPinnedEntryCount)",
            snapshot.missingPinnedEntryIdentifiers.isEmpty
                ? nil
                : "stale ids \(bounded(snapshot.missingPinnedEntryIdentifiers.joined(separator: ","), limit: 120))",
            snapshot.filteredPinnedEntryIdentifiers.isEmpty
                ? nil
                : "filtered ids \(bounded(snapshot.filteredPinnedEntryIdentifiers.joined(separator: ","), limit: 120))",
            "delta \(snapshot.sessionDelta.map(String.init) ?? "none")",
            "fallback reason \(snapshot.selectedFallbackReasonIdentifier)",
            "cleanup candidates \(snapshot.cleanupCandidateCount)",
            snapshot.hiddenCleanupCandidateCount > 0 ? "hidden cleanup \(snapshot.hiddenCleanupCandidateCount)" : nil,
            "warning state \(snapshot.warningStateIdentifier)",
            "warnings \(snapshot.warningCount)",
            snapshot.hiddenWarningCount > 0 ? "hidden warnings \(snapshot.hiddenWarningCount)" : nil,
            snapshot.warningIdentifiers.isEmpty
                ? nil
                : "warning ids \(bounded(snapshot.warningIdentifiers.joined(separator: ","), limit: 120))",
            "copy \(snapshot.exportTextLength) chars",
            "export \(bounded(snapshot.exportIdentifier, limit: 54))",
            snapshot.selectedEntryIdentifier.map { "selected \(bounded($0, limit: 54))" },
            snapshot.compareEntryIdentifier.map { "compare \(bounded($0, limit: 54))" },
            "id \(bounded(snapshot.identifier, limit: 54))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapShareArtifactPinsDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareArtifactPinnedReferenceSnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityReason)"
        return [
            availability,
            snapshot.isSearchActive
                ? "search \(snapshot.searchQuerySnippet) \(snapshot.searchQueryFingerprint)"
                : "search none",
            "matches \(snapshot.matchingEntryCount)/\(snapshot.unfilteredVisibleCount)",
            snapshot.noMatchAvailabilityReason.map { "no-match \($0)" },
            "pins \(snapshot.pinnedEntryCount)",
            "retained pins \(snapshot.retainedPinnedEntryCount)",
            "missing pins \(snapshot.missingPinnedEntryCount)",
            "filtered pins \(snapshot.filteredPinnedEntryCount)",
            "quick \(snapshot.quickSelectEntryCount)",
            "selected pin \(snapshot.selectedPinStateIdentifier)",
            "copy \(snapshot.exportTextLength) chars",
            snapshot.missingPinnedEntryIdentifiers.isEmpty
                ? nil
                : "stale ids \(bounded(snapshot.missingPinnedEntryIdentifiers.joined(separator: ","), limit: 120))",
            snapshot.filteredPinnedEntryIdentifiers.isEmpty
                ? nil
                : "filtered ids \(bounded(snapshot.filteredPinnedEntryIdentifiers.joined(separator: ","), limit: 120))",
            snapshot.quickSelectEntryIdentifiers.isEmpty
                ? nil
                : "quick ids \(bounded(snapshot.quickSelectEntryIdentifiers.joined(separator: ","), limit: 120))",
            snapshot.selectedEntryIdentifier.map { "selected \(bounded($0, limit: 54))" },
            snapshot.references.isEmpty
                ? nil
                : "refs \(bounded(snapshot.references.map { "S\($0.sessionNumber)" }.joined(separator: ","), limit: 80))",
            "warning state \(snapshot.warningStateIdentifier)",
            "warnings \(snapshot.warningCount)",
            snapshot.hiddenWarningCount > 0 ? "hidden warnings \(snapshot.hiddenWarningCount)" : nil,
            "export \(bounded(snapshot.exportIdentifier, limit: 54))",
            "id \(bounded(snapshot.identifier, limit: 54))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapShareArtifactTourDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareArtifactTourSnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityReason)"
        let position = snapshot.selectedOrdinal.map { "\($0)/\(snapshot.entryCount)" } ?? "none/\(snapshot.entryCount)"
        return [
            availability,
            "state \(snapshot.stateIdentifier)",
            "source \(snapshot.selectionSourceIdentifier)",
            "hold \(snapshot.savedTourHoldStateIdentifier)",
            snapshot.requestedSavedTourHoldEntryIdentifier.map {
                "held id \(bounded($0, limit: 54))"
            },
            snapshot.retainedSavedTourHoldEntryIdentifier.map {
                "retained held \(bounded($0, limit: 54))"
            },
            snapshot.filteredSavedTourHoldEntryIdentifier.map {
                "filtered held \(bounded($0, limit: 54))"
            },
            snapshot.isSearchActive
                ? "search \(snapshot.searchQuerySnippet) \(snapshot.searchQueryFingerprint)"
                : "search none",
            "matches \(snapshot.matchingEntryCount)/\(snapshot.unfilteredVisibleCount)",
            snapshot.noMatchAvailabilityReason.map { "no-match \($0)" },
            "selection \(position)",
            snapshot.sessionNumber.map { "session \($0)" },
            snapshot.filename.map { "file \(bounded($0, limit: 72))" },
            "pins \(snapshot.pinnedEntryCount)",
            "retained pins \(snapshot.retainedPinnedEntryCount)",
            "missing pins \(snapshot.missingPinnedEntryCount)",
            "filtered pins \(snapshot.filteredPinnedEntryCount)",
            snapshot.missingPinnedEntryIdentifiers.isEmpty
                ? nil
                : "stale ids \(bounded(snapshot.missingPinnedEntryIdentifiers.joined(separator: ","), limit: 120))",
            snapshot.filteredPinnedEntryIdentifiers.isEmpty
                ? nil
                : "filtered ids \(bounded(snapshot.filteredPinnedEntryIdentifiers.joined(separator: ","), limit: 120))",
            "warning state \(snapshot.warningStateIdentifier)",
            "warnings \(snapshot.warningCount)",
            snapshot.hiddenWarningCount > 0 ? "hidden warnings \(snapshot.hiddenWarningCount)" : nil,
            snapshot.warningIdentifiers.isEmpty
                ? nil
                : "warning ids \(bounded(snapshot.warningIdentifiers.joined(separator: ","), limit: 120))",
            "display \(snapshot.shouldDisplay)",
            "seed \(snapshot.rotationSeed)",
            snapshot.selectedEntryIdentifier.map { "entry \(bounded($0, limit: 54))" },
            "title \(snapshot.titleSnippet)",
            "status \(snapshot.statusSnippet)",
            "session text \(snapshot.sessionText)",
            optionalIdentifier("commit", snapshot.commitSnippet),
            "id \(bounded(snapshot.identifier, limit: 54))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapShareArtifactPreviewDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareArtifactPreviewSnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityReason)"
        let position = snapshot.selectedOrdinal.map { "\($0)/\(snapshot.entryCount)" } ?? "none/\(snapshot.entryCount)"
        return [
            availability,
            snapshot.isSearchActive
                ? "search \(snapshot.searchQuerySnippet) \(snapshot.searchQueryFingerprint)"
                : "search none",
            "matches \(snapshot.matchCount)/\(snapshot.unfilteredVisibleCount)",
            snapshot.noMatchAvailabilityReason.map { "no-match \($0)" },
            "selection \(position)",
            snapshot.sessionNumber.map { "session \($0)" },
            snapshot.filename.map { "file \(bounded($0, limit: 72))" },
            "fallback reason \(snapshot.selectedFallbackReasonIdentifier)",
            subsetExportDetail("selected export", snapshot.selectedExport),
            subsetExportDetail("filtered export", snapshot.filteredExport),
            "warning state \(snapshot.warningStateIdentifier)",
            "warnings \(snapshot.warningCount)",
            snapshot.selectedEntryIdentifier.map { "entry \(bounded($0, limit: 54))" },
            snapshot.selectedFallbackEntryIdentifier.map { "fallback \(bounded($0, limit: 54))" },
            "previous \(bounded(snapshot.previousEntryIdentifier ?? "none", limit: 54))",
            "next \(bounded(snapshot.nextEntryIdentifier ?? "none", limit: 54))",
            "title \(snapshot.titleSnippet)",
            "status \(snapshot.statusSnippet)",
            optionalIdentifier("commit", snapshot.commitSnippet),
            "markdown \(snapshot.markdownLength) chars",
            "id \(bounded(snapshot.identifier, limit: 54))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapShareArtifactCommandsDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareArtifactCommandSnapshot
    ) -> String {
        [
            "cmd \(snapshot.commandCount)/\(snapshot.actionCount) e\(snapshot.enabledCommandCount) d\(snapshot.disabledCommandCount)",
            "source-menu \(bounded(snapshot.sourceActionMenuIdentifier, limit: 24))",
            "command-plan \(bounded(snapshot.commandPlanIdentifier, limit: 24))",
            "history \(snapshot.historyAvailabilityReason)",
            "no-match \(snapshot.previewNoMatchAvailabilityReason ?? snapshot.tourNoMatchAvailabilityReason ?? "none")",
            "disabled \(identifierListSummary(snapshot.disabledActionKindIdentifiers, visibleLimit: 5))",
            "omitted \(identifierListSummary(snapshot.omittedActionKindIdentifiers, visibleLimit: 4))",
            "shortcuts \(identifierListSummary(snapshot.shortcutIdentifiers, visibleLimit: 3))",
            "exports s:\(snapshot.selectedExportAvailabilityReason) f:\(snapshot.filteredExportAvailabilityReason) r:\(snapshot.rollupAvailabilityReason) c:\(snapshot.comparisonAvailabilityReason)",
            "pins stale \(snapshot.missingPinnedEntryCount) filtered \(snapshot.filteredPinnedEntryCount)",
            "hold \(snapshot.tourSavedHoldStateIdentifier)",
            "promoted \(snapshot.comparisonPromotedHoldStateIdentifier)",
            "app-collisions \(snapshot.appLevelShortcutCollisionStateIdentifier) \(identifierListSummary(snapshot.appLevelShortcutCollisionIdentifiers.isEmpty ? snapshot.appLevelShortcutIdentifiers : snapshot.appLevelShortcutCollisionIdentifiers, visibleLimit: 3))",
            "sections \(commandSectionSummary(snapshot.sections))",
            snapshot.tourFilteredSavedHoldEntryIdentifier.map { "filtered hold \(bounded($0, limit: 32))" },
            "id \(bounded(snapshot.identifier, limit: 30))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapCommandAvailabilityAttentionDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareArtifactCommandSnapshot
    ) -> String {
        let collisionIdentifiers = snapshot.appLevelShortcutCollisionIdentifiers.isEmpty
            ? snapshot.appLevelShortcutIdentifiers
            : snapshot.appLevelShortcutCollisionIdentifiers
        let cleanupState = snapshot.omittedActionKindIdentifiers.contains("cleanupOldArtifacts")
            ? "omitted"
            : identifierListSummary(snapshot.omittedActionKindIdentifiers, visibleLimit: 2)
        let isCorrelated = !snapshot.commandPlanIdentifier.isEmpty
            && !snapshot.sourceActionMenuIdentifier.isEmpty
            && snapshot.commandPlanIdentifier != snapshot.sourceActionMenuIdentifier
            && snapshot.commandCount + snapshot.omittedActionKindIdentifiers.count == snapshot.actionCount

        return [
            "disabled \(identifierListSummary(snapshot.disabledActionKindIdentifiers, visibleLimit: 2))",
            "pins stale \(snapshot.missingPinnedEntryCount) filtered \(snapshot.filteredPinnedEntryCount)",
            "hold \(snapshot.tourSavedHoldStateIdentifier)",
            "promoted \(snapshot.comparisonPromotedHoldStateIdentifier)",
            "cleanup \(cleanupState)",
            "collisions \(snapshot.appLevelShortcutCollisionStateIdentifier) \(identifierListSummary(collisionIdentifiers, visibleLimit: 2))",
            "correlated \(isCorrelated ? "yes" : "no") \(snapshot.commandCount)+\(snapshot.omittedActionKindIdentifiers.count)/\(snapshot.actionCount)"
        ].joined(separator: " | ")
    }

    private static func subsetExportDetail(
        _ label: String,
        _ snapshot: CinematicDiagnosticsReport.RunRecapShareArtifactSubsetExportSnapshot
    ) -> String {
        let availability = snapshot.isAvailable
            ? "available"
            : "empty \(snapshot.availabilityReason)"
        return [
            "\(label) \(availability)",
            "e \(snapshot.exportEntryCount)",
            "selected \(snapshot.selectedCount)",
            "filtered \(snapshot.filteredCount)/\(snapshot.unfilteredVisibleCount)",
            "copy \(snapshot.markdownLength) chars",
            "q \(snapshot.searchQuerySnippet)",
            "warn \(snapshot.warningStateIdentifier)",
            "id \(bounded(snapshot.exportIdentifier, limit: 24))"
        ].joined(separator: " ")
    }

    private static func commandSectionSummary(
        _ sections: [CinematicDiagnosticsReport.RunRecapShareArtifactCommandSectionSnapshot]
    ) -> String {
        let summaries = sections.map { section in
            let prefix = section.sectionIdentifier.prefix(3)
            return "\(prefix):\(section.commandCount)/\(section.enabledCommandCount)/\(section.disabledCommandCount)"
        }
        return identifierListSummary(summaries, visibleLimit: 5)
    }

    private static func identifierListSummary(_ identifiers: [String], visibleLimit: Int) -> String {
        guard !identifiers.isEmpty else { return "none" }
        let visibleIdentifiers = identifiers.prefix(max(0, visibleLimit))
        let visibleText = visibleIdentifiers.joined(separator: ",")
        let hiddenCount = identifiers.count - visibleIdentifiers.count
        guard hiddenCount > 0 else {
            return bounded(visibleText, limit: 160)
        }
        return bounded("\(visibleText),+\(hiddenCount)", limit: 160)
    }

    private static func runRecapSceneFocusDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapSceneFocusSnapshot
    ) -> String {
        guard snapshot.isActive else {
            return "empty"
        }

        return [
            "active",
            "descriptor \(snapshot.descriptorIdentifier)",
            snapshot.terminalBeatID.map { "beat \($0)" },
            "terminal \(snapshot.terminalStatusIdentifier)",
            "style \(snapshot.terminalStyleIdentifier)",
            "shot \(snapshot.cameraShotIdentifier)",
            snapshot.lookTarget.map { "look \(position($0))" },
            optionalIdentifier("node", snapshot.commitNodeIdentifier),
            snapshot.usesFallbackTarget
                ? "fallback \(snapshot.fallbackTargetIdentifier ?? "target")"
                : nil,
            "light \(snapshot.lightFamilyIdentifier)",
            "effect \(snapshot.arenaEffectIdentifier)",
            "phase \(fixed(snapshot.phaseLightIntensity))",
            "id \(bounded(snapshot.identifier, limit: 180))"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func runRecapEndCardDetail(
        _ snapshot: CinematicDiagnosticsReport.RunRecapEndCardSnapshot
    ) -> String {
        guard snapshot.isActive else {
            return "empty"
        }

        return [
            "active",
            "descriptor \(bounded(snapshot.descriptorIdentifier, limit: 56))",
            "recap \(bounded(snapshot.recapIdentifier, limit: 56))",
            "pin cue \(snapshot.pinnedComparisonCueStateIdentifier)",
            "pin mode \(snapshot.pinnedComparisonCueModeIdentifier)",
            snapshot.hasPinnedComparisonCue
                ? "pin sessions S\(snapshot.pinnedComparisonCueSelectedSessionNumber ?? 0)->S\(snapshot.pinnedComparisonCueTargetSessionNumber ?? 0)"
                : nil,
            snapshot.hasPinnedComparisonCue
                ? "pin \(snapshot.pinnedComparisonCueDeltaLabel) \(snapshot.pinnedComparisonCueRailTreatmentIdentifier)"
                : nil,
            snapshot.hasPinnedComparisonCue
                && snapshot.pinnedComparisonCuePromotedHoldStateIdentifier != "none"
                ? "pin promoted hold \(snapshot.pinnedComparisonCuePromotedHoldStateIdentifier)"
                : nil,
            snapshot.pinnedComparisonCueNoMatchStateIdentifier == "none"
                ? nil
                : "pin no-match \(snapshot.pinnedComparisonCueNoMatchStateIdentifier)",
            snapshot.hasPinnedComparisonCue
                ? "pin counts \(snapshot.pinnedComparisonCueRetainedPinnedEntryCount)/\(snapshot.pinnedComparisonCuePinnedEntryCount) stale \(snapshot.pinnedComparisonCueMissingPinnedEntryCount) filtered \(snapshot.pinnedComparisonCueFilteredPinnedEntryCount)"
                : nil,
            "title-source \(snapshot.titleSourceIdentifier)",
            "flavor \(snapshot.flavorStateIdentifier)",
            "style \(snapshot.styleIdentifier)/\(snapshot.colorIdentifier)",
            "anchor \(snapshot.anchorIdentifier)",
            "treatment \(snapshot.plaqueTreatmentAccentIdentifier)/\(snapshot.plaqueTreatmentRouteIdentifier)",
            "lengths \(snapshot.titleLength)/\(snapshot.detailLength)/\(snapshot.statusLength)",
            "title \(bounded(snapshot.title, limit: 64))",
            "detail \(bounded(snapshot.detail, limit: 72))",
            "status \(bounded(snapshot.status, limit: 72))",
            "scale \(fixed(snapshot.scale))",
            "cadence \(fixed(snapshot.cadence))",
            "light \(snapshot.lightFamilyIdentifier)/\(snapshot.tintFamilyIdentifier)",
            "glyph \(snapshot.glyphIdentifier)",
            "plate \(fixed(snapshot.plateWidth))x\(fixed(snapshot.plateHeight))",
            "recipe \(snapshot.plaqueTreatmentRenderRecipeIdentifier)"
        ].compactMap { $0 }.joined(separator: " | ")
    }

    private static func narrativeCueLayoutDescriptorDetail(
        _ label: String,
        _ layout: CinematicDiagnosticsReport.NarrativeCueLayoutSnapshot
    ) -> String {
        [
            label,
            layout.facingModeIdentifier,
            "pos \(position(layout.anchorPosition))",
            "box \(fixed(layout.plateWidth))x\(fixed(layout.plateHeight))",
            "text \(fixed(layout.primaryTextWidth))/\(fixed(layout.secondaryTextWidth))",
            "font \(fixed(layout.primaryFontSize))/\(fixed(layout.secondaryFontSize))",
            "back \(fixed(layout.backingOpacity))",
            "glyph \(layout.glyphSideIdentifier)@\(position(layout.glyphOffset))",
            "z \(fixed(layout.plateZOffset))/\(fixed(layout.primaryTextOffset.z))/\(fixed(layout.glyphOffset.z))"
        ].joined(separator: " ")
    }

    private static func narrativeCueDescriptorDetail(
        _ label: String,
        _ descriptor: CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot
    ) -> String {
        [
            label,
            descriptor.anchorIdentifier,
            descriptor.visibilityIdentifier,
            descriptor.lightFamilyIdentifier,
            "tint \(descriptor.tintFamilyIdentifier)",
            narrativeCueTreatmentDetail(descriptor),
            "scale \(fixed(descriptor.scale))",
            "opacity \(fixed(descriptor.opacity))",
            "cadence \(fixed(descriptor.cadence))s",
            "\"\(descriptor.text)\""
        ].joined(separator: " ")
    }

    private static func narrativeCueTreatmentDetail(
        _ descriptor: CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot
    ) -> String {
        guard descriptor.plaqueTreatmentAccentIdentifier != "none" else {
            return "treatment none"
        }
        let primitives = descriptor.plaqueTreatmentRenderPrimitiveIdentifiers.isEmpty
            ? "none"
            : descriptor.plaqueTreatmentRenderPrimitiveIdentifiers.joined(separator: ",")
        return [
            "treatment \(descriptor.plaqueTreatmentAccentIdentifier)/\(descriptor.plaqueTreatmentRouteIdentifier)",
            "primitives \(primitives)",
            "count \(descriptor.plaqueTreatmentRenderPrimitiveCount)"
        ].joined(separator: " ")
    }

    private static func completedLabel(_ count: Int) -> String {
        count == 1 ? "1 completed" : "\(count) completed"
    }

    private static func position(_ value: SIMD3<Float>) -> String {
        [
            fixed(value.x),
            fixed(value.y),
            fixed(value.z)
        ].joined(separator: ",")
    }

    private static func fixed(_ value: Float) -> String {
        fixed(Double(value))
    }

    private static func fixed(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "-" }
        guard normalized.count > limit else { return normalized }

        let prefixLimit = max(1, limit - 3)
        let prefix = normalized.prefix(prefixLimit)
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func boundedMultiline(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map {
                $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !normalized.isEmpty else { return "" }
        guard normalized.count > limit else { return normalized }

        let prefixLimit = max(1, limit - 3)
        let prefix = normalized.prefix(prefixLimit)
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

struct CinematicDiagnosticsWarningBundleHistory: Equatable {
    static let maxEntries = 6
    static let copyTextMaxCharacters = 1_600
    static let entryCopyLineMaxCharacters = 320
    static let rollupRowCopyTextMaxCharacters = 640
    static let rollupRowDetailMaxCharacters = 220
    static let recentEntryRollupLimit = 3
    static let identifierMaxCharacters = CinematicVisualSmokeReport.warningIdentifierMaxCharacters
    static let visibleWarningIdentifierLimit = 6
    static let visibleAnchorLimit = 5

    var entries: [Entry] = []
    var omittedCount: Int = 0
    var nextSequence: Int = 1
    private(set) var currentUnresolvedBundle: Entry?

    var isAvailable: Bool {
        !entries.isEmpty
    }

    var hasCurrentUnresolvedBundle: Bool {
        currentUnresolvedBundle != nil
    }

    var capturedCount: Int {
        entries.reduce(omittedCount) { $0 + $1.captureCount }
    }

    var repeatedWarningIdentifiers: [String] {
        let repeatedAcrossCaptures = Self.repeatedIdentifiers(
            entries.flatMap { entry in
                Array(repeating: entry.warningIdentifiers, count: entry.captureCount).flatMap { $0 }
            }
        )
        return Self.orderedUnique(entries.flatMap(\.repeatedWarningIdentifiers) + repeatedAcrossCaptures)
    }

    var rollup: RollupDescriptor {
        Self.rollupDescriptor(
            entries: entries,
            omittedCount: omittedCount,
            capturedCount: capturedCount,
            currentUnresolvedBundle: currentUnresolvedBundle,
            repeatedWarningIdentifiers: repeatedWarningIdentifiers
        )
    }

    var copyLabel: String {
        rollup.copyLabel
    }

    var copyHelp: String {
        rollup.copyHelp
    }

    var copyText: String {
        rollup.copyText
    }

    struct Entry: Identifiable, Equatable {
        var id: String { "\(sequence)-\(bundleIdentifier)" }

        var sequence: Int
        var bundleIdentifier: String
        var captureCount: Int
        var targetCount: Int
        var warningCount: Int
        var targetIdentifiers: [String]
        var warningIdentifiers: [String]
        var repeatedWarningIdentifiers: [String]
        var targetAnchors: [String]
        var relatedRowAnchors: [String]

        var copyLine: String {
            CinematicDiagnosticsWarningBundleHistory.entryCopyLine(self)
        }
    }

    struct RollupDescriptor: Equatable {
        var id: String
        var stateIdentifier: String
        var stateLabel: String
        var stateDetail: String
        var entryCount: Int
        var capturedCount: Int
        var omittedCount: Int
        var currentBundleIdentifier: String?
        var repeatedWarningIdentifiers: [String]
        var targetAnchorSummary: String
        var relatedRowAnchorSummary: String
        var rows: [RowDescriptor]
        var copyLabel: String
        var copyHelp: String
        var copyText: String

        var isAvailable: Bool {
            entryCount > 0 && !copyText.isEmpty
        }

        var countsLabel: String {
            "entries \(entryCount) | captures \(capturedCount) | omitted \(omittedCount)"
        }

        var recentBundleRows: [RowDescriptor] {
            rows.filter { $0.kind == .recentBundle }
        }

        var groupedWarningIdentifierRows: [RowDescriptor] {
            rows.filter { $0.kind == .warningIdentifierGroup }
        }

        var repeatedIdentifierRows: [RowDescriptor] {
            rows.filter { $0.kind == .repeatedIdentifiers }
        }

        var anchorSummaryRows: [RowDescriptor] {
            rows.filter { $0.kind == .targetAnchors || $0.kind == .relatedRowAnchors }
        }

        struct RowDescriptor: Identifiable, Equatable {
            var id: String
            var kind: Kind
            var label: String
            var detail: String
            var countLabel: String
            var copyLabel: String
            var copyHelp: String
            var copyLine: String
            var copyText: String

            enum Kind: String, Equatable {
                case recentBundle = "recent-bundle"
                case warningIdentifierGroup = "warning-identifier-group"
                case repeatedIdentifiers = "repeated-identifiers"
                case targetAnchors = "target-anchors"
                case relatedRowAnchors = "related-row-anchors"
            }
        }
    }

    func recording(
        _ attentionSummary: CinematicDiagnosticsSummary.AttentionSummary
    ) -> CinematicDiagnosticsWarningBundleHistory {
        var history = self
        history.record(attentionSummary)
        return history
    }

    mutating func record(
        _ attentionSummary: CinematicDiagnosticsSummary.AttentionSummary
    ) {
        guard let entry = Self.entry(
            attentionSummary: attentionSummary,
            sequence: nextSequence
        ) else {
            currentUnresolvedBundle = nil
            return
        }

        if currentUnresolvedBundle?.bundleIdentifier == entry.bundleIdentifier,
           var last = entries.last,
           last.bundleIdentifier == entry.bundleIdentifier {
            last.captureCount += 1
            entries[entries.count - 1] = last
            currentUnresolvedBundle = last
            return
        }

        entries.append(entry)
        nextSequence += 1
        trimToLimit()
        currentUnresolvedBundle = entries.last
    }

    private mutating func trimToLimit() {
        let overflow = entries.count - Self.maxEntries
        guard overflow > 0 else { return }
        let removed = entries.prefix(overflow)
        omittedCount += removed.reduce(0) { $0 + $1.captureCount }
        entries.removeFirst(overflow)
    }

    private static func entry(
        attentionSummary: CinematicDiagnosticsSummary.AttentionSummary,
        sequence: Int
    ) -> Entry? {
        let targets = attentionSummary.targets
        guard !targets.isEmpty else { return nil }

        let targetIdentifiers = orderedUnique(targets.map(\.id))
        let targetAnchors = orderedUnique(targets.map(\.targetAnchorID))
        let warningIdentifiers = targets.flatMap(\.visibleWarningIdentifiers)
        let relatedRowAnchors = orderedUnique(
            targets.compactMap(\.relatedRowID).map { "diagnostics-row-\($0)" }
        )
        let bundleSeed = targets.map { target in
            [
                target.id,
                target.targetGroupID,
                target.targetAnchorID,
                target.relatedGroupID ?? "none",
                target.relatedRowID ?? "none",
                target.visibleWarningIdentifiers.joined(separator: ",")
            ].joined(separator: "/")
        }.joined(separator: "|")

        return Entry(
            sequence: sequence,
            bundleIdentifier: "warning-bundle-\(stableFingerprint(bundleSeed))",
            captureCount: 1,
            targetCount: targets.count,
            warningCount: targets.reduce(0) { $0 + $1.warningCount },
            targetIdentifiers: targetIdentifiers.map(safeToken),
            warningIdentifiers: orderedUnique(warningIdentifiers).map(safeToken),
            repeatedWarningIdentifiers: repeatedIdentifiers(warningIdentifiers).map(safeToken),
            targetAnchors: targetAnchors.map(safeToken),
            relatedRowAnchors: relatedRowAnchors.map(safeToken)
        )
    }

    private struct WarningIdentifierGroup: Equatable {
        var identifier: String
        var captureCount: Int
        var bundleCount: Int
        var sequences: [Int]
    }

    private static func rollupDescriptor(
        entries: [Entry],
        omittedCount: Int,
        capturedCount: Int,
        currentUnresolvedBundle: Entry?,
        repeatedWarningIdentifiers: [String]
    ) -> RollupDescriptor {
        let state = rollupStateDescriptor(
            entries: entries,
            currentUnresolvedBundle: currentUnresolvedBundle
        )
        let targetAnchors = orderedUnique(entries.flatMap(\.targetAnchors))
        let relatedRowAnchors = orderedUnique(entries.flatMap(\.relatedRowAnchors))
        let warningGroups = warningIdentifierGroups(entries: entries)
        let currentSequence = currentUnresolvedBundle?.sequence
        let rows = entries.isEmpty
            ? []
            : recentEntryRollupRows(entries: entries, currentSequence: currentSequence)
                + warningIdentifierGroupRows(warningGroups)
                + repeatedWarningIdentifierRows(
                    repeatedWarningIdentifiers,
                    warningGroups: warningGroups
                )
                + anchorSummaryRows(
                    targetAnchors: targetAnchors,
                    relatedRowAnchors: relatedRowAnchors
                )
        let targetAnchorSummary = identifierSummary(
            targetAnchors,
            visibleLimit: visibleAnchorLimit
        )
        let relatedRowAnchorSummary = identifierSummary(
            relatedRowAnchors,
            visibleLimit: visibleAnchorLimit
        )
        let copyText = rollupCopyText(
            stateIdentifier: state.identifier,
            stateLabel: state.label,
            stateDetail: state.detail,
            entryCount: entries.count,
            capturedCount: capturedCount,
            omittedCount: omittedCount,
            repeatedWarningIdentifiers: repeatedWarningIdentifiers,
            targetAnchorSummary: targetAnchorSummary,
            relatedRowAnchorSummary: relatedRowAnchorSummary,
            rows: rows
        )

        return RollupDescriptor(
            id: "cinematic-diagnostics-warning-bundle-history-rollup",
            stateIdentifier: state.identifier,
            stateLabel: state.label,
            stateDetail: state.detail,
            entryCount: entries.count,
            capturedCount: capturedCount,
            omittedCount: max(0, omittedCount),
            currentBundleIdentifier: currentUnresolvedBundle?.bundleIdentifier,
            repeatedWarningIdentifiers: repeatedWarningIdentifiers,
            targetAnchorSummary: targetAnchorSummary,
            relatedRowAnchorSummary: relatedRowAnchorSummary,
            rows: rows,
            copyLabel: entries.isEmpty ? "No warning bundles" : "Copy warning bundles",
            copyHelp: rollupCopyHelp(
                stateLabel: state.label,
                entryCount: entries.count,
                capturedCount: capturedCount,
                omittedCount: omittedCount
            ),
            copyText: copyText
        )
    }

    private static func rollupStateDescriptor(
        entries: [Entry],
        currentUnresolvedBundle: Entry?
    ) -> (identifier: String, label: String, detail: String) {
        guard !entries.isEmpty else {
            return (
                "empty",
                "No warning history",
                "No warning bundles have been captured."
            )
        }

        if let currentUnresolvedBundle {
            let detail = [
                "#\(currentUnresolvedBundle.sequence)",
                currentUnresolvedBundle.bundleIdentifier,
                "captures \(currentUnresolvedBundle.captureCount)",
                "targets \(currentUnresolvedBundle.targetCount)",
                "warnings \(currentUnresolvedBundle.warningCount)"
            ].joined(separator: " | ")
            return (
                "current-unresolved",
                "Current unresolved",
                bounded(detail, limit: rollupRowDetailMaxCharacters)
            )
        }

        let latestSequence = entries.last?.sequence ?? 0
        let detail = [
            "current diagnostics clear",
            "retained \(entries.count)",
            "latest #\(latestSequence)"
        ].joined(separator: " | ")
        return (
            "cleared-retained",
            "Cleared, retained",
            bounded(detail, limit: rollupRowDetailMaxCharacters)
        )
    }

    private static func rollupCopyHelp(
        stateLabel: String,
        entryCount: Int,
        capturedCount: Int,
        omittedCount: Int
    ) -> String {
        guard entryCount > 0 else { return "No warning bundle history to copy" }
        return bounded(
            "Copy warning bundle history: \(stateLabel.lowercased()), entries \(entryCount), captures \(capturedCount), omitted \(max(0, omittedCount))",
            limit: rollupRowDetailMaxCharacters
        )
    }

    private static func recentEntryRollupRows(
        entries: [Entry],
        currentSequence: Int?
    ) -> [RollupDescriptor.RowDescriptor] {
        let recentEntries = Array(entries.suffix(recentEntryRollupLimit).reversed())
        return recentEntries.map { entry in
            let isCurrent = currentSequence == entry.sequence
            let stateLabel = isCurrent ? "current" : "retained"
            let warnings = identifierSummary(
                entry.warningIdentifiers,
                visibleLimit: visibleWarningIdentifierLimit
            )
            let anchors = identifierSummary(
                entry.targetAnchors,
                visibleLimit: visibleAnchorLimit
            )
            let detail = bounded(
                "\(entry.bundleIdentifier) | \(entry.targetCount) targets | \(entry.warningCount) warnings | \(warnings) | anchors \(anchors)",
                limit: rollupRowDetailMaxCharacters
            )
            let copyText = rollupRowCopyText(
                lines: [
                    "Warning bundle history row",
                    "Kind: recent-bundle",
                    "State: \(stateLabel)",
                    "Bundle: \(entry.bundleIdentifier)",
                    "Sequence: #\(entry.sequence)",
                    "Counts: captures \(entry.captureCount) | targets \(entry.targetCount) | warnings \(entry.warningCount)",
                    "Target identifiers: \(identifierSummary(entry.targetIdentifiers, visibleLimit: visibleAnchorLimit))",
                    "Warning identifiers: \(warnings)",
                    "Repeated warning identifiers: \(entry.repeatedWarningIdentifiers.isEmpty ? "none" : identifierSummary(entry.repeatedWarningIdentifiers, visibleLimit: visibleWarningIdentifierLimit))",
                    "Target anchors: \(anchors)",
                    "Related row anchors: \(identifierSummary(entry.relatedRowAnchors, visibleLimit: visibleAnchorLimit))"
                ]
            )

            return RollupDescriptor.RowDescriptor(
                id: "warning-bundle-history-entry-\(entry.sequence)",
                kind: .recentBundle,
                label: "#\(entry.sequence) \(stateLabel)",
                detail: detail,
                countLabel: "x\(entry.captureCount)",
                copyLabel: "Copy warning bundle #\(entry.sequence)",
                copyHelp: bounded(
                    "Copy warning bundle #\(entry.sequence) anchors and warning identifiers",
                    limit: rollupRowDetailMaxCharacters
                ),
                copyLine: entry.copyLine,
                copyText: copyText
            )
        }
    }

    private static func warningIdentifierGroups(entries: [Entry]) -> [WarningIdentifierGroup] {
        var order: [String] = []
        var groups: [String: WarningIdentifierGroup] = [:]
        for entry in entries {
            for identifier in entry.warningIdentifiers {
                if groups[identifier] == nil {
                    order.append(identifier)
                    groups[identifier] = WarningIdentifierGroup(
                        identifier: identifier,
                        captureCount: 0,
                        bundleCount: 0,
                        sequences: []
                    )
                }
                if var group = groups[identifier] {
                    group.captureCount += entry.captureCount
                    group.bundleCount += 1
                    group.sequences.append(entry.sequence)
                    groups[identifier] = group
                }
            }
        }

        return order.compactMap { groups[$0] }
    }

    private static func warningIdentifierGroupRows(
        _ groups: [WarningIdentifierGroup]
    ) -> [RollupDescriptor.RowDescriptor] {
        groups.prefix(visibleWarningIdentifierLimit).map { group in
            let sequenceSummary = identifierSummary(
                group.sequences.map { "#\($0)" },
                visibleLimit: visibleAnchorLimit
            )
            let detail = bounded(
                "\(group.identifier) | captures \(group.captureCount) | bundles \(group.bundleCount) | seq \(sequenceSummary)",
                limit: rollupRowDetailMaxCharacters
            )
            let copyLine = bounded(
                "warning-group \(group.identifier) | captures \(group.captureCount) | bundles \(group.bundleCount) | sequences \(sequenceSummary)",
                limit: entryCopyLineMaxCharacters
            )
            let copyText = rollupRowCopyText(
                lines: [
                    "Warning bundle history row",
                    "Kind: warning-identifier-group",
                    "Warning identifier: \(group.identifier)",
                    "Counts: captures \(group.captureCount) | bundles \(group.bundleCount)",
                    "Sequences: \(sequenceSummary)"
                ]
            )

            return RollupDescriptor.RowDescriptor(
                id: "warning-bundle-history-warning-\(stableFingerprint(group.identifier))",
                kind: .warningIdentifierGroup,
                label: "Warning id",
                detail: detail,
                countLabel: "x\(group.captureCount)",
                copyLabel: "Copy warning identifier \(group.identifier)",
                copyHelp: bounded(
                    "Copy warning identifier group captures for \(group.identifier)",
                    limit: rollupRowDetailMaxCharacters
                ),
                copyLine: copyLine,
                copyText: copyText
            )
        }
    }

    private static func repeatedWarningIdentifierRows(
        _ repeatedWarningIdentifiers: [String],
        warningGroups: [WarningIdentifierGroup]
    ) -> [RollupDescriptor.RowDescriptor] {
        guard !repeatedWarningIdentifiers.isEmpty else { return [] }
        let groupsByIdentifier = Dictionary(uniqueKeysWithValues: warningGroups.map { ($0.identifier, $0) })
        let detailTokens = repeatedWarningIdentifiers.prefix(visibleWarningIdentifierLimit).map { identifier in
            let captureCount = max(2, groupsByIdentifier[identifier]?.captureCount ?? 2)
            return "\(identifier) x\(captureCount)"
        }
        let hiddenCount = repeatedWarningIdentifiers.count - detailTokens.count
        let detail = bounded(
            detailTokens.joined(separator: ", ") + (hiddenCount > 0 ? ", +\(hiddenCount)" : ""),
            limit: rollupRowDetailMaxCharacters
        )
        let repeatedSummary = identifierSummary(
            repeatedWarningIdentifiers,
            visibleLimit: visibleWarningIdentifierLimit
        )
        let copyLine = bounded(
            "repeated-warnings \(repeatedSummary)",
            limit: entryCopyLineMaxCharacters
        )
        let copyText = rollupRowCopyText(
            lines: [
                "Warning bundle history row",
                "Kind: repeated-identifiers",
                "Repeated warning identifiers: \(repeatedSummary)"
            ]
        )

        return [
            RollupDescriptor.RowDescriptor(
                id: "warning-bundle-history-repeated-warnings",
                kind: .repeatedIdentifiers,
                label: "Repeated ids",
                detail: detail,
                countLabel: "\(repeatedWarningIdentifiers.count)",
                copyLabel: "Copy repeated warning identifiers",
                copyHelp: "Copy repeated warning identifiers from retained warning bundles",
                copyLine: copyLine,
                copyText: copyText
            )
        ]
    }

    private static func anchorSummaryRows(
        targetAnchors: [String],
        relatedRowAnchors: [String]
    ) -> [RollupDescriptor.RowDescriptor] {
        let targetRow = anchorSummaryRow(
            id: "warning-bundle-history-target-anchors",
            kind: .targetAnchors,
            label: "Target anchors",
            anchors: targetAnchors
        )
        guard !relatedRowAnchors.isEmpty else { return [targetRow] }
        return [
            targetRow,
            anchorSummaryRow(
                id: "warning-bundle-history-related-row-anchors",
                kind: .relatedRowAnchors,
                label: "Related rows",
                anchors: relatedRowAnchors
            )
        ]
    }

    private static func anchorSummaryRow(
        id: String,
        kind: RollupDescriptor.RowDescriptor.Kind,
        label: String,
        anchors: [String]
    ) -> RollupDescriptor.RowDescriptor {
        let summary = identifierSummary(anchors, visibleLimit: visibleAnchorLimit)
        let copyLine = bounded(
            "\(kind.rawValue) \(summary)",
            limit: entryCopyLineMaxCharacters
        )
        let copyText = rollupRowCopyText(
            lines: [
                "Warning bundle history row",
                "Kind: \(kind.rawValue)",
                "Anchors: \(summary)"
            ]
        )

        return RollupDescriptor.RowDescriptor(
            id: id,
            kind: kind,
            label: label,
            detail: bounded(summary, limit: rollupRowDetailMaxCharacters),
            countLabel: "\(anchors.count)",
            copyLabel: "Copy \(label.lowercased())",
            copyHelp: "Copy \(label.lowercased()) from retained warning bundles",
            copyLine: copyLine,
            copyText: copyText
        )
    }

    private static func rollupCopyText(
        stateIdentifier: String,
        stateLabel: String,
        stateDetail: String,
        entryCount: Int,
        capturedCount: Int,
        omittedCount: Int,
        repeatedWarningIdentifiers: [String],
        targetAnchorSummary: String,
        relatedRowAnchorSummary: String,
        rows: [RollupDescriptor.RowDescriptor]
    ) -> String {
        guard entryCount > 0 else { return "" }

        let repeated = repeatedWarningIdentifiers.isEmpty
            ? "none"
            : identifierSummary(repeatedWarningIdentifiers, visibleLimit: visibleWarningIdentifierLimit)
        let lines = [
            "Cinematic diagnostics warning bundles",
            "Export correlation: warning summary targets, target anchors, and related diagnostics row anchors",
            "State: \(stateIdentifier) | \(stateLabel) | \(stateDetail)",
            "Counts: entries \(entryCount) | captures \(capturedCount) | omitted \(max(0, omittedCount))",
            "Repeated warnings: \(repeated)",
            "Target anchors: \(targetAnchorSummary)",
            "Related row anchors: \(relatedRowAnchorSummary)",
            "Rows:"
        ] + rows.map(\.copyLine)

        return boundedMultiline(
            lines.joined(separator: "\n"),
            limit: copyTextMaxCharacters
        )
    }

    private static func rollupRowCopyText(lines: [String]) -> String {
        boundedMultiline(
            lines.joined(separator: "\n"),
            limit: rollupRowCopyTextMaxCharacters
        )
    }

    private static func entryCopyLine(_ entry: Entry) -> String {
        let repeated = entry.repeatedWarningIdentifiers.isEmpty
            ? "none"
            : identifierSummary(entry.repeatedWarningIdentifiers, visibleLimit: visibleWarningIdentifierLimit)
        let related = entry.relatedRowAnchors.isEmpty
            ? "none"
            : identifierSummary(entry.relatedRowAnchors, visibleLimit: visibleAnchorLimit)
        let line = [
            "#\(entry.sequence)",
            "x\(entry.captureCount)",
            "\(entry.targetCount) targets",
            "\(entry.warningCount) warnings",
            "targets \(identifierSummary(entry.targetIdentifiers, visibleLimit: visibleAnchorLimit))",
            "warnings \(identifierSummary(entry.warningIdentifiers, visibleLimit: visibleWarningIdentifierLimit))",
            "repeated \(repeated)",
            "anchors \(identifierSummary(entry.targetAnchors, visibleLimit: visibleAnchorLimit))",
            "related \(related)"
        ].joined(separator: " | ")

        return bounded(line, limit: entryCopyLineMaxCharacters)
    }

    private static func identifierSummary(_ identifiers: [String], visibleLimit: Int) -> String {
        guard !identifiers.isEmpty else { return "none" }
        let visible = identifiers.prefix(max(0, visibleLimit))
        let hiddenCount = identifiers.count - visible.count
        let text = visible.joined(separator: ",")
        guard hiddenCount > 0 else {
            return bounded(text, limit: entryCopyLineMaxCharacters)
        }
        return bounded("\(text),+\(hiddenCount)", limit: entryCopyLineMaxCharacters)
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let token = safeToken(value)
            guard !seen.contains(token) else { continue }
            seen.insert(token)
            result.append(token)
        }
        return result
    }

    private static func repeatedIdentifiers(_ values: [String]) -> [String] {
        var counts: [String: Int] = [:]
        var result: [String] = []
        for value in values {
            let token = safeToken(value)
            counts[token, default: 0] += 1
            if counts[token] == 2 {
                result.append(token)
            }
        }
        return result
    }

    private static func stableFingerprint(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func safeToken(_ text: String) -> String {
        bounded(text, limit: identifierMaxCharacters)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "-" }
        guard normalized.count > limit else { return normalized }

        let prefixLimit = max(1, limit - 3)
        let prefix = normalized.prefix(prefixLimit)
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func boundedMultiline(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map {
                $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !normalized.isEmpty else { return "" }
        guard normalized.count > limit else { return normalized }

        let prefixLimit = max(1, limit - 3)
        let prefix = normalized.prefix(prefixLimit)
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

enum CinematicDiagnostics {
    struct ActivityCase: Equatable {
        var identifier: String
        var phase: String
        var immediateTitle: String
        var completedCount: Int
        var profile: RepositoryActivityProfile
        var isRunning: Bool = true
        var isAutoPlaying: Bool = false
        var isPaused: Bool = false
        var hasRepository: Bool = true
    }

    @MainActor
    static func currentReport(
        for project: CompassProject,
        idleStoryCyclePlan: CinematicIdleStoryCyclePlan? = nil,
        timelineFocusPlan: CinematicTimelineSceneFocusPlan = .none,
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan = .none,
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan = .none,
        nativeFeedbackDeliverySnapshot: NativeFeedbackDeliverySnapshot? = nil
    ) -> CinematicDiagnosticsReport {
        let commitConstellationPlan = project.cinematicCommitConstellationPlan
        let reliabilityFeedback = PlanReliabilityFeedback(
            state: project.state,
            sessions: project.sessions
        )
        let recoveryCuePlan = CinematicRecoveryCuePlanner.plan(
            recentRunCues: reliabilityFeedback.recentRunCues,
            influenceSettings: project.cinematicInfluenceSettings
        )
        let runRecapPlan = CinematicRunRecapPlanner.plan(
            state: project.state,
            sessions: project.sessions,
            isRunning: project.isRunning,
            isAutoPlaying: project.isAutoPlaying,
            recentRunCues: reliabilityFeedback.recentRunCues,
            commitConstellationPlan: commitConstellationPlan,
            nativeFeedbackLifecycle: project.cinematicNativeFeedbackCueLifecycle,
            flavor: project.cinematicRunRecapFlavor
        )
        let runRecapSharePlan = CinematicRunRecapSharePlanner.plan(
            recapPlan: runRecapPlan,
            recapFocusDescriptor: runRecapSceneFocusPlan.descriptor,
            endCardDescriptor: runRecapEndCardPlan.descriptor
        )
        let runRecapShareArtifactPlan = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: runRecapSharePlan,
            sessions: project.sessions
        )
        return report(
            repoName: project.displayName,
            phase: (project.isPaused ? LoopPhase.paused : project.phase).rawValue,
            immediateTitle: project.immediateTitle,
            completedCount: project.state.completed.count,
            planCompassPlan: CinematicPlanCompassPlan(state: project.state),
            latestEvent: project.liveLog.last.map(CinematicBriefingEvent.init(line:)),
            latestCommitSubject: commitConstellationPlan.newestSubject,
            languageProfile: project.languageProfile,
            activityProfile: project.activityProfile,
            influenceSettings: project.cinematicInfluenceSettings,
            isRunning: project.isRunning,
            isAutoPlaying: project.isAutoPlaying,
            isPaused: project.isPaused,
            hasRepository: project.hasRepository,
            commitConstellationPlan: commitConstellationPlan,
            recoveryCuePlan: recoveryCuePlan,
            idleStoryCyclePlan: idleStoryCyclePlan,
            isLiveFollowActive: CinematicIdleStoryCyclePlanner.hasLiveFollowTarget(lines: project.liveLog),
            hasExplicitUserFocus: timelineFocusPlan.descriptor != nil
                || runRecapSceneFocusPlan.descriptor != nil
                || runRecapEndCardPlan.descriptor != nil,
            timelineFocusPlan: timelineFocusPlan,
            runRecapPlan: runRecapPlan,
            runRecapSceneFocusPlan: runRecapSceneFocusPlan,
            runRecapEndCardPlan: runRecapEndCardPlan,
            runRecapShareArtifactPlan: runRecapShareArtifactPlan,
            runRecapShareArtifactHistoryPlan: project.cinematicRunRecapShareArtifactHistory,
            runRecapShareArtifactCleanupResult: project.cinematicRunRecapShareArtifactCleanup,
            runRecapShareArtifactPreviewSelectedEntryIdentifier:
                project.cinematicRunRecapShareArtifactLibraryContext.selectedEntryIdentifier,
            runRecapShareArtifactPreviewSearchQuery:
                project.cinematicRunRecapShareArtifactLibraryContext.searchText,
            runRecapShareArtifactComparisonTargetMode:
                project.cinematicRunRecapShareArtifactLibraryContext.comparisonTargetMode,
            runRecapShareArtifactPinnedEntryIdentifiers:
                project.cinematicRunRecapShareArtifactLibraryContext.pinnedEntryIdentifiers,
            runRecapShareArtifactSavedTourHoldEntryIdentifier:
                project.cinematicRunRecapShareArtifactLibraryContext.savedTourHoldEntryIdentifier,
            diagnosticsWarningBundleHistory: project.cinematicDiagnosticsWarningBundleHistory,
            nativeFeedbackCue: project.cinematicNativeFeedbackCue,
            nativeFeedbackLifecycle: project.cinematicNativeFeedbackCueLifecycle,
            nativeFeedbackDeliverySnapshot: nativeFeedbackDeliverySnapshot
                ?? NativeFeedbackService.shared.deliverySnapshot(mode: project.nativeFeedbackMode)
        )
    }

    static func report(
        repoName: String,
        phase: String,
        immediateTitle: String,
        completedCount: Int,
        planCompassPlan: CinematicPlanCompassPlan? = nil,
        latestEvent: CinematicBriefingEvent?,
        latestCommitSubject: String? = nil,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings,
        isRunning: Bool = true,
        isAutoPlaying: Bool = false,
        isPaused: Bool = false,
        hasRepository: Bool = true,
        commitConstellationPlan: CinematicCommitConstellationPlan = .empty,
        recoveryCuePlan: CinematicRecoveryCuePlan = .none,
        idleStoryCyclePlan: CinematicIdleStoryCyclePlan? = nil,
        idleStoryCycleSession: CinematicIdleStoryCyclePlan.SessionInput = CinematicIdleStoryCyclePlan.SessionInput(),
        isLiveFollowActive: Bool = false,
        hasExplicitUserFocus: Bool = false,
        timelineFocusPlan: CinematicTimelineSceneFocusPlan = .none,
        runRecapPlan: CinematicRunRecapPlan = .empty(reason: "no-finished-session"),
        runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan = .none,
        runRecapEndCardPlan: CinematicRunRecapEndCardPlan = .none,
        runRecapShareArtifactPlan providedRunRecapShareArtifactPlan: CinematicRunRecapShareArtifactPlan? = nil,
        runRecapShareArtifactHistoryPlan providedRunRecapShareArtifactHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan? = nil,
        runRecapShareArtifactCleanupResult providedRunRecapShareArtifactCleanupResult: CinematicRunRecapShareArtifactCleanupResult? = nil,
        runRecapShareArtifactPreviewSelectedEntryIdentifier: String? = nil,
        runRecapShareArtifactPreviewSearchQuery: String? = nil,
        runRecapShareArtifactComparisonTargetMode: CinematicRunRecapShareArtifactComparisonTargetMode = .adjacent,
        runRecapShareArtifactPinnedEntryIdentifiers: [String] = [],
        runRecapShareArtifactSavedTourHoldEntryIdentifier: String? = nil,
        diagnosticsWarningBundleHistory: CinematicDiagnosticsWarningBundleHistory = CinematicDiagnosticsWarningBundleHistory(),
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan? = nil,
        nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle = CinematicNativeFeedbackCueLifecycle(),
        nativeFeedbackDeliverySnapshot: NativeFeedbackDeliverySnapshot = NativeFeedbackDeliverySnapshot(
            mode: .notifications
        )
    ) -> CinematicDiagnosticsReport {
        let languageMotif = CinematicMotif.language(for: languageProfile)
        let activityMotif = CinematicMotif.activity(for: activityProfile)
        let briefing = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: repoName,
                currentPhase: phase,
                immediatePlanTitle: immediateTitle,
                completedCount: completedCount,
                latestEvent: latestEvent,
                latestCommitSubject: latestCommitSubject
            )
        )
        let worldText = CinematicWorldTextService.deterministicWorldText(
            for: CinematicWorldTextInput(
                repoName: repoName,
                currentPhase: phase,
                immediatePlanTitle: immediateTitle,
                completedCount: completedCount,
                latestEvent: latestEvent,
                latestCommitSubject: latestCommitSubject,
                languageProfile: languageProfile,
                activityProfile: activityProfile
            )
        )
        let influenceIdentifier = settingsIdentifier(influenceSettings)
        let languageSnapshot = languageSnapshot(for: languageMotif)
        let activitySnapshot = activitySnapshot(for: activityMotif)
        let recoveryCueSnapshot = recoveryCueSnapshot(for: recoveryCuePlan)
        let loopPhase = loopPhase(from: phase)
        let effectivePhase: LoopPhase = isPaused ? .paused : loopPhase
        let stageBeat = CinematicStageBeatPlanner.plan(
            phase: effectivePhase,
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
            influenceSettings: influenceSettings,
            recoveryCuePlan: recoveryCuePlan
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
            influenceSettings: influenceSettings,
            recoveryCuePlan: recoveryCuePlan
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
        let runRecapShareArtifactHistoryPlan = providedRunRecapShareArtifactHistoryPlan
            ?? CinematicRunRecapShareArtifactHistoryPlan.unavailable(reason: "not-scanned")
        let runRecapShareArtifactLibraryContext = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: runRecapShareArtifactPreviewSelectedEntryIdentifier,
            searchText: runRecapShareArtifactPreviewSearchQuery ?? "",
            pinnedEntryIdentifiers: runRecapShareArtifactPinnedEntryIdentifiers,
            comparisonTargetMode: runRecapShareArtifactComparisonTargetMode,
            savedTourHoldEntryIdentifier: runRecapShareArtifactSavedTourHoldEntryIdentifier
        )
        let runRecapShareArtifactTourPlan = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: runRecapShareArtifactHistoryPlan,
            libraryContext: runRecapShareArtifactLibraryContext,
            rotationSeed: idleStoryCycleSession.sessionOrdinal
        )
        let resolvedIdleStoryCyclePlan = idleStoryCyclePlan ?? CinematicIdleStoryCyclePlanner.plan(
            session: idleStoryCycleSession,
            isLiveFollowActive: isLiveFollowActive,
            hasExplicitUserFocus: hasExplicitUserFocus,
            influenceSettings: influenceSettings,
            commitConstellationPlan: commitConstellationPlan,
            timelineSceneFocusPlan: timelineFocusPlan,
            nativeFeedbackCue: nativeFeedbackCue,
            nativeFeedbackPlaqueDescriptor: nativeFeedbackCue == nil ? nil : narrativeCuePlan.questPlaque,
            diagnosticsWarningBundleHistory: diagnosticsWarningBundleHistory,
            runRecapPlan: runRecapPlan,
            runRecapSceneFocusPlan: runRecapSceneFocusPlan,
            runRecapEndCardPlan: runRecapEndCardPlan,
            runRecapShareArtifactTourPlan: runRecapShareArtifactTourPlan
        )
        let stageBeatSnapshot = stageBeatSnapshot(for: stageBeat)
        let stageEffectSnapshot = stageEffectSnapshot(for: stageEffectPlan)
        let stageAtmosphereSnapshot = stageAtmosphereSnapshot(for: stageAtmospherePlan)
        let stagePhasePolishSnapshot = stagePhasePolishSnapshot(for: stagePhasePolishPlan)
        let narrativeCueSnapshot = narrativeCueSnapshot(for: narrativeCuePlan)
        let nativeFeedbackSnapshot = nativeFeedbackSnapshot(
            for: nativeFeedbackCue,
            lifecycle: nativeFeedbackLifecycle,
            narrativeCuePlan: narrativeCuePlan
        )
        let narrativeCueReadability = CinematicNarrativeCueReadabilitySignals(plan: narrativeCuePlan)
        let nativeFeedbackLifecycleIdentifier = nativeFeedbackLifecycle.hasState
            ? nativeFeedbackLifecycle.identifier
            : nil
        let overlayDisplayPlan = CinematicOverlayDisplayPlanner.plan(
            phase: loopPhase,
            isRunning: isRunning,
            isAutoPlaying: isAutoPlaying,
            isPaused: isPaused,
            hasRepository: hasRepository,
            worldText: worldText,
            briefing: briefing,
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings,
            narrativeCueReadability: narrativeCueReadability,
            nativeFeedbackCue: nativeFeedbackCue,
            nativeFeedbackLifecycleIdentifier: nativeFeedbackLifecycleIdentifier
        )
        let overlayDisplaySnapshot = overlayDisplaySnapshot(for: overlayDisplayPlan)
        let worldTextSnapshot = worldTextSnapshot(for: worldText)
        let briefingSnapshot = briefingSnapshot(for: briefing)
        let cameraTuningSnapshot = cameraTuningSnapshot(settings: influenceSettings)
        let activityTuningSnapshot = activityTuningSnapshot(
            activityProfile: activityProfile,
            settings: influenceSettings
        )
        let setDressingSnapshot = setDressingSnapshot(for: setDressingPlan)
        let commitConstellationSnapshot = commitConstellationSnapshot(for: commitConstellationPlan)
        let idleStoryCycleSnapshot = idleStoryCycleSnapshot(for: resolvedIdleStoryCyclePlan)
        let timelineFocusSnapshot = timelineFocusSnapshot(for: timelineFocusPlan)
        let runRecapSnapshot = runRecapSnapshot(for: runRecapPlan)
        let runRecapSceneFocusSnapshot = runRecapSceneFocusSnapshot(for: runRecapSceneFocusPlan)
        let runRecapEndCardSnapshot = runRecapEndCardSnapshot(for: runRecapEndCardPlan)
        let runRecapSharePlan = CinematicRunRecapSharePlanner.plan(
            recapPlan: runRecapPlan,
            recapFocusDescriptor: runRecapSceneFocusPlan.descriptor,
            endCardDescriptor: runRecapEndCardPlan.descriptor
        )
        let runRecapShareArtifactPlan = providedRunRecapShareArtifactPlan
            ?? CinematicRunRecapShareArtifactPlanner.plan(
                sharePlan: runRecapSharePlan,
                sessionNumber: runRecapPlan.sessionNumber
            )
        let runRecapShareSnapshot = runRecapShareSnapshot(for: runRecapSharePlan)
        let runRecapShareArtifactSnapshot = runRecapShareArtifactSnapshot(for: runRecapShareArtifactPlan)
        let runRecapShareArtifactHistorySnapshot = runRecapShareArtifactHistorySnapshot(
            for: runRecapShareArtifactHistoryPlan,
            cleanupResult: providedRunRecapShareArtifactCleanupResult
        )
        let runRecapShareArtifactPreviewPlan = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: runRecapShareArtifactHistoryPlan,
            selectedEntryIdentifier: runRecapShareArtifactPreviewSelectedEntryIdentifier,
            searchQuery: runRecapShareArtifactPreviewSearchQuery
        )
        let selectedRunRecapShareArtifactExportPlan = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: runRecapShareArtifactHistoryPlan,
            selectedEntryIdentifier: runRecapShareArtifactPreviewSelectedEntryIdentifier,
            searchQuery: runRecapShareArtifactPreviewSearchQuery,
            scope: .selected
        )
        let filteredRunRecapShareArtifactExportPlan = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: runRecapShareArtifactHistoryPlan,
            selectedEntryIdentifier: runRecapShareArtifactPreviewSelectedEntryIdentifier,
            searchQuery: runRecapShareArtifactPreviewSearchQuery,
            scope: .filtered
        )
        let runRecapShareArtifactRollupPlan = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: runRecapShareArtifactHistoryPlan,
            selectedEntryIdentifier: runRecapShareArtifactPreviewSelectedEntryIdentifier,
            searchQuery: runRecapShareArtifactPreviewSearchQuery
        )
        let runRecapShareArtifactComparisonPlan = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: runRecapShareArtifactHistoryPlan,
            selectedEntryIdentifier: runRecapShareArtifactPreviewSelectedEntryIdentifier,
            searchQuery: runRecapShareArtifactPreviewSearchQuery,
            targetMode: runRecapShareArtifactComparisonTargetMode,
            pinnedEntryIdentifiers: runRecapShareArtifactPinnedEntryIdentifiers,
            savedTourHoldEntryIdentifier: runRecapShareArtifactSavedTourHoldEntryIdentifier
        )
        let runRecapShareArtifactPinnedReferencePlan = CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: runRecapShareArtifactHistoryPlan,
            pinnedEntryIdentifiers: runRecapShareArtifactPinnedEntryIdentifiers,
            selectedEntryIdentifier: runRecapShareArtifactPreviewSelectedEntryIdentifier,
            searchQuery: runRecapShareArtifactPreviewSearchQuery
        )
        let runRecapShareArtifactActionMenuPlan = CinematicRunRecapShareArtifactActionMenuPlanner.plan(
            previewPlan: runRecapShareArtifactPreviewPlan,
            rollupPlan: runRecapShareArtifactRollupPlan,
            comparisonPlan: runRecapShareArtifactComparisonPlan,
            pinnedReferencePlan: runRecapShareArtifactPinnedReferencePlan,
            tourPlan: runRecapShareArtifactTourPlan,
            selectedExportPlan: selectedRunRecapShareArtifactExportPlan,
            filteredExportPlan: filteredRunRecapShareArtifactExportPlan,
            historyPlan: runRecapShareArtifactHistoryPlan
        )
        let runRecapShareArtifactCommandPlan = CinematicRunRecapShareArtifactCommandPlanner.plan(
            actionMenuPlan: runRecapShareArtifactActionMenuPlan
        )
        let runRecapShareArtifactRollupSnapshot = runRecapShareArtifactRollupSnapshot(
            for: runRecapShareArtifactRollupPlan
        )
        let runRecapShareArtifactComparisonSnapshot = runRecapShareArtifactComparisonSnapshot(
            for: runRecapShareArtifactComparisonPlan
        )
        let runRecapShareArtifactPinnedReferenceSnapshot = runRecapShareArtifactPinnedReferenceSnapshot(
            for: runRecapShareArtifactPinnedReferencePlan
        )
        let runRecapShareArtifactTourSnapshot = runRecapShareArtifactTourSnapshot(
            for: runRecapShareArtifactTourPlan
        )
        let runRecapShareArtifactPreviewSnapshot = runRecapShareArtifactPreviewSnapshot(
            for: runRecapShareArtifactPreviewPlan,
            selectedExportPlan: selectedRunRecapShareArtifactExportPlan,
            filteredExportPlan: filteredRunRecapShareArtifactExportPlan
        )
        let runRecapShareArtifactCommandSnapshot = runRecapShareArtifactCommandSnapshot(
            commandPlan: runRecapShareArtifactCommandPlan,
            actionMenuPlan: runRecapShareArtifactActionMenuPlan,
            historyPlan: runRecapShareArtifactHistoryPlan,
            previewPlan: runRecapShareArtifactPreviewPlan,
            rollupPlan: runRecapShareArtifactRollupPlan,
            comparisonPlan: runRecapShareArtifactComparisonPlan,
            pinnedReferencePlan: runRecapShareArtifactPinnedReferencePlan,
            tourPlan: runRecapShareArtifactTourPlan,
            selectedExportPlan: selectedRunRecapShareArtifactExportPlan,
            filteredExportPlan: filteredRunRecapShareArtifactExportPlan
        )
        let cameraSnapshots = CinematicCameraShot.allCases.map {
            cameraSnapshot(for: $0, settings: influenceSettings)
        }

        var reportIdentifierParts = [
                "repo:\(repoName)",
                "phase:\(phase)",
                "language:\(languageSnapshot.identifier)",
                "activity:\(activitySnapshot.identifier)",
                "recovery:\(recoveryCueSnapshot.identifier)",
                "stage:\(stageBeatSnapshot.identifier)",
                "stage-effect:\(stageEffectSnapshot.identifier)",
                "stage-atmosphere:\(stageAtmosphereSnapshot.identifier)",
                "phase-polish:\(stagePhasePolishSnapshot.identifier)",
                "narrative-cues:\(narrativeCueSnapshot.identifier)",
                "native-feedback:\(nativeFeedbackSnapshot.identifier)",
                "native-feedback-delivery:\(nativeFeedbackDeliverySnapshot.identifier)",
                "overlay:\(overlayDisplaySnapshot.identifier)",
                "influence:\(influenceIdentifier)",
                "set-dressing:\(setDressingSnapshot.identifier)",
                "commit-constellation:\(commitConstellationSnapshot.identifier)",
                "idle-story-cycle:\(idleStoryCycleSnapshot.identifier)",
                "timeline-focus:\(timelineFocusSnapshot.identifier)",
                "run-recap:\(runRecapSnapshot.identifier)",
                "run-recap-share:\(runRecapShareSnapshot.identifier)",
                "run-recap-share-artifact:\(runRecapShareArtifactSnapshot.identifier)",
                "run-recap-share-artifact-history:\(runRecapShareArtifactHistorySnapshot.identifier)",
                "run-recap-share-artifact-rollup:\(runRecapShareArtifactRollupSnapshot.identifier)",
                "run-recap-share-artifact-comparison:\(runRecapShareArtifactComparisonSnapshot.identifier)",
                "run-recap-share-artifact-comparison-export:\(runRecapShareArtifactComparisonSnapshot.exportIdentifier)",
                "run-recap-share-artifact-comparison-mode:\(runRecapShareArtifactComparisonSnapshot.targetModeIdentifier)",
                "run-recap-share-artifact-comparison-pinned-target:\(runRecapShareArtifactComparisonSnapshot.pinnedTargetEntryIdentifier ?? "none")",
                "run-recap-share-artifact-comparison-pinned-state:\(runRecapShareArtifactComparisonSnapshot.pinnedTargetStateIdentifier)",
                "run-recap-share-artifact-comparison-promoted-hold:\(runRecapShareArtifactComparisonSnapshot.promotedHoldStateIdentifier)",
                "run-recap-share-artifact-pins:\(runRecapShareArtifactPinnedReferenceSnapshot.identifier)",
                "run-recap-share-artifact-pins-export:\(runRecapShareArtifactPinnedReferenceSnapshot.exportIdentifier)",
                "run-recap-share-artifact-tour:\(runRecapShareArtifactTourSnapshot.identifier)",
                "run-recap-share-artifact-tour-state:\(runRecapShareArtifactTourSnapshot.stateIdentifier)",
                "run-recap-share-artifact-tour-source:\(runRecapShareArtifactTourSnapshot.selectionSourceIdentifier)",
                "run-recap-share-artifact-tour-hold:\(runRecapShareArtifactTourSnapshot.savedTourHoldStateIdentifier)",
                "run-recap-share-artifact-tour-held-entry:\(runRecapShareArtifactTourSnapshot.requestedSavedTourHoldEntryIdentifier ?? "none")",
                "run-recap-share-artifact-preview:\(runRecapShareArtifactPreviewSnapshot.identifier)",
                "run-recap-share-artifact-selected-export:\(runRecapShareArtifactPreviewSnapshot.selectedExport.identifier)",
                "run-recap-share-artifact-filtered-export:\(runRecapShareArtifactPreviewSnapshot.filteredExport.identifier)",
                "run-recap-share-artifact-cleanup:\(runRecapShareArtifactHistorySnapshot.lastCleanupResultIdentifier)",
                "run-recap-share-artifact-commands:\(runRecapShareArtifactCommandSnapshot.identifier)",
                "run-recap-share-artifact-command-plan:\(runRecapShareArtifactCommandSnapshot.commandPlanIdentifier)",
                "run-recap-share-artifact-command-source-menu:\(runRecapShareArtifactCommandSnapshot.sourceActionMenuIdentifier)",
                "run-recap-share-artifact-command-collisions:\(runRecapShareArtifactCommandSnapshot.appLevelShortcutCollisionStateIdentifier)",
                "run-recap-focus:\(runRecapSceneFocusSnapshot.identifier)",
                "run-recap-end-card:\(runRecapEndCardSnapshot.identifier)",
                "run-recap-end-card-pinned-cue:\(runRecapEndCardSnapshot.pinnedComparisonCueIdentifier ?? "none")",
                "run-recap-end-card-pinned-cue-mode:\(runRecapEndCardSnapshot.pinnedComparisonCueModeIdentifier)",
                "run-recap-end-card-pinned-cue-state:\(runRecapEndCardSnapshot.pinnedComparisonCueStateIdentifier)",
                "run-recap-end-card-pinned-cue-promoted-hold:\(runRecapEndCardSnapshot.pinnedComparisonCuePromotedHoldStateIdentifier)",
                "run-recap-end-card-pinned-cue-no-match:\(runRecapEndCardSnapshot.pinnedComparisonCueNoMatchStateIdentifier)"
            ]
        if let planCompassPlan {
            reportIdentifierParts.append("plan-compass:\(planCompassPlan.identifier)")
            reportIdentifierParts.append("plan-compass-copy:\(planCompassPlan.copyIdentifier)")
            reportIdentifierParts.append("plan-compass-export:\(planCompassPlan.exportIdentifier)")
        }

        return CinematicDiagnosticsReport(
            identifier: reportIdentifierParts.joined(separator: "|"),
            repoName: repoName,
            phase: phase,
            immediateTitle: immediateTitle,
            completedCount: completedCount,
            planCompass: planCompassPlan,
            influenceIdentifier: influenceIdentifier,
            languageMotif: languageSnapshot,
            activityMotif: activitySnapshot,
            nativeFeedback: nativeFeedbackSnapshot,
            nativeFeedbackDelivery: nativeFeedbackDeliverySnapshot,
            recoveryCue: recoveryCueSnapshot,
            stageBeat: stageBeatSnapshot,
            stageEffect: stageEffectSnapshot,
            stageAtmosphere: stageAtmosphereSnapshot,
            stagePhasePolish: stagePhasePolishSnapshot,
            narrativeCue: narrativeCueSnapshot,
            overlayDisplay: overlayDisplaySnapshot,
            worldText: worldTextSnapshot,
            briefing: briefingSnapshot,
            cameraTuning: cameraTuningSnapshot,
            activityTuning: activityTuningSnapshot,
            setDressing: setDressingSnapshot,
            commitConstellation: commitConstellationSnapshot,
            idleStoryCycle: idleStoryCycleSnapshot,
            timelineFocus: timelineFocusSnapshot,
            runRecap: runRecapSnapshot,
            runRecapShare: runRecapShareSnapshot,
            runRecapShareArtifact: runRecapShareArtifactSnapshot,
            runRecapShareArtifactHistory: runRecapShareArtifactHistorySnapshot,
            runRecapShareArtifactRollup: runRecapShareArtifactRollupSnapshot,
            runRecapShareArtifactComparison: runRecapShareArtifactComparisonSnapshot,
            runRecapShareArtifactPins: runRecapShareArtifactPinnedReferenceSnapshot,
            runRecapShareArtifactTour: runRecapShareArtifactTourSnapshot,
            runRecapShareArtifactPreview: runRecapShareArtifactPreviewSnapshot,
            runRecapShareArtifactCommands: runRecapShareArtifactCommandSnapshot,
            runRecapSceneFocus: runRecapSceneFocusSnapshot,
            runRecapEndCard: runRecapEndCardSnapshot,
            cameraSnapshots: cameraSnapshots
        )
    }

    static func representativeSmokeMatrix(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicDiagnosticsReport] {
        RepositoryLanguage.allCases.flatMap { language in
            representativeActivityCases().flatMap { activityCase in
                CinematicRecoveryCuePlanner.representativePlans(influenceSettings: influenceSettings).map { recoveryCuePlan in
                    let commitConstellationPlan = representativeCommitConstellationPlan(for: activityCase)
                    let timelineFocusPlan = CinematicTimelineSceneFocusPlanner.representativePlan(
                        activityCaseIdentifier: activityCase.identifier,
                        recoveryCuePlan: recoveryCuePlan,
                        commitConstellationPlan: commitConstellationPlan
                    )
                    let runRecapContext = representativeRunRecapFocusContext(
                        for: activityCase,
                        commitConstellationPlan: commitConstellationPlan
                    )
                    return report(
                        repoName: "Diagnostics \(language.displayName)",
                        phase: activityCase.phase,
                        immediateTitle: activityCase.immediateTitle,
                        completedCount: activityCase.completedCount,
                        latestEvent: nil,
                        languageProfile: representativeLanguageProfile(for: language),
                        activityProfile: activityCase.profile,
                        influenceSettings: influenceSettings,
                        isRunning: activityCase.isRunning,
                        isAutoPlaying: activityCase.isAutoPlaying,
                        isPaused: activityCase.isPaused,
                        hasRepository: activityCase.hasRepository,
                        commitConstellationPlan: commitConstellationPlan,
                        recoveryCuePlan: recoveryCuePlan,
                        timelineFocusPlan: timelineFocusPlan,
                        runRecapPlan: runRecapContext.runRecapPlan,
                        runRecapSceneFocusPlan: runRecapContext.runRecapSceneFocusPlan,
                        runRecapEndCardPlan: runRecapContext.runRecapEndCardPlan
                    )
                }
            }
        }
    }

    static func representativeNativeFeedbackSmokeReports(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicDiagnosticsReport] {
        let start = Date(timeIntervalSinceReferenceDate: 7_000)
        let activeReports = [
            representativeNativeFeedbackSmokeReport(
                repoName: "Native Feedback Verify",
                phase: .verifying,
                immediateTitle: "Verify native feedback seal route",
                completedCount: 3,
                language: .swift,
                activityProfile: activityProfile(recentCommitCount: 1),
                influenceSettings: influenceSettings,
                milestone: .verifyStarted,
                recentRunCues: [:],
                now: start
            ),
            representativeNativeFeedbackSmokeReport(
                repoName: "Native Feedback Warning",
                phase: .developing,
                immediateTitle: "Retry develop with warning cue",
                completedCount: 2,
                language: .typeScriptJavaScript,
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 2)),
                influenceSettings: influenceSettings,
                milestone: .developRetrying,
                recentRunCues: [
                    11: representativeRunCue(
                        kind: .dirtyWorktree,
                        severity: .warning,
                        label: "Clean Worktree",
                        detail: "2 pending changes",
                        systemImage: "pencil.and.outline"
                    )
                ],
                now: start.addingTimeInterval(1)
            ),
            representativeNativeFeedbackSmokeReport(
                repoName: "Native Feedback Retry",
                phase: .developing,
                immediateTitle: "Retry develop after verify failure",
                completedCount: 2,
                language: .python,
                activityProfile: activityProfile(
                    recentFailedCount: 1,
                    lastTerminalStatus: .failed,
                    failureStreak: 1
                ),
                influenceSettings: influenceSettings,
                milestone: .developRetrying,
                recentRunCues: [
                    7: representativeRunCue(
                        kind: .failedVerify,
                        severity: .failure,
                        label: "Retry Develop",
                        detail: "swift test exited 65",
                        systemImage: "checkmark.seal.fill"
                    )
                ],
                now: start.addingTimeInterval(2)
            ),
            representativeNativeFeedbackSmokeReport(
                repoName: "Native Feedback Post Checks",
                phase: .failed,
                immediateTitle: "Post-check failure native cue",
                completedCount: 4,
                language: .go,
                activityProfile: activityProfile(recentCommitCount: 2),
                influenceSettings: influenceSettings,
                milestone: .postChecksFailed,
                recentRunCues: [:],
                now: start.addingTimeInterval(3)
            )
        ].compactMap { $0 }

        guard let expiredReport = representativeExpiredNativeFeedbackSmokeReport(
            influenceSettings: influenceSettings,
            now: start.addingTimeInterval(4)
        ) else {
            return activeReports
        }

        return activeReports + [expiredReport]
    }

    static func representativeIdleStoryCycleSmokeReports(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicDiagnosticsReport] {
        let commitConstellationPlan = CinematicTimelineSceneFocusPlanner.representativeCommitConstellationPlan()
        let timelineFocusPlan = CinematicTimelineSceneFocusPlanner.representativePlan(
            activityCaseIdentifier: "commit",
            recoveryCuePlan: .none,
            commitConstellationPlan: commitConstellationPlan
        )
        let activityCase = ActivityCase(
            identifier: "commit",
            phase: LoopPhase.succeeded.rawValue,
            immediateTitle: "Cycle idle cinematic story",
            completedCount: 5,
            profile: activityProfile(recentCommitCount: 2, lastTerminalStatus: .succeeded, successStreak: 2),
            isRunning: false
        )
        let recapContext = representativeRunRecapFocusContext(
            for: activityCase,
            commitConstellationPlan: commitConstellationPlan
        )
        let tourHistoryPlan = representativeSavedRecapArtifactTourHistoryPlan(
            caseIdentifier: "idle-cycle",
            warningCount: 0
        )
        let nativeFeedbackCue = CinematicNativeFeedbackCuePlanner.plan(
            milestone: .verifyStarted,
            content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Idle Story Cycle"),
            phase: .verifying,
            feedbackMode: .notifications,
            recentRunCues: [:]
        )
        let diagnosticsWarningBundleHistory = representativeDiagnosticsWarningBundleHistory()
        var elapsedTime: TimeInterval = 0
        var phaseReports: [CinematicDiagnosticsReport] = []
        for _ in CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases {
            let report = representativeIdleStoryCycleSmokeReport(
                influenceSettings: influenceSettings,
                activityCase: activityCase,
                commitConstellationPlan: commitConstellationPlan,
                timelineFocusPlan: timelineFocusPlan,
                nativeFeedbackCue: nativeFeedbackCue,
                recapContext: recapContext,
                tourHistoryPlan: tourHistoryPlan,
                diagnosticsWarningBundleHistory: diagnosticsWarningBundleHistory,
                session: CinematicIdleStoryCyclePlan.SessionInput(
                    elapsedTime: elapsedTime,
                    sessionOrdinal: 0
                ),
                isLiveFollowActive: false,
                hasExplicitUserFocus: false
            )
            phaseReports.append(report)
            elapsedTime += max(report.idleStoryCycle.cadence, 0.1) + 0.01
        }
        let suppressedReport = representativeIdleStoryCycleSmokeReport(
            influenceSettings: influenceSettings,
            activityCase: activityCase,
            commitConstellationPlan: commitConstellationPlan,
            timelineFocusPlan: timelineFocusPlan,
            nativeFeedbackCue: nativeFeedbackCue,
            recapContext: recapContext,
            tourHistoryPlan: tourHistoryPlan,
            diagnosticsWarningBundleHistory: diagnosticsWarningBundleHistory,
            session: CinematicIdleStoryCyclePlan.SessionInput(),
            isLiveFollowActive: true,
            hasExplicitUserFocus: false
        )

        return phaseReports + [suppressedReport]
    }

    private static func representativeDiagnosticsWarningBundleHistory() -> CinematicDiagnosticsWarningBundleHistory {
        var history = CinematicDiagnosticsWarningBundleHistory()
        history.record(
            CinematicDiagnosticsSummary.AttentionSummary(
                targets: [
                    CinematicDiagnosticsSummary.AttentionTarget(
                        id: "visual-smoke-idle-warning-pulse",
                        targetGroupID: "visual-smoke",
                        targetAnchorID: "visual-smoke-check-idle-story-cycle-coverage",
                        relatedGroupID: "repository-context",
                        relatedRowID: "idle-story-cycle",
                        label: "Idle warning pulse",
                        detail: "visual smoke warning pulse",
                        warningCount: 2,
                        visibleWarningIdentifiers: [
                            "visual-smoke.idle-story-cycle",
                            "visual-smoke.idle-story-cycle"
                        ],
                        copyText: "Idle warning pulse"
                    ),
                    CinematicDiagnosticsSummary.AttentionTarget(
                        id: "visual-smoke-idle-warning-anchor",
                        targetGroupID: "visual-smoke",
                        targetAnchorID: "visual-smoke-check-run-recap-artifact-command-availability",
                        relatedGroupID: "repository-context",
                        relatedRowID: "run-recap-share-artifact-commands",
                        label: "Command warning pulse",
                        detail: "visual smoke command warning",
                        warningCount: 1,
                        visibleWarningIdentifiers: ["visual-smoke.recap-artifact-commands"],
                        copyText: "Command warning pulse"
                    )
                ]
            )
        )
        return history
    }

    static func representativeSavedRecapArtifactTourSmokeReports(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicDiagnosticsReport] {
        [
            representativeSavedRecapArtifactTourSmokeReport(
                caseIdentifier: "recent",
                searchQuery: nil,
                pinnedSessions: [],
                missingPins: [],
                warningCount: 0,
                rotationSeed: 1,
                influenceSettings: influenceSettings
            ),
            representativeSavedRecapArtifactTourSmokeReport(
                caseIdentifier: "pinned",
                searchQuery: nil,
                pinnedSessions: [22],
                missingPins: [],
                warningCount: 0,
                rotationSeed: 0,
                influenceSettings: influenceSettings
            ),
            representativeSavedRecapArtifactTourSmokeReport(
                caseIdentifier: "held",
                searchQuery: nil,
                pinnedSessions: [22],
                missingPins: [],
                heldSession: 21,
                missingHold: nil,
                warningCount: 0,
                rotationSeed: 0,
                influenceSettings: influenceSettings
            ),
            representativeSavedRecapArtifactTourSmokeReport(
                caseIdentifier: "search-filtered",
                searchQuery: "selected archive beacon",
                pinnedSessions: [21],
                missingPins: [],
                warningCount: 0,
                rotationSeed: 0,
                influenceSettings: influenceSettings
            ),
            representativeSavedRecapArtifactTourSmokeReport(
                caseIdentifier: "filtered-hold",
                searchQuery: "selected archive beacon",
                pinnedSessions: [22],
                missingPins: [],
                heldSession: 21,
                missingHold: nil,
                warningCount: 0,
                rotationSeed: 0,
                influenceSettings: influenceSettings
            ),
            representativeSavedRecapArtifactTourSmokeReport(
                caseIdentifier: "no-match",
                searchQuery: "missing archive smoke",
                pinnedSessions: [],
                missingPins: [],
                warningCount: 0,
                rotationSeed: 0,
                influenceSettings: influenceSettings
            ),
            representativeSavedRecapArtifactTourSmokeReport(
                caseIdentifier: "stale-pin",
                searchQuery: nil,
                pinnedSessions: [],
                missingPins: ["missing-saved-tour-pin"],
                warningCount: 0,
                rotationSeed: 0,
                influenceSettings: influenceSettings
            ),
            representativeSavedRecapArtifactTourSmokeReport(
                caseIdentifier: "stale-hold",
                searchQuery: nil,
                pinnedSessions: [21],
                missingPins: [],
                heldSession: nil,
                missingHold: "missing-saved-tour-hold",
                warningCount: 0,
                rotationSeed: 0,
                influenceSettings: influenceSettings
            ),
            representativeSavedRecapArtifactTourSmokeReport(
                caseIdentifier: "warning",
                searchQuery: nil,
                pinnedSessions: [],
                missingPins: [],
                warningCount: 1,
                rotationSeed: 0,
                influenceSettings: influenceSettings
            )
        ]
    }

    static func representativePinnedComparisonCueSmokeReports(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicDiagnosticsReport] {
        let active = representativePinnedComparisonCueSmokeReport(
            caseIdentifier: "active",
            selectedSession: 12,
            targetSession: 10,
            searchQuery: nil,
            pinnedSessions: [10],
            missingPins: [],
            warningCount: 0,
            influenceSettings: influenceSettings
        )
        let selectedOnly = representativePinnedComparisonCueSmokeReport(
            caseIdentifier: "selected-only",
            selectedSession: 12,
            targetSession: 10,
            searchQuery: nil,
            pinnedSessions: [12],
            missingPins: [],
            warningCount: 0,
            influenceSettings: influenceSettings
        )
        let noMatch = representativePinnedComparisonCueSmokeReport(
            caseIdentifier: "no-match",
            selectedSession: 12,
            targetSession: 10,
            searchQuery: "missing pinned comparison smoke",
            pinnedSessions: [10],
            missingPins: [],
            warningCount: 0,
            influenceSettings: influenceSettings
        )
        let stale = representativePinnedComparisonCueSmokeReport(
            caseIdentifier: "stale",
            selectedSession: 12,
            targetSession: 10,
            searchQuery: nil,
            pinnedSessions: [],
            missingPins: ["missing-pinned-comparison-smoke"],
            warningCount: 0,
            influenceSettings: influenceSettings
        )
        let filteredPin = representativePinnedComparisonCueSmokeReport(
            caseIdentifier: "filtered-pin",
            selectedSession: 12,
            targetSession: 10,
            searchQuery: "selected bridge beacon",
            pinnedSessions: [10],
            missingPins: [],
            warningCount: 1,
            influenceSettings: influenceSettings
        )
        let promotedHold = representativePinnedComparisonCueSmokeReport(
            caseIdentifier: "promoted-hold",
            selectedSession: 12,
            targetSession: 10,
            searchQuery: nil,
            pinnedSessions: [10],
            missingPins: [],
            savedTourHoldSession: 10,
            warningCount: 0,
            influenceSettings: influenceSettings
        )
        let filteredPromotedHold = representativePinnedComparisonCueSmokeReport(
            caseIdentifier: "filtered-promoted-hold",
            selectedSession: 12,
            targetSession: 10,
            searchQuery: "selected bridge beacon",
            pinnedSessions: [10],
            missingPins: [],
            savedTourHoldSession: 10,
            warningCount: 0,
            influenceSettings: influenceSettings
        )

        return [active, selectedOnly, noMatch, stale, filteredPin, promotedHold, filteredPromotedHold]
    }

    static func representativeRunRecapArtifactCommandSmokeReports(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicDiagnosticsReport] {
        let unavailableHistory = CinematicRunRecapShareArtifactHistoryPlan.unavailable(
            reason: "command-smoke-unavailable"
        )
        let cleanupHistory = representativeRunRecapArtifactCommandCleanupHistoryPlan()

        return [
            representativeRunRecapArtifactCommandSmokeReport(
                caseIdentifier: "available",
                historyPlan: representativeSavedRecapArtifactTourHistoryPlan(
                    caseIdentifier: "command-available",
                    warningCount: 0
                ),
                selectedSession: 21,
                pinnedSessions: [20],
                influenceSettings: influenceSettings
            ),
            representativeRunRecapArtifactCommandSmokeReport(
                caseIdentifier: "unavailable",
                historyPlan: unavailableHistory,
                selectedSession: nil,
                influenceSettings: influenceSettings
            ),
            representativeRunRecapArtifactCommandSmokeReport(
                caseIdentifier: "no-match",
                historyPlan: representativeSavedRecapArtifactTourHistoryPlan(
                    caseIdentifier: "command-no-match",
                    warningCount: 0
                ),
                searchQuery: "missing command availability smoke",
                selectedSession: 22,
                influenceSettings: influenceSettings
            ),
            representativeRunRecapArtifactCommandSmokeReport(
                caseIdentifier: "stale-pin",
                historyPlan: representativeSavedRecapArtifactTourHistoryPlan(
                    caseIdentifier: "command-stale-pin",
                    warningCount: 0
                ),
                selectedSession: 22,
                missingPins: ["missing-command-smoke-pin"],
                comparisonTargetMode: .pinnedReference,
                influenceSettings: influenceSettings
            ),
            representativeRunRecapArtifactCommandSmokeReport(
                caseIdentifier: "filtered-hold",
                historyPlan: representativeSavedRecapArtifactTourHistoryPlan(
                    caseIdentifier: "command-filtered-hold",
                    warningCount: 0
                ),
                searchQuery: "selected archive beacon",
                selectedSession: 22,
                heldSession: 21,
                influenceSettings: influenceSettings
            ),
            representativeRunRecapArtifactCommandSmokeReport(
                caseIdentifier: "promoted-hold",
                historyPlan: representativeSavedRecapArtifactTourHistoryPlan(
                    caseIdentifier: "command-promoted-hold",
                    warningCount: 0
                ),
                selectedSession: 22,
                pinnedSessions: [21],
                heldSession: 21,
                comparisonTargetMode: .pinnedReference,
                influenceSettings: influenceSettings
            ),
            representativeRunRecapArtifactCommandSmokeReport(
                caseIdentifier: "filtered-promoted-hold",
                historyPlan: representativeSavedRecapArtifactTourHistoryPlan(
                    caseIdentifier: "command-filtered-promoted-hold",
                    warningCount: 0
                ),
                searchQuery: "selected archive beacon",
                selectedSession: 22,
                pinnedSessions: [21],
                heldSession: 21,
                comparisonTargetMode: .pinnedReference,
                influenceSettings: influenceSettings
            ),
            representativeRunRecapArtifactCommandSmokeReport(
                caseIdentifier: "cleanup-omitted",
                historyPlan: cleanupHistory,
                selectedSession: 22,
                pinnedSessions: [21],
                influenceSettings: influenceSettings
            )
        ]
    }

    static func representativeActivityCases() -> [ActivityCase] {
        [
            ActivityCase(
                identifier: "unavailable",
                phase: "Staging",
                immediateTitle: "No immediate plan",
                completedCount: 0,
                profile: .empty
            ),
            ActivityCase(
                identifier: "missing-repository",
                phase: "Staging",
                immediateTitle: "Reconnect repository for cinematic diagnostics",
                completedCount: 0,
                profile: .empty,
                hasRepository: false
            ),
            ActivityCase(
                identifier: "clean",
                phase: "Developing",
                immediateTitle: "Add deterministic cinematic diagnostics",
                completedCount: 1,
                profile: activityProfile()
            ),
            ActivityCase(
                identifier: "dirty-light",
                phase: "Developing",
                immediateTitle: "Update renderer smoke copy",
                completedCount: 2,
                profile: activityProfile(worktreeChanges: worktreeChanges(modified: 2))
            ),
            ActivityCase(
                identifier: "dirty-moderate",
                phase: "Developing",
                immediateTitle: "Refine camera pressure tuning",
                completedCount: 3,
                profile: activityProfile(worktreeChanges: worktreeChanges(modified: 8))
            ),
            ActivityCase(
                identifier: "dirty-heavy",
                phase: "Verifying",
                immediateTitle: "Stabilize intense activity tuning",
                completedCount: 4,
                profile: activityProfile(worktreeChanges: worktreeChanges(modified: 16))
            ),
            ActivityCase(
                identifier: "conflicted",
                phase: "Recovering",
                immediateTitle: "Resolve deterministic cinematic conflict",
                completedCount: 2,
                profile: activityProfile(worktreeChanges: worktreeChanges(conflicted: 1))
            ),
            ActivityCase(
                identifier: "commit",
                phase: "Committing",
                immediateTitle: "Record cinematic diagnostics commit",
                completedCount: 5,
                profile: activityProfile(recentCommitCount: 2)
            ),
            ActivityCase(
                identifier: "success",
                phase: "Verifying",
                immediateTitle: "Confirm cinematic diagnostics smoke path",
                completedCount: 6,
                profile: activityProfile(lastTerminalStatus: .succeeded, successStreak: 3)
            ),
            ActivityCase(
                identifier: "recovery",
                phase: "Recovering",
                immediateTitle: "Recover cinematic diagnostics after failure",
                completedCount: 3,
                profile: activityProfile(
                    lastTerminalStatus: .succeeded,
                    successStreak: 1,
                    recoveredFromFailure: true
                )
            ),
            ActivityCase(
                identifier: "failure",
                phase: "Repairing",
                immediateTitle: "Fix cinematic diagnostics failure state",
                completedCount: 1,
                profile: activityProfile(
                    recentFailedCount: 1,
                    lastTerminalStatus: .failed,
                    failureStreak: 1
                )
            )
        ]
    }

    private static func representativeCommitConstellationPlan(
        for activityCase: ActivityCase
    ) -> CinematicCommitConstellationPlan {
        guard activityCase.identifier == "commit" else { return .empty }
        return CinematicTimelineSceneFocusPlanner.representativeCommitConstellationPlan()
    }

    private struct RunRecapFocusContext {
        var runRecapPlan: CinematicRunRecapPlan
        var runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan
        var runRecapEndCardPlan: CinematicRunRecapEndCardPlan
    }

    private static func representativeRunRecapFocusContext(
        for activityCase: ActivityCase,
        commitConstellationPlan: CinematicCommitConstellationPlan
    ) -> RunRecapFocusContext {
        guard let status = representativeRunRecapStatus(for: activityCase.identifier) else {
            return RunRecapFocusContext(
                runRecapPlan: .empty(reason: "no-finished-session"),
                runRecapSceneFocusPlan: .none,
                runRecapEndCardPlan: .none
            )
        }

        let sessionNumber = 70 + activityCase.completedCount
        let session = SessionRecord(
            session: sessionNumber,
            startedAt: Double(sessionNumber * 1_000),
            endedAt: Double(sessionNumber * 1_000 + 620),
            plan: activityCase.immediateTitle,
            verify: "swift test --filter CinematicVisualSmokeReportTests",
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: status,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
        let flavorInput = CinematicRunRecapPlanner.flavorInput(
            state: PlanState(
                completed: ["Completed \(activityCase.immediateTitle.lowercased())"],
                immediate: nil,
                midTerm: "",
                longTerm: ""
            ),
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitConstellationPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let generatedFlavor = activityCase.identifier == "recovery"
            ? flavorInput.map {
                CinematicRunRecapFlavor(
                    sourceIdentifier: $0.sourceIdentifier,
                    title: "Generated Recovery Recap",
                    detail: "Recovered diagnostics are ready with a generated recap card.",
                    titleSource: .generated
                )
            }
            : nil
        let recapPlan = CinematicRunRecapPlanner.plan(
            state: PlanState(
                completed: ["Completed \(activityCase.immediateTitle.lowercased())"],
                immediate: nil,
                midTerm: "",
                longTerm: ""
            ),
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitConstellationPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle(),
            flavor: generatedFlavor
        )
        let timelinePlan = CinematicSessionTimelinePlan(sessions: [session])
        let focusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitConstellationPlan,
            timelinePlan: timelinePlan
        )
        let endCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )

        return RunRecapFocusContext(
            runRecapPlan: recapPlan,
            runRecapSceneFocusPlan: focusPlan,
            runRecapEndCardPlan: endCardPlan
        )
    }

    private static func representativeSavedRecapArtifactTourSmokeReport(
        caseIdentifier: String,
        searchQuery: String?,
        pinnedSessions: [Int],
        missingPins: [String],
        heldSession: Int? = nil,
        missingHold: String? = nil,
        warningCount: Int,
        rotationSeed: Int,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport {
        let historyPlan = representativeSavedRecapArtifactTourHistoryPlan(
            caseIdentifier: caseIdentifier,
            warningCount: warningCount
        )
        let entryIdentifiersBySession = Dictionary(
            uniqueKeysWithValues: historyPlan.entries.map { ($0.sessionNumber, $0.identifier) }
        )
        let pinnedEntryIdentifiers = pinnedSessions.compactMap {
            entryIdentifiersBySession[$0]
        } + missingPins
        let savedTourHoldEntryIdentifier = heldSession.flatMap {
            entryIdentifiersBySession[$0]
        } ?? missingHold
        let tourPlan = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: historyPlan,
            libraryContext: CinematicRunRecapShareArtifactLibraryContext(
                selectedEntryIdentifier: historyPlan.entries.first?.identifier,
                searchText: searchQuery ?? "",
                pinnedEntryIdentifiers: pinnedEntryIdentifiers,
                savedTourHoldEntryIdentifier: savedTourHoldEntryIdentifier
            ),
            rotationSeed: rotationSeed
        )
        let idleStoryCyclePlan = CinematicIdleStoryCyclePlanner.plan(
            session: CinematicIdleStoryCyclePlan.SessionInput(
                elapsedTime: 0,
                sessionOrdinal: rotationSeed
            ),
            isLiveFollowActive: false,
            hasExplicitUserFocus: false,
            influenceSettings: influenceSettings,
            commitConstellationPlan: .empty,
            timelineSceneFocusPlan: .none,
            nativeFeedbackCue: nil,
            nativeFeedbackPlaqueDescriptor: nil,
            runRecapPlan: .empty(reason: "saved-tour-smoke"),
            runRecapSceneFocusPlan: .none,
            runRecapEndCardPlan: .none,
            runRecapShareArtifactTourPlan: tourPlan
        )

        return report(
            repoName: "Saved Tour \(caseIdentifier)",
            phase: LoopPhase.succeeded.rawValue,
            immediateTitle: "Cover saved recap artifact tour \(caseIdentifier)",
            completedCount: 1,
            latestEvent: nil,
            languageProfile: representativeLanguageProfile(for: .swift),
            activityProfile: activityProfile(recentCommitCount: 1, lastTerminalStatus: .succeeded),
            influenceSettings: influenceSettings,
            isRunning: false,
            idleStoryCyclePlan: idleStoryCyclePlan,
            idleStoryCycleSession: CinematicIdleStoryCyclePlan.SessionInput(sessionOrdinal: rotationSeed),
            runRecapShareArtifactHistoryPlan: historyPlan,
            runRecapShareArtifactPreviewSelectedEntryIdentifier: historyPlan.entries.first?.identifier,
            runRecapShareArtifactPreviewSearchQuery: searchQuery,
            runRecapShareArtifactPinnedEntryIdentifiers: pinnedEntryIdentifiers,
            runRecapShareArtifactSavedTourHoldEntryIdentifier: savedTourHoldEntryIdentifier
        )
    }

    private static func representativeRunRecapArtifactCommandSmokeReport(
        caseIdentifier: String,
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        searchQuery: String? = nil,
        selectedSession: Int? = 22,
        pinnedSessions: [Int] = [],
        missingPins: [String] = [],
        heldSession: Int? = nil,
        missingHold: String? = nil,
        comparisonTargetMode: CinematicRunRecapShareArtifactComparisonTargetMode = .adjacent,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport {
        let entryIdentifiersBySession = Dictionary(
            uniqueKeysWithValues: historyPlan.entries.map { ($0.sessionNumber, $0.identifier) }
        )
        let selectedEntryIdentifier = selectedSession.flatMap {
            entryIdentifiersBySession[$0]
        } ?? historyPlan.entries.first?.identifier
        let pinnedEntryIdentifiers = pinnedSessions.compactMap {
            entryIdentifiersBySession[$0]
        } + missingPins
        let savedTourHoldEntryIdentifier = heldSession.flatMap {
            entryIdentifiersBySession[$0]
        } ?? missingHold
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchText: searchQuery ?? "",
            pinnedEntryIdentifiers: pinnedEntryIdentifiers,
            comparisonTargetMode: comparisonTargetMode,
            savedTourHoldEntryIdentifier: savedTourHoldEntryIdentifier
        )

        return report(
            repoName: "Recap Commands \(caseIdentifier)",
            phase: LoopPhase.succeeded.rawValue,
            immediateTitle: "Cover recap artifact command availability \(caseIdentifier)",
            completedCount: 1,
            latestEvent: nil,
            languageProfile: representativeLanguageProfile(for: .swift),
            activityProfile: activityProfile(recentCommitCount: 1, lastTerminalStatus: .succeeded),
            influenceSettings: influenceSettings,
            isRunning: false,
            runRecapShareArtifactHistoryPlan: historyPlan,
            runRecapShareArtifactPreviewSelectedEntryIdentifier: context.selectedEntryIdentifier,
            runRecapShareArtifactPreviewSearchQuery: context.searchText,
            runRecapShareArtifactComparisonTargetMode: context.comparisonTargetMode,
            runRecapShareArtifactPinnedEntryIdentifiers: context.pinnedEntryIdentifiers,
            runRecapShareArtifactSavedTourHoldEntryIdentifier: context.savedTourHoldEntryIdentifier
        )
    }

    private static func representativeRunRecapArtifactCommandCleanupHistoryPlan()
        -> CinematicRunRecapShareArtifactHistoryPlan {
        var history = representativeSavedRecapArtifactTourHistoryPlan(
            caseIdentifier: "command-cleanup-omitted",
            warningCount: 0
        )
        let cleanupIdentifiers = ["command-cleanup-omitted-candidate"]
        history.identifier = "command-cleanup-history-\(fingerprint(history.identifier))"
        history.totalCount = history.entries.count + cleanupIdentifiers.count
        history.hiddenCount = cleanupIdentifiers.count
        history.cleanupCandidateCount = cleanupIdentifiers.count
        history.hiddenCleanupCandidateCount = 0
        history.cleanupCandidateIdentifiers = cleanupIdentifiers
        history.exportIdentifier = "command-cleanup-history-export-\(fingerprint(history.exportIdentifier))"
        return history
    }

    private static func representativeSavedRecapArtifactTourHistoryPlan(
        caseIdentifier: String,
        warningCount: Int
    ) -> CinematicRunRecapShareArtifactHistoryPlan {
        let entries = [22, 21, 20].map { session in
            representativeSavedRecapArtifactTourHistoryEntry(
                caseIdentifier: caseIdentifier,
                session: session
            )
        }
        let warnings = (0..<warningCount).map { index in
            CinematicRunRecapShareArtifactHistoryPlan.Warning(
                identifier: "saved-tour-warning-\(caseIdentifier)-\(index)",
                fileDisplayText: "saved-tour-\(caseIdentifier)-\(index).md",
                message: "Representative saved recap artifact tour warning"
            )
        }
        return CinematicRunRecapShareArtifactHistoryPlan(
            identifier: "saved-tour-history-\(caseIdentifier)",
            isAvailable: true,
            availabilityReason: "available",
            storageRootDisplayText: "/tmp/compass-saved-tour-\(caseIdentifier)",
            sessionsDisplayText: "/tmp/compass-saved-tour-\(caseIdentifier)/sessions",
            retentionLimit: CinematicRunRecapShareArtifactHistoryPlan.retentionLimit,
            entries: entries,
            totalCount: entries.count,
            hiddenCount: 0,
            cleanupCandidateCount: 0,
            hiddenCleanupCandidateCount: 0,
            cleanupCandidateIdentifiers: [],
            warnings: warnings,
            warningCount: warnings.count,
            hiddenWarningCount: 0,
            exportIdentifier: "saved-tour-history-export-\(caseIdentifier)",
            combinedMarkdownExport: entries.map(\.markdownContents).joined(separator: "\n\n")
        )
    }

    private static func representativeSavedRecapArtifactTourHistoryEntry(
        caseIdentifier: String,
        session: Int
    ) -> CinematicRunRecapShareArtifactHistoryPlan.Entry {
        let role: String
        let body: String
        switch session {
        case 22:
            role = "selected"
            body = "selected archive beacon for saved tour \(caseIdentifier)"
        case 21:
            role = "pinned"
            body = "pinned archive target for saved tour \(caseIdentifier)"
        default:
            role = "recent"
            body = "recent archive body for saved tour \(caseIdentifier)"
        }
        let filename = "\(session)-saved-tour-\(caseIdentifier)-\(role).md"
        let markdown = """
        # Compass Run Recap Share

        - Artifact: saved-tour-\(caseIdentifier)-\(role)
        - Availability: available
        - Session: \(session)
        - Filename: \(filename)
        - Share: saved-tour-share
        - Recap: saved-tour-recap
        - Focus: none
        - End card: none
        - Title: Saved tour \(role) \(session)
        - Status: succeeded
        - Detail: Saved tour smoke detail
        - Commit: Saved tour commit \(session)

        ## Events
        - event

        ## Share Text

        ```text
        \(body)
        ```
        """
        return CinematicRunRecapShareArtifactHistoryPlan.Entry(
            identifier: "saved-tour-\(caseIdentifier)-entry-\(session)",
            sessionNumber: session,
            filename: filename,
            url: URL(fileURLWithPath: "/tmp/\(filename)"),
            pathDisplayText: "/tmp/\(filename)",
            titleSnippet: "Saved tour \(role) \(session)",
            statusSnippet: "succeeded",
            commitSnippet: "Saved tour commit \(session)",
            markdownContents: markdown,
            markdownLength: markdown.count
        )
    }

    private static func representativePinnedComparisonCueSmokeReport(
        caseIdentifier: String,
        selectedSession: Int,
        targetSession: Int,
        searchQuery: String?,
        pinnedSessions: [Int],
        missingPins: [String],
        savedTourHoldSession: Int? = nil,
        missingSavedTourHold: String? = nil,
        warningCount: Int,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport {
        let state = PlanState(
            completed: ["Completed pinned comparison \(caseIdentifier)"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
        let session = SessionRecord(
            session: selectedSession,
            startedAt: Double(selectedSession * 1_000),
            endedAt: Double(selectedSession * 1_000 + 420),
            plan: "Stage pinned comparison cue \(caseIdentifier)",
            verify: "swift test --filter CinematicVisualSmokeReportTests",
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: .succeeded,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
        let recapPlan = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: .empty,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let historyPlan = representativePinnedComparisonHistoryPlan(
            caseIdentifier: caseIdentifier,
            selectedSession: selectedSession,
            targetSession: targetSession,
            warningCount: warningCount
        )
        let entryIdentifiersBySession = Dictionary(
            uniqueKeysWithValues: historyPlan.entries.map { ($0.sessionNumber, $0.identifier) }
        )
        let selectedEntryIdentifier = entryIdentifiersBySession[selectedSession]
        let pinnedEntryIdentifiers = pinnedSessions.compactMap {
            entryIdentifiersBySession[$0]
        } + missingPins
        let savedTourHoldEntryIdentifier = savedTourHoldSession.flatMap {
            entryIdentifiersBySession[$0]
        } ?? missingSavedTourHold
        let comparisonPlan = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: historyPlan,
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchQuery: searchQuery,
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: pinnedEntryIdentifiers,
            savedTourHoldEntryIdentifier: savedTourHoldEntryIdentifier
        )
        let endCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            artifactComparisonPlan: comparisonPlan
        )

        return report(
            repoName: "Pinned Cue \(caseIdentifier)",
            phase: LoopPhase.succeeded.rawValue,
            immediateTitle: "Cover pinned comparison cue \(caseIdentifier)",
            completedCount: 1,
            latestEvent: nil,
            languageProfile: representativeLanguageProfile(for: .swift),
            activityProfile: activityProfile(recentCommitCount: 1, lastTerminalStatus: .succeeded),
            influenceSettings: influenceSettings,
            isRunning: false,
            runRecapPlan: recapPlan,
            runRecapEndCardPlan: endCardPlan,
            runRecapShareArtifactHistoryPlan: historyPlan,
            runRecapShareArtifactPreviewSelectedEntryIdentifier: selectedEntryIdentifier,
            runRecapShareArtifactPreviewSearchQuery: searchQuery,
            runRecapShareArtifactComparisonTargetMode: .pinnedReference,
            runRecapShareArtifactPinnedEntryIdentifiers: pinnedEntryIdentifiers,
            runRecapShareArtifactSavedTourHoldEntryIdentifier: savedTourHoldEntryIdentifier
        )
    }

    private static func representativePinnedComparisonHistoryPlan(
        caseIdentifier: String,
        selectedSession: Int,
        targetSession: Int,
        warningCount: Int
    ) -> CinematicRunRecapShareArtifactHistoryPlan {
        let sessions = Array(Set([selectedSession, targetSession, max(1, targetSession - 1)])).sorted(by: >)
        let entries = sessions.map { session in
            representativePinnedComparisonHistoryEntry(
                caseIdentifier: caseIdentifier,
                session: session,
                selectedSession: selectedSession,
                targetSession: targetSession
            )
        }
        let warnings = (0..<warningCount).map { index in
            CinematicRunRecapShareArtifactHistoryPlan.Warning(
                identifier: "pinned-cue-warning-\(caseIdentifier)-\(index)",
                fileDisplayText: "pinned-cue-\(caseIdentifier)-\(index).md",
                message: "Representative pinned comparison warning"
            )
        }
        return CinematicRunRecapShareArtifactHistoryPlan(
            identifier: "pinned-cue-history-\(caseIdentifier)",
            isAvailable: true,
            availabilityReason: "available",
            storageRootDisplayText: "/tmp/compass-pinned-cue-\(caseIdentifier)",
            sessionsDisplayText: "/tmp/compass-pinned-cue-\(caseIdentifier)/sessions",
            retentionLimit: CinematicRunRecapShareArtifactHistoryPlan.retentionLimit,
            entries: entries,
            totalCount: entries.count,
            hiddenCount: 0,
            cleanupCandidateCount: 0,
            hiddenCleanupCandidateCount: 0,
            cleanupCandidateIdentifiers: [],
            warnings: warnings,
            warningCount: warnings.count,
            hiddenWarningCount: 0,
            exportIdentifier: "pinned-cue-history-export-\(caseIdentifier)",
            combinedMarkdownExport: entries.map(\.markdownContents).joined(separator: "\n\n")
        )
    }

    private static func representativePinnedComparisonHistoryEntry(
        caseIdentifier: String,
        session: Int,
        selectedSession: Int,
        targetSession: Int
    ) -> CinematicRunRecapShareArtifactHistoryPlan.Entry {
        let role: String
        let body: String
        if session == selectedSession {
            role = "selected"
            body = "selected bridge beacon for pinned comparison cue \(caseIdentifier)"
        } else if session == targetSession {
            role = "target"
            body = "target bridge archive for pinned comparison cue \(caseIdentifier)"
        } else {
            role = "adjacent"
            body = "adjacent bridge archive for pinned comparison cue \(caseIdentifier)"
        }
        let filename = "\(session)-pinned-cue-\(caseIdentifier)-\(role).md"
        let markdown = """
        # Compass Run Recap Share

        - Artifact: pinned-cue-\(caseIdentifier)-\(role)
        - Availability: available
        - Session: \(session)
        - Filename: \(filename)
        - Share: pinned-cue-share
        - Recap: pinned-cue-recap
        - Focus: none
        - End card: none
        - Title: Pinned cue \(role) \(session)
        - Status: succeeded
        - Detail: Pinned comparison smoke detail
        - Commit: Pinned comparison cue commit \(session)

        ## Events
        - event

        ## Share Text

        ```text
        \(body)
        ```
        """
        let identifier = "pinned-cue-\(caseIdentifier)-entry-\(session)"
        return CinematicRunRecapShareArtifactHistoryPlan.Entry(
            identifier: identifier,
            sessionNumber: session,
            filename: filename,
            url: URL(fileURLWithPath: "/tmp/\(filename)"),
            pathDisplayText: "/tmp/\(filename)",
            titleSnippet: "Pinned cue \(role) \(session)",
            statusSnippet: "succeeded",
            commitSnippet: "Pinned comparison cue commit \(session)",
            markdownContents: markdown,
            markdownLength: markdown.count
        )
    }

    private static func representativeRunRecapStatus(
        for activityCaseIdentifier: String
    ) -> SessionStatus? {
        switch activityCaseIdentifier {
        case "commit", "success", "recovery":
            return .succeeded
        case "failure":
            return .failed
        case "dirty-heavy":
            return .cancelled
        default:
            return nil
        }
    }

    private static func representativeNativeFeedbackSmokeReport(
        repoName: String,
        phase: LoopPhase,
        immediateTitle: String,
        completedCount: Int,
        language: RepositoryLanguage,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings,
        milestone: NativeFeedbackMilestone,
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue],
        now: Date
    ) -> CinematicDiagnosticsReport? {
        guard let cue = CinematicNativeFeedbackCuePlanner.plan(
            milestone: milestone,
            content: NativeFeedbackContent(milestone: milestone, projectName: repoName),
            phase: phase,
            feedbackMode: .notifications,
            recentRunCues: recentRunCues
        ) else {
            return nil
        }

        var lifecycle = CinematicNativeFeedbackCueLifecycle()
        let activeCue = lifecycle.record(cue, now: now)
        return report(
            repoName: repoName,
            phase: phase.rawValue,
            immediateTitle: immediateTitle,
            completedCount: completedCount,
            latestEvent: nil,
            languageProfile: representativeLanguageProfile(for: language),
            activityProfile: activityProfile,
            influenceSettings: influenceSettings,
            nativeFeedbackCue: activeCue,
            nativeFeedbackLifecycle: lifecycle
        )
    }

    private static func representativeIdleStoryCycleSmokeReport(
        influenceSettings: CinematicInfluenceSettings,
        activityCase: ActivityCase,
        commitConstellationPlan: CinematicCommitConstellationPlan,
        timelineFocusPlan: CinematicTimelineSceneFocusPlan,
        nativeFeedbackCue: CinematicNativeFeedbackCuePlan?,
        recapContext: RunRecapFocusContext,
        tourHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan,
        diagnosticsWarningBundleHistory: CinematicDiagnosticsWarningBundleHistory,
        session: CinematicIdleStoryCyclePlan.SessionInput,
        isLiveFollowActive: Bool,
        hasExplicitUserFocus: Bool
    ) -> CinematicDiagnosticsReport {
        report(
            repoName: "Idle Story Cycle",
            phase: activityCase.phase,
            immediateTitle: activityCase.immediateTitle,
            completedCount: activityCase.completedCount,
            latestEvent: nil,
            languageProfile: representativeLanguageProfile(for: .swift),
            activityProfile: activityCase.profile,
            influenceSettings: influenceSettings,
            isRunning: false,
            isAutoPlaying: false,
            isPaused: false,
            hasRepository: true,
            commitConstellationPlan: commitConstellationPlan,
            idleStoryCycleSession: session,
            isLiveFollowActive: isLiveFollowActive,
            hasExplicitUserFocus: hasExplicitUserFocus,
            timelineFocusPlan: timelineFocusPlan,
            runRecapPlan: recapContext.runRecapPlan,
            runRecapSceneFocusPlan: recapContext.runRecapSceneFocusPlan,
            runRecapEndCardPlan: recapContext.runRecapEndCardPlan,
            runRecapShareArtifactHistoryPlan: tourHistoryPlan,
            diagnosticsWarningBundleHistory: diagnosticsWarningBundleHistory,
            nativeFeedbackCue: nativeFeedbackCue
        )
    }

    private static func representativeExpiredNativeFeedbackSmokeReport(
        influenceSettings: CinematicInfluenceSettings,
        now: Date
    ) -> CinematicDiagnosticsReport? {
        guard let cue = CinematicNativeFeedbackCuePlanner.plan(
            milestone: .verifyStarted,
            content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Native Feedback Expired"),
            phase: .verifying,
            feedbackMode: .notifications,
            recentRunCues: [:]
        ) else {
            return nil
        }

        var lifecycle = CinematicNativeFeedbackCueLifecycle()
        _ = lifecycle.record(cue, now: now)
        _ = lifecycle.expire(
            now: now.addingTimeInterval(CinematicNativeFeedbackCueLifecycle.standardDisplayDuration)
        )

        return report(
            repoName: "Native Feedback Expired",
            phase: LoopPhase.verifying.rawValue,
            immediateTitle: "Archive expired native feedback cue",
            completedCount: 3,
            latestEvent: nil,
            languageProfile: representativeLanguageProfile(for: .swift),
            activityProfile: activityProfile(recentCommitCount: 1),
            influenceSettings: influenceSettings,
            nativeFeedbackCue: nil,
            nativeFeedbackLifecycle: lifecycle
        )
    }

    private static func representativeRunCue(
        kind: PlanReliabilityFeedback.Kind,
        severity: PlanReliabilityFeedback.Severity,
        label: String,
        detail: String,
        systemImage: String
    ) -> PlanReliabilityFeedback.RunCue {
        PlanReliabilityFeedback.RunCue(
            notice: PlanReliabilityFeedback.Notice(
                id: "\(kind.rawValue)-native-feedback-smoke",
                kind: kind,
                severity: severity,
                sessionNumber: 0,
                title: label,
                detail: detail,
                actionLabel: label,
                metadata: nil,
                systemImage: systemImage
            )
        )
    }

    private static func languageSnapshot(
        for motif: CinematicLanguageMotif
    ) -> CinematicDiagnosticsReport.LanguageMotifSnapshot {
        let ambientSpellIdentifier = motif.ambientSpell.diagnosticsIdentifier
        let identifier = [
            motif.sigilIdentifier,
            motif.styleIdentifier,
            ambientSpellIdentifier,
            fixed(Double(motif.phaseBlend))
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.LanguageMotifSnapshot(
            identifier: identifier,
            language: motif.language,
            sigilIdentifier: motif.sigilIdentifier,
            styleIdentifier: motif.styleIdentifier,
            ambientSpellIdentifier: ambientSpellIdentifier,
            phaseBlend: Double(motif.phaseBlend)
        )
    }

    private static func activitySnapshot(
        for motif: CinematicActivityMotif
    ) -> CinematicDiagnosticsReport.ActivityMotifSnapshot {
        let tintSourceIdentifier = motif.tintSource?.diagnosticsIdentifier
        let transitionSpellIdentifier = motif.transitionSpell?.diagnosticsIdentifier
        let ambientOverrideIdentifier = motif.ambientOverride?.diagnosticsIdentifier
        let identifier = [
            motif.sigilIdentifier,
            motif.styleIdentifier,
            motif.eventKind.rawValue,
            tintSourceIdentifier ?? "none",
            transitionSpellIdentifier ?? "none",
            ambientOverrideIdentifier ?? "none"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.ActivityMotifSnapshot(
            identifier: identifier,
            eventKindIdentifier: motif.eventKind.rawValue,
            sigilIdentifier: motif.sigilIdentifier,
            styleIdentifier: motif.styleIdentifier,
            tintSourceIdentifier: tintSourceIdentifier,
            transitionSpellIdentifier: transitionSpellIdentifier,
            ambientOverrideIdentifier: ambientOverrideIdentifier,
            usesCommitAmbient: motif.usesCommitAmbient,
            usesSuccessAmbient: motif.usesSuccessAmbient,
            shouldShakeOnTransition: motif.shouldShakeOnTransition
        )
    }

    private static func recoveryCueSnapshot(
        for plan: CinematicRecoveryCuePlan
    ) -> CinematicDiagnosticsReport.RecoveryCueSnapshot {
        let selectedCue = plan.selectedCue
        let descriptor = plan.visualDescriptor
        let cameraShakeIdentifier = descriptor.flatMap { cueDescriptor -> String? in
            guard cueDescriptor.shouldShakeCamera else { return nil }
            return CinematicStageEffectPlan.CameraShake(
                shouldShake: true,
                duration: cueDescriptor.cameraShakeDuration,
                scale: cueDescriptor.cameraShakeScale
            ).identifier
        }
        let identifier = [
            "cue:\(selectedCue?.identifier ?? "none")",
            "visual:\(descriptor?.identifier ?? "none")",
            "camera:\(cameraShakeIdentifier ?? "steady")"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.RecoveryCueSnapshot(
            identifier: identifier,
            selectedCueIdentifier: selectedCue?.identifier,
            sessionNumber: selectedCue?.sessionNumber,
            kindIdentifier: selectedCue?.kind.rawValue ?? "none",
            severityIdentifier: selectedCue?.severity.rawValue,
            label: selectedCue?.label,
            detail: selectedCue?.detail,
            systemImage: selectedCue?.systemImage,
            visualIdentifier: descriptor?.identifier ?? "none",
            treatmentIdentifier: descriptor?.treatmentIdentifier ?? "none",
            lightFamilyIdentifier: descriptor?.lightFamily.rawValue ?? "none",
            fractureLightFamilyIdentifier: descriptor?.fractureLightFamily.rawValue ?? "none",
            symbolIdentifier: descriptor?.symbolIdentifier,
            phaseLightIntensity: descriptor?.phaseLightIntensity ?? 0,
            intensity: descriptor?.intensity ?? 0,
            postureIdentifier: descriptor?.posture.rawValue ?? "none",
            arenaEffectIdentifier: descriptor?.arenaEffect.rawValue ?? "none",
            fractureOpacity: descriptor?.fractureOpacity ?? 0,
            fractureSpread: descriptor?.fractureSpread ?? 0,
            healingOpacity: descriptor?.healingOpacity ?? 0,
            shouldShakeCamera: descriptor?.shouldShakeCamera ?? false,
            cameraShakeIdentifier: cameraShakeIdentifier
        )
    }

    private static func stageBeatSnapshot(
        for beat: CinematicStageBeat
    ) -> CinematicDiagnosticsReport.StageBeatSnapshot {
        let accent = beat.activityAccent
        return CinematicDiagnosticsReport.StageBeatSnapshot(
            identifier: beat.identifier,
            phaseIdentifier: beat.phaseIdentifier,
            kindIdentifier: beat.kindIdentifier,
            cameraShotIdentifier: beat.cameraShotIdentifier,
            lightFamilyIdentifier: beat.lightFamilyIdentifier,
            arenaEffectIdentifier: beat.arenaEffectIdentifier,
            phaseLightIntensity: beat.phaseLightIntensity,
            shouldShakeCamera: beat.shouldShakeCamera,
            shouldRunVictorySurge: beat.shouldRunVictorySurge,
            shouldRunHistoryChains: beat.shouldRunHistoryChains,
            activityAccentIdentifier: beat.activityAccentIdentifier,
            activityEventKindIdentifier: accent?.eventKind.rawValue,
            activityLightFamilyIdentifier: accent?.lightFamily.rawValue,
            activityArenaEffectIdentifier: accent?.arenaEffect.rawValue
        )
    }

    private static func stageEffectSnapshot(
        for plan: CinematicStageEffectPlan
    ) -> CinematicDiagnosticsReport.StageEffectSnapshot {
        let effects = plan.effects
        let tuning = plan.tuningMetadata
        let ringIdentifiers = effects.flatMap(\.arenaRings).map(\.identifier)
        let phaseLightPulseIdentifiers = effects.compactMap { $0.phaseLightPulse?.identifier }
        let sparkBurstIdentifiers = effects.flatMap(\.sparkBursts).map(\.identifier)
        let historyTrailIdentifiers = effects.flatMap(\.historyTrails).map(\.identifier)
        let victoryCadenceIdentifier = effects.compactMap { $0.victoryCadence?.identifier }.first
        let cameraShakeIdentifiers = effects.compactMap { $0.cameraShake?.identifier }
        let identifier = [
            "phase:\(plan.phaseEffect.identifier)",
            "activity:\(plan.activityEffect?.identifier ?? "none")",
            "recovery:\(plan.recoveryEffect?.identifier ?? "none")",
            "rings:\(ringIdentifiers.joined(separator: ","))",
            "pulses:\(phaseLightPulseIdentifiers.joined(separator: ","))",
            "sparks:\(sparkBurstIdentifiers.joined(separator: ","))",
            "history:\(historyTrailIdentifiers.joined(separator: ","))",
            "victory:\(victoryCadenceIdentifier ?? "none")",
            "camera:\(cameraShakeIdentifiers.joined(separator: ","))",
            "recovery-cue:\(plan.recoveryCueIdentifier)",
            "tuning:\(tuning.identifier)"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.StageEffectSnapshot(
            identifier: identifier,
            phaseEffectIdentifier: plan.phaseEffect.identifier,
            phaseSourceIdentifier: plan.phaseEffect.sourceIdentifier,
            phaseArenaEffectIdentifier: plan.phaseEffect.arenaEffect.rawValue,
            activityEffectIdentifier: plan.activityEffect?.identifier,
            activitySourceIdentifier: plan.activityEffect?.sourceIdentifier,
            activityArenaEffectIdentifier: plan.activityEffect?.arenaEffect.rawValue,
            recoveryEffectIdentifier: plan.recoveryEffect?.identifier,
            recoverySourceIdentifier: plan.recoveryEffect?.sourceIdentifier,
            recoveryArenaEffectIdentifier: plan.recoveryEffect?.arenaEffect.rawValue,
            arenaRingIdentifiers: ringIdentifiers,
            phaseLightPulseIdentifiers: phaseLightPulseIdentifiers,
            sparkBurstIdentifiers: sparkBurstIdentifiers,
            historyTrailIdentifiers: historyTrailIdentifiers,
            victoryCadenceIdentifier: victoryCadenceIdentifier,
            cameraShakeIdentifiers: cameraShakeIdentifiers,
            arenaRingCount: ringIdentifiers.count,
            phaseLightPulseCount: phaseLightPulseIdentifiers.count,
            sparkBurstCount: sparkBurstIdentifiers.count,
            historyTrailCount: historyTrailIdentifiers.count,
            tuningIdentifier: tuning.identifier,
            recoveryCueIdentifier: plan.recoveryCueIdentifier,
            recoveryCueKindIdentifier: plan.recoveryCueKindIdentifier,
            pressureLevelIdentifier: tuning.pressureLevelIdentifier,
            pressureFraction: tuning.pressureFraction,
            energy: tuning.energy,
            influenceStyleIdentifier: tuning.influenceStyleIdentifier,
            influenceIntensity: tuning.influenceIntensity,
            influenceFraction: tuning.influenceFraction,
            activityLightBoost: tuning.activityLightBoost,
            activityLightBoostFraction: tuning.activityLightBoostFraction,
            runePulseScale: tuning.runePulseScale,
            activityPulseDuration: tuning.activityPulseDuration,
            ringDurationScale: tuning.ringDurationScale,
            ringScaleMultiplier: tuning.ringScaleMultiplier,
            ringOpacityMultiplier: tuning.ringOpacityMultiplier,
            colorAlphaMultiplier: tuning.colorAlphaMultiplier,
            pulseIntensityMultiplier: tuning.pulseIntensityMultiplier,
            pulseDurationMultiplier: tuning.pulseDurationMultiplier,
            sparkBirthRateMultiplier: tuning.sparkBirthRateMultiplier,
            historyTrailTargetCount: tuning.historyTrailCount,
            cameraShakeMultiplier: tuning.cameraShakeMultiplier,
            cameraShakeDurationMultiplier: tuning.cameraShakeDurationMultiplier,
            victoryCadenceMultiplier: tuning.victoryCadenceMultiplier
        )
    }

    private static func stageAtmosphereSnapshot(
        for plan: CinematicStageAtmospherePlan
    ) -> CinematicDiagnosticsReport.StageAtmosphereSnapshot {
        let identifier = [
            "beat:\(plan.beatIdentifier)",
            "phase:\(plan.phaseIdentifier)",
            "activity:\(plan.activityIdentifier)",
            "pressure:\(plan.pressureLevelIdentifier):\(fixed(Double(plan.pressureFraction)))",
            "energy:\(fixed(Double(plan.energy)))",
            "influence:\(plan.influenceStyleIdentifier):\(fixed(Double(plan.influenceIntensity))):\(fixed(Double(plan.influenceFraction)))",
            "halo:\(plan.pressureHalo.identifier)",
            "pulse:\(plan.atmosphericPulse.identifier)",
            "light:\(plan.pressureLighting.identifier)",
            "backdrop:\(plan.backdropTint.identifier)",
            "floor:\(plan.floorTint.identifier)"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.StageAtmosphereSnapshot(
            identifier: identifier,
            beatIdentifier: plan.beatIdentifier,
            phaseIdentifier: plan.phaseIdentifier,
            activityIdentifier: plan.activityIdentifier,
            pressureLevelIdentifier: plan.pressureLevelIdentifier,
            influenceStyleIdentifier: plan.influenceStyleIdentifier,
            influenceIntensity: plan.influenceIntensity,
            pressureFraction: plan.pressureFraction,
            influenceFraction: plan.influenceFraction,
            energy: plan.energy,
            pressureHaloIdentifier: plan.pressureHalo.identifier,
            pressureHaloRadius: plan.pressureHalo.radius,
            pressureHaloOpacity: plan.pressureHalo.opacity,
            pressureHaloScale: plan.pressureHalo.scale,
            pressureHaloColorAlpha: plan.pressureHalo.colorAlpha,
            atmosphericPulseIdentifier: plan.atmosphericPulse.identifier,
            atmosphericPulseCadence: plan.atmosphericPulse.cadence,
            atmosphericPulseAmplitude: plan.atmosphericPulse.amplitude,
            atmosphericPulseOpacity: plan.atmosphericPulse.opacity,
            pressureLightingIdentifier: plan.pressureLighting.identifier,
            phaseLightPressureBoost: plan.pressureLighting.phaseLightPressureBoost,
            rimLightPressureBoost: plan.pressureLighting.rimLightPressureBoost,
            pressureLightColorAlpha: plan.pressureLighting.colorAlpha,
            backdropTintIdentifier: plan.backdropTint.identifier,
            backdropTintRed: plan.backdropTint.red,
            backdropTintGreen: plan.backdropTint.green,
            backdropTintBlue: plan.backdropTint.blue,
            backdropTintOpacity: plan.backdropTint.opacity,
            backdropTintBlendFraction: plan.backdropTint.blendFraction,
            floorTintIdentifier: plan.floorTint.identifier,
            floorTintRed: plan.floorTint.red,
            floorTintGreen: plan.floorTint.green,
            floorTintBlue: plan.floorTint.blue,
            floorTintOpacity: plan.floorTint.opacity,
            floorTintBlendFraction: plan.floorTint.blendFraction
        )
    }

    private static func stagePhasePolishSnapshot(
        for plan: CinematicStagePhasePolishPlan
    ) -> CinematicDiagnosticsReport.StagePhasePolishSnapshot {
        let identifier = [
            "beat:\(plan.beatIdentifier)",
            "effect:\(plan.stageEffectTuningIdentifier)",
            "atmosphere:\(plan.atmosphereIdentifier)",
            "phase:\(plan.phaseIdentifier)",
            "activity:\(plan.activityIdentifier)",
            "recovery:\(plan.recoveryCueIdentifier)",
            "posture:\(plan.postureIdentifier)",
            "pose:\(plan.wizardPose.identifier)",
            "orb:\(plan.staffOrb.identifier)",
            "sigil:\(plan.sigilEmphasis.identifier)",
            "portal:\(plan.portalBackdrop.identifier)",
            "fracture:\(plan.fractureRecovery.identifier)",
            "cadence:\(plan.cadence.identifier)",
            "influence:\(plan.influenceIdentifier)"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.StagePhasePolishSnapshot(
            identifier: identifier,
            beatIdentifier: plan.beatIdentifier,
            stageEffectTuningIdentifier: plan.stageEffectTuningIdentifier,
            atmosphereIdentifier: plan.atmosphereIdentifier,
            phaseIdentifier: plan.phaseIdentifier,
            activityIdentifier: plan.activityIdentifier,
            recoveryCueIdentifier: plan.recoveryCueIdentifier,
            recoveryCueKindIdentifier: plan.recoveryCueKindIdentifier,
            influenceIdentifier: plan.influenceIdentifier,
            postureIdentifier: plan.postureIdentifier,
            wizardPoseIdentifier: plan.wizardPose.identifier,
            poseIntensity: plan.wizardPose.poseIntensity,
            staffOrbIdentifier: plan.staffOrb.identifier,
            staffOrbLightFamilyIdentifier: plan.staffOrb.lightFamily.rawValue,
            staffOrbScale: plan.staffOrb.scale,
            staffOrbEmission: plan.staffOrb.emission,
            staffOrbPulseAmplitude: plan.staffOrb.pulseAmplitude,
            sigilEmphasisIdentifier: plan.sigilEmphasis.identifier,
            sigilOrbitRadius: plan.sigilEmphasis.orbitRadius,
            sigilSealEmphasis: plan.sigilEmphasis.sealEmphasis,
            sigilVictoryEmphasis: plan.sigilEmphasis.victoryEmphasis,
            sigilPulseAmplitude: plan.sigilEmphasis.pulseAmplitude,
            portalBackdropIdentifier: plan.portalBackdrop.identifier,
            portalLightFamilyIdentifier: plan.portalBackdrop.lightFamily.rawValue,
            portalAperture: plan.portalBackdrop.portalAperture,
            portalScale: plan.portalBackdrop.portalScale,
            portalOpacity: plan.portalBackdrop.portalOpacity,
            backdropAperture: plan.portalBackdrop.backdropAperture,
            backdropOpacityBoost: plan.portalBackdrop.backdropOpacityBoost,
            fractureRecoveryIdentifier: plan.fractureRecovery.identifier,
            fractureLightFamilyIdentifier: plan.fractureRecovery.lightFamily.rawValue,
            fractureOpacity: plan.fractureRecovery.fractureOpacity,
            fractureSpread: plan.fractureRecovery.fractureSpread,
            healingOpacity: plan.fractureRecovery.healingOpacity,
            cadenceIdentifier: plan.cadence.identifier,
            poseCadence: plan.cadence.poseCadence,
            orbPulseCadence: plan.cadence.orbPulseCadence,
            sigilOrbitCadence: plan.cadence.sigilOrbitCadence,
            fractureCadence: plan.cadence.fractureCadence
        )
    }

    private static func narrativeCueSnapshot(
        for plan: CinematicSceneNarrativeCuePlan
    ) -> CinematicDiagnosticsReport.NarrativeCueSnapshot {
        let quest = narrativeCueDescriptorSnapshot(for: plan.questPlaque)
        let arena = narrativeCueDescriptorSnapshot(for: plan.arenaInscription)
        let activity = narrativeCueDescriptorSnapshot(for: plan.activityBanner)
        let identifier = [
            "beat:\(plan.stageBeatIdentifier)",
            "phase-polish:\(plan.stagePhasePolishIdentifier)",
            "language:\(plan.languageIdentifier)",
            "activity:\(plan.activityIdentifier)",
            "quest:\(quest.identifier)",
            "arena:\(arena.identifier)",
            "banner:\(activity.identifier)",
            "influence:\(plan.influenceIdentifier)",
            "native:\(plan.nativeFeedbackCueIdentifier)",
            "native-lifecycle:\(plan.nativeFeedbackLifecycleIdentifier)"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.NarrativeCueSnapshot(
            identifier: identifier,
            stageBeatIdentifier: plan.stageBeatIdentifier,
            stagePhasePolishIdentifier: plan.stagePhasePolishIdentifier,
            languageIdentifier: plan.languageIdentifier,
            activityIdentifier: plan.activityIdentifier,
            influenceIdentifier: plan.influenceIdentifier,
            nativeFeedbackCueIdentifier: plan.nativeFeedbackCueIdentifier,
            nativeFeedbackLifecycleIdentifier: plan.nativeFeedbackLifecycleIdentifier,
            nativeFeedbackSourceIdentifier: plan.nativeFeedbackSourceIdentifier,
            nativeFeedbackStyleIdentifier: plan.nativeFeedbackStyleIdentifier,
            nativeFeedbackMilestoneIdentifier: plan.nativeFeedbackMilestoneIdentifier,
            nativeFeedbackAffectedDescriptorIdentifiers: plan.nativeFeedbackAffectedDescriptorIdentifiers,
            questPlaque: quest,
            arenaInscription: arena,
            activityBanner: activity
        )
    }

    private static func nativeFeedbackSnapshot(
        for cue: CinematicNativeFeedbackCuePlan?,
        lifecycle: CinematicNativeFeedbackCueLifecycle,
        narrativeCuePlan: CinematicSceneNarrativeCuePlan
    ) -> CinematicDiagnosticsReport.NativeFeedbackSnapshot {
        let lifecycleIdentifier = lifecycle.hasState
            ? lifecycle.identifier
            : cue?.lifecycleIdentifier ?? "none"
        let lifecycleStateIdentifier = lifecycle.hasState
            ? lifecycle.stateIdentifier
            : cue?.lifecycleStateIdentifier ?? "none"
        let activeCueIdentifier = lifecycle.active?.cueIdentifier ?? "none"
        let archiveIdentifiers = lifecycle.recentArchiveIdentifiers
        let activeHistoryEntry = lifecycle.active.map(nativeFeedbackHistoryEntry)
        let archiveHistoryEntries = lifecycle.recentArchive.map(nativeFeedbackHistoryEntry)
        let historyEntries = [activeHistoryEntry].compactMap { $0 } + archiveHistoryEntries
        let historyIdentifier = historyEntries.isEmpty
            ? "none"
            : historyEntries.map(\.identifier).joined(separator: ",")

        guard let cue else {
            return CinematicDiagnosticsReport.NativeFeedbackSnapshot(
                identifier: [
                    "native-feedback.none",
                    "lifecycle:\(lifecycleIdentifier)",
                    "state:\(lifecycleStateIdentifier)",
                    "archives:\(archiveIdentifiers.isEmpty ? "none" : archiveIdentifiers.joined(separator: ","))",
                    "history:\(historyIdentifier)"
                ].joined(separator: "|"),
                cueIdentifier: "none",
                lifecycleIdentifier: lifecycleIdentifier,
                lifecycleStateIdentifier: lifecycleStateIdentifier,
                lifecycleActiveCueIdentifier: activeCueIdentifier,
                lifecycleRecentArchiveIdentifiers: archiveIdentifiers,
                lifecycleRecentArchiveCount: archiveIdentifiers.count,
                lifecycleActiveHistoryEntry: activeHistoryEntry,
                lifecycleArchiveHistoryEntries: archiveHistoryEntries,
                lifecycleHistoryEntryCount: historyEntries.count,
                sourceIdentifier: "none",
                styleIdentifier: "none",
                milestoneIdentifier: "none",
                affectedNarrativeDescriptorIdentifiers: []
            )
        }

        let affectedDescriptors = narrativeCuePlan.nativeFeedbackAffectedDescriptorIdentifiers
        let identifier = [
            cue.identifier,
            "source:\(cue.sourceIdentifier)",
            "style:\(cue.styleIdentifier)",
            "milestone:\(cue.milestoneIdentifier)",
            "lifecycle:\(lifecycleIdentifier)",
            "state:\(lifecycleStateIdentifier)",
            "archives:\(archiveIdentifiers.count)",
            "history:\(historyIdentifier)",
            "affects:\(affectedDescriptors.isEmpty ? "none" : affectedDescriptors.joined(separator: ","))"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.NativeFeedbackSnapshot(
            identifier: identifier,
            cueIdentifier: cue.identifier,
            lifecycleIdentifier: lifecycleIdentifier,
            lifecycleStateIdentifier: lifecycleStateIdentifier,
            lifecycleActiveCueIdentifier: activeCueIdentifier,
            lifecycleRecentArchiveIdentifiers: archiveIdentifiers,
            lifecycleRecentArchiveCount: archiveIdentifiers.count,
            lifecycleActiveHistoryEntry: activeHistoryEntry,
            lifecycleArchiveHistoryEntries: archiveHistoryEntries,
            lifecycleHistoryEntryCount: historyEntries.count,
            sourceIdentifier: cue.sourceIdentifier,
            styleIdentifier: cue.styleIdentifier,
            milestoneIdentifier: cue.milestoneIdentifier,
            affectedNarrativeDescriptorIdentifiers: affectedDescriptors
        )
    }

    private static func nativeFeedbackHistoryEntry(
        _ active: CinematicNativeFeedbackCueLifecycle.ActiveCue
    ) -> CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot {
        let cue = active.cue
        let metadata = active.metadata
        return nativeFeedbackHistoryEntry(
            cueIdentifier: cue.identifier,
            lifecycleIdentifier: metadata.identifier,
            sequence: metadata.sequence,
            stateIdentifier: metadata.state.rawValue,
            reasonIdentifier: nil,
            milestoneIdentifier: cue.milestoneIdentifier,
            sourceIdentifier: cue.sourceIdentifier,
            styleIdentifier: cue.styleIdentifier,
            displayDuration: metadata.displayDuration
        )
    }

    private static func nativeFeedbackHistoryEntry(
        _ archived: CinematicNativeFeedbackCueLifecycle.ArchivedCue
    ) -> CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot {
        nativeFeedbackHistoryEntry(
            cueIdentifier: archived.cueIdentifier,
            lifecycleIdentifier: archived.lifecycleIdentifier,
            sequence: archived.sequence,
            stateIdentifier: archived.stateIdentifier,
            reasonIdentifier: archived.archiveReason.rawValue,
            milestoneIdentifier: archived.milestoneIdentifier,
            sourceIdentifier: archived.sourceIdentifier,
            styleIdentifier: archived.styleIdentifier,
            displayDuration: archived.displayDuration
        )
    }

    private static func nativeFeedbackHistoryEntry(
        cueIdentifier: String,
        lifecycleIdentifier: String,
        sequence: Int,
        stateIdentifier: String,
        reasonIdentifier: String?,
        milestoneIdentifier: String,
        sourceIdentifier: String?,
        styleIdentifier: String?,
        displayDuration: TimeInterval
    ) -> CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot {
        let identifier = [
            "seq:\(sequence)",
            "state:\(stateIdentifier)",
            reasonIdentifier.map { "reason:\($0)" },
            "milestone:\(milestoneIdentifier)",
            sourceIdentifier.map { "source:\($0)" },
            styleIdentifier.map { "style:\($0)" },
            "duration:\(fixed(displayDuration))",
            "lifecycle:\(lifecycleIdentifier)"
        ].compactMap { $0 }.joined(separator: "|")

        return CinematicDiagnosticsReport.NativeFeedbackHistoryEntrySnapshot(
            identifier: identifier,
            cueIdentifier: cueIdentifier,
            lifecycleIdentifier: lifecycleIdentifier,
            sequence: sequence,
            stateIdentifier: stateIdentifier,
            reasonIdentifier: reasonIdentifier,
            milestoneIdentifier: milestoneIdentifier,
            sourceIdentifier: sourceIdentifier,
            styleIdentifier: styleIdentifier,
            displayDuration: displayDuration
        )
    }

    private static func narrativeCueDescriptorSnapshot(
        for descriptor: CinematicSceneNarrativeCuePlan.CueDescriptor
    ) -> CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot {
        CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot(
            identifier: descriptor.identifier,
            stableID: descriptor.stableID,
            text: descriptor.text,
            secondaryText: descriptor.secondaryText,
            glyphIdentifier: descriptor.glyphIdentifier,
            anchorIdentifier: descriptor.anchorIdentifier,
            visibilityIdentifier: descriptor.visibilityIdentifier,
            scale: descriptor.scale,
            opacity: descriptor.opacity,
            lightFamilyIdentifier: descriptor.lightFamilyIdentifier,
            tintFamilyIdentifier: descriptor.tintFamilyIdentifier,
            cadence: descriptor.cadence,
            plaqueTreatmentIdentifier: descriptor.plaqueTreatmentIdentifier,
            plaqueTreatmentAccentIdentifier: descriptor.plaqueTreatmentAccentIdentifier,
            plaqueTreatmentRouteIdentifier: descriptor.plaqueTreatmentRouteIdentifier,
            plaqueTreatmentRenderRecipeIdentifier: descriptor.plaqueTreatmentRenderRecipeIdentifier,
            plaqueTreatmentRenderPrimitiveIdentifiers: descriptor.plaqueTreatmentRenderPrimitiveIdentifiers,
            plaqueTreatmentRenderPrimitiveCount: descriptor.plaqueTreatmentRenderPrimitiveCount,
            layout: narrativeCueLayoutSnapshot(for: descriptor.layout)
        )
    }

    private static func narrativeCueLayoutSnapshot(
        for layout: CinematicSceneNarrativeCuePlan.CueDescriptor.LayoutDescriptor
    ) -> CinematicDiagnosticsReport.NarrativeCueLayoutSnapshot {
        CinematicDiagnosticsReport.NarrativeCueLayoutSnapshot(
            identifier: layout.identifier,
            anchorPosition: layout.anchorPosition,
            facingModeIdentifier: layout.facingModeIdentifier,
            plateWidth: layout.plateSize.x,
            plateHeight: layout.plateSize.y,
            primaryTextWidth: layout.primaryTextWidth,
            secondaryTextWidth: layout.secondaryTextWidth,
            primaryFontSize: layout.primaryFontSize,
            secondaryFontSize: layout.secondaryFontSize,
            backingOpacity: layout.backingOpacity,
            glyphSideIdentifier: layout.glyphSideIdentifier,
            glyphOffset: layout.glyphOffset,
            plateDepth: layout.plateDepth,
            plateZOffset: layout.plateZOffset,
            primaryTextOffset: layout.primaryTextOffset,
            secondaryTextOffset: layout.secondaryTextOffset
        )
    }

    private static func overlayDisplaySnapshot(
        for plan: CinematicOverlayDisplayPlan
    ) -> CinematicDiagnosticsReport.OverlayDisplaySnapshot {
        CinematicDiagnosticsReport.OverlayDisplaySnapshot(
            identifier: plan.identifier,
            modeIdentifier: plan.modeIdentifier,
            visiblePillIdentifiers: plan.visiblePillIdentifiers,
            hudProminenceIdentifier: plan.hudProminenceIdentifier,
            chromeStyleIdentifier: plan.chromeStyleIdentifier,
            gradientStrength: plan.gradientStrength,
            worldTextMaxWidth: plan.worldTextMaxWidth,
            hudMaxWidth: plan.hudMaxWidth,
            pillLineLimit: plan.pillLineLimit,
            hudTitleLineLimit: plan.hudTitleLineLimit,
            hudDetailLineLimit: plan.hudDetailLineLimit,
            hudProfileLineLimit: plan.hudProfileLineLimit,
            hudStatusLineLimit: plan.hudStatusLineLimit,
            overlayOpacity: plan.overlayOpacity,
            reasonIdentifier: plan.reasonIdentifier,
            narrativeCueReadabilityIdentifier: plan.narrativeCueReadabilityIdentifier,
            nativeFeedbackCueIdentifier: plan.nativeFeedbackCueIdentifier,
            nativeFeedbackLifecycleIdentifier: plan.nativeFeedbackLifecycleIdentifier,
            nativeFeedbackBannerPolicyIdentifier: plan.nativeFeedbackBannerPolicyIdentifier,
            showsNativeFeedbackBanner: plan.showsNativeFeedbackBanner
        )
    }

    private static func worldTextSnapshot(
        for worldText: CinematicWorldText
    ) -> CinematicDiagnosticsReport.WorldTextSnapshot {
        let identifier = [
            worldText.questLabel,
            worldText.arenaCallout,
            worldText.activityCallout
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.WorldTextSnapshot(
            identifier: identifier,
            questLabel: worldText.questLabel,
            arenaCallout: worldText.arenaCallout,
            activityCallout: worldText.activityCallout
        )
    }

    private static func briefingSnapshot(
        for briefing: CinematicBriefing
    ) -> CinematicDiagnosticsReport.BriefingSnapshot {
        let identifier = [briefing.title, briefing.detail].joined(separator: "|")
        return CinematicDiagnosticsReport.BriefingSnapshot(
            identifier: identifier,
            title: briefing.title,
            detail: briefing.detail
        )
    }

    private static func cameraTuningSnapshot(
        settings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport.CameraTuningSnapshot {
        let orbitScale = CinematicTuning.cameraOrbitScale(settings: settings)
        let pullbackScale = CinematicTuning.cameraPullbackScale(settings: settings)
        let heightOffset = CinematicTuning.cameraHeightOffset(settings: settings)
        let followResponsiveness = CinematicTuning.cameraFollowResponsiveness(settings: settings)
        let followFieldOfView = CinematicTuning.cameraFollowFieldOfView(settings: settings)
        let driftScale = CinematicTuning.cameraDriftScale(settings: settings)
        let shakeScale = CinematicTuning.cameraShakeScale(settings: settings)
        let identifier = [
            settingsIdentifier(settings),
            fixed(Double(orbitScale)),
            fixed(Double(pullbackScale)),
            fixed(Double(heightOffset)),
            fixed(Double(followResponsiveness)),
            fixed(Double(followFieldOfView)),
            fixed(Double(driftScale)),
            fixed(Double(shakeScale))
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.CameraTuningSnapshot(
            identifier: identifier,
            orbitScale: orbitScale,
            pullbackScale: pullbackScale,
            heightOffset: heightOffset,
            followResponsiveness: followResponsiveness,
            followFieldOfView: followFieldOfView,
            driftScale: driftScale,
            shakeScale: shakeScale
        )
    }

    private static func activityTuningSnapshot(
        activityProfile: RepositoryActivityProfile,
        settings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport.ActivityTuningSnapshot {
        let ambientSpawnCadence = CinematicTuning.ambientSpawnCadence(
            activityProfile: activityProfile,
            settings: settings
        )
        let ambientEnemyLimit = CinematicTuning.ambientEnemyLimit(
            activityProfile: activityProfile,
            settings: settings
        )
        let activityLightBoost = CinematicTuning.activityLightBoost(
            activityProfile: activityProfile,
            settings: settings
        )
        let activityPressureScale = CinematicTuning.activityPressureScale(settings: settings)
        let pressureLevelIdentifier = activityProfile.pressureLevel.rawValue
        let identifier = [
            settingsIdentifier(settings),
            pressureLevelIdentifier,
            fixed(ambientSpawnCadence),
            String(ambientEnemyLimit),
            fixed(Double(activityLightBoost)),
            fixed(Double(activityPressureScale))
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.ActivityTuningSnapshot(
            identifier: identifier,
            pressureLevelIdentifier: pressureLevelIdentifier,
            ambientSpawnCadence: ambientSpawnCadence,
            ambientEnemyLimit: ambientEnemyLimit,
            activityLightBoost: activityLightBoost,
            activityPressureScale: activityPressureScale
        )
    }

    private static func setDressingSnapshot(
        for plan: CinematicSetDressingPlan
    ) -> CinematicDiagnosticsReport.SetDressingSnapshot {
        CinematicDiagnosticsReport.SetDressingSnapshot(
            identifier: plan.identifier,
            languageArchitectureIdentifier: plan.languageArchitecture.identifier,
            activityMarkerIdentifier: plan.activityMarker.identifier,
            pedestalLayoutIdentifier: plan.languageArchitecture.pedestalLayoutIdentifier,
            shardFormationIdentifier: plan.languageArchitecture.shardFormationIdentifier,
            pedestalSlotCount: plan.languageArchitecture.pedestalSlots.count,
            shardSlotCount: plan.languageArchitecture.shardSlots.count,
            layoutGeometryCoverageIdentifier: plan.languageArchitecture.layoutCoverageIdentifier,
            layoutGeometryIsBounded: plan.languageArchitecture.geometryIsBounded,
            pedestalCount: plan.pedestalFlames.pedestalCount,
            flameLightIntensity: plan.pedestalFlames.flameLightIntensity,
            flameOpacity: plan.pedestalFlames.flameOpacity,
            rimOpacity: plan.pedestalFlames.rimOpacity,
            shardCount: plan.floatingShards.shardCount,
            shardEmissionOpacity: plan.floatingShards.emissionOpacity,
            runeIntensityIdentifier: plan.runeIntensity.identifier,
            animationCadenceIdentifier: plan.animationCadence.identifier,
            flamePulseRate: plan.animationCadence.flamePulseRate,
            shardBobRate: plan.animationCadence.shardBobRate,
            ambientSpawnCadence: plan.ambientSpawnCadence,
            ambientEnemyLimit: plan.ambientEnemyLimit,
            activityLightBoost: plan.activityLightBoost,
            materialTextureVariantIdentifier: plan.materialTextureVariants.identifier,
            backdropTextureAssetIdentifier: plan.materialTextureVariants.backdropTextureAsset.identifier,
            arenaTextureAssetIdentifier: plan.materialTextureVariants.arenaTextureAsset.identifier,
            backdropTextureRouteIdentifier: plan.materialTextureVariants.backdropTextureAsset.routeIdentifier,
            arenaTextureRouteIdentifier: plan.materialTextureVariants.arenaTextureAsset.routeIdentifier,
            textureRoleCoverageIdentifier: plan.materialTextureVariants.textureRoleCoverageIdentifier,
            runeMaterialIdentifier: plan.materialTextureVariants.runeMaterialIdentifier,
            runeMaterialTreatmentIdentifier: plan.materialTextureVariants.runeMaterialTreatment.identifier,
            runeFloorEmissionOpacity: plan.materialTextureVariants.runeMaterialTreatment.floorEmissionOpacity,
            runeSegmentOpacityScale: plan.materialTextureVariants.runeMaterialTreatment.segmentOpacityScale,
            arenaAccentOpacityScale: plan.materialTextureVariants.runeMaterialTreatment.arenaAccentOpacityScale,
            backdropTextureName: plan.materialTextureVariants.backdropTextureName,
            arenaTextureName: plan.materialTextureVariants.arenaTextureName,
            usesFallbackTextureAsset: plan.materialTextureVariants.usesFallbackTextureAsset
        )
    }

    private static func commitConstellationSnapshot(
        for plan: CinematicCommitConstellationPlan
    ) -> CinematicDiagnosticsReport.CommitConstellationSnapshot {
        let focusPlan = plan.focusPlan
        return CinematicDiagnosticsReport.CommitConstellationSnapshot(
            identifier: [
                plan.identifier,
                "focus:\(focusPlan.identifier)"
            ].joined(separator: "|"),
            count: plan.count,
            newestSubject: plan.newestSubject,
            nodeIdentifiers: plan.nodeIdentifiers,
            branchIdentifiers: plan.branchIdentifiers,
            focusIdentifier: focusPlan.identifier,
            focusShotIdentifier: focusPlan.shot.identifier,
            focusLookTarget: focusPlan.lookTarget,
            usesFallbackFocus: focusPlan.isFallback
        )
    }

    private static func idleStoryCycleSnapshot(
        for plan: CinematicIdleStoryCyclePlan
    ) -> CinematicDiagnosticsReport.IdleStoryCycleSnapshot {
        guard let descriptor = plan.descriptor else {
            return CinematicDiagnosticsReport.IdleStoryCycleSnapshot(
                identifier: plan.identifier,
                isActive: false,
                phaseIdentifier: "none",
                sourceDescriptorIdentifier: "none",
                targetKindIdentifier: "none",
                cadence: 0,
                cameraTreatmentIdentifier: "none",
                anchorTreatmentIdentifier: "none",
                choreographyIdentifier: "none",
                dwellDuration: 0,
                transitionDurationScale: 0,
                cameraPressureIdentifier: "none",
                targetBias: 0,
                comfortDamping: 0,
                shakeHintIdentifier: "none",
                pulseHintIdentifier: "none",
                suppressionReason: plan.suppressionReason,
                phaseCopy: "",
                descriptorIdentifier: "none",
                cycleSlot: 0,
                phaseIndex: -1,
                diagnosticsWarningBundleIdentifier: "none",
                diagnosticsWarningSequence: 0,
                diagnosticsWarningCaptureCount: 0,
                diagnosticsWarningTargetCount: 0,
                diagnosticsWarningWarningCount: 0,
                diagnosticsWarningTargetIdentifiers: [],
                diagnosticsWarningIdentifiers: [],
                diagnosticsWarningRepeatedIdentifiers: [],
                diagnosticsWarningTargetAnchors: [],
                diagnosticsWarningRelatedRowAnchors: []
            )
        }
        let warningDescriptor = descriptor.diagnosticsWarningPulseDescriptor

        return CinematicDiagnosticsReport.IdleStoryCycleSnapshot(
            identifier: plan.identifier,
            isActive: true,
            phaseIdentifier: descriptor.phaseIdentifier,
            sourceDescriptorIdentifier: descriptor.sourceDescriptorIdentifier,
            targetKindIdentifier: descriptor.targetKindIdentifier,
            cadence: descriptor.cadence,
            cameraTreatmentIdentifier: descriptor.cameraTreatmentIdentifier,
            anchorTreatmentIdentifier: descriptor.anchorTreatmentIdentifier,
            choreographyIdentifier: descriptor.choreography.identifier,
            dwellDuration: descriptor.choreography.dwellDuration,
            transitionDurationScale: descriptor.choreography.transitionDurationScale,
            cameraPressureIdentifier: descriptor.choreography.cameraPressureIdentifier,
            targetBias: descriptor.choreography.targetBias,
            comfortDamping: descriptor.choreography.comfortDamping,
            shakeHintIdentifier: descriptor.choreography.shakeHintIdentifier,
            pulseHintIdentifier: descriptor.choreography.pulseHintIdentifier,
            suppressionReason: plan.suppressionReason,
            phaseCopy: descriptor.phaseCopy,
            descriptorIdentifier: descriptor.identifier,
            cycleSlot: descriptor.cycleSlot,
            phaseIndex: descriptor.phaseIndex,
            diagnosticsWarningBundleIdentifier: warningDescriptor?.bundleIdentifier ?? "none",
            diagnosticsWarningSequence: warningDescriptor?.sequence ?? 0,
            diagnosticsWarningCaptureCount: warningDescriptor?.captureCount ?? 0,
            diagnosticsWarningTargetCount: warningDescriptor?.targetCount ?? 0,
            diagnosticsWarningWarningCount: warningDescriptor?.warningCount ?? 0,
            diagnosticsWarningTargetIdentifiers: warningDescriptor?.targetIdentifiers ?? [],
            diagnosticsWarningIdentifiers: warningDescriptor?.warningIdentifiers ?? [],
            diagnosticsWarningRepeatedIdentifiers: warningDescriptor?.repeatedWarningIdentifiers ?? [],
            diagnosticsWarningTargetAnchors: warningDescriptor?.targetAnchors ?? [],
            diagnosticsWarningRelatedRowAnchors: warningDescriptor?.relatedRowAnchors ?? []
        )
    }

    private static func timelineFocusSnapshot(
        for plan: CinematicTimelineSceneFocusPlan
    ) -> CinematicDiagnosticsReport.TimelineFocusSnapshot {
        guard let descriptor = plan.descriptor else {
            return CinematicDiagnosticsReport.TimelineFocusSnapshot(
                identifier: plan.identifier,
                selectedBeatID: plan.selectedBeatID,
                isActive: false,
                kindIdentifier: "none",
                descriptorIdentifier: "none",
                label: nil,
                cameraShotIdentifier: "none",
                lookTarget: nil,
                lightFamilyIdentifier: "none",
                arenaEffectIdentifier: "none",
                phaseLightIntensity: 0,
                commitNodeIdentifier: nil,
                recoveryTreatmentIdentifier: nil,
                recoveryVisualIdentifier: nil,
                usesFallbackTarget: false
            )
        }

        return CinematicDiagnosticsReport.TimelineFocusSnapshot(
            identifier: plan.identifier,
            selectedBeatID: plan.selectedBeatID,
            isActive: true,
            kindIdentifier: descriptor.kindIdentifier,
            descriptorIdentifier: descriptor.identifier,
            label: descriptor.label,
            cameraShotIdentifier: descriptor.cameraShotIdentifier,
            lookTarget: descriptor.lookTarget,
            lightFamilyIdentifier: descriptor.lightFamilyIdentifier,
            arenaEffectIdentifier: descriptor.arenaEffectIdentifier,
            phaseLightIntensity: descriptor.phaseLightIntensity,
            commitNodeIdentifier: descriptor.commitNodeIdentifier,
            recoveryTreatmentIdentifier: descriptor.recoveryTreatmentIdentifier,
            recoveryVisualIdentifier: descriptor.recoveryVisualIdentifier,
            usesFallbackTarget: descriptor.usesFallbackTarget
        )
    }

    private static func runRecapSnapshot(
        for plan: CinematicRunRecapPlan
    ) -> CinematicDiagnosticsReport.RunRecapSnapshot {
        CinematicDiagnosticsReport.RunRecapSnapshot(
            identifier: plan.identifier,
            availabilityIdentifier: plan.availabilityIdentifier,
            isAvailable: plan.isAvailable,
            sessionNumber: plan.sessionNumber,
            title: plan.title,
            detail: plan.detail,
            status: plan.status,
            statusIdentifier: plan.statusIdentifier,
            styleIdentifier: plan.style.rawValue,
            colorIdentifier: plan.colorIdentifier,
            systemImage: plan.systemImage,
            latestCompletedSummary: plan.latestCompletedSummary,
            newestCommitHighlight: plan.newestCommitHighlight,
            completedCount: plan.completedCount,
            commitHighlightCount: plan.commitHighlightCount,
            eventChipCount: plan.eventChipCount,
            eventChipIdentifiers: plan.eventChips.map(\.identifier),
            sourceIdentifier: plan.sourceIdentifier,
            flavorStateIdentifier: plan.flavorStateIdentifier,
            flavorIdentifier: plan.flavorIdentifier,
            flavorSourceIdentifier: plan.flavorSourceIdentifier,
            titleSourceIdentifier: plan.titleSourceIdentifier
        )
    }

    private static func runRecapShareSnapshot(
        for plan: CinematicRunRecapSharePlan
    ) -> CinematicDiagnosticsReport.RunRecapShareSnapshot {
        CinematicDiagnosticsReport.RunRecapShareSnapshot(
            identifier: plan.identifier,
            availabilityIdentifier: plan.availabilityIdentifier,
            availabilityReason: plan.availabilityReason,
            isAvailable: plan.isAvailable,
            recapIdentifier: plan.recapIdentifier,
            recapFocusIdentifier: plan.recapFocusIdentifier,
            endCardIdentifier: plan.endCardIdentifier,
            title: plan.title,
            detail: plan.detail,
            status: plan.status,
            commitHighlight: plan.commitHighlight,
            eventSummaries: plan.eventSummaries,
            eventSummaryCount: plan.eventSummaryCount,
            visualDescriptorTokens: plan.visualDescriptorTokens,
            visualDescriptorTokenCount: plan.visualDescriptorTokenCount,
            text: plan.text,
            textLength: plan.textLength
        )
    }

    private static func runRecapShareArtifactSnapshot(
        for plan: CinematicRunRecapShareArtifactPlan
    ) -> CinematicDiagnosticsReport.RunRecapShareArtifactSnapshot {
        CinematicDiagnosticsReport.RunRecapShareArtifactSnapshot(
            identifier: plan.identifier,
            isAvailable: plan.isAvailable,
            availabilityReason: plan.availabilityReason,
            sessionNumber: plan.sessionNumber,
            filename: plan.filename,
            shareIdentifier: plan.shareIdentifier,
            recapIdentifier: plan.recapIdentifier,
            recapFocusIdentifier: plan.recapFocusIdentifier,
            endCardIdentifier: plan.endCardIdentifier,
            title: plan.title,
            status: plan.status,
            detail: plan.detail,
            commitHighlight: plan.commitHighlight,
            eventSummaryCount: plan.eventSummaryCount,
            visualDescriptorTokenCount: plan.visualDescriptorTokenCount,
            markdownLength: plan.markdownLength
        )
    }

    private static func runRecapShareArtifactHistorySnapshot(
        for plan: CinematicRunRecapShareArtifactHistoryPlan,
        cleanupResult: CinematicRunRecapShareArtifactCleanupResult?
    ) -> CinematicDiagnosticsReport.RunRecapShareArtifactHistorySnapshot {
        CinematicDiagnosticsReport.RunRecapShareArtifactHistorySnapshot(
            identifier: plan.identifier,
            isAvailable: plan.isAvailable,
            availabilityReason: plan.availabilityReason,
            retentionLimit: plan.retentionLimit,
            totalCount: plan.totalCount,
            hiddenCount: plan.hiddenCount,
            cleanupCandidateCount: plan.cleanupCandidateCount,
            hiddenCleanupCandidateCount: plan.hiddenCleanupCandidateCount,
            cleanupCandidateIdentifiers: plan.cleanupCandidateIdentifiers,
            latestSessionNumber: plan.latestEntry?.sessionNumber,
            latestFilename: plan.latestEntry?.filename,
            exportIdentifier: plan.exportIdentifier,
            exportMarkdownLength: plan.combinedMarkdownLength,
            warningCount: plan.warningCount,
            hiddenWarningCount: plan.hiddenWarningCount,
            warningIdentifiers: plan.warnings.map(\.identifier),
            warningStateIdentifier: plan.hasWarnings ? "warnings" : "clear",
            lastCleanupResultIdentifier: cleanupResult?.identifier ?? "none",
            lastCleanupResultStatus: cleanupResult?.status.rawValue ?? "none"
        )
    }

    private static func runRecapShareArtifactRollupSnapshot(
        for plan: CinematicRunRecapShareArtifactRollupPlan
    ) -> CinematicDiagnosticsReport.RunRecapShareArtifactRollupSnapshot {
        CinematicDiagnosticsReport.RunRecapShareArtifactRollupSnapshot(
            identifier: plan.identifier,
            exportIdentifier: plan.exportIdentifier,
            isAvailable: plan.isAvailable,
            availabilityReason: plan.availabilityReason,
            isSearchActive: plan.isSearchActive,
            searchQuerySnippet: plan.searchQuerySnippet,
            searchQueryFingerprint: plan.searchQueryFingerprint,
            noMatchAvailabilityReason: plan.noMatchAvailabilityReason,
            retainedEntryCount: plan.retainedEntryCount,
            totalCount: plan.totalCount,
            hiddenCount: plan.hiddenCount,
            matchingEntryCount: plan.matchingEntryCount,
            unfilteredVisibleCount: plan.unfilteredVisibleCount,
            selectedEntryIdentifier: plan.selectedEntryIdentifier,
            selectedFallbackEntryIdentifier: plan.selectedFallbackEntryIdentifier,
            selectedFallbackReasonIdentifier: plan.selectedFallbackReasonIdentifier,
            sessionRangeLabel: plan.sessionRangeLabel,
            newestEntryIdentifier: plan.newestEntryIdentifier,
            newestSessionNumber: plan.newestSessionNumber,
            newestFilename: plan.newestFilename,
            oldestEntryIdentifier: plan.oldestEntryIdentifier,
            oldestSessionNumber: plan.oldestSessionNumber,
            oldestFilename: plan.oldestFilename,
            statusBuckets: plan.statusBuckets.map { bucket in
                CinematicDiagnosticsReport.RunRecapShareArtifactRollupStatusBucketSnapshot(
                    identifier: bucket.identifier,
                    label: bucket.label,
                    count: bucket.count
                )
            },
            statusBucketSummary: plan.statusBucketSummary,
            cleanupCandidateCount: plan.cleanupCandidateCount,
            hiddenCleanupCandidateCount: plan.hiddenCleanupCandidateCount,
            cleanupCandidateIdentifiers: plan.cleanupCandidateIdentifiers,
            warningStateIdentifier: plan.warningStateIdentifier,
            warningCount: plan.warningCount,
            hiddenWarningCount: plan.hiddenWarningCount,
            warningIdentifiers: plan.warningIdentifiers,
            hasWarnings: plan.hasWarnings,
            insightText: plan.insightText,
            exportTextLength: plan.exportTextLength,
            copyLabel: plan.copyLabel,
            copyHelp: plan.copyHelp
        )
    }

    private static func runRecapShareArtifactComparisonSnapshot(
        for plan: CinematicRunRecapShareArtifactComparisonPlan
    ) -> CinematicDiagnosticsReport.RunRecapShareArtifactComparisonSnapshot {
        CinematicDiagnosticsReport.RunRecapShareArtifactComparisonSnapshot(
            identifier: plan.identifier,
            exportIdentifier: plan.exportIdentifier,
            isAvailable: plan.isAvailable,
            availabilityReason: plan.availabilityReason,
            isSearchActive: plan.isSearchActive,
            searchQuerySnippet: plan.searchQuerySnippet,
            searchQueryFingerprint: plan.searchQueryFingerprint,
            noMatchAvailabilityReason: plan.noMatchAvailabilityReason,
            retainedEntryCount: plan.retainedEntryCount,
            totalCount: plan.totalCount,
            hiddenCount: plan.hiddenCount,
            matchingEntryCount: plan.matchingEntryCount,
            unfilteredVisibleCount: plan.unfilteredVisibleCount,
            selectedEntryIdentifier: plan.selectedEntryIdentifier,
            selectedFallbackEntryIdentifier: plan.selectedFallbackEntryIdentifier,
            selectedFallbackReasonIdentifier: plan.selectedFallbackReasonIdentifier,
            compareEntryIdentifier: plan.compareEntryIdentifier,
            targetModeIdentifier: plan.targetModeIdentifier,
            targetDirectionIdentifier: plan.targetDirectionIdentifier,
            pinnedTargetEntryIdentifier: plan.pinnedTargetEntryIdentifier,
            pinnedTargetStateIdentifier: plan.pinnedTargetStateIdentifier,
            pinnedTargetUnavailableReasonIdentifier: plan.pinnedTargetUnavailableReasonIdentifier,
            promotedHoldStateIdentifier: plan.promotedHoldStateIdentifier,
            requestedSavedTourHoldEntryIdentifier: plan.requestedSavedTourHoldEntryIdentifier,
            retainedSavedTourHoldEntryIdentifier: plan.retainedSavedTourHoldEntryIdentifier,
            filteredSavedTourHoldEntryIdentifier: plan.filteredSavedTourHoldEntryIdentifier,
            requestedPinnedEntryIdentifiers: plan.requestedPinnedEntryIdentifiers,
            retainedPinnedEntryIdentifiers: plan.retainedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: plan.missingPinnedEntryIdentifiers,
            filteredPinnedEntryIdentifiers: plan.filteredPinnedEntryIdentifiers,
            pinnedEntryCount: plan.pinnedEntryCount,
            retainedPinnedEntryCount: plan.retainedPinnedEntryCount,
            missingPinnedEntryCount: plan.missingPinnedEntryCount,
            filteredPinnedEntryCount: plan.filteredPinnedEntryCount,
            sessionDelta: plan.sessionDelta,
            selectedSessionNumber: plan.selectedSessionNumber,
            compareSessionNumber: plan.compareSessionNumber,
            selectedFilename: plan.selectedFilename,
            compareFilename: plan.compareFilename,
            selectedTitleSnippet: plan.selectedTitleSnippet,
            compareTitleSnippet: plan.compareTitleSnippet,
            selectedStatusSnippet: plan.selectedStatusSnippet,
            compareStatusSnippet: plan.compareStatusSnippet,
            selectedCommitSnippet: plan.selectedCommitSnippet,
            compareCommitSnippet: plan.compareCommitSnippet,
            selectedBodyPreviewText: plan.selectedBodyPreviewText,
            compareBodyPreviewText: plan.compareBodyPreviewText,
            cleanupCandidateCount: plan.cleanupCandidateCount,
            hiddenCleanupCandidateCount: plan.hiddenCleanupCandidateCount,
            cleanupCandidateIdentifiers: plan.cleanupCandidateIdentifiers,
            warningStateIdentifier: plan.warningStateIdentifier,
            warningCount: plan.warningCount,
            hiddenWarningCount: plan.hiddenWarningCount,
            warningIdentifiers: plan.warningIdentifiers,
            hasWarnings: plan.hasWarnings,
            exportTextLength: plan.exportTextLength,
            copyLabel: plan.copyLabel,
            copyHelp: plan.copyHelp
        )
    }

    private static func runRecapShareArtifactPinnedReferenceSnapshot(
        for plan: CinematicRunRecapShareArtifactPinnedReferencePlan
    ) -> CinematicDiagnosticsReport.RunRecapShareArtifactPinnedReferenceSnapshot {
        CinematicDiagnosticsReport.RunRecapShareArtifactPinnedReferenceSnapshot(
            identifier: plan.identifier,
            exportIdentifier: plan.exportIdentifier,
            isAvailable: plan.isAvailable,
            availabilityReason: plan.availabilityReason,
            isSearchActive: plan.isSearchActive,
            searchQuerySnippet: plan.searchQuerySnippet,
            searchQueryFingerprint: plan.searchQueryFingerprint,
            noMatchAvailabilityReason: plan.noMatchAvailabilityReason,
            retainedEntryCount: plan.retainedEntryCount,
            totalCount: plan.totalCount,
            hiddenCount: plan.hiddenCount,
            matchingEntryCount: plan.matchingEntryCount,
            unfilteredVisibleCount: plan.unfilteredVisibleCount,
            selectedEntryIdentifier: plan.selectedEntryIdentifier,
            selectedEntryIsPinned: plan.selectedEntryIsPinned,
            selectedPinStateIdentifier: plan.selectedPinStateIdentifier,
            requestedPinnedEntryIdentifiers: plan.requestedPinnedEntryIdentifiers,
            retainedPinnedEntryIdentifiers: plan.retainedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: plan.missingPinnedEntryIdentifiers,
            filteredPinnedEntryIdentifiers: plan.filteredPinnedEntryIdentifiers,
            quickSelectEntryIdentifiers: plan.quickSelectEntryIdentifiers,
            pinnedEntryCount: plan.pinnedEntryCount,
            retainedPinnedEntryCount: plan.retainedPinnedEntryCount,
            missingPinnedEntryCount: plan.missingPinnedEntryCount,
            filteredPinnedEntryCount: plan.filteredPinnedEntryCount,
            quickSelectEntryCount: plan.quickSelectEntryCount,
            references: plan.references.map { reference in
                CinematicDiagnosticsReport.RunRecapShareArtifactPinnedReferenceEntrySnapshot(
                    identifier: reference.identifier,
                    sessionNumber: reference.sessionNumber,
                    filename: reference.filename,
                    titleSnippet: reference.titleSnippet,
                    statusSnippet: reference.statusSnippet,
                    commitSnippet: reference.commitSnippet,
                    isQuickSelectable: reference.isQuickSelectable
                )
            },
            warningStateIdentifier: plan.warningStateIdentifier,
            warningCount: plan.warningCount,
            hiddenWarningCount: plan.hiddenWarningCount,
            warningIdentifiers: plan.warningIdentifiers,
            hasWarnings: plan.hasWarnings,
            exportTextLength: plan.exportTextLength,
            copyLabel: plan.copyLabel,
            copyHelp: plan.copyHelp
        )
    }

    private static func runRecapShareArtifactTourSnapshot(
        for plan: CinematicRunRecapShareArtifactTourPlan
    ) -> CinematicDiagnosticsReport.RunRecapShareArtifactTourSnapshot {
        CinematicDiagnosticsReport.RunRecapShareArtifactTourSnapshot(
            identifier: plan.identifier,
            isAvailable: plan.isAvailable,
            availabilityReason: plan.availabilityReason,
            stateIdentifier: plan.stateIdentifier,
            selectionSourceIdentifier: plan.selectionSourceIdentifier,
            savedTourHoldStateIdentifier: plan.savedTourHoldStateIdentifier,
            requestedSavedTourHoldEntryIdentifier: plan.requestedSavedTourHoldEntryIdentifier,
            retainedSavedTourHoldEntryIdentifier: plan.retainedSavedTourHoldEntryIdentifier,
            filteredSavedTourHoldEntryIdentifier: plan.filteredSavedTourHoldEntryIdentifier,
            isSearchActive: plan.isSearchActive,
            searchQuerySnippet: plan.searchQuerySnippet,
            searchQueryFingerprint: plan.searchQueryFingerprint,
            noMatchAvailabilityReason: plan.noMatchAvailabilityReason,
            retainedEntryCount: plan.retainedEntryCount,
            totalCount: plan.totalCount,
            hiddenCount: plan.hiddenCount,
            matchingEntryCount: plan.matchingEntryCount,
            unfilteredVisibleCount: plan.unfilteredVisibleCount,
            selectedEntryIdentifier: plan.selectedEntryIdentifier,
            selectedOrdinal: plan.selectedOrdinal,
            entryCount: plan.entryCount,
            rotationSeed: plan.rotationSeed,
            sessionNumber: plan.sessionNumber,
            filename: plan.filename,
            titleSnippet: plan.titleSnippet,
            statusSnippet: plan.statusSnippet,
            commitSnippet: plan.commitSnippet,
            bodyPreviewText: plan.bodyPreviewText,
            sessionText: plan.sessionText,
            requestedPinnedEntryIdentifiers: plan.requestedPinnedEntryIdentifiers,
            retainedPinnedEntryIdentifiers: plan.retainedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: plan.missingPinnedEntryIdentifiers,
            filteredPinnedEntryIdentifiers: plan.filteredPinnedEntryIdentifiers,
            pinnedEntryCount: plan.pinnedEntryCount,
            retainedPinnedEntryCount: plan.retainedPinnedEntryCount,
            missingPinnedEntryCount: plan.missingPinnedEntryCount,
            filteredPinnedEntryCount: plan.filteredPinnedEntryCount,
            warningStateIdentifier: plan.warningStateIdentifier,
            warningCount: plan.warningCount,
            hiddenWarningCount: plan.hiddenWarningCount,
            warningIdentifiers: plan.warningIdentifiers,
            hasWarnings: plan.hasWarnings,
            shouldDisplay: plan.shouldDisplay
        )
    }

    private static func runRecapShareArtifactPreviewSnapshot(
        for plan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        selectedExportPlan: CinematicRunRecapShareArtifactSubsetExportPlan,
        filteredExportPlan: CinematicRunRecapShareArtifactSubsetExportPlan
    ) -> CinematicDiagnosticsReport.RunRecapShareArtifactPreviewSnapshot {
        CinematicDiagnosticsReport.RunRecapShareArtifactPreviewSnapshot(
            identifier: plan.identifier,
            isAvailable: plan.isAvailable,
            availabilityReason: plan.availabilityReason,
            isSearchActive: plan.isSearchActive,
            searchQuerySnippet: plan.searchQuerySnippet,
            searchQueryFingerprint: plan.searchQueryFingerprint,
            matchCount: plan.matchCount,
            unfilteredVisibleCount: plan.unfilteredVisibleCount,
            noMatchAvailabilityReason: plan.noMatchAvailabilityReason,
            selectedEntryIdentifier: plan.selectedEntryIdentifier,
            selectedFallbackEntryIdentifier: plan.selectedFallbackEntryIdentifier,
            selectedFallbackReasonIdentifier: plan.selectedFallbackReasonIdentifier,
            previousEntryIdentifier: plan.previousEntryIdentifier,
            nextEntryIdentifier: plan.nextEntryIdentifier,
            selectedIndex: plan.selectedIndex,
            selectedOrdinal: plan.selectedOrdinal,
            entryCount: plan.entryCount,
            sessionNumber: plan.sessionNumber,
            filename: plan.filename,
            titleSnippet: plan.titleSnippet,
            statusSnippet: plan.statusSnippet,
            commitSnippet: plan.commitSnippet,
            pathSnippet: plan.pathSnippet,
            bodyPreviewText: plan.bodyPreviewText,
            markdownLength: plan.markdownLength,
            warningStateIdentifier: plan.warningStateIdentifier,
            warningCount: plan.warningCount,
            hasWarnings: plan.hasWarnings,
            selectedExport: runRecapShareArtifactSubsetExportSnapshot(for: selectedExportPlan),
            filteredExport: runRecapShareArtifactSubsetExportSnapshot(for: filteredExportPlan)
        )
    }

    private static func runRecapShareArtifactSubsetExportSnapshot(
        for plan: CinematicRunRecapShareArtifactSubsetExportPlan
    ) -> CinematicDiagnosticsReport.RunRecapShareArtifactSubsetExportSnapshot {
        CinematicDiagnosticsReport.RunRecapShareArtifactSubsetExportSnapshot(
            identifier: plan.identifier,
            exportIdentifier: plan.exportIdentifier,
            scopeIdentifier: plan.scopeIdentifier,
            isAvailable: plan.isAvailable,
            availabilityReason: plan.availabilityReason,
            isSearchActive: plan.isSearchActive,
            searchQuerySnippet: plan.searchQuerySnippet,
            searchQueryFingerprint: plan.searchQueryFingerprint,
            noMatchAvailabilityReason: plan.noMatchAvailabilityReason,
            retainedEntryCount: plan.retainedEntryCount,
            totalCount: plan.totalCount,
            hiddenCount: plan.hiddenCount,
            selectedCount: plan.selectedCount,
            filteredCount: plan.filteredCount,
            exportEntryCount: plan.exportEntryCount,
            unfilteredVisibleCount: plan.unfilteredVisibleCount,
            selectedEntryIdentifier: plan.selectedEntryIdentifier,
            selectedFallbackEntryIdentifier: plan.selectedFallbackEntryIdentifier,
            selectedFallbackReasonIdentifier: plan.selectedFallbackReasonIdentifier,
            exportedEntryIdentifiers: plan.exportedEntryIdentifiers,
            warningStateIdentifier: plan.warningStateIdentifier,
            warningCount: plan.warningCount,
            hiddenWarningCount: plan.hiddenWarningCount,
            warningIdentifiers: plan.warningIdentifiers,
            hasWarnings: plan.hasWarnings,
            markdownLength: plan.markdownLength,
            copyLabel: plan.copyLabel,
            copyHelp: plan.copyHelp
        )
    }

    private static func runRecapShareArtifactCommandSnapshot(
        commandPlan: CinematicRunRecapShareArtifactCommandPlan,
        actionMenuPlan: CinematicRunRecapShareArtifactActionMenuPlan,
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        rollupPlan: CinematicRunRecapShareArtifactRollupPlan,
        comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan,
        pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan,
        tourPlan: CinematicRunRecapShareArtifactTourPlan,
        selectedExportPlan: CinematicRunRecapShareArtifactSubsetExportPlan,
        filteredExportPlan: CinematicRunRecapShareArtifactSubsetExportPlan
    ) -> CinematicDiagnosticsReport.RunRecapShareArtifactCommandSnapshot {
        typealias Section = CinematicRunRecapShareArtifactActionMenuPlan.Section
        typealias Snapshot = CinematicDiagnosticsReport.RunRecapShareArtifactCommandSnapshot
        typealias SectionSnapshot = CinematicDiagnosticsReport.RunRecapShareArtifactCommandSectionSnapshot

        let enabledCommandCount = commandPlan.commands.filter(\.isEnabled).count
        let disabledActionKindIdentifiers = commandPlan.commands
            .filter { !$0.isEnabled }
            .map { $0.sourceActionKind.rawValue }
        let commandActionKinds = Set(commandPlan.commands.map(\.sourceActionKind))
        let omittedActionKindIdentifiers = actionMenuPlan.actions
            .filter { !commandActionKinds.contains($0.actionKind) }
            .map { $0.actionKind.rawValue }
        let sections = Section.allCases.map { section -> SectionSnapshot in
            let sectionCommands = commandPlan.commands(in: section)
            let sectionEnabledCount = sectionCommands.filter(\.isEnabled).count
            return SectionSnapshot(
                sectionIdentifier: section.rawValue,
                commandCount: sectionCommands.count,
                enabledCommandCount: sectionEnabledCount,
                disabledCommandCount: sectionCommands.count - sectionEnabledCount
            )
        }
        let shortcutIdentifiers = commandPlan.commands.map(\.shortcut.identifier)
        let appLevelShortcutIdentifiers = recapArtifactAppLevelShortcutIdentifiers()
        let appLevelShortcutIdentifierSet = Set(appLevelShortcutIdentifiers)
        let appLevelShortcutCollisionIdentifiers = shortcutIdentifiers.filter(appLevelShortcutIdentifierSet.contains)
        let appLevelShortcutCollisionStateIdentifier = appLevelShortcutCollisionIdentifiers.isEmpty
            ? "clear"
            : "collision"

        let identifier = bounded(
            [
                "run-recap-share-artifact-command-diagnostics",
                "commands:\(commandPlan.commandCount)",
                "actions:\(actionMenuPlan.actionCount)",
                "enabled:\(enabledCommandCount)",
                "disabled:\(commandPlan.commandCount - enabledCommandCount)",
                "menu:\(fingerprint(actionMenuPlan.identifier))",
                "plan:\(fingerprint(commandPlan.identifier))",
                "history:\(fingerprint(historyPlan.identifier))",
                "preview:\(fingerprint(previewPlan.identifier))",
                "rollup:\(fingerprint(rollupPlan.identifier))",
                "comparison:\(fingerprint(comparisonPlan.identifier))",
                "pins:\(fingerprint(pinnedReferencePlan.identifier))",
                "tour:\(fingerprint(tourPlan.identifier))",
                "selected-export:\(fingerprint(selectedExportPlan.identifier))",
                "filtered-export:\(fingerprint(filteredExportPlan.identifier))",
                "shortcuts:\(fingerprint(shortcutIdentifiers.joined(separator: "|")))",
                "disabled-kinds:\(fingerprint(disabledActionKindIdentifiers.joined(separator: "|")))",
                "omitted-kinds:\(fingerprint(omittedActionKindIdentifiers.joined(separator: "|")))",
                "app-shortcuts:\(fingerprint(appLevelShortcutIdentifiers.joined(separator: "|")))",
                "collisions:\(appLevelShortcutCollisionStateIdentifier)",
                "collision-ids:\(fingerprint(appLevelShortcutCollisionIdentifiers.joined(separator: "|")))",
                "history-availability:\(historyPlan.availabilityReason)",
                "preview-no-match:\(previewPlan.noMatchAvailabilityReason ?? "none")",
                "selected-export:\(selectedExportPlan.availabilityReason)",
                "filtered-export:\(filteredExportPlan.availabilityReason)",
                "rollup:\(rollupPlan.availabilityReason)",
                "comparison:\(comparisonPlan.availabilityReason)",
                "pins:\(pinnedReferencePlan.availabilityReason)",
                "missing-pins:\(pinnedReferencePlan.missingPinnedEntryCount)",
                "filtered-pins:\(pinnedReferencePlan.filteredPinnedEntryCount)",
                "tour:\(tourPlan.availabilityReason)",
                "hold:\(tourPlan.savedTourHoldStateIdentifier)",
                "filtered-hold:\(tourPlan.filteredSavedTourHoldEntryIdentifier ?? "none")",
                "tour-no-match:\(tourPlan.noMatchAvailabilityReason ?? "none")",
                "promoted-hold:\(comparisonPlan.promotedHoldStateIdentifier)"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactCommandPlan.identifierMaxCharacters
        )

        return Snapshot(
            identifier: identifier,
            commandPlanIdentifier: commandPlan.identifier,
            sourceActionMenuIdentifier: actionMenuPlan.identifier,
            sourceHistoryIdentifier: historyPlan.identifier,
            sourcePreviewIdentifier: previewPlan.identifier,
            sourceRollupIdentifier: rollupPlan.identifier,
            sourceComparisonIdentifier: comparisonPlan.identifier,
            sourcePinsIdentifier: pinnedReferencePlan.identifier,
            sourceTourIdentifier: tourPlan.identifier,
            sourceSelectedExportIdentifier: selectedExportPlan.identifier,
            sourceFilteredExportIdentifier: filteredExportPlan.identifier,
            actionCount: actionMenuPlan.actionCount,
            commandCount: commandPlan.commandCount,
            enabledCommandCount: enabledCommandCount,
            disabledCommandCount: commandPlan.commandCount - enabledCommandCount,
            sectionCount: sections.count,
            sections: sections,
            shortcutIdentifiers: shortcutIdentifiers,
            disabledActionKindIdentifiers: disabledActionKindIdentifiers,
            omittedActionKindIdentifiers: omittedActionKindIdentifiers,
            appLevelShortcutCollisionStateIdentifier: appLevelShortcutCollisionStateIdentifier,
            appLevelShortcutIdentifiers: appLevelShortcutIdentifiers,
            appLevelShortcutCollisionIdentifiers: appLevelShortcutCollisionIdentifiers,
            historyAvailabilityReason: historyPlan.availabilityReason,
            previewNoMatchAvailabilityReason: previewPlan.noMatchAvailabilityReason,
            selectedExportAvailabilityReason: selectedExportPlan.availabilityReason,
            filteredExportAvailabilityReason: filteredExportPlan.availabilityReason,
            rollupAvailabilityReason: rollupPlan.availabilityReason,
            comparisonAvailabilityReason: comparisonPlan.availabilityReason,
            comparisonPromotedHoldStateIdentifier: comparisonPlan.promotedHoldStateIdentifier,
            pinsAvailabilityReason: pinnedReferencePlan.availabilityReason,
            missingPinnedEntryCount: pinnedReferencePlan.missingPinnedEntryCount,
            filteredPinnedEntryCount: pinnedReferencePlan.filteredPinnedEntryCount,
            tourAvailabilityReason: tourPlan.availabilityReason,
            tourSavedHoldStateIdentifier: tourPlan.savedTourHoldStateIdentifier,
            tourFilteredSavedHoldEntryIdentifier: tourPlan.filteredSavedTourHoldEntryIdentifier,
            tourNoMatchAvailabilityReason: tourPlan.noMatchAvailabilityReason
        )
    }

    private static func runRecapSceneFocusSnapshot(
        for plan: CinematicRunRecapSceneFocusPlan
    ) -> CinematicDiagnosticsReport.RunRecapSceneFocusSnapshot {
        guard let descriptor = plan.descriptor else {
            return CinematicDiagnosticsReport.RunRecapSceneFocusSnapshot(
                identifier: plan.identifier,
                isActive: false,
                descriptorIdentifier: "none",
                recapIdentifier: "none",
                terminalBeatID: nil,
                terminalStatusIdentifier: "none",
                terminalStyleIdentifier: "none",
                cameraShotIdentifier: "none",
                lookTarget: nil,
                lightFamilyIdentifier: "none",
                arenaEffectIdentifier: "none",
                phaseLightIntensity: 0,
                commitNodeIdentifier: nil,
                fallbackTargetIdentifier: nil,
                usesFallbackTarget: false
            )
        }

        return CinematicDiagnosticsReport.RunRecapSceneFocusSnapshot(
            identifier: plan.identifier,
            isActive: true,
            descriptorIdentifier: descriptor.identifier,
            recapIdentifier: descriptor.recapIdentifier,
            terminalBeatID: descriptor.terminalBeatID,
            terminalStatusIdentifier: descriptor.terminalStatusIdentifier,
            terminalStyleIdentifier: descriptor.terminalStyleIdentifier,
            cameraShotIdentifier: descriptor.cameraShotIdentifier,
            lookTarget: descriptor.lookTarget,
            lightFamilyIdentifier: descriptor.lightFamilyIdentifier,
            arenaEffectIdentifier: descriptor.arenaEffectIdentifier,
            phaseLightIntensity: descriptor.phaseLightIntensity,
            commitNodeIdentifier: descriptor.commitNodeIdentifier,
            fallbackTargetIdentifier: descriptor.fallbackTargetIdentifier,
            usesFallbackTarget: descriptor.usesFallbackTarget
        )
    }

    private static func runRecapEndCardSnapshot(
        for plan: CinematicRunRecapEndCardPlan
    ) -> CinematicDiagnosticsReport.RunRecapEndCardSnapshot {
        guard let descriptor = plan.descriptor else {
            return CinematicDiagnosticsReport.RunRecapEndCardSnapshot(
                identifier: plan.identifier,
                isActive: false,
                descriptorIdentifier: "none",
                recapIdentifier: "none",
                title: "",
                detail: "",
                status: "",
                titleSourceIdentifier: "none",
                flavorStateIdentifier: "none",
                flavorIdentifier: nil,
                flavorSourceIdentifier: nil,
                styleIdentifier: "none",
                colorIdentifier: "none",
                anchorIdentifier: "none",
                scale: 0,
                cadence: 0,
                lightFamilyIdentifier: "none",
                tintFamilyIdentifier: "none",
                glyphIdentifier: "none",
                layoutIdentifier: "none",
                plateWidth: 0,
                plateHeight: 0,
                plaqueTreatmentIdentifier: "none",
                plaqueTreatmentAccentIdentifier: "none",
                plaqueTreatmentRouteIdentifier: "none",
                plaqueTreatmentRenderRecipeIdentifier: "none",
                plaqueTreatmentRenderPrimitiveIdentifiers: [],
                plaqueTreatmentRenderPrimitiveCount: 0,
                hasPinnedComparisonCue: false,
                pinnedComparisonCueIdentifier: nil,
                pinnedComparisonCueComparisonIdentifier: nil,
                pinnedComparisonCueComparisonExportIdentifier: nil,
                pinnedComparisonCueModeIdentifier: "none",
                pinnedComparisonCueStateIdentifier: "inactive",
                pinnedComparisonCueNoMatchStateIdentifier: "none",
                pinnedComparisonCueTargetDirectionIdentifier: "none",
                pinnedComparisonCueSelectedEntryIdentifier: nil,
                pinnedComparisonCueTargetEntryIdentifier: nil,
                pinnedComparisonCueSelectedSessionNumber: nil,
                pinnedComparisonCueTargetSessionNumber: nil,
                pinnedComparisonCueDeltaLabel: "",
                pinnedComparisonCuePinnedEntryCount: 0,
                pinnedComparisonCueRetainedPinnedEntryCount: 0,
                pinnedComparisonCueMissingPinnedEntryCount: 0,
                pinnedComparisonCueFilteredPinnedEntryCount: 0,
                pinnedComparisonCuePromotedHoldStateIdentifier: "none",
                pinnedComparisonCuePromotedHoldEntryIdentifier: nil,
                pinnedComparisonCueWarningStateIdentifier: "none",
                pinnedComparisonCueGlyphIdentifier: "none",
                pinnedComparisonCueRailTreatmentIdentifier: "none",
                pinnedComparisonCueLabel: "",
                pinnedComparisonCueDetail: "",
                pinnedComparisonCueLabelLength: 0,
                pinnedComparisonCueDetailLength: 0,
                pinnedComparisonCueDeltaLabelLength: 0,
                titleLength: 0,
                detailLength: 0,
                statusLength: 0
            )
        }

        let cue = descriptor.pinnedComparisonCue
        return CinematicDiagnosticsReport.RunRecapEndCardSnapshot(
            identifier: plan.identifier,
            isActive: true,
            descriptorIdentifier: descriptor.identifier,
            recapIdentifier: descriptor.recapIdentifier,
            title: descriptor.title,
            detail: descriptor.detail,
            status: descriptor.status,
            titleSourceIdentifier: descriptor.titleSourceIdentifier,
            flavorStateIdentifier: descriptor.flavorStateIdentifier,
            flavorIdentifier: descriptor.flavorIdentifier,
            flavorSourceIdentifier: descriptor.flavorSourceIdentifier,
            styleIdentifier: descriptor.styleIdentifier,
            colorIdentifier: descriptor.colorIdentifier,
            anchorIdentifier: descriptor.anchorIdentifier,
            scale: descriptor.scale,
            cadence: descriptor.cadence,
            lightFamilyIdentifier: descriptor.lightFamilyIdentifier,
            tintFamilyIdentifier: descriptor.tintFamilyIdentifier,
            glyphIdentifier: descriptor.glyphIdentifier,
            layoutIdentifier: descriptor.layout.identifier,
            plateWidth: descriptor.layout.plateSize.x,
            plateHeight: descriptor.layout.plateSize.y,
            plaqueTreatmentIdentifier: descriptor.plaqueTreatmentIdentifier,
            plaqueTreatmentAccentIdentifier: descriptor.plaqueTreatmentAccentIdentifier,
            plaqueTreatmentRouteIdentifier: descriptor.plaqueTreatmentRouteIdentifier,
            plaqueTreatmentRenderRecipeIdentifier: descriptor.plaqueTreatmentRenderRecipeIdentifier,
            plaqueTreatmentRenderPrimitiveIdentifiers: descriptor.plaqueTreatmentRenderPrimitiveIdentifiers,
            plaqueTreatmentRenderPrimitiveCount: descriptor.plaqueTreatmentRenderPrimitiveCount,
            hasPinnedComparisonCue: descriptor.hasPinnedComparisonCue,
            pinnedComparisonCueIdentifier: cue?.identifier,
            pinnedComparisonCueComparisonIdentifier: cue?.comparisonIdentifier,
            pinnedComparisonCueComparisonExportIdentifier: cue?.comparisonExportIdentifier,
            pinnedComparisonCueModeIdentifier: descriptor.pinnedComparisonCueModeIdentifier,
            pinnedComparisonCueStateIdentifier: descriptor.pinnedComparisonCueStateIdentifier,
            pinnedComparisonCueNoMatchStateIdentifier: descriptor.pinnedComparisonCueNoMatchStateIdentifier,
            pinnedComparisonCueTargetDirectionIdentifier: cue?.targetDirectionIdentifier ?? "none",
            pinnedComparisonCueSelectedEntryIdentifier: cue?.selectedEntryIdentifier,
            pinnedComparisonCueTargetEntryIdentifier: cue?.targetEntryIdentifier,
            pinnedComparisonCueSelectedSessionNumber: cue?.selectedSessionNumber,
            pinnedComparisonCueTargetSessionNumber: cue?.targetSessionNumber,
            pinnedComparisonCueDeltaLabel: cue?.deltaLabel ?? "",
            pinnedComparisonCuePinnedEntryCount: cue?.pinnedEntryCount ?? 0,
            pinnedComparisonCueRetainedPinnedEntryCount: cue?.retainedPinnedEntryCount ?? 0,
            pinnedComparisonCueMissingPinnedEntryCount: cue?.missingPinnedEntryCount ?? 0,
            pinnedComparisonCueFilteredPinnedEntryCount: cue?.filteredPinnedEntryCount ?? 0,
            pinnedComparisonCuePromotedHoldStateIdentifier: cue?.promotedHoldStateIdentifier ?? "none",
            pinnedComparisonCuePromotedHoldEntryIdentifier: cue?.promotedHoldEntryIdentifier,
            pinnedComparisonCueWarningStateIdentifier: cue?.warningStateIdentifier ?? "none",
            pinnedComparisonCueGlyphIdentifier: cue?.glyphIdentifier ?? "none",
            pinnedComparisonCueRailTreatmentIdentifier: cue?.railTreatmentIdentifier ?? "none",
            pinnedComparisonCueLabel: cue?.label ?? "",
            pinnedComparisonCueDetail: cue?.detail ?? "",
            pinnedComparisonCueLabelLength: cue?.labelLength ?? 0,
            pinnedComparisonCueDetailLength: cue?.detailLength ?? 0,
            pinnedComparisonCueDeltaLabelLength: cue?.deltaLabelLength ?? 0,
            titleLength: descriptor.titleLength,
            detailLength: descriptor.detailLength,
            statusLength: descriptor.statusLength
        )
    }

    private static func cameraSnapshot(
        for shot: CinematicCameraShot,
        settings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport.CameraSnapshot {
        let position = CinematicTuning.cameraPosition(for: shot, settings: settings)
        let fieldOfView = CinematicTuning.cameraFieldOfView(for: shot, settings: settings)
        let transitionDuration = CinematicTuning.cameraTransitionDuration(for: shot, settings: settings)
        let identifier = [
            shot.identifier,
            settingsIdentifier(settings),
            positionIdentifier(position),
            fixed(Double(fieldOfView)),
            fixed(transitionDuration)
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.CameraSnapshot(
            identifier: identifier,
            shotIdentifier: shot.identifier,
            position: position,
            fieldOfView: fieldOfView,
            transitionDuration: transitionDuration
        )
    }

    private static func representativeLanguageProfile(
        for language: RepositoryLanguage
    ) -> RepositoryLanguageProfile {
        var counts = RepositoryLanguageCounts()
        counts[language] = language == .unknown ? 0 : 4
        return RepositoryLanguageProfile(
            counts: counts,
            manifestHints: manifestHints(for: language),
            primaryLanguage: language,
            scannedFileCount: language == .unknown ? 0 : 4,
            scannedDirectoryCount: language == .unknown ? 0 : 1,
            wasTruncated: false
        )
    }

    private static func manifestHints(for language: RepositoryLanguage) -> [RepositoryManifestHint] {
        switch language {
        case .typeScriptJavaScript:
            return [.packageJSON]
        case .python:
            return [.pyprojectToml]
        case .go:
            return [.goMod]
        case .rust:
            return [.cargoToml]
        case .swift:
            return [.packageSwift]
        case .markdown, .other, .unknown:
            return []
        }
    }

    private static func activityProfile(
        worktreeChanges: RepositoryWorktreeChangeCounts = RepositoryWorktreeChangeCounts(),
        recentSessionCount: Int = 1,
        recentSucceededCount: Int = 0,
        recentFailedCount: Int = 0,
        recentCommitCount: Int = 0,
        lastTerminalStatus: SessionStatus? = nil,
        successStreak: Int = 0,
        failureStreak: Int = 0,
        recoveredFromFailure: Bool = false
    ) -> RepositoryActivityProfile {
        RepositoryActivityProfile(
            isAvailable: true,
            worktreeChanges: worktreeChanges,
            recentSessionCount: recentSessionCount,
            recentSucceededCount: recentSucceededCount,
            recentFailedCount: recentFailedCount,
            recentCommitCount: recentCommitCount,
            lastTerminalStatus: lastTerminalStatus,
            lastSuccessfulSession: successStreak > 0 ? 1 : nil,
            lastFailedSession: failureStreak > 0 || recoveredFromFailure ? 0 : nil,
            successStreak: successStreak,
            failureStreak: failureStreak,
            recoveredFromFailure: recoveredFromFailure
        )
    }

    private static func worktreeChanges(
        added: Int = 0,
        modified: Int = 0,
        deleted: Int = 0,
        renamed: Int = 0,
        untracked: Int = 0,
        conflicted: Int = 0,
        other: Int = 0
    ) -> RepositoryWorktreeChangeCounts {
        var changes = RepositoryWorktreeChangeCounts()
        changes.added = added
        changes.modified = modified
        changes.deleted = deleted
        changes.renamed = renamed
        changes.untracked = untracked
        changes.conflicted = conflicted
        changes.other = other
        return changes
    }

    private static func loopPhase(from phase: String) -> LoopPhase {
        if let loopPhase = LoopPhase(rawValue: phase) {
            return loopPhase
        }

        let lowercased = phase.lowercased()
        if lowercased.contains("develop") {
            return .developing
        }
        if lowercased.contains("verify") || lowercased.contains("commit") {
            return .verifying
        }
        if lowercased.contains("recover") || lowercased.contains("repair") || lowercased.contains("fail") {
            return .failed
        }
        if lowercased.contains("plan") {
            return .planning
        }
        if lowercased.contains("pause") {
            return .paused
        }
        if lowercased.contains("cancel") {
            return .cancelled
        }
        return .idle
    }

    private static func settingsIdentifier(_ settings: CinematicInfluenceSettings) -> String {
        "\(settings.cameraStyle.rawValue)|\(fixed(settings.intensity))|\(settings.comfortMode.rawValue)"
    }

    private static func positionIdentifier(_ position: SIMD3<Float>) -> String {
        [
            fixed(Double(position.x)),
            fixed(Double(position.y)),
            fixed(Double(position.z))
        ].joined(separator: ",")
    }

    private static func recapArtifactAppLevelShortcutIdentifiers() -> [String] {
        typealias Shortcut = CinematicRunRecapShareArtifactCommandPlan.Shortcut
        return [
            Shortcut(key: .o, modifiers: [.command]),
            Shortcut(key: .r, modifiers: [.command]),
            Shortcut(key: .returnKey, modifiers: [.command])
        ].map(\.identifier)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func fixed(_ value: Float) -> String {
        fixed(Double(value))
    }

    private static func fixed(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

private extension SpellSchool {
    var diagnosticsIdentifier: String {
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

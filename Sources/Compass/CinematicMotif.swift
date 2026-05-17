import AppKit
import Foundation

enum CinematicLanguageSigilStyle: String, CaseIterable, Equatable {
    case swiftComet = "swift-comet"
    case scriptCircuit = "script-circuit"
    case pythonCoil = "python-coil"
    case goCurrent = "go-current"
    case rustGear = "rust-gear"
    case markdownRune = "markdown-rune"
    case polyglotPrism = "polyglot-prism"
    case unknownGate = "unknown-gate"
}

enum CinematicActivityEventKind: String, CaseIterable, Equatable {
    case unavailable
    case clean
    case dirty
    case conflicted
    case commit
    case success
    case recovery
    case failure
}

enum CinematicActivitySigilStyle: String, CaseIterable, Equatable {
    case dimGate = "dim-gate"
    case calmHalo = "calm-halo"
    case pressureShard = "pressure-shard"
    case fractureCross = "fracture-cross"
    case historyBranch = "history-branch"
    case sealBurst = "seal-burst"
    case recoveryArc = "recovery-arc"
    case backlashSpike = "backlash-spike"
}

struct CinematicLanguageMotif: Equatable {
    var language: RepositoryLanguage
    var accent: NSColor
    var secondaryAccent: NSColor
    var ambientSpell: SpellSchool
    var phaseBlend: CGFloat
    var sigilIdentifier: String
    var style: CinematicLanguageSigilStyle

    var styleIdentifier: String {
        style.rawValue
    }

    func phaseColor(_ base: NSColor) -> NSColor {
        base.mixing(with: accent, fraction: phaseBlend)
    }
}

struct CinematicActivityMotif: Equatable {
    var eventKind: CinematicActivityEventKind
    var tintSource: SpellSchool?
    var transitionSpell: SpellSchool?
    var ambientOverride: SpellSchool?
    var usesCommitAmbient: Bool
    var usesSuccessAmbient: Bool
    var shouldShakeOnTransition: Bool
    var sigilIdentifier: String
    var style: CinematicActivitySigilStyle

    var styleIdentifier: String {
        style.rawValue
    }

    func ambientSpell(languageAmbient: SpellSchool, spawnIndex: Int) -> SpellSchool {
        if let ambientOverride {
            return ambientOverride
        }
        if usesCommitAmbient && spawnIndex % 3 == 0 {
            return .git
        }
        if usesSuccessAmbient && spawnIndex % 2 == 0 {
            return .verify
        }
        return languageAmbient
    }
}

enum CinematicMotif {
    static let phaseBlendRange: ClosedRange<CGFloat> = 0...0.5
    static let activityTintBlend: CGFloat = 0.24

    static func language(for profile: RepositoryLanguageProfile) -> CinematicLanguageMotif {
        language(for: profile.primaryLanguage)
    }

    static func language(for language: RepositoryLanguage) -> CinematicLanguageMotif {
        let motif: CinematicLanguageMotif
        switch language {
        case .swift:
            motif = CinematicLanguageMotif(
                language: language,
                accent: NSColor(calibratedRed: 1.0, green: 0.43, blue: 0.15, alpha: 1),
                secondaryAccent: NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.34, alpha: 1),
                ambientSpell: .edit,
                phaseBlend: 0.38,
                sigilIdentifier: "language.swift",
                style: .swiftComet
            )
        case .typeScriptJavaScript:
            motif = CinematicLanguageMotif(
                language: language,
                accent: NSColor(calibratedRed: 0.22, green: 0.66, blue: 1.0, alpha: 1),
                secondaryAccent: NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.24, alpha: 1),
                ambientSpell: .shell,
                phaseBlend: 0.3,
                sigilIdentifier: "language.typescript-javascript",
                style: .scriptCircuit
            )
        case .python:
            motif = CinematicLanguageMotif(
                language: language,
                accent: NSColor(calibratedRed: 0.24, green: 0.48, blue: 0.95, alpha: 1),
                secondaryAccent: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.24, alpha: 1),
                ambientSpell: .insight,
                phaseBlend: 0.32,
                sigilIdentifier: "language.python",
                style: .pythonCoil
            )
        case .go:
            motif = CinematicLanguageMotif(
                language: language,
                accent: NSColor(calibratedRed: 0.0, green: 0.74, blue: 0.82, alpha: 1),
                secondaryAccent: NSColor(calibratedRed: 0.42, green: 1.0, blue: 0.82, alpha: 1),
                ambientSpell: .scan,
                phaseBlend: 0.32,
                sigilIdentifier: "language.go",
                style: .goCurrent
            )
        case .rust:
            motif = CinematicLanguageMotif(
                language: language,
                accent: NSColor(calibratedRed: 0.92, green: 0.38, blue: 0.14, alpha: 1),
                secondaryAccent: NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.28, alpha: 1),
                ambientSpell: .git,
                phaseBlend: 0.34,
                sigilIdentifier: "language.rust",
                style: .rustGear
            )
        case .markdown:
            motif = CinematicLanguageMotif(
                language: language,
                accent: NSColor(calibratedRed: 0.48, green: 0.62, blue: 1.0, alpha: 1),
                secondaryAccent: NSColor(calibratedRed: 0.82, green: 0.9, blue: 1.0, alpha: 1),
                ambientSpell: .insight,
                phaseBlend: 0.26,
                sigilIdentifier: "language.markdown",
                style: .markdownRune
            )
        case .other:
            motif = CinematicLanguageMotif(
                language: language,
                accent: NSColor(calibratedRed: 0.56, green: 0.5, blue: 0.72, alpha: 1),
                secondaryAccent: NSColor(calibratedRed: 0.72, green: 0.68, blue: 0.9, alpha: 1),
                ambientSpell: .pressure,
                phaseBlend: 0.18,
                sigilIdentifier: "language.other",
                style: .polyglotPrism
            )
        case .unknown:
            motif = CinematicLanguageMotif(
                language: language,
                accent: NSColor(calibratedRed: 0.32, green: 0.84, blue: 1.0, alpha: 1),
                secondaryAccent: NSColor(calibratedRed: 0.28, green: 0.58, blue: 1.0, alpha: 1),
                ambientSpell: .pressure,
                phaseBlend: 0.12,
                sigilIdentifier: "language.unknown",
                style: .unknownGate
            )
        }

        assert(phaseBlendRange.contains(motif.phaseBlend))
        return motif
    }

    static func activity(for profile: RepositoryActivityProfile) -> CinematicActivityMotif {
        guard !profile.isEmpty else {
            return CinematicActivityMotif(
                eventKind: .unavailable,
                tintSource: nil,
                transitionSpell: nil,
                ambientOverride: nil,
                usesCommitAmbient: false,
                usesSuccessAmbient: false,
                shouldShakeOnTransition: false,
                sigilIdentifier: "activity.unavailable",
                style: .dimGate
            )
        }

        let eventKind: CinematicActivityEventKind
        let style: CinematicActivitySigilStyle
        if profile.worktreeChanges.conflicted > 0 {
            eventKind = .conflicted
            style = .fractureCross
        } else if profile.failureStreak > 0 {
            eventKind = .failure
            style = .backlashSpike
        } else if profile.worktreeChanges.isDirty {
            eventKind = .dirty
            style = .pressureShard
        } else if profile.recoveredFromFailure {
            eventKind = .recovery
            style = .recoveryArc
        } else if profile.successStreak > 1 {
            eventKind = .success
            style = .sealBurst
        } else if profile.recentCommitCount > 0 {
            eventKind = .commit
            style = .historyBranch
        } else {
            eventKind = .clean
            style = .calmHalo
        }

        let tintSource: SpellSchool?
        if profile.worktreeChanges.conflicted > 0 || profile.failureStreak > 0 {
            tintSource = .failure
        } else if profile.worktreeChanges.isDirty {
            tintSource = .pressure
        } else if profile.successStreak > 1 {
            tintSource = .verify
        } else if profile.recentCommitCount > 0 {
            tintSource = .git
        } else {
            tintSource = nil
        }

        let transitionSpell: SpellSchool?
        switch eventKind {
        case .conflicted, .failure:
            transitionSpell = .failure
        case .dirty:
            transitionSpell = .pressure
        case .commit:
            transitionSpell = .git
        case .success, .recovery:
            transitionSpell = .verify
        case .unavailable, .clean:
            transitionSpell = nil
        }

        let ambientOverride: SpellSchool?
        if profile.worktreeChanges.conflicted > 0 || profile.failureStreak > 0 {
            ambientOverride = .failure
        } else if profile.pressureLevel == .heavy {
            ambientOverride = .pressure
        } else {
            ambientOverride = nil
        }

        return CinematicActivityMotif(
            eventKind: eventKind,
            tintSource: tintSource,
            transitionSpell: transitionSpell,
            ambientOverride: ambientOverride,
            usesCommitAmbient: profile.recentCommitCount > 0,
            usesSuccessAmbient: profile.successStreak > 1,
            shouldShakeOnTransition: eventKind == .conflicted || eventKind == .failure,
            sigilIdentifier: "activity.\(eventKind.rawValue)",
            style: style
        )
    }
}

private extension NSColor {
    func mixing(with other: NSColor, fraction: CGFloat) -> NSColor {
        let amount = max(0, min(1, fraction))
        let lhs = usingColorSpace(.deviceRGB) ?? self
        let rhs = other.usingColorSpace(.deviceRGB) ?? other
        return NSColor(
            calibratedRed: lhs.redComponent + (rhs.redComponent - lhs.redComponent) * amount,
            green: lhs.greenComponent + (rhs.greenComponent - lhs.greenComponent) * amount,
            blue: lhs.blueComponent + (rhs.blueComponent - lhs.blueComponent) * amount,
            alpha: lhs.alphaComponent + (rhs.alphaComponent - lhs.alphaComponent) * amount
        )
    }
}

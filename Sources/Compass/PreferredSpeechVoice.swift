import AVFoundation
import CompassCore
import Foundation

/// Picks an on-device English voice and configures utterances for narration.
/// Ranking is quality then preferred name stems — locale is ignored.
enum PreferredSpeechVoice {
  /// Soft preference when no phase-specific stem is requested / available.
  private static let fallbackNameStems: [String] = [
    "lee", "zoe", "ava", "nora", "nicky", "samantha", "susan", "allison",
    "matilda", "karen", "moira", "aaron", "evan", "tom", "daniel", "oliver",
  ]

  private static let noveltyIdentifierMarkers: [String] = [
    "BadNews", "Bahh", "Bells", "Boing", "Bubbles", "Cellos", "Deranged",
    "GoodNews", "Hysterical", "Junior", "Organ", "Princess", "Trinoids",
    "Whisper", "Zarvox", "Albert", "Fred", "Ralph", "Kathy",
    "eloquence",
  ]

  /// Distinct voices per agent so spoken thinking is recognizable by ear.
  static func preferredNameStem(for phase: AgentPhase) -> String {
    switch phase {
    case .plan: return "lee"
    case .develop: return "zoe"
    case .critic: return "matilda"
    case .requirementsAudit: return "nora"
    }
  }

  static func bestEnglishVoice(
    among voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices(),
    preferredNameStem: String? = nil
  ) -> AVSpeechSynthesisVoice? {
    let english = voices.filter { $0.language.lowercased().hasPrefix("en") }
    let candidates = english.filter { !isNovelty($0) }
    let pool = candidates.isEmpty ? english : candidates
    guard !pool.isEmpty else { return nil }

    if let stem = preferredNameStem?.lowercased(), !stem.isEmpty {
      let matching = pool.filter { $0.name.lowercased().hasPrefix(stem) }
      if let named = pickBest(from: matching, nameStems: [stem]) {
        return named
      }
    }

    return pickBest(from: pool, nameStems: fallbackNameStems)
  }

  static func bestEnglishVoice(
    among voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices(),
    phase: AgentPhase?
  ) -> AVSpeechSynthesisVoice? {
    bestEnglishVoice(
      among: voices,
      preferredNameStem: phase.map(preferredNameStem(for:))
    )
  }

  static func configure(_ utterance: AVSpeechUtterance, phase: AgentPhase? = nil) {
    utterance.voice = bestEnglishVoice(phase: phase)
    // Slightly under default so prose has room to breathe.
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
    utterance.volume = 0.85
    utterance.preUtteranceDelay = 0.12
  }

  private static func pickBest(
    from pool: [AVSpeechSynthesisVoice],
    nameStems: [String]
  ) -> AVSpeechSynthesisVoice? {
    guard !pool.isEmpty else { return nil }
    return pool.sorted { lhs, rhs in
      if lhs.quality.rawValue != rhs.quality.rawValue {
        return lhs.quality.rawValue > rhs.quality.rawValue
      }
      let lhsName = namePreferenceScore(lhs.name, stems: nameStems)
      let rhsName = namePreferenceScore(rhs.name, stems: nameStems)
      if lhsName != rhsName {
        return lhsName > rhsName
      }
      return lhs.identifier < rhs.identifier
    }.first
  }

  private static func isNovelty(_ voice: AVSpeechSynthesisVoice) -> Bool {
    let id = voice.identifier
    return noveltyIdentifierMarkers.contains { id.contains($0) }
  }

  private static func namePreferenceScore(_ name: String, stems: [String]) -> Int {
    let normalized = name.lowercased()
    if let index = stems.firstIndex(where: { normalized.hasPrefix($0) }) {
      return stems.count - index
    }
    return 0
  }
}

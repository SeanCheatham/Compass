import AVFoundation
import Foundation

/// Picks the most natural on-device English voice available and configures
/// utterances for thought-style narration (slightly slower, small lead-in).
enum PreferredSpeechVoice {
  /// Soft preference among high-quality English voices when quality ties.
  private static let preferredNameStems: [String] = [
    "lee", "zoe", "ava", "nora", "nicky", "samantha", "susan", "allison",
    "matilda", "karen", "moira", "aaron", "evan", "tom", "daniel", "oliver",
  ]

  private static let noveltyIdentifierMarkers: [String] = [
    "BadNews", "Bahh", "Bells", "Boing", "Bubbles", "Cellos", "Deranged",
    "GoodNews", "Hysterical", "Junior", "Organ", "Princess", "Trinoids",
    "Whisper", "Zarvox", "Albert", "Fred", "Ralph", "Kathy",
    "eloquence",
  ]

  static func bestEnglishVoice(
    among voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices(),
    preferredLanguage: String = currentPreferredEnglishLanguage()
  ) -> AVSpeechSynthesisVoice? {
    let english = voices.filter { normalizedLanguage($0.language).hasPrefix("en") }
    let candidates = english.filter { !isNovelty($0) }
    let pool = candidates.isEmpty ? english : candidates
    guard !pool.isEmpty else { return nil }

    let preferred = normalizedLanguage(preferredLanguage)

    return pool.sorted { lhs, rhs in
      if lhs.quality.rawValue != rhs.quality.rawValue {
        return lhs.quality.rawValue > rhs.quality.rawValue
      }
      // Explicit name stems beat locale so a preferred Premium voice (e.g. Lee
      // en-AU) is not displaced by a same-quality voice that matches the Mac
      // locale (e.g. Zoe en-US).
      let lhsName = namePreferenceScore(lhs.name)
      let rhsName = namePreferenceScore(rhs.name)
      if lhsName != rhsName {
        return lhsName > rhsName
      }
      let lhsLocale = localePreferenceScore(lhs.language, preferred: preferred)
      let rhsLocale = localePreferenceScore(rhs.language, preferred: preferred)
      if lhsLocale != rhsLocale {
        return lhsLocale > rhsLocale
      }
      return lhs.identifier < rhs.identifier
    }.first
  }

  static func configure(_ utterance: AVSpeechUtterance) {
    utterance.voice = bestEnglishVoice()
    // Slightly under default so prose has room to breathe.
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
    utterance.volume = 0.85
    utterance.preUtteranceDelay = 0.12
  }

  static func currentPreferredEnglishLanguage() -> String {
    let code = Locale.current.language.languageCode?.identifier ?? "en"
    guard code.lowercased() == "en" else { return "en-US" }
    if let region = Locale.current.region?.identifier, !region.isEmpty {
      return "en-\(region)"
    }
    return "en-US"
  }

  private static func isNovelty(_ voice: AVSpeechSynthesisVoice) -> Bool {
    let id = voice.identifier
    return noveltyIdentifierMarkers.contains { id.contains($0) }
  }

  private static func normalizedLanguage(_ language: String) -> String {
    language.lowercased().replacingOccurrences(of: "_", with: "-")
  }

  private static func localePreferenceScore(_ language: String, preferred: String) -> Int {
    let lang = normalizedLanguage(language)
    let pref = normalizedLanguage(preferred)
    if lang == pref {
      return 4
    }
    let prefRegion = pref.split(separator: "-").dropFirst().first.map(String.init)
    let voiceRegion = lang.split(separator: "-").dropFirst().first.map(String.init)
    if let prefRegion, voiceRegion == prefRegion {
      return 3
    }
    if lang.hasPrefix("en-us") {
      return 2
    }
    if lang.hasPrefix("en") {
      return 1
    }
    return 0
  }

  private static func namePreferenceScore(_ name: String) -> Int {
    let normalized = name.lowercased()
    if let index = preferredNameStems.firstIndex(where: { normalized.hasPrefix($0) }) {
      return preferredNameStems.count - index
    }
    return 0
  }
}

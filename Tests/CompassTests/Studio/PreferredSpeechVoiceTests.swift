import AVFoundation
import Foundation
import Testing

@testable import Compass

@Suite("PreferredSpeechVoice")
struct PreferredSpeechVoiceTests {
  @Test
  func prefersPremiumOverEnhancedAndCompact() {
    // Use real installed voices when available; otherwise skip soft assertion.
    let voices = AVSpeechSynthesisVoice.speechVoices()
    guard let best = PreferredSpeechVoice.bestEnglishVoice(among: voices) else {
      return
    }
    let english = voices.filter { $0.language.lowercased().hasPrefix("en") }
    let maxQuality = english.map(\.quality.rawValue).max() ?? 0
    #expect(best.quality.rawValue == maxQuality)
    #expect(best.language.lowercased().hasPrefix("en"))
  }

  @Test
  func prefersMatchingLocaleWhenQualityTies() {
    let voices = AVSpeechSynthesisVoice.speechVoices().filter {
      $0.language.lowercased().hasPrefix("en") && $0.quality == .default
    }
    guard voices.count >= 2 else { return }
    let preferred = "en-GB"
    guard let best = PreferredSpeechVoice.bestEnglishVoice(
      among: voices,
      preferredLanguage: preferred
    ) else {
      return
    }
    let hasMatching = voices.contains { $0.language.lowercased().hasPrefix("en-gb") }
    if hasMatching {
      #expect(best.language.lowercased().hasPrefix("en-gb"))
    }
  }

  @Test
  func configureSetsVoiceRateAndVolume() {
    let utterance = AVSpeechUtterance(string: "Hmm, maybe I should check the parser next.")
    PreferredSpeechVoice.configure(utterance)
    #expect(utterance.rate == AVSpeechUtteranceDefaultSpeechRate * 0.9)
    #expect(utterance.volume == 0.85)
    #expect(utterance.preUtteranceDelay == 0.12)
    if PreferredSpeechVoice.bestEnglishVoice() != nil {
      #expect(utterance.voice != nil)
    }
  }
}

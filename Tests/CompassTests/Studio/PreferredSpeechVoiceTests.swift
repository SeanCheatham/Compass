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
  func prefersNamedStemOverMatchingLocaleWhenQualityTies() {
    let voices = AVSpeechSynthesisVoice.speechVoices()
    let lee = voices.first {
      $0.name.lowercased().hasPrefix("lee") && $0.quality == .premium
    }
    let zoe = voices.first {
      $0.name.lowercased().hasPrefix("zoe") && $0.quality == .premium
    }
    guard let lee, let zoe else { return }

    let best = PreferredSpeechVoice.bestEnglishVoice(
      among: [lee, zoe],
      preferredLanguage: "en-US"
    )
    #expect(best?.identifier == lee.identifier)
  }

  @Test
  func prefersMatchingLocaleWhenNameScoresTie() {
    // Compact novelty-free voices with no preferred-stem names: locale should decide.
    let voices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
      guard voice.language.lowercased().hasPrefix("en") else { return false }
      guard voice.quality == .default else { return false }
      let name = voice.name.lowercased()
      let stems = ["lee", "zoe", "ava", "nora", "nicky", "samantha", "susan", "allison",
                   "matilda", "karen", "moira", "aaron", "evan", "tom", "daniel", "oliver"]
      return !stems.contains { name.hasPrefix($0) }
    }
    let enGB = voices.filter { $0.language.lowercased().hasPrefix("en-gb") }
    let enUS = voices.filter { $0.language.lowercased().hasPrefix("en-us") }
    guard let gb = enGB.first, let us = enUS.first else { return }

    let best = PreferredSpeechVoice.bestEnglishVoice(
      among: [gb, us],
      preferredLanguage: "en-GB"
    )
    #expect(best?.language.lowercased().hasPrefix("en-gb") == true)
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

import AVFoundation
import CompassCore
import Foundation
import Testing

@testable import Compass

@Suite("PreferredSpeechVoice")
struct PreferredSpeechVoiceTests {
  @Test
  func prefersPremiumOverEnhancedAndCompact() {
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
  func prefersLeeStemOverZoeWhenBothPremium() {
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
      preferredNameStem: "lee"
    )
    #expect(best?.identifier == lee.identifier)
  }

  @Test
  func phaseMapsToDistinctPreferredStems() {
    #expect(PreferredSpeechVoice.preferredNameStem(for: .plan) == "lee")
    #expect(PreferredSpeechVoice.preferredNameStem(for: .develop) == "zoe")
    #expect(PreferredSpeechVoice.preferredNameStem(for: .critic) == "matilda")
    #expect(PreferredSpeechVoice.preferredNameStem(for: .health) == "aaron")
  }

  @Test
  func phaseSelectsMatchingInstalledPremiumVoice() {
    let voices = AVSpeechSynthesisVoice.speechVoices()
    let lee = voices.first {
      $0.name.lowercased().hasPrefix("lee") && $0.quality == .premium
    }
    let zoe = voices.first {
      $0.name.lowercased().hasPrefix("zoe") && $0.quality == .premium
    }
    let matilda = voices.first {
      $0.name.lowercased().hasPrefix("matilda") && $0.quality == .premium
    }
    guard let lee, let zoe, let matilda else { return }

    let pool = [lee, zoe, matilda]
    #expect(
      PreferredSpeechVoice.bestEnglishVoice(among: pool, phase: .plan)?.identifier
        == lee.identifier
    )
    #expect(
      PreferredSpeechVoice.bestEnglishVoice(among: pool, phase: .develop)?.identifier
        == zoe.identifier
    )
    #expect(
      PreferredSpeechVoice.bestEnglishVoice(among: pool, phase: .critic)?.identifier
        == matilda.identifier
    )
  }

  @Test
  func missingPreferredStemFallsBackWithoutUsingLocale() {
    let voices = AVSpeechSynthesisVoice.speechVoices()
    let zoe = voices.first {
      $0.name.lowercased().hasPrefix("zoe") && $0.quality == .premium
    }
    let matilda = voices.first {
      $0.name.lowercased().hasPrefix("matilda") && $0.quality == .premium
    }
    guard let zoe, let matilda else { return }

    // Plan prefers Lee, which is absent — fall back by quality then fallback stems.
    // Zoe precedes Matilda in the fallback stem list.
    let best = PreferredSpeechVoice.bestEnglishVoice(
      among: [zoe, matilda],
      phase: .plan
    )
    #expect(best?.identifier == zoe.identifier)
  }

  @Test
  func configureSetsVoiceRateAndVolume() {
    let utterance = AVSpeechUtterance(string: "Hmm, maybe I should check the parser next.")
    PreferredSpeechVoice.configure(utterance, phase: .plan)
    #expect(utterance.rate == AVSpeechUtteranceDefaultSpeechRate * 0.9)
    #expect(utterance.volume == 0.85)
    #expect(utterance.preUtteranceDelay == 0.12)
    if PreferredSpeechVoice.bestEnglishVoice(phase: .plan) != nil {
      #expect(utterance.voice != nil)
    }
  }
}

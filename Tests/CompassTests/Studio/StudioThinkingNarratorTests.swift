import Foundation
import Testing

@testable import CompassCore

@Suite("StudioThinkingNarrator")
struct StudioThinkingNarratorTests {
  private static func provider(
    available: Bool,
    response: String?
  ) -> FoundationModelsAvailability.TextProvider {
    FoundationModelsAvailability.TextProvider(
      isAvailable: { available },
      streamText: { _ in response }
    )
  }

  @Test
  func narrateReturnsSanitizedModelText() async {
    let narration = await FoundationModelsAvailability.withTextProvider(
      Self.provider(available: true, response: "\"I'm checking the parser before editing.\"")
    ) {
      await StudioThinkingNarrator.narrate(
        thinking: "Let me look at src/parser.rs:42 to see how tokens are split.")
    }
    #expect(narration == "I'm checking the parser before editing.")
  }

  @Test
  func narrateRejectsCodeishOutput() async {
    let narration = await FoundationModelsAvailability.withTextProvider(
      Self.provider(available: true, response: "Editing `foo() { return 1 }` now")
    ) {
      await StudioThinkingNarrator.narrate(thinking: "fix the parser")
    }
    #expect(narration == nil)
  }

  @Test
  func narrateReturnsNilWhenUnavailable() async {
    let narration = await FoundationModelsAvailability.withTextProvider(
      Self.provider(available: false, response: "ignored")
    ) {
      await StudioThinkingNarrator.narrate(thinking: "some thought")
    }
    #expect(narration == nil)
  }

  @Test
  func narrateReturnsNilForEmptyInput() async {
    let narration = await FoundationModelsAvailability.withTextProvider(
      Self.provider(available: true, response: "unused")
    ) {
      await StudioThinkingNarrator.narrate(thinking: "   \n  ")
    }
    #expect(narration == nil)
  }

  @Test
  func fallbackCollapsesToSingleBoundedLine() {
    let long = String(repeating: "word ", count: 100)
    let fallback = StudioThinkingNarrator.fallbackSpokenText(
      for: "First line.\nSecond line.\n\(long)")
    #expect(!fallback.contains("\n"))
    #expect(fallback.count <= StudioThinkingNarrator.maxSpokenCharacters)
    #expect(fallback.hasPrefix("First line. Second line."))
  }

  @Test
  func fallbackRejectsURLsAndCode() {
    #expect(StudioThinkingNarrator.fallbackSpokenText(for: "see https://example.com/x") == "")
    #expect(StudioThinkingNarrator.fallbackSpokenText(for: "run `x` { y }") == "")
  }

  @Test
  func promptIncludesThoughtAndConstraints() {
    let prompt = StudioThinkingNarrator.prompt(for: "thinking about tests")
    #expect(prompt.contains("thinking about tests"))
    #expect(prompt.contains("inner voice"))
    #expect(prompt.contains("Under 50 words"))
    #expect(prompt.contains("first-person"))
  }
}

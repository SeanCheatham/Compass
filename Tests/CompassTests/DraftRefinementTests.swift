import Foundation
import Testing

@testable import Compass

struct DraftRefinementTests {
  @Test func testDraftReadinessGuideStartsEmptyDraftWithOutcomeCue() throws {
    let guide = DraftReadinessGuide(draft: "   ")

    try #require(guide.status == .empty)
    try #require(guide.title == "Start with the outcome")
    try #require(guide.scoreLabel == "0 of 3")
    try #require(guide.cues.map(\.title) == ["Outcome", "Why", "Success signal"])
    try #require(guide.cues.allSatisfy { !$0.isSatisfied })
  }

  @Test func testDraftReadinessGuideNamesMissingSignalsForPartialDraft() throws {
    let guide = DraftReadinessGuide(draft: "make setup faster")

    try #require(guide.status == .needsDetail)
    try #require(guide.scoreLabel == "1 of 3")
    try #require(guide.detail == "Missing: Why, Success signal.")
    try #require(guide.missingSignalText == "Why, Success signal")
    try #require(guide.satisfiedSignalText == "Outcome")
    try #require(guide.cues[0].isSatisfied)
    try #require(!guide.cues[1].isSatisfied)
    try #require(!guide.cues[2].isSatisfied)
    try #require(guide.coachingPrompts.map(\.question) == [
      "Who is stuck, and why?",
      "How will you know it worked?",
    ])
    try #require(
      guide.coachingPrompts[1].detail
        == "Name a visible result, error, test, or check Compass can verify.")
    try #require(guide.allowsNarration)
    try #require(guide.narrationIdentifier.contains("questions:Who is stuck, and why?"))
  }

  @Test func testDraftReadinessGuideMarksActionableDraftReady() throws {
    let guide = DraftReadinessGuide(
      draft:
        "Make setup faster because users get stuck; success looks like the setup check shows clear progress."
    )

    try #require(guide.status == .ready)
    try #require(guide.title == "Ready for Plan")
    try #require(guide.scoreLabel == "3 of 3")
    try #require(guide.cues.allSatisfy { $0.isSatisfied })
    try #require(guide.coachingPrompts.isEmpty)
    try #require(!guide.allowsNarration)
  }

  @Test func testDraftReadinessGuideRejectsVagueSuccessSignals() throws {
    let guide = DraftReadinessGuide(
      draft: "Make setup easier because users are stuck; it works."
    )

    try #require(guide.status == .needsDetail)
    try #require(guide.scoreLabel == "2 of 3")
    try #require(guide.detail == "Missing: Success signal.")
    try #require(guide.cues[0].isSatisfied)
    try #require(guide.cues[1].isSatisfied)
    try #require(!guide.cues[2].isSatisfied)
    try #require(
      guide.cues[2].detail == "Replace vague words like works or done with visible proof.")
  }

  @Test func testDraftReadinessGuideAcceptsSpecificDoneWhenSignals() throws {
    let guide = DraftReadinessGuide(
      draft: "Show recovery copy because users get locked out; done when the recovery banner appears."
    )

    try #require(guide.status == .ready)
    try #require(guide.scoreLabel == "3 of 3")
    try #require(guide.cues[2].isSatisfied)
  }

  @Test func testDraftIntakeGuideSummarizesQueuedDraftSignals() throws {
    let guide = DraftIntakeGuide(
      drafts: """
        - Make setup faster because users get stuck; success looks like the setup check shows clear progress.

        - Improve onboarding copy
        """
    )

    try #require(guide.entries.count == 2)
    try #require(guide.entries[0].readiness.status == .ready)
    try #require(guide.entries[1].readiness.status == .needsDetail)
    try #require(guide.status == .needsDetail)
    try #require(guide.title == "Draft queue needs detail")
    try #require(guide.scoreLabel == "1 of 2 ready")
    try #require(guide.missingSignalTitles == ["Why", "Success signal"])
    try #require(
      guide.detail == "2 queued drafts. 1 of 2 ready. Missing across queue: Why, Success signal.")
    try #require(guide.promptText.contains("Draft 1: Ready for Plan (3 of 3)"))
    try #require(guide.promptText.contains("Signals present: Outcome, Why, Success signal"))
    try #require(guide.promptText.contains("Draft 2: Add one more signal (1 of 3)"))
    try #require(guide.promptText.contains("Missing signals: Why, Success signal"))
  }

  @Test func testDraftIntakeGuideNamesCappedQueuesWithoutLosingTotals() throws {
    let guide = DraftIntakeGuide(
      drafts: """
        - Make setup faster because users get stuck; success looks like tests pass.
        - Show recovery copy because users get locked out; done when recovery copy appears.
        - Explain failed verifies because owners get confused; success shows the first error.
        - Add draft polish because planning starts rough; success shows clearer queue copy.
        - Improve sandbox setup because onboarding is hard; done when the readiness panel shows progress.
        - Surface provider failures because API keys expire; success shows a model connection repair.
        - Improve onboarding copy
        """
    )

    try #require(guide.entries.count == DraftIntakeGuide.maxEntries)
    try #require(guide.totalEntryCount == 7)
    try #require(guide.hiddenEntryCount == 1)
    try #require(guide.hiddenCountSentence == "1 more draft remains")
    try #require(guide.scoreLabel == "6 of 7 ready")
    try #require(guide.entryCountLabel == "7 queued drafts")
    try #require(guide.status == .needsDetail)
    try #require(guide.missingSignalTitles == ["Why", "Success signal"])
    try #require(guide.detail.contains("Showing first 6"))
    try #require(guide.detail.contains("1 more draft remains in the raw draft list"))
    try #require(guide.promptText.contains("Readiness map note: Showing first 6 of 7 drafts."))
    try #require(
      guide.promptText
        .contains("1 more draft remains in the raw drafts above; preserve them"))
    try #require(
      DraftIntakeGuideNarrator.prompt(for: guide)
        .contains("Queue scope: 7 total drafts; 1 outside the visible checklist."))
    try #require(guide.narrationIdentifier.contains("total:7"))
    try #require(guide.narrationIdentifier.contains("hidden:1"))
  }

  @Test func testDraftIntakeGuideFallsBackToParagraphEntries() throws {
    let guide = DraftIntakeGuide(
      drafts: """
        Make plan repair copy clearer because users get stuck.

        Show a visible success state when the repair packet is copied.
        """
    )

    try #require(guide.entries.map(\.number) == [1, 2])
    try #require(guide.entries[0].draft == "Make plan repair copy clearer because users get stuck.")
    try #require(
      guide.entries[1].draft == "Show a visible success state when the repair packet is copied.")
  }

  @Test func testDraftIntakeGuideAcceptsNumberedAndCheckboxEntries() throws {
    let guide = DraftIntakeGuide(
      drafts: """
        1. [ ] Make setup faster because users get stuck; success looks like tests pass.
        2) [x] Improve onboarding copy
        [ ] Show 2FA recovery because users get locked out; done when recovery copy appears.
        """
    )

    try #require(guide.entries.map(\.number) == [1, 2, 3])
    try #require(
      guide.entries[0].draft
        == "Make setup faster because users get stuck; success looks like tests pass.")
    try #require(guide.entries[0].readiness.status == .ready)
    try #require(guide.entries[1].draft == "Improve onboarding copy")
    try #require(guide.entries[1].readiness.status == .needsDetail)
    try #require(
      guide.entries[2].draft
        == "Show 2FA recovery because users get locked out; done when recovery copy appears.")
    try #require(guide.entries[2].readiness.status == .ready)
    try #require(guide.promptText.contains("Text: Improve onboarding copy"))
    try #require(!guide.promptText.contains("[x]"))
    try #require(!guide.promptText.contains("[ ]"))
  }

  @Test func testDraftIntakeGuideSummarizesReadyAndEmptyQueueStates() throws {
    let empty = DraftIntakeGuide(drafts: " \n ")

    try #require(empty.status == .empty)
    try #require(empty.title == "No queued drafts")
    try #require(empty.scoreLabel == "0 queued")
    try #require(empty.detail == "Add one clear direction above when you are ready.")
    try #require(!empty.allowsNarration)

    let ready = DraftIntakeGuide(
      drafts: """
        - Make setup faster because users get stuck; success looks like tests pass.
        - Show clearer progress because customers wait; done when the progress banner appears.
        """
    )

    try #require(ready.status == .ready)
    try #require(ready.title == "Draft queue ready")
    try #require(ready.scoreLabel == "2 of 2 ready")
    try #require(ready.allowsNarration)
    try #require(ready.missingSignalTitles.isEmpty)
    try #require(
      ready.detail
        == "Every queued draft names the outcome, why it matters, and how done should look.")
  }

  @Test func testDraftIntakeGuideNarrationIdentifierTracksQueueSignals() throws {
    let initial = DraftIntakeGuide(drafts: "- Improve onboarding copy")
    let refined = DraftIntakeGuide(
      drafts: "- Improve onboarding copy because users get stuck; success looks like tests pass.")

    try #require(initial.narrationIdentifier.contains("Draft queue needs detail"))
    try #require(initial.narrationIdentifier.contains("missing:Why, Success signal"))
    try #require(refined.narrationIdentifier.contains("Draft queue ready"))
    try #require(refined.narrationIdentifier.contains("present:Outcome, Why, Success signal"))
    try #require(initial.narrationIdentifier != refined.narrationIdentifier)
  }

  @Test func testDraftIntakeGuideNarratorUsesFoundationModelsAsOptionalQueuePolish()
    async throws
  {
    let guide = DraftIntakeGuide(
      drafts: """
        - Improve onboarding copy
        - Make setup faster because users get stuck; success looks like tests pass.
        """
    )

    try await withMockFoundationModels(response: "Add why and a success signal to the first draft.")
    {
      let generatedNarration = await DraftIntakeGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      try #require(narration.guideIdentifier == guide.narrationIdentifier)
      try #require(narration.text == "Add why and a success signal to the first draft.")
    }
  }

  @Test func testDraftIntakeGuideNarratorSkipsEmptyAndRejectsStructuredOutput() async {
    let empty = DraftIntakeGuide(drafts: "")
    await withMockFoundationModels(response: "Queue is empty.") {
      let narration = await DraftIntakeGuideNarrator.narrate(guide: empty)
      #expect(narration == nil)
    }

    let guide = DraftIntakeGuide(drafts: "- Improve onboarding copy")
    await withMockFoundationModels(response: #"{"text":"invented"}"#) {
      let narration = await DraftIntakeGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await DraftIntakeGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  @Test func testDraftReadinessGuideNarratorUsesFoundationModelsAsOptionalCoach() async throws {
    let guide = DraftReadinessGuide(draft: "Improve onboarding copy")

    try await withMockFoundationModels(
      response: "Who is confused by the onboarding copy, and what should look different?"
    ) {
      let generatedNarration = await DraftReadinessGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      try #require(narration.guideIdentifier == guide.narrationIdentifier)
      try #require(
        narration.text == "Who is confused by the onboarding copy, and what should look different?"
      )
    }
  }

  @Test func testDraftReadinessGuideNarratorSkipsReadyAndRejectsStructuredOutput() async {
    let ready = DraftReadinessGuide(
      draft: "Improve onboarding copy because users are confused; success shows clearer steps."
    )
    await withMockFoundationModels(response: "Should not be used.") {
      let narration = await DraftReadinessGuideNarrator.narrate(guide: ready)
      #expect(narration == nil)
    }

    let guide = DraftReadinessGuide(draft: "Improve onboarding copy")
    await withMockFoundationModels(response: #"{"text":"invented"}"#) {
      let narration = await DraftReadinessGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "- Ask a hidden question") {
      let narration = await DraftReadinessGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await DraftReadinessGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  @Test func testParserAcceptsGeneratedJSONRefinement() throws {
    let context = makeContext()
    let refinement = try #require(
      DraftRefinementService.parseGeneratedRefinement(
        #"{"refined":"Add parser tests for Package.swift."}"#,
        draft: "add parser tests for Package.swift",
        context: context
      )
    )

    try #require(refinement.originalDraft == "add parser tests for Package.swift")
    try #require(refinement.refinedText == "Add parser tests for Package.swift.")
    try #require(refinement.source == .generated)
  }

  @Test func testParserAcceptsGeneratedRefinedLine() throws {
    let context = makeContext()
    let refinement = try #require(
      DraftRefinementService.parseGeneratedRefinement(
        "Refined: Add parser tests for Package.swift.",
        draft: "add parser tests for Package.swift",
        context: context
      )
    )

    try #require(refinement.refinedText == "Add parser tests for Package.swift.")
  }

  @Test func testParserRejectsInventedFilesNumbersAndConstraints() throws {
    let context = makeContext()
    let draft = "add parser tests"

    try #require(
      DraftRefinementService.parseGeneratedRefinement(
        "Refined: Add parser tests in Sources/App.swift.",
        draft: draft,
        context: context
      ) == nil
    )
    try #require(
      DraftRefinementService.parseGeneratedRefinement(
        "Refined: Add 3 parser tests.",
        draft: draft,
        context: context
      ) == nil
    )
    try #require(
      DraftRefinementService.parseGeneratedRefinement(
        "Refined: Add parser tests that must pass.",
        draft: draft,
        context: context
      ) == nil
    )
  }

  @Test func testParserAcceptsRefinedLineAfterPreamble() throws {
    let context = makeContext()
    let refinement = try #require(
      DraftRefinementService.parseGeneratedRefinement(
        """
        Here is a clearer version:
        Refined: Add parser tests for Package.swift.
        """,
        draft: "add parser tests for Package.swift",
        context: context
      )
    )

    try #require(refinement.refinedText == "Add parser tests for Package.swift.")
    try #require(refinement.source == .generated)
  }

  @Test func testParserIgnoresTrailingCommentaryAfterRefinedLine() throws {
    let context = makeContext()
    let refinement = try #require(
      DraftRefinementService.parseGeneratedRefinement(
        """
        Refined: Add parser tests for Package.swift.
        Note: Also update docs.
        """,
        draft: "add parser tests for Package.swift",
        context: context
      )
    )

    try #require(refinement.refinedText == "Add parser tests for Package.swift.")
  }

  @Test func testParserRejectsInventedOutcomeAndExtraStructure() throws {
    let context = makeContext()
    let draft = "add parser tests"

    try #require(
      DraftRefinementService.parseGeneratedRefinement(
        "Refined: Completed parser tests.",
        draft: draft,
        context: context
      ) == nil
    )
    try #require(
      DraftRefinementService.parseGeneratedRefinement(
        #"{"refined":"Add parser tests.","note":"extra commentary"}"#,
        draft: draft,
        context: context
      ) == nil
    )
    try #require(
      DraftRefinementService.parseGeneratedRefinement(
        """
        Add parser tests for Package.swift.
        Also update docs.
        """,
        draft: draft,
        context: context
      ) == nil
    )
  }

  @Test func testDeterministicFallbackNormalizesWithoutInventingDetails() throws {
    let context = makeContext()
    let refinement = try #require(
      DraftRefinementService.deterministicRefinement(
        draft: "  - review Package.swift in 2 areas  ",
        context: context
      )
    )

    try #require(refinement.refinedText == "Review Package.swift in 2 areas.")
    try #require(refinement.source == .deterministic)
    try #require(refinement.refinedText.contains("Package.swift"))
    try #require(refinement.refinedText.contains("2"))
    try #require(!refinement.refinedText.contains("Sources/App.swift"))
    try #require(!refinement.refinedText.contains("must"))

    let taskRefinement = try #require(
      DraftRefinementService.deterministicRefinement(
        draft: "2) [ ] 2FA recovery copy stays visible",
        context: context
      )
    )
    try #require(taskRefinement.refinedText == "2FA recovery copy stays visible.")
  }

  @Test func testPreviewPlannerDebouncesAndUsesCacheKey() throws {
    let context = makeContext()
    let plan = DraftRefinementPreviewPlanner.plan(
      draft: "  add parser tests  ",
      context: context,
      cachedKeys: []
    )

    try #require(plan.visibility == .debounce)
    try #require(plan.delayNanoseconds == 600_000_000)

    let key = DraftRefinementPreviewKey(trimmedDraft: "add parser tests", context: context)
    try #require(plan.cacheKey == key)

    let cachedPlan = DraftRefinementPreviewPlanner.plan(
      draft: "add parser tests",
      context: context,
      cachedKeys: [key]
    )

    try #require(cachedPlan.visibility == .cached)
    try #require(cachedPlan.delayNanoseconds == 0)
    try #require(cachedPlan.cacheKey == key)
    try #require(cachedPlan.shouldShowPreviewSurface)
  }

  @Test func testPreviewPlannerHidesForEmptyDraftButUsesQuickPolishWhenModelUnavailable()
    throws
  {
    let context = makeContext()
    let emptyPlan = DraftRefinementPreviewPlanner.plan(
      draft: "   ",
      context: context,
      cachedKeys: []
    )
    let unavailablePlan = DraftRefinementPreviewPlanner.plan(
      draft: "add parser tests",
      context: context,
      cachedKeys: []
    )

    try #require(emptyPlan.visibility == .hiddenEmptyDraft)
    try #require(!emptyPlan.shouldShowPreviewSurface)
    try #require(unavailablePlan.visibility == .debounce)
    try #require(unavailablePlan.cacheKey != nil)
    try #require(unavailablePlan.shouldShowPreviewSurface)
  }

  @Test func testPreviewAvailabilityIncludesDeterministicQuickPolish() async throws {
    try await withMockFoundationModels(available: false) {
      try #require(DraftRefinementService.isPreviewAvailable)

      let refinement = try #require(
        await DraftRefinementService.makeRefinement(
          draft: "add parser tests",
          context: makeContext()
        )
      )

      try #require(refinement.source == .deterministic)
      try #require(refinement.refinedText == "Add parser tests.")
    }
  }

  private func makeContext() -> DraftRefinementContext {
    DraftRefinementContext(
      repoName: "Compass",
      immediatePlan: "Add parser tests for Package.swift",
      midTermPlan: "Refine drafts",
      longTermPlan: "Keep Compass read-only until explicit actions",
      primaryLanguage: "Swift"
    )
  }
}

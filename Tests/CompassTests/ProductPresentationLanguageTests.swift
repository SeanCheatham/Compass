import Foundation
import Testing

@testable import Compass

struct ProductPresentationLanguageTests {
  @Test func roundAndStatusLabelsUseProductLanguage() throws {
    try #require(
      ProductPresentationLanguage.roundLabel(kind: .productPlans, ordinal: 1)
        == "Round 1: Plan proof"
    )
    try #require(
      ProductPresentationLanguage.roundLabel(kind: .coreTechnology, ordinal: 2)
        == "Round 2: Core technology"
    )
    try #require(
      ProductPresentationLanguage.roundLabel(kind: .productImplementation, ordinal: 3)
        == "Round 3: Product use"
    )
    try #require(
      ProductPresentationLanguage.roundGateLabel(kind: .productImplementation)
        == "Product use and pay gate"
    )
    try #require(
      ProductPresentationLanguage.contenderStatusLabel(.needsRevision)
        == "Revision needed"
    )
  }

  @Test func evidenceDimensionsMapToSemanticToneAndIconRoles() throws {
    try #require(ProductPresentationLanguage.evidenceLabel(for: .payIntent) == "Pay intent")
    try #require(ProductPresentationLanguage.iconRole(for: .painFit) == .pain)
    try #require(ProductPresentationLanguage.iconRole(for: .alternativeAdvantage) == .alternative)
    try #require(ProductPresentationLanguage.iconRole(for: .payIntent) == .payIntent)
    try #require(ProductPresentationLanguage.iconRole(for: .productUseProof) == .useProof)
    try #require(ProductPresentationLanguage.tone(for: EvidenceStrength.strong) == .strong)
    try #require(ProductPresentationLanguage.tone(for: EvidenceStrength.blocked) == .blocked)
  }

  @Test func proofDebtCopyPairsCountsWithMeaning() throws {
    let proofDebt = ProofDebtSummary(
      missingGates: ["Buyer proof missing", "Pay intent weak"],
      completedCount: 1,
      requiredCount: 2,
      nextProofTarget: "economic-buyer simulated-user proof",
      readinessState: "Plan proof missing",
      blockingCount: 2,
      auditReferences: []
    )

    let copy = ProductPresentationLanguage.proofDebtCopy(for: proofDebt)

    try #require(copy.shortLabel == "1/2 - Buyer proof missing")
    try #require(copy.detail == "Buyer proof missing, Pay intent weak")
    try #require(copy.nextTargetLabel == "economic-buyer simulated-user proof")
    try #require(copy.tone == .progressing)
  }

  @Test func actionLabelsAvoidQueueAndInternalActionCopy() throws {
    try #require(
      ProductPresentationLanguage.actionLabel(for: .runPlanProof)
        == "Run plan proof"
    )
    try #require(
      ProductPresentationLanguage.actionLabel(for: .runCohort, targetDecision: .promote)
        == "Run validation proof"
    )
    try #require(
      ProductPresentationLanguage.actionLabel(for: .prepareWorktree)
        == "Prepare implementation track"
    )
    try #require(
      ProductPresentationLanguage.expectedDecisionLabel(
        actionKind: .runPlanProof
      ) == "Advance to feasibility, revise, or eliminate"
    )
    try #require(
      ProductPresentationLanguage.disabledReasonLabel(
        "scenario cohort has no enabled scenario"
      ) == "No enabled product-test scenario is ready."
    )
  }

  @Test func primaryCopyRejectsAuditReferencesWhileAuditTextKeepsThem() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "LedgerLift",
      rawPain: "Finance operators lose weekly reporting context.",
      now: Date(timeIntervalSince1970: 10)
    )
    let cockpit = ProductDecisionCockpit.build(
      config: config,
      evidenceIndex: .empty,
      isPersonaModelAvailable: false
    )
    let nextMove = try #require(cockpit.nextMove)
    let proofDebt = try #require(cockpit.contenders.first?.proofDebt)
    let primary = [
      nextMove.actionTitle,
      nextMove.why,
      nextMove.expectedDecision,
      ProductPresentationLanguage.proofDebtCopy(for: proofDebt).shortLabel,
    ].joined(separator: "\n")
    let auditText = ProductPresentationLanguage.auditText(for: cockpit.auditReferences)

    try #require(
      !ProductPresentationLanguage.primaryTextContainsAuditReference(
        primary,
        auditReferences: cockpit.auditReferences
      )
    )
    try #require(auditText.contains(config.tournaments[0].id))
    try #require(auditText.contains(config.tournamentExperiments[0].branchName))
    try #require(
      cockpit.auditReferences.allSatisfy {
        ProductPresentationLanguage.disclosureLayer(for: $0.kind) == .audit
      }
    )
  }

  @Test func portableLanguageDoesNotImportSwiftUI() throws {
    let source = try String(
      contentsOfFile: "Sources/Compass/ProductPresentationLanguage.swift",
      encoding: .utf8
    )

    try #require(!source.contains("import SwiftUI"))
  }
}

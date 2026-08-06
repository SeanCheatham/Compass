import AppKit
import CompassCore
import Foundation

@MainActor
extension CompassProject {
  func saveBrief() async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      try workspace.writeBrief(brief)
      // Keep ledger aligned when requirements are added/removed.
      let ledger = workspace.readRequirementLedger(reconciledWith: brief)
      try workspace.writeRequirementLedger(ledger)
      requirementLedger = ledger
      log("Saved brief.", level: .success)
    } catch {
      fail(error)
    }
  }

  /// Fill the Brief tab from a curated random starter idea (in-memory; Save to persist).
  func applyRandomBriefIdea() {
    brief = ProjectBriefIdeaGenerator.random()
    requirementLedger = requirementLedger.reconciled(with: brief)
    log("Filled brief with a random idea. Save when you want to keep it.", level: .info)
  }

  func saveRequirementLedger() async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      try workspace.writeRequirementLedger(
        requirementLedger,
        reconciledWith: brief
      )
      requirementLedger = workspace.readRequirementLedger(reconciledWith: brief)
      log("Saved requirement criteria.", level: .success)
    } catch {
      fail(error)
    }
  }

  func saveLessons() async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      try workspace.writeLessons(lessons)
      log("Saved lessons.", level: .success)
    } catch {
      fail(error)
    }
  }

  func affirmAssumption(id: String, comment: String?) async {
    await reviewAssumption(
      id: id,
      status: .affirmed,
      comment: comment,
      feedback: "Assumption affirmed."
    )
  }

  func denyAssumption(id: String, comment: String?) async {
    await reviewAssumption(
      id: id,
      status: .denied,
      comment: comment,
      feedback: "Assumption denied."
    )
  }

  func markAssumptionImplicit(id: String, comment: String?) async {
    await reviewAssumption(
      id: id,
      status: .implicit,
      comment: comment,
      feedback: "Assumption moved back to implicit."
    )
  }

  func archiveAssumption(id: String, comment: String?) async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      _ = try workspace.removeAssumption(id: id, comment: comment)
      assumptions = try workspace.readAssumptionLedger().assumptions
      log("Assumption archived.", level: .success)
    } catch {
      fail(error)
    }
  }

  func saveDrafts() async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      try workspace.writeDrafts(drafts)
      log("Saved drafts.", level: .success)
    } catch {
      fail(error)
    }
  }

  private func reviewAssumption(
    id: String,
    status: AssumptionRecord.Status,
    comment: String?,
    feedback: String
  ) async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      _ = try workspace.reviewAssumption(id: id, status: status, comment: comment)
      assumptions = try workspace.readAssumptionLedger().assumptions
      log(feedback, level: .success)
    } catch {
      fail(error)
    }
  }

  func addDraft() async {
    await queueDraft(
      draftEntry,
      clearsDraftEntry: true,
      feedback: "Draft queued."
    )
  }

  func queueDraft(
    _ text: String,
    clearsDraftEntry: Bool,
    feedback: String
  ) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      try workspace.appendDraft(trimmed)
      if clearsDraftEntry {
        draftEntry = ""
      }
      drafts = workspace.readDrafts()
      log(feedback, level: .success)
    } catch {
      fail(error)
    }
  }
}

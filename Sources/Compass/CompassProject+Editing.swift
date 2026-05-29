import AppKit
import Foundation

@MainActor
extension CompassProject {
  func saveVision() async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      try workspace.writeVision(vision)
      log("Saved vision.", level: .success)
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

  func acceptDraftRefinement(_ refinement: DraftRefinement) async {
    await queueDraft(
      refinement.refinedText,
      clearsDraftEntry: true,
      feedback: "Refined draft queued."
    )
  }

  func modifyDraft(with refinement: DraftRefinement) {
    draftEntry = refinement.refinedText
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

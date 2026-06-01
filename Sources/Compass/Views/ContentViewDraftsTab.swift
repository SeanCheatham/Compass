import AppKit
import SwiftUI

struct DraftsTab: View {
  @ObservedObject var project: CompassProject
  @State private var pendingDraftsText = ""
  @State private var draftRefinementPreview: DraftRefinement?
  @State private var draftRefinementTask: Task<Void, Never>?
  @State private var draftRefinementRescheduleTask: Task<Void, Never>?
  @State private var draftRefinementCache: [DraftRefinementPreviewKey: DraftRefinement] = [:]
  @State private var activeDraftRefinementKey: DraftRefinementPreviewKey?
  @State private var isDraftRefinementActive = false
  @State private var isDraftRefinementPreviewAvailable = DraftRefinementService.isPreviewAvailable

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeader("New Draft", systemImage: "square.and.pencil")
      HStack(alignment: .top, spacing: 10) {
        TextField("Describe the next direction", text: $project.draftEntry, axis: .vertical)
          .lineLimit(2...5)
          .textFieldStyle(.roundedBorder)
          .onKeyPress(keys: [.return], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            return handleDraftSubmissionShortcut()
          }
        Button {
          submitNewDraft()
        } label: {
          Label("Add", systemImage: "plus")
        }
        .disabled(
          !project.hasRepository
            || project.draftEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      if shouldShowDraftRefinementPreview {
        DraftRefinementPreviewCard(
          refinement: draftRefinementPreview,
          isRefining: isDraftRefinementActive,
          canAccept: project.hasRepository,
          accept: acceptDraftRefinement,
          modify: modifyDraftRefinement
        )
      }

      HStack {
        SectionHeader("Pending Drafts", systemImage: "tray")
        Spacer()
        Button {
          Task { await project.saveDrafts() }
        } label: {
          Label("Save", systemImage: "square.and.arrow.down")
        }
        .disabled(!project.hasRepository)
      }
      TextEditor(text: $pendingDraftsText)
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
          if pendingDraftsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("No drafts queued.")
              .foregroundStyle(.secondary)
              .padding(12)
          }
        }
        .frame(minHeight: 160)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .onAppear {
      syncPendingDraftsFromProject()
      refreshDraftRefinementAvailability()
    }
    .onDisappear {
      cancelDraftRefinementPreview()
      cancelDraftRefinementReschedule()
      project.drafts = pendingDraftsText
    }
    .onChange(of: project.drafts) {
      syncPendingDraftsFromProject()
    }
    .onChange(of: pendingDraftsText) {
      if pendingDraftsText != project.drafts {
        project.drafts = pendingDraftsText
      }
    }
    .onChange(of: project.draftEntry) {
      requestDraftRefinementReschedule()
    }
    .onChange(of: project.state) {
      requestDraftRefinementReschedule()
    }
    .onChange(of: project.languageProfile) {
      requestDraftRefinementReschedule()
    }
    .onChange(of: project.repoURL) {
      requestDraftRefinementReschedule()
    }
  }

  private var trimmedDraftEntry: String {
    DraftRefinementService.normalizeDraft(project.draftEntry)
  }

  private var draftRefinementContext: DraftRefinementContext {
    DraftRefinementContext(project: project)
  }

  private var shouldShowDraftRefinementPreview: Bool {
    isDraftRefinementPreviewAvailable
      && !trimmedDraftEntry.isEmpty
      && (isDraftRefinementActive || draftRefinementPreview != nil)
  }

  private func syncPendingDraftsFromProject() {
    guard pendingDraftsText != project.drafts else { return }
    pendingDraftsText = project.drafts
  }

  private func submitNewDraft() {
    cancelDraftRefinementReschedule()
    cancelDraftRefinementPreview()
    Task {
      await project.addDraft()
      syncPendingDraftsFromProject()
    }
  }

  private func refreshDraftRefinementAvailability() {
    isDraftRefinementPreviewAvailable = DraftRefinementService.isPreviewAvailable
    if isDraftRefinementPreviewAvailable {
      requestDraftRefinementReschedule()
    } else {
      cancelDraftRefinementPreview()
    }
  }

  private func requestDraftRefinementReschedule() {
    guard !isDraftRefinementActive else { return }
    draftRefinementRescheduleTask?.cancel()
    draftRefinementRescheduleTask = Task { @MainActor in
      await Task.yield()
      guard !Task.isCancelled else { return }
      scheduleDraftRefinementPreview()
    }
  }

  private func cancelDraftRefinementReschedule() {
    draftRefinementRescheduleTask?.cancel()
    draftRefinementRescheduleTask = nil
  }

  private func scheduleDraftRefinementPreview() {
    isDraftRefinementPreviewAvailable = DraftRefinementService.isPreviewAvailable
    if project.isRunning {
      cancelDraftRefinementPreview()
      return
    }
    let context = draftRefinementContext
    let plan = DraftRefinementPreviewPlanner.plan(
      draft: project.draftEntry,
      context: context,
      cachedKeys: Set(draftRefinementCache.keys)
    )

    switch plan.visibility {
    case .hiddenEmptyDraft:
      cancelDraftRefinementPreview()
    case .cached:
      draftRefinementTask?.cancel()
      isDraftRefinementActive = false
      activeDraftRefinementKey = plan.cacheKey
      draftRefinementPreview = plan.cacheKey.flatMap { draftRefinementCache[$0] }
    case .debounce:
      guard let key = plan.cacheKey else {
        cancelDraftRefinementPreview()
        return
      }
      draftRefinementTask?.cancel()
      activeDraftRefinementKey = key
      draftRefinementPreview = nil
      isDraftRefinementActive = true
      let draft = key.trimmedDraft
      draftRefinementTask = Task {
        do {
          try await Task.sleep(nanoseconds: plan.delayNanoseconds)
        } catch {
          return
        }

        let shouldGenerate = await MainActor.run { () -> Bool in
          !Task.isCancelled && activeDraftRefinementKey == key
        }
        guard shouldGenerate else { return }

        let context = await MainActor.run {
          DraftRefinementContext(project: project)
        }
        let refinement = await DraftRefinementService.makeRefinement(
          draft: draft,
          context: context
        )

        await MainActor.run {
          guard !Task.isCancelled, activeDraftRefinementKey == key else {
            isDraftRefinementActive = false
            return
          }
          if let refinement {
            draftRefinementCache[key] = refinement
            trimDraftRefinementCache()
          }
          draftRefinementPreview = refinement
          isDraftRefinementActive = false
        }
      }
    }
  }

  private func cancelDraftRefinementPreview() {
    draftRefinementTask?.cancel()
    draftRefinementTask = nil
    activeDraftRefinementKey = nil
    draftRefinementPreview = nil
    isDraftRefinementActive = false
  }

  private func trimDraftRefinementCache() {
    while draftRefinementCache.count > 12, let key = draftRefinementCache.keys.first {
      draftRefinementCache.removeValue(forKey: key)
    }
  }

  private func handleDraftSubmissionShortcut() -> KeyPress.Result {
    guard project.hasRepository else { return .handled }

    if isDraftRefinementActive {
      return .handled
    }

    if let refinement = draftRefinementPreview {
      acceptDraftRefinement(refinement)
      return .handled
    }

    guard !trimmedDraftEntry.isEmpty else { return .handled }

    submitNewDraft()
    return .handled
  }

  private func acceptDraftRefinement(_ refinement: DraftRefinement) {
    cancelDraftRefinementReschedule()
    cancelDraftRefinementPreview()
    Task {
      await project.acceptDraftRefinement(refinement)
      syncPendingDraftsFromProject()
    }
  }

  private func modifyDraftRefinement(_ refinement: DraftRefinement) {
    cancelDraftRefinementReschedule()
    cancelDraftRefinementPreview()
    project.modifyDraft(with: refinement)
  }
}

struct DraftRefinementPreviewCard: View {
  var refinement: DraftRefinement?
  var isRefining: Bool
  var canAccept: Bool
  var accept: (DraftRefinement) -> Void
  var modify: (DraftRefinement) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Label("Refined draft", systemImage: "sparkles")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        if let refinement {
          Text(refinement.source == .generated ? "On-device model" : "Quick polish")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.7), in: Capsule())
        }
        Spacer()
        if isRefining {
          ProgressView()
            .controlSize(.small)
        }
      }

      if let refinement {
        Text(refinement.refinedText)
          .font(.callout)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)

        HStack(spacing: 8) {
          Spacer()
          Button {
            modify(refinement)
          } label: {
            Label("Modify", systemImage: "arrow.triangle.2.circlepath")
          }
          Button {
            accept(refinement)
          } label: {
            Label("Accept", systemImage: "checkmark")
          }
          .buttonStyle(.borderedProminent)
          .disabled(!canAccept)
        }
        .controlSize(.small)
      } else if isRefining {
        Text("Refining draft…")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .frame(minHeight: 72, alignment: .topLeading)
    .padding(10)
    .background(.quaternary.opacity(0.26), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(.secondary.opacity(0.12))
    }
  }
}

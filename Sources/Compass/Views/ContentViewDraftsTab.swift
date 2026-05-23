import AppKit
import SwiftUI


struct DraftsTab: View {
  @ObservedObject var project: CompassProject
  @State private var draftRefinementPreview: DraftRefinement?
  @State private var draftRefinementTask: Task<Void, Never>?
  @State private var draftRefinementCache: [DraftRefinementPreviewKey: DraftRefinement] = [:]
  @State private var activeDraftRefinementKey: DraftRefinementPreviewKey?
  @State private var isDraftRefinementGenerating = false
  @State private var isDraftRefinementModelAvailable = DraftRefinementService.isPreviewAvailable

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeader("New Draft", systemImage: "square.and.pencil")
      HStack(alignment: .top, spacing: 10) {
        TextField("Describe the next direction", text: $project.draftEntry, axis: .vertical)
          .lineLimit(2...5)
          .textFieldStyle(.roundedBorder)
        Button {
          Task { await project.addDraft() }
        } label: {
          Label("Add", systemImage: "plus")
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(
          !project.hasRepository
            || project.draftEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      if shouldShowDraftRefinementPreview {
        DraftRefinementPreviewCard(
          refinement: draftRefinementPreview,
          isGenerating: isDraftRefinementGenerating,
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
      TextEditor(text: $project.drafts)
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
          if project.drafts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("No drafts queued.")
              .foregroundStyle(.secondary)
              .padding(12)
          }
        }
    }
    .onAppear {
      refreshDraftRefinementAvailability()
    }
    .onDisappear {
      cancelDraftRefinementPreview()
    }
    .onChange(of: project.draftEntry) {
      scheduleDraftRefinementPreview()
    }
    .onChange(of: project.state) {
      scheduleDraftRefinementPreview()
    }
    .onChange(of: project.languageProfile) {
      scheduleDraftRefinementPreview()
    }
    .onChange(of: project.repoURL) {
      scheduleDraftRefinementPreview()
    }
  }

  private var trimmedDraftEntry: String {
    DraftRefinementService.normalizeDraft(project.draftEntry)
  }

  private var draftRefinementContext: DraftRefinementContext {
    DraftRefinementContext(project: project)
  }

  private var shouldShowDraftRefinementPreview: Bool {
    isDraftRefinementModelAvailable
      && !trimmedDraftEntry.isEmpty
      && (isDraftRefinementGenerating || draftRefinementPreview != nil)
  }

  private func refreshDraftRefinementAvailability() {
    isDraftRefinementModelAvailable = DraftRefinementService.isPreviewAvailable
    if isDraftRefinementModelAvailable {
      scheduleDraftRefinementPreview()
    } else {
      cancelDraftRefinementPreview()
    }
  }

  private func scheduleDraftRefinementPreview() {
    isDraftRefinementModelAvailable = DraftRefinementService.isPreviewAvailable
    let context = draftRefinementContext
    let plan = DraftRefinementPreviewPlanner.plan(
      draft: project.draftEntry,
      context: context,
      isModelAvailable: isDraftRefinementModelAvailable,
      cachedKeys: Set(draftRefinementCache.keys)
    )

    switch plan.visibility {
    case .hiddenEmptyDraft, .hiddenUnavailableModel:
      cancelDraftRefinementPreview()
    case .cached:
      draftRefinementTask?.cancel()
      isDraftRefinementGenerating = false
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
      isDraftRefinementGenerating = false
      let draft = key.trimmedDraft
      draftRefinementTask = Task { @MainActor in
        do {
          try await Task.sleep(nanoseconds: plan.delayNanoseconds)
        } catch {
          return
        }
        guard !Task.isCancelled, activeDraftRefinementKey == key else { return }
        isDraftRefinementGenerating = true
        let refinement = await DraftRefinementService.makeRefinement(
          draft: draft,
          context: context
        )
        guard !Task.isCancelled, activeDraftRefinementKey == key else { return }
        if let refinement {
          draftRefinementCache[key] = refinement
          trimDraftRefinementCache()
        }
        draftRefinementPreview = refinement
        isDraftRefinementGenerating = false
      }
    }
  }

  private func cancelDraftRefinementPreview() {
    draftRefinementTask?.cancel()
    draftRefinementTask = nil
    activeDraftRefinementKey = nil
    draftRefinementPreview = nil
    isDraftRefinementGenerating = false
  }

  private func trimDraftRefinementCache() {
    while draftRefinementCache.count > 12, let key = draftRefinementCache.keys.first {
      draftRefinementCache.removeValue(forKey: key)
    }
  }

  private func acceptDraftRefinement(_ refinement: DraftRefinement) {
    cancelDraftRefinementPreview()
    Task {
      await project.acceptDraftRefinement(refinement)
    }
  }

  private func modifyDraftRefinement(_ refinement: DraftRefinement) {
    cancelDraftRefinementPreview()
    project.modifyDraft(with: refinement)
  }
}


struct DraftRefinementPreviewCard: View {
  var refinement: DraftRefinement?
  var isGenerating: Bool
  var canAccept: Bool
  var accept: (DraftRefinement) -> Void
  var modify: (DraftRefinement) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Label("Refined draft", systemImage: "sparkles")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        if isGenerating {
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
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.26), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(.secondary.opacity(0.12))
    }
  }
}

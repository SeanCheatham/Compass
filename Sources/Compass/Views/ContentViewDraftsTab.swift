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
  @State private var draftReadinessNarration: DraftReadinessGuideNarration?
  @State private var draftQueueNarration: DraftIntakeGuideNarration?

  var body: some View {
    let draftReadinessGuide = DraftReadinessGuide(draft: project.draftEntry)
    let draftQueueGuide = DraftIntakeGuide(drafts: pendingDraftsText)
    let draftStarter = DraftStarterTemplate(draft: project.draftEntry)
    let draftIdeas = DraftIdeaLibrary.ideas(for: project.languageProfile)

    VStack(alignment: .leading, spacing: 14) {
      HStack {
        SectionHeader("New Draft", systemImage: "square.and.pencil")
        Spacer()
        Button {
          project.draftEntry = draftStarter.text
        } label: {
          Label(draftStarter.title, systemImage: draftStarter.systemImage)
        }
        .controlSize(.small)
        .disabled(!project.hasRepository || !draftStarter.isEnabled)
        .help(draftStarter.helpText)
      }
      DraftIdeaChips(ideas: draftIdeas, isEnabled: project.hasRepository) { idea in
        project.draftEntry = idea.text
      }
      HStack(alignment: .top, spacing: 10) {
        TextField(DraftReadinessGuide.entryPlaceholder, text: $project.draftEntry, axis: .vertical)
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
      DraftReadinessGuideView(
        guide: draftReadinessGuide,
        narration: matchingNarration(for: draftReadinessGuide)
      )

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
      DraftQueueReadinessView(
        guide: draftQueueGuide,
        narration: matchingNarration(for: draftQueueGuide)
      )
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
    .task(id: "\(draftReadinessGuide.narrationIdentifier)|running-\(project.isRunning)") {
      draftReadinessNarration = nil
      guard !project.isRunning, draftReadinessGuide.allowsNarration else { return }
      try? await Task.sleep(nanoseconds: 700_000_000)
      guard !Task.isCancelled else { return }
      draftReadinessNarration = await DraftReadinessGuideNarrator.narrate(
        guide: draftReadinessGuide
      )
    }
    .task(id: "\(draftQueueGuide.narrationIdentifier)|running-\(project.isRunning)") {
      draftQueueNarration = nil
      guard !project.isRunning else { return }
      try? await Task.sleep(nanoseconds: 700_000_000)
      guard !Task.isCancelled else { return }
      draftQueueNarration = await DraftIntakeGuideNarrator.narrate(guide: draftQueueGuide)
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

  private func matchingNarration(
    for guide: DraftReadinessGuide
  ) -> DraftReadinessGuideNarration? {
    guard draftReadinessNarration?.guideIdentifier == guide.narrationIdentifier else {
      return nil
    }
    return draftReadinessNarration
  }

  private func matchingNarration(for guide: DraftIntakeGuide) -> DraftIntakeGuideNarration? {
    guard draftQueueNarration?.guideIdentifier == guide.narrationIdentifier else {
      return nil
    }
    return draftQueueNarration
  }
}

struct DraftIdeaChips: View {
  var ideas: [DraftIdeaTemplate]
  var isEnabled: Bool
  var select: (DraftIdeaTemplate) -> Void

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 7) {
        ForEach(ideas) { idea in
          Button {
            select(idea)
          } label: {
            Label(idea.title, systemImage: idea.systemImage)
              .lineLimit(1)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(!isEnabled)
          .help(idea.text)
        }
      }
      .padding(.vertical, 1)
    }
    .scrollIndicators(.hidden)
  }
}

struct DraftQueueReadinessView: View {
  var guide: DraftIntakeGuide
  var narration: DraftIntakeGuideNarration? = nil

  var body: some View {
    let queuePayload = DraftIntakeClipboardPayload(guide: guide)

    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(guide.title, systemImage: systemImage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(color)

        Text(guide.scoreLabel)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary.opacity(0.7), in: Capsule())

        Spacer()

        CopyDraftQueueButton(payload: queuePayload)
      }

      Text(narration?.text ?? guide.detail)
        .font(.caption)
        .foregroundStyle(narration == nil ? .secondary : .primary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      DraftQueueNextActionRow(action: guide.nextAction, color: color)

      if !guide.entries.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(guide.entries.enumerated()), id: \.element.id) { index, entry in
            DraftQueueReadinessRow(entry: entry)

            if index < guide.entries.count - 1 {
              Divider()
            }
          }
        }
        .padding(.top, 2)
      }

      if narration != nil {
        Label("On-device queue note", systemImage: "sparkles")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(0.18))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(guide.title). \(narration?.text ?? guide.detail). \(guide.scoreLabel). Next action: \(guide.nextAction.title). \(guide.nextAction.detail)"
    )
  }

  private var color: Color {
    switch guide.status {
    case .empty:
      return .secondary
    case .needsDetail:
      return .orange
    case .ready:
      return .green
    }
  }

  private var systemImage: String {
    switch guide.status {
    case .empty:
      return "tray"
    case .needsDetail:
      return "exclamationmark.triangle"
    case .ready:
      return "checkmark.seal"
    }
  }
}

struct DraftQueueNextActionRow: View {
  var action: DraftIntakeGuide.NextAction
  var color: Color

  var body: some View {
    HStack(alignment: .top, spacing: 7) {
      Image(systemName: action.systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .frame(width: 18)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text("Next action: \(action.title)")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(2)

        Text(action.detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.top, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Next action: \(action.title). \(action.detail)")
  }
}

struct CopyDraftQueueButton: View {
  var payload: DraftIntakeClipboardPayload
  @State private var copied = false

  var body: some View {
    Button {
      copyTextToPasteboard(payload.text)
      copied = true
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        copied = false
      }
    } label: {
      Label(
        copied ? "Copied" : "Copy Queue",
        systemImage: copied ? "checkmark" : "doc.on.doc"
      )
      .lineLimit(1)
    }
    .controlSize(.small)
    .disabled(payload.isEmpty)
    .help(ClipboardHelpText.draftQueue)
  }
}

struct DraftQueueReadinessRow: View {
  var entry: DraftIntakeGuide.Entry

  private let cueColumns = [
    GridItem(.adaptive(minimum: 118), spacing: 6, alignment: .leading)
  ]

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      Text("\(entry.number)")
        .font(.caption2.weight(.bold))
        .foregroundStyle(color)
        .frame(width: 22, height: 22)
        .background(color.opacity(0.12), in: Circle())
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(entry.readiness.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)

          Text(entry.readiness.scoreLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

          Spacer()
        }

        Text(entry.draft)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)

        LazyVGrid(columns: cueColumns, alignment: .leading, spacing: 6) {
          ForEach(entry.readiness.cues) { cue in
            Label(cue.title, systemImage: cue.systemImage)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(cue.isSatisfied ? color : .secondary)
              .lineLimit(1)
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .background(
                (cue.isSatisfied ? color.opacity(0.12) : Color.secondary.opacity(0.08)),
                in: Capsule()
              )
              .help(cue.detail)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "Draft \(entry.number). \(entry.readiness.title). \(entry.missingSignalText) missing."
    )
  }

  private var color: Color {
    switch entry.readiness.status {
    case .empty:
      return .secondary
    case .needsDetail:
      return .orange
    case .ready:
      return .green
    }
  }
}

struct DraftReadinessGuideView: View {
  var guide: DraftReadinessGuide
  var narration: DraftReadinessGuideNarration? = nil

  private let coachingColumns = [
    GridItem(.adaptive(minimum: 180), spacing: 6, alignment: .leading)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(guide.title, systemImage: systemImage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(color)

        Text(guide.scoreLabel)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary.opacity(0.7), in: Capsule())

        Spacer()
      }

      Text(narration?.text ?? guide.detail)
        .font(.caption)
        .foregroundStyle(narration == nil ? .secondary : .primary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      HStack(spacing: 6) {
        ForEach(guide.cues) { cue in
          Label(cue.title, systemImage: cue.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(cue.isSatisfied ? color : .secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
              (cue.isSatisfied ? color.opacity(0.12) : Color.secondary.opacity(0.08)),
              in: Capsule()
            )
            .help(cue.detail)
        }
      }

      if !guide.coachingPrompts.isEmpty {
        LazyVGrid(columns: coachingColumns, alignment: .leading, spacing: 6) {
          ForEach(guide.coachingPrompts) { prompt in
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text(prompt.question)
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(.primary)
                  .lineLimit(2)

                Text(prompt.detail)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            } icon: {
              Image(systemName: prompt.systemImage)
                .foregroundStyle(color)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .help(prompt.detail)
          }
        }
      }

      if narration != nil {
        Label("On-device draft note", systemImage: "sparkles")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(0.18))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(guide.title). \(narration?.text ?? guide.detail). \(guide.scoreLabel) signals present."
    )
  }

  private var color: Color {
    switch guide.status {
    case .empty:
      return .secondary
    case .needsDetail:
      return .orange
    case .ready:
      return .green
    }
  }

  private var systemImage: String {
    switch guide.status {
    case .empty:
      return "square.and.pencil"
    case .needsDetail:
      return "list.bullet.clipboard"
    case .ready:
      return "checkmark.seal"
    }
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

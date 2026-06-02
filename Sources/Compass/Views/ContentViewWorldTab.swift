import AppKit
import RealityKit
import SwiftUI
import simd

struct WorldTab: View {
  let repoURL: URL
  let workspace: CompassWorkspace?
  let isActive: Bool
  let sessionRecords: () -> [SessionRecord]
  let onLoadArchivedSessions: () async -> Void

  @StateObject private var model = WorldTabViewModel()

  var body: some View {
    ZStack {
      worldBackground
      content
    }
    .task(id: repoURL.standardizedFileURL.path) {
      guard isActive else { return }
      await model.load(repoURL: repoURL, workspace: workspace)
    }
    .onChange(of: isActive) { _, active in
      if active {
        Task { await model.load(repoURL: repoURL, workspace: workspace) }
      } else {
        model.pause()
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if model.isLoading {
      loadingView
    } else if let errorMessage = model.errorMessage {
      ContentUnavailableView(
        "World Map Unavailable",
        systemImage: "exclamationmark.triangle",
        description: Text(errorMessage)
      )
      .foregroundStyle(.white)
    } else if let graph = model.graph, graph.isEmpty {
      ContentUnavailableView(
        "No World Yet",
        systemImage: "cube.transparent",
        description: Text("Index the repository to build a code-path world.")
      )
      .foregroundStyle(.white)
    } else if let graph = model.graph {
      HStack(spacing: 14) {
        ZStack(alignment: .topLeading) {
          WorldRealitySceneView(
            graph: graph,
            selectedNodeID: model.selectedNodeID,
            route: model.route,
            routeIndex: model.routeIndex
          )
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(.white.opacity(0.16), lineWidth: 1)
          )
          .realityViewCameraControls(.orbit)

          VStack(alignment: .leading, spacing: 10) {
            if let script = model.tourScript {
              WorldSceneGuideOverlay(script: script)
                .frame(maxWidth: 430, alignment: .leading)
            }

            WorldMiniMap(
              graph: graph,
              selectedNodeID: model.selectedNodeID,
              route: model.route,
              onSelect: model.selectNode
            )
            .frame(width: 150, height: 112)
          }
          .padding(14)
        }

        WorldSidebarPanel(
          model: model,
          repoURL: repoURL,
          workspace: workspace,
          isActive: isActive,
          sessionRecords: sessionRecords,
          onLoadArchivedSessions: onLoadArchivedSessions
        )
        .frame(width: 340)
      }
      .padding(16)
    }
  }

  private var loadingView: some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.large)
      Text("Lighting the world...")
        .font(.headline)
      Text("Tracing inferred paths through the codemap.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var worldBackground: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.05, green: 0.06, blue: 0.07),
          Color(red: 0.09, green: 0.07, blue: 0.06),
          Color(red: 0.02, green: 0.025, blue: 0.03),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Rectangle()
        .fill(.black.opacity(0.22))
    }
    .ignoresSafeArea()
  }
}

@MainActor
final class WorldTabViewModel: ObservableObject {
  @Published private(set) var graph: WorldGraph?
  @Published private(set) var isLoading = false
  @Published private(set) var errorMessage: String?
  @Published var selectedEntrypointID: String?
  @Published var selectedNodeID: String?
  @Published var searchText = ""
  @Published var route: [String] = []
  @Published var routeIndex = 0
  @Published private(set) var isPlaying = false
  @Published private(set) var atlasNarration: WorldAtlasNarration?
  @Published private(set) var tourScript: WorldTourScript?

  private var loadedRepoPath: String?
  private var playbackTask: Task<Void, Never>?
  private var guideTask: Task<Void, Never>?
  private var guideNarrationIdentifier: String?

  var selectedNode: WorldNode? {
    guard let graph, let selectedNodeID else { return nil }
    return graph.nodeByID[selectedNodeID]
  }

  var activeNodeID: String? {
    guard !route.isEmpty else { return selectedNodeID }
    return route[min(routeIndex, route.count - 1)]
  }

  var activeNode: WorldNode? {
    guard let graph, let activeNodeID else { return nil }
    return graph.nodeByID[activeNodeID]
  }

  var branchChoices: [WorldNode] {
    WorldNavigator.branchChoices(in: graph ?? WorldGraph(), at: activeNodeID)
  }

  var atlas: WorldAtlas? {
    guard let graph else { return nil }
    return WorldAtlas(
      graph: graph,
      route: route,
      routeIndex: routeIndex,
      selectedNodeID: selectedNodeID
    )
  }

  var matchingAtlasNarration: WorldAtlasNarration? {
    guard let atlas else { return nil }
    guard atlasNarration?.atlasIdentifier == atlas.narrationIdentifier else { return nil }
    return atlasNarration
  }

  var searchResults: [WorldNode] {
    guard let graph else { return [] }
    let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !needle.isEmpty else { return [] }
    return graph.nodes
      .filter { node in
        node.label.lowercased().contains(needle)
          || node.detail?.lowercased().contains(needle) == true
          || node.location?.filePath.lowercased().contains(needle) == true
      }
      .prefix(8)
      .map { $0 }
  }

  func load(repoURL: URL, workspace: CompassWorkspace?) async {
    let repoPath = repoURL.standardizedFileURL.path
    guard loadedRepoPath != repoPath || graph == nil else { return }
    isLoading = true
    errorMessage = nil
    pause()
    resetGuide()

    guard let workspace else {
      graph = nil
      route = []
      selectedNodeID = nil
      selectedEntrypointID = nil
      loadedRepoPath = repoPath
      errorMessage = "Compass has not initialized a workspace for this repository yet."
      isLoading = false
      return
    }

    let codemapDirectory = CodemapStore.defaultDirectory(forWorkspace: workspace)
    let builder = WorldGraphBuilder(repoURL: repoURL, codemapDirectory: codemapDirectory)
    let built = await Task.detached(priority: .userInitiated) {
      await builder.buildCached()
    }.value

    let entrypointID = built.entrypointIDs.first
    let initialRoute = WorldNavigator.route(in: built, from: entrypointID)
    selectedEntrypointID = entrypointID
    route = initialRoute
    routeIndex = 0
    selectedNodeID = initialRoute.first ?? built.nodes.first?.id
    loadedRepoPath = repoPath
    graph = built
    isLoading = false
    refreshGuide()
  }

  func selectEntrypoint(_ id: String?) {
    selectedEntrypointID = id
    guard let graph else { return }
    route = WorldNavigator.route(in: graph, from: id)
    routeIndex = 0
    selectedNodeID = route.first ?? id
    refreshGuide()
  }

  func selectNode(_ id: String) {
    selectedNodeID = id
    if let index = route.firstIndex(of: id) {
      routeIndex = index
    }
    refreshGuide()
  }

  func selectBranch(_ id: String) {
    selectedNodeID = id
    if let index = route.firstIndex(of: id) {
      routeIndex = index
    } else {
      route.insert(id, at: min(routeIndex + 1, route.count))
      routeIndex = min(routeIndex + 1, route.count - 1)
    }
    refreshGuide()
  }

  func stepForward() {
    guard !route.isEmpty else { return }
    routeIndex = min(routeIndex + 1, route.count - 1)
    selectedNodeID = route[routeIndex]
    refreshGuide()
  }

  func stepBackward() {
    guard !route.isEmpty else { return }
    routeIndex = max(routeIndex - 1, 0)
    selectedNodeID = route[routeIndex]
    refreshGuide()
  }

  func togglePlayback() {
    isPlaying ? pause() : play()
  }

  func play() {
    guard !route.isEmpty else { return }
    isPlaying = true
    playbackTask?.cancel()
    playbackTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run {
          guard let self, self.isPlaying else { return }
          if self.routeIndex >= max(0, self.route.count - 1) {
            self.pause()
          } else {
            self.stepForward()
          }
        }
      }
    }
  }

  func pause() {
    isPlaying = false
    playbackTask?.cancel()
    playbackTask = nil
  }

  private func resetGuide() {
    guideTask?.cancel()
    guideTask = nil
    guideNarrationIdentifier = nil
    atlasNarration = nil
    tourScript = nil
  }

  private func refreshGuide() {
    guard let graph, let atlas else {
      resetGuide()
      return
    }

    let narration = matchingAtlasNarration
    tourScript = WorldTourScript(
      graph: graph,
      atlas: atlas,
      route: route,
      routeIndex: routeIndex,
      selectedNodeID: selectedNodeID,
      narration: narration
    )

    guard guideNarrationIdentifier != atlas.narrationIdentifier else { return }
    guideNarrationIdentifier = atlas.narrationIdentifier
    if atlasNarration?.atlasIdentifier != atlas.narrationIdentifier {
      atlasNarration = nil
    }

    guideTask?.cancel()
    guideTask = Task { [weak self] in
      let generated = await WorldAtlasNarrator.narrate(atlas: atlas)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let self, self.atlas?.narrationIdentifier == atlas.narrationIdentifier else {
          return
        }
        self.atlasNarration = generated
        self.tourScript = WorldTourScript(
          graph: graph,
          atlas: atlas,
          route: self.route,
          routeIndex: self.routeIndex,
          selectedNodeID: self.selectedNodeID,
          narration: self.matchingAtlasNarration
        )
      }
    }
  }

  deinit {
    playbackTask?.cancel()
    guideTask?.cancel()
  }
}

private enum WorldPanelMode: String, CaseIterable, Identifiable {
  case guide = "Guide"
  case code = "Code"

  var id: Self { self }

  var systemImage: String {
    switch self {
    case .guide: return "sparkles.rectangle.stack"
    case .code: return "doc.text.magnifyingglass"
    }
  }
}

private struct WorldSidebarPanel: View {
  @ObservedObject var model: WorldTabViewModel
  let repoURL: URL
  let workspace: CompassWorkspace?
  let isActive: Bool
  let sessionRecords: () -> [SessionRecord]
  let onLoadArchivedSessions: () async -> Void
  @State private var mode: WorldPanelMode = .guide

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("World panel", selection: $mode) {
        ForEach(WorldPanelMode.allCases) { mode in
          Label(mode.rawValue, systemImage: mode.systemImage)
            .tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      switch mode {
      case .guide:
        WorldInspectorPanel(
          model: model,
          onRevealInCode: { _ in mode = .code }
        )
      case .code:
        WorldCodeBrowserPanel(
          repoURL: repoURL,
          workspace: workspace,
          isActive: isActive,
          sessionRecords: sessionRecords,
          onLoadArchivedSessions: onLoadArchivedSessions
        )
      }
    }
    .padding(14)
    .foregroundStyle(.white)
    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(.white.opacity(0.14), lineWidth: 1)
    )
    .frame(maxHeight: .infinity, alignment: .top)
  }
}

struct WorldInspectorPanel: View {
  @ObservedObject var model: WorldTabViewModel
  let onRevealInCode: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      controls
      if let script = model.tourScript {
        WorldTourScriptPanel(script: script)
      }
      if let atlas = model.atlas {
        WorldAtlasPanel(
          atlas: atlas,
          narration: model.matchingAtlasNarration
        )
      }
      branchChoices
      search
      Divider().overlay(.white.opacity(0.2))
      selectedNode
      Spacer()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label("World", systemImage: "sparkle.magnifyingglass")
        .font(.headline)
      Text("Inferred static paths")
        .font(.caption)
        .foregroundStyle(.white.opacity(0.62))
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let graph = model.graph, !graph.entrypoints.isEmpty {
        Picker(
          "Entry",
          selection: Binding(
            get: { model.selectedEntrypointID ?? graph.entrypointIDs.first },
            set: { model.selectEntrypoint($0) }
          )
        ) {
          ForEach(graph.entrypoints) { node in
            Text(node.label).tag(Optional(node.id))
          }
        }
        .pickerStyle(.menu)
      }

      HStack(spacing: 8) {
        Button {
          model.stepBackward()
        } label: {
          Image(systemName: "backward.end.fill")
        }
        .help("Step backward")

        Button {
          model.togglePlayback()
        } label: {
          Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
        }
        .help(model.isPlaying ? "Pause" : "Play")

        Button {
          model.stepForward()
        } label: {
          Image(systemName: "forward.end.fill")
        }
        .help("Step forward")

        Spacer()

        Text(routeLabel)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.white.opacity(0.62))
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
  }

  private var branchChoices: some View {
    Group {
      if !model.branchChoices.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Doors")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.64))
          ForEach(model.branchChoices.prefix(4)) { node in
            Button {
              model.selectBranch(node.id)
            } label: {
              Label(node.label, systemImage: "door.left.hand.open")
                .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
      }
    }
  }

  private var search: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Search symbols or files", text: $model.searchText)
        .textFieldStyle(.roundedBorder)
      if !model.searchResults.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(model.searchResults) { node in
            Button {
              model.selectNode(node.id)
            } label: {
              HStack(spacing: 6) {
                Image(systemName: iconName(for: node.kind))
                  .frame(width: 14)
                Text(node.label)
                  .lineLimit(1)
                Spacer()
              }
              .font(.caption)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var selectedNode: some View {
    if let node = model.selectedNode ?? model.activeNode {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          Image(systemName: iconName(for: node.kind))
            .foregroundStyle(color(for: node.kind))
          Text(node.label)
            .font(.headline)
            .lineLimit(2)
        }

        Text(node.kind.rawValue)
          .font(.caption.weight(.semibold))
          .foregroundStyle(color(for: node.kind))

        if let detail = node.detail, !detail.isEmpty {
          Text(detail)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(4)
        }

        if let location = node.location {
          VStack(alignment: .leading, spacing: 4) {
            Label(location.filePath, systemImage: "doc.text")
              .lineLimit(2)
            Label(location.lineLabel, systemImage: "number")
          }
          .font(.caption)
          .foregroundStyle(.white.opacity(0.66))

          Button {
            onRevealInCode(location.filePath)
          } label: {
            Label("Show in Code", systemImage: "doc.text.magnifyingglass")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        }

        Label(
          node.confidence.rawValue.capitalized,
          systemImage: "gauge.with.dots.needle.bottom.50percent"
        )
        .font(.caption)
        .foregroundStyle(.white.opacity(0.62))
      }
    } else {
      Text("Select a chamber to inspect its code facts.")
        .font(.callout)
        .foregroundStyle(.white.opacity(0.66))
    }
  }

  private var routeLabel: String {
    guard !model.route.isEmpty else { return "0/0" }
    return "\(model.routeIndex + 1)/\(model.route.count)"
  }

  private func iconName(for kind: WorldNodeKind) -> String {
    switch kind {
    case .module: return "map"
    case .file: return "doc.text"
    case .type: return "shippingbox"
    case .function: return "circle.hexagongrid"
    case .branch: return "arrow.triangle.branch"
    case .loop: return "arrow.2.circlepath"
    case .switchCase: return "switch.2"
    case .errorPath: return "exclamationmark.triangle"
    case .unresolvedPassage: return "questionmark.diamond"
    }
  }

  private func color(for kind: WorldNodeKind) -> Color {
    switch kind {
    case .module: return Color(red: 0.77, green: 0.55, blue: 0.32)
    case .file: return Color(red: 0.42, green: 0.67, blue: 0.74)
    case .type: return Color(red: 0.62, green: 0.72, blue: 0.45)
    case .function: return Color(red: 0.88, green: 0.72, blue: 0.38)
    case .branch: return Color(red: 0.84, green: 0.48, blue: 0.38)
    case .loop: return Color(red: 0.38, green: 0.76, blue: 0.62)
    case .switchCase: return Color(red: 0.72, green: 0.58, blue: 0.86)
    case .errorPath: return Color(red: 0.94, green: 0.39, blue: 0.32)
    case .unresolvedPassage: return Color(red: 0.58, green: 0.62, blue: 0.68)
    }
  }
}

private struct WorldSceneGuideOverlay: View {
  let script: WorldTourScript

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 7) {
        Image(systemName: "quote.bubble")
          .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.32))
        Text(script.progressLabel)
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(.white.opacity(0.74))
        Spacer(minLength: 0)
      }

      Text(script.currentStep?.title ?? script.title)
        .font(.headline)
        .lineLimit(1)
      Text(script.currentStep?.narration ?? script.overview)
        .font(.caption)
        .foregroundStyle(.white.opacity(0.78))
        .lineLimit(3)
    }
    .padding(12)
    .foregroundStyle(.white)
    .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(.white.opacity(0.16), lineWidth: 1)
    )
    .accessibilityElement(children: .combine)
  }
}

private struct WorldTourScriptPanel: View {
  let script: WorldTourScript

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Divider().overlay(.white.opacity(0.16))

      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label("Tour Script", systemImage: "sparkles.tv")
          .font(.caption.weight(.semibold))
        Spacer(minLength: 8)
        Text(script.progressLabel)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.white.opacity(0.58))
      }

      Text(script.overview)
        .font(.caption)
        .foregroundStyle(.white.opacity(0.72))
        .lineLimit(3)

      if let step = script.currentStep {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: iconName(for: step.sceneCue))
            .frame(width: 16)
            .foregroundStyle(color(for: step.sceneCue))
          VStack(alignment: .leading, spacing: 3) {
            Text(step.title)
              .font(.caption.weight(.semibold))
              .lineLimit(1)
            Text(step.subtitle)
              .font(.caption2)
              .foregroundStyle(.white.opacity(0.56))
              .lineLimit(2)
            Text(step.narration)
              .font(.caption2)
              .foregroundStyle(.white.opacity(0.72))
              .lineLimit(3)
          }
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func iconName(for cue: WorldTourScript.SceneCue) -> String {
    switch cue {
    case .entrance: return "door.left.hand.open"
    case .region: return "map"
    case .chamber: return "cube.transparent"
    case .structure: return "shippingbox"
    case .action: return "circle.hexagongrid"
    case .decision: return "arrow.triangle.branch"
    case .warning: return "exclamationmark.triangle"
    case .unknown: return "questionmark.diamond"
    }
  }

  private func color(for cue: WorldTourScript.SceneCue) -> Color {
    switch cue {
    case .entrance, .region, .chamber:
      return Color(red: 0.42, green: 0.67, blue: 0.74)
    case .structure:
      return Color(red: 0.62, green: 0.72, blue: 0.45)
    case .action:
      return Color(red: 0.88, green: 0.72, blue: 0.38)
    case .decision:
      return Color(red: 0.84, green: 0.48, blue: 0.38)
    case .warning:
      return Color(red: 0.94, green: 0.39, blue: 0.32)
    case .unknown:
      return Color(red: 0.58, green: 0.62, blue: 0.68)
    }
  }
}

private struct WorldCodeBrowserPanel: View {
  let repoURL: URL
  let workspace: CompassWorkspace?
  let isActive: Bool
  let sessionRecords: () -> [SessionRecord]
  let onLoadArchivedSessions: () async -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Label("Code", systemImage: "doc.text.magnifyingglass")
          .font(.headline)
        Spacer()
      }
      Text("Repository browser")
        .font(.caption)
        .foregroundStyle(.white.opacity(0.62))

      ExploreTab(
        repoURL: repoURL,
        workspace: workspace,
        isActive: isActive,
        sessionRecords: sessionRecords,
        onLoadArchivedSessions: onLoadArchivedSessions
      )
      .equatable()
      .environment(\.colorScheme, .dark)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 7))
    }
  }
}

private struct WorldAtlasPanel: View {
  let atlas: WorldAtlas
  let narration: WorldAtlasNarration?

  private let metricColumns = [
    GridItem(.flexible(), spacing: 8, alignment: .leading),
    GridItem(.flexible(), spacing: 8, alignment: .leading),
  ]

  var body: some View {
    let clipboardPayload = WorldAtlasClipboardPayload(atlas: atlas, narration: narration)

    VStack(alignment: .leading, spacing: 10) {
      Divider().overlay(.white.opacity(0.16))

      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(atlas.title, systemImage: "sparkles.rectangle.stack")
          .font(.caption.weight(.semibold))
        Spacer(minLength: 8)
        CopyWorldAtlasButton(payload: clipboardPayload)
        Text(atlas.progressLabel)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.white.opacity(0.58))
          .lineLimit(1)
      }

      Text(atlas.detail)
        .font(.caption)
        .foregroundStyle(.white.opacity(0.72))
        .lineLimit(3)

      WorldAtlasSpotlightRow(spotlight: atlas.spotlight)

      if let narration {
        HStack(alignment: .top, spacing: 7) {
          Image(systemName: "text.bubble")
            .frame(width: 14)
            .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.32))
          Text(narration.text)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(4)
        }
        .accessibilityElement(children: .combine)
      }

      LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 8) {
        ForEach(atlas.metrics) { metric in
          VStack(alignment: .leading, spacing: 2) {
            Text(metric.value)
              .font(.callout.monospacedDigit().weight(.semibold))
              .foregroundStyle(.white)
              .lineLimit(1)
            Text(metric.label)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.white.opacity(0.64))
              .lineLimit(1)
            Text(metric.detail)
              .font(.caption2)
              .foregroundStyle(.white.opacity(0.48))
              .lineLimit(2)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .combine)
        }
      }

      if !atlas.terrain.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("Terrain")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.58))
          ForEach(atlas.terrain.prefix(4)) { terrain in
            HStack(alignment: .firstTextBaseline, spacing: 7) {
              Image(systemName: terrain.systemImageName)
                .frame(width: 14)
                .foregroundStyle(.white.opacity(0.72))
              VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                  Text(terrain.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                  Text("\(terrain.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                }
                Text(terrain.detail)
                  .font(.caption2)
                  .foregroundStyle(.white.opacity(0.52))
                  .lineLimit(2)
              }
            }
          }
        }
      }

      if !atlas.routeStops.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("Walk")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.58))
          ForEach(atlas.routeStops.prefix(4)) { stop in
            HStack(alignment: .firstTextBaseline, spacing: 7) {
              Image(systemName: stop.isCurrent ? "circle.fill" : "circle")
                .font(.system(size: 7, weight: .semibold))
                .frame(width: 14)
                .foregroundStyle(stop.isCurrent ? .yellow : .white.opacity(0.45))
              VStack(alignment: .leading, spacing: 1) {
                Text(stop.label)
                  .font(.caption.weight(stop.isCurrent ? .semibold : .regular))
                  .lineLimit(1)
                Text(stop.detail)
                  .font(.caption2)
                  .foregroundStyle(.white.opacity(0.52))
                  .lineLimit(1)
              }
            }
          }
        }
      }

      if !atlas.notices.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(atlas.notices.prefix(3)) { notice in
            HStack(alignment: .top, spacing: 7) {
              Image(systemName: iconName(for: notice.severity))
                .frame(width: 14)
                .foregroundStyle(color(for: notice.severity))
              VStack(alignment: .leading, spacing: 1) {
                Text(notice.label)
                  .font(.caption.weight(.semibold))
                  .lineLimit(1)
                Text(notice.detail)
                  .font(.caption2)
                  .foregroundStyle(.white.opacity(0.54))
                  .lineLimit(2)
              }
            }
          }
        }
      }
    }
  }

  private func iconName(for severity: WorldAtlas.Notice.Severity) -> String {
    switch severity {
    case .info: return "info.circle"
    case .warning: return "exclamationmark.triangle"
    case .danger: return "bolt.trianglebadge.exclamationmark"
    }
  }

  private func color(for severity: WorldAtlas.Notice.Severity) -> Color {
    switch severity {
    case .info: return .white.opacity(0.62)
    case .warning: return Color(red: 0.95, green: 0.72, blue: 0.32)
    case .danger: return Color(red: 0.94, green: 0.39, blue: 0.32)
    }
  }
}

private struct WorldAtlasSpotlightRow: View {
  let spotlight: WorldAtlas.Spotlight

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: spotlight.systemImageName)
        .frame(width: 16)
        .foregroundStyle(color)
      VStack(alignment: .leading, spacing: 2) {
        Text(spotlight.title)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        Text(spotlight.detail)
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.58))
          .lineLimit(2)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
    .overlay {
      RoundedRectangle(cornerRadius: 7)
        .stroke(color.opacity(0.22))
    }
    .accessibilityElement(children: .combine)
  }

  private var color: Color {
    switch spotlight.tone {
    case .neutral:
      return .white.opacity(0.68)
    case .ready:
      return Color(red: 0.88, green: 0.72, blue: 0.38)
    case .warning:
      return Color(red: 0.95, green: 0.72, blue: 0.32)
    case .danger:
      return Color(red: 0.94, green: 0.39, blue: 0.32)
    }
  }
}

private struct CopyWorldAtlasButton: View {
  var payload: WorldAtlasClipboardPayload
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
      Label(copied ? "Copied" : "Copy World", systemImage: copied ? "checkmark" : "doc.on.doc")
        .labelStyle(.iconOnly)
    }
    .buttonStyle(.bordered)
    .controlSize(.mini)
    .disabled(payload.isEmpty)
    .help("Copy a bounded World Atlas handoff for another model or teammate.")
    .accessibilityLabel(copied ? "Copied World Atlas" : "Copy World Atlas")
  }
}

struct WorldMiniMap: View {
  let graph: WorldGraph
  let selectedNodeID: String?
  let route: [String]
  let onSelect: (String) -> Void

  var body: some View {
    GeometryReader { proxy in
      Canvas { context, size in
        let points = projectedPoints(in: size)
        let routeSet = Set(route)

        for edge in graph.edges where edge.kind != .imports {
          guard let a = points[edge.sourceID], let b = points[edge.targetID] else { continue }
          var path = Path()
          path.move(to: a)
          path.addLine(to: b)
          let highlighted = routeSet.contains(edge.sourceID) && routeSet.contains(edge.targetID)
          context.stroke(
            path,
            with: .color(highlighted ? .yellow.opacity(0.62) : .white.opacity(0.08)),
            lineWidth: highlighted ? 1.25 : 0.65
          )
        }

        for node in graph.nodes {
          guard let point = points[node.id] else { continue }
          let radius: CGFloat = node.id == selectedNodeID ? 3.8 : 2.2
          let rect = CGRect(
            x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
          context.fill(
            Path(ellipseIn: rect),
            with: .color(routeSet.contains(node.id) ? .yellow.opacity(0.9) : .white.opacity(0.46))
          )
        }
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onEnded { value in
            let points = projectedPoints(in: proxy.size)
            if let id = nearestNodeID(to: value.location, in: points) {
              onSelect(id)
            }
          }
      )
    }
    .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(.white.opacity(0.09), lineWidth: 1)
    )
  }

  private func projectedPoints(in size: CGSize) -> [String: CGPoint] {
    guard !graph.nodes.isEmpty else { return [:] }
    let xs = graph.nodes.map { CGFloat($0.position.x) }
    let zs = graph.nodes.map { CGFloat($0.position.z) }
    let minX = xs.min() ?? 0
    let maxX = xs.max() ?? 1
    let minZ = zs.min() ?? 0
    let maxZ = zs.max() ?? 1
    let xSpan = max(maxX - minX, 1)
    let zSpan = max(maxZ - minZ, 1)
    let inset: CGFloat = 16

    return Dictionary(
      uniqueKeysWithValues: graph.nodes.map { node in
        let x = inset + ((CGFloat(node.position.x) - minX) / xSpan) * max(1, size.width - inset * 2)
        let y =
          inset + ((CGFloat(node.position.z) - minZ) / zSpan) * max(1, size.height - inset * 2)
        return (node.id, CGPoint(x: x, y: y))
      })
  }

  private func nearestNodeID(to point: CGPoint, in points: [String: CGPoint]) -> String? {
    points.min { lhs, rhs in
      distanceSquared(lhs.value, point) < distanceSquared(rhs.value, point)
    }?.key
  }

  private func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return dx * dx + dy * dy
  }
}

struct WorldRealitySceneView: View {
  let graph: WorldGraph
  let selectedNodeID: String?
  let route: [String]
  let routeIndex: Int

  var body: some View {
    RealityView { content in
      content.camera = .virtual
      content.environment = .default
      content.add(
        WorldRealitySceneFactory.makeScene(
          graph: graph,
          selectedNodeID: selectedNodeID,
          route: route,
          routeIndex: routeIndex
        )
      )
    } update: { content in
      content.entities.removeAll()
      content.camera = .virtual
      content.add(
        WorldRealitySceneFactory.makeScene(
          graph: graph,
          selectedNodeID: selectedNodeID,
          route: route,
          routeIndex: routeIndex
        )
      )
    } placeholder: {
      ProgressView()
    }
  }
}

@MainActor
enum WorldRealitySceneFactory {
  private static let maxSceneNodes = 450
  private static let maxSceneEdges = 90

  private struct SceneBounds {
    var minX: Float
    var maxX: Float
    var minZ: Float
    var maxZ: Float

    var center: SIMD3<Float> {
      SIMD3<Float>((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
    }

    var width: Float {
      max(maxX - minX, 12)
    }

    var depth: Float {
      max(maxZ - minZ, 18)
    }
  }

  static func makeScene(
    graph: WorldGraph,
    selectedNodeID: String?,
    route: [String],
    routeIndex: Int
  ) -> Entity {
    let root = Entity()
    root.name = "CompassWorldRoot"

    let routePrefix = Array(route.prefix(min(routeIndex + 1, route.count)))
    let routeSet = Set(routePrefix)
    let fullRouteSet = Set(route)
    let currentNodeID = routePrefix.last ?? selectedNodeID
    let entrypointSet = Set(graph.entrypointIDs)
    let sceneNodes = prioritizedSceneNodes(
      in: graph,
      selectedNodeID: selectedNodeID,
      routeSet: routeSet
    )
    let bounds = sceneBounds(for: sceneNodes)
    let visibleNodeIDs = Set(sceneNodes.map(\.id))
    let lookup = Dictionary(uniqueKeysWithValues: sceneNodes.map { ($0.id, $0) })
    let currentPosition =
      currentNodeID.flatMap { lookup[$0]?.position.simd }
      ?? selectedNodeID.flatMap { lookup[$0]?.position.simd }
      ?? bounds.center
    let sceneEdges = prioritizedSceneEdges(
      graph.edges.filter { edge in
        edge.kind != .imports
          && visibleNodeIDs.contains(edge.sourceID)
          && visibleNodeIDs.contains(edge.targetID)
      },
      selectedNodeID: selectedNodeID,
      currentNodeID: currentNodeID,
      routeSet: routeSet,
      fullRouteSet: fullRouteSet
    )

    addCinematicStage(to: root, bounds: bounds, focus: currentPosition)
    addLights(to: root, bounds: bounds, focus: currentPosition)

    for edge in sceneEdges {
      guard let source = lookup[edge.sourceID], let target = lookup[edge.targetID] else { continue }
      root.addChild(
        corridorEntity(
          from: source.position.simd,
          to: target.position.simd,
          kind: edge.kind,
          highlighted: routeSet.contains(edge.sourceID) && routeSet.contains(edge.targetID)
        )
      )
    }

    for node in sceneNodes {
      let active = routePrefix.last == node.id
      let selected = selectedNodeID == node.id
      let inRoute = routeSet.contains(node.id)
      let showLabel =
        active || selected || entrypointSet.contains(node.id)
        || (inRoute && ![WorldNodeKind.module, .file, .type].contains(node.kind))
      root.addChild(
        chamberEntity(
          for: node,
          active: active,
          selected: selected,
          inRoute: inRoute,
          showLabel: showLabel
        )
      )
      if let routeStepIndex = routePrefix.firstIndex(of: node.id) {
        root.addChild(
          routeBeaconEntity(
            for: node,
            step: routeStepIndex + 1,
            active: active
          )
        )
      }
    }

    let camera = PerspectiveCamera()
    camera.name = "WorldCamera"
    let cameraPose = cameraPose(
      focus: currentPosition,
      route: route,
      routeIndex: routeIndex,
      lookup: graph.nodeByID,
      bounds: bounds
    )
    camera.look(at: cameraPose.target, from: cameraPose.eye, relativeTo: nil)
    root.addChild(camera)

    return root
  }

  private static func prioritizedSceneNodes(
    in graph: WorldGraph,
    selectedNodeID: String?,
    routeSet: Set<String>
  ) -> [WorldNode] {
    guard graph.nodes.count > maxSceneNodes else { return graph.nodes }
    let entrypointSet = Set(graph.entrypointIDs)
    return Array(
      graph.nodes.sorted { lhs, rhs in
        let lhsScore = sceneNodeScore(
          lhs,
          selectedNodeID: selectedNodeID,
          routeSet: routeSet,
          entrypointSet: entrypointSet
        )
        let rhsScore = sceneNodeScore(
          rhs,
          selectedNodeID: selectedNodeID,
          routeSet: routeSet,
          entrypointSet: entrypointSet
        )
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.id < rhs.id
      }.prefix(maxSceneNodes)
    )
  }

  private static func prioritizedSceneEdges(
    _ edges: [WorldEdge],
    selectedNodeID: String?,
    currentNodeID: String?,
    routeSet: Set<String>,
    fullRouteSet: Set<String>
  ) -> [WorldEdge] {
    return Array(
      edges.sorted { lhs, rhs in
        let lhsScore = sceneEdgeScore(
          lhs,
          selectedNodeID: selectedNodeID,
          currentNodeID: currentNodeID,
          routeSet: routeSet,
          fullRouteSet: fullRouteSet
        )
        let rhsScore = sceneEdgeScore(
          rhs,
          selectedNodeID: selectedNodeID,
          currentNodeID: currentNodeID,
          routeSet: routeSet,
          fullRouteSet: fullRouteSet
        )
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        if lhs.sourceID != rhs.sourceID { return lhs.sourceID < rhs.sourceID }
        return lhs.targetID < rhs.targetID
      }.prefix(maxSceneEdges)
    )
  }

  private static func sceneNodeScore(
    _ node: WorldNode,
    selectedNodeID: String?,
    routeSet: Set<String>,
    entrypointSet: Set<String>
  ) -> Int {
    var score = 0
    if node.id == selectedNodeID { score += 10_000 }
    if routeSet.contains(node.id) { score += 8_000 }
    if entrypointSet.contains(node.id) { score += 7_000 }
    switch node.kind {
    case .function: score += 600
    case .branch, .loop, .switchCase, .errorPath: score += 520
    case .file: score += 420
    case .module: score += 360
    case .unresolvedPassage: score += 300
    case .type: score += 180
    }
    return score
  }

  private static func sceneEdgeScore(
    _ edge: WorldEdge,
    selectedNodeID: String?,
    currentNodeID: String?,
    routeSet: Set<String>,
    fullRouteSet: Set<String>
  ) -> Int {
    var score = 0
    if routeSet.contains(edge.sourceID), routeSet.contains(edge.targetID) { score += 10_000 }
    if fullRouteSet.contains(edge.sourceID), fullRouteSet.contains(edge.targetID) { score += 7_000 }
    if edge.sourceID == currentNodeID || edge.targetID == currentNodeID { score += 3_200 }
    if edge.sourceID == selectedNodeID || edge.targetID == selectedNodeID { score += 2_600 }
    switch edge.confidence {
    case .high: score += 180
    case .medium: score += 90
    case .low: score -= 80
    }
    switch edge.kind {
    case .branches, .loops, .calls, .`throws`: score += 600
    case .contains: score += 260
    case .returns: score += 160
    case .imports: score += 0
    }
    return score
  }

  private static func sceneBounds(for nodes: [WorldNode]) -> SceneBounds {
    guard let first = nodes.first else {
      return SceneBounds(minX: -6, maxX: 6, minZ: -16, maxZ: 4)
    }

    var minX = first.position.x
    var maxX = first.position.x
    var minZ = first.position.z
    var maxZ = first.position.z
    for node in nodes.dropFirst() {
      minX = min(minX, node.position.x)
      maxX = max(maxX, node.position.x)
      minZ = min(minZ, node.position.z)
      maxZ = max(maxZ, node.position.z)
    }
    return SceneBounds(
      minX: minX - 3.5,
      maxX: maxX + 3.5,
      minZ: minZ - 5,
      maxZ: maxZ + 5
    )
  }

  private static func addCinematicStage(
    to root: Entity,
    bounds: SceneBounds,
    focus: SIMD3<Float>
  ) {
    let stageWidth = bounds.width + 14
    let stageDepth = bounds.depth + 18
    let stageCenter = SIMD3<Float>(bounds.center.x, -0.22, bounds.center.z - 1.5)
    let terrainMaterial = SimpleMaterial(
      color: NSColor(calibratedRed: 0.075, green: 0.068, blue: 0.058, alpha: 1),
      roughness: 0.98,
      isMetallic: false
    )
    let terrain = ModelEntity(
      mesh: .generateBox(width: stageWidth, height: 0.12, depth: stageDepth),
      materials: [terrainMaterial]
    )
    terrain.name = "WorldTerrainPlate"
    terrain.position = stageCenter
    root.addChild(terrain)

    let lowerShelf = ModelEntity(
      mesh: .generateBox(width: stageWidth + 1.6, height: 0.18, depth: stageDepth + 1.6),
      materials: [
        SimpleMaterial(
          color: NSColor(calibratedRed: 0.028, green: 0.028, blue: 0.032, alpha: 1),
          roughness: 0.9,
          isMetallic: false
        )
      ]
    )
    lowerShelf.name = "WorldTerrainShadowShelf"
    lowerShelf.position = stageCenter + SIMD3<Float>(0, -0.16, 0)
    root.addChild(lowerShelf)

    let minX = stageCenter.x - stageWidth / 2
    let minZ = stageCenter.z - stageDepth / 2
    let gridMaterial = UnlitMaterial(
      color: NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.34, alpha: 0.13)
    )
    for index in 0...8 {
      let t = Float(index) / 8
      let x = minX + stageWidth * t
      let strip = ModelEntity(
        mesh: .generateBox(width: 0.018, height: 0.014, depth: stageDepth),
        materials: [gridMaterial]
      )
      strip.name = "WorldTerrainGridX-\(index)"
      strip.position = SIMD3<Float>(x, -0.145, stageCenter.z)
      root.addChild(strip)
    }
    for index in 0...10 {
      let t = Float(index) / 10
      let z = minZ + stageDepth * t
      let strip = ModelEntity(
        mesh: .generateBox(width: stageWidth, height: 0.014, depth: 0.018),
        materials: [gridMaterial]
      )
      strip.name = "WorldTerrainGridZ-\(index)"
      strip.position = SIMD3<Float>(stageCenter.x, -0.144, z)
      root.addChild(strip)
    }

    let backdrop = ModelEntity(
      mesh: .generateBox(width: stageWidth + 5, height: 8.5, depth: 0.18),
      materials: [
        UnlitMaterial(
          color: NSColor(calibratedRed: 0.025, green: 0.03, blue: 0.038, alpha: 0.9)
        )
      ]
    )
    backdrop.name = "WorldSkyVault"
    backdrop.position = SIMD3<Float>(stageCenter.x, 3.6, minZ - 2.4)
    root.addChild(backdrop)

    let horizonGlow = ModelEntity(
      mesh: .generateBox(width: stageWidth + 4, height: 0.12, depth: 0.2),
      materials: [
        UnlitMaterial(
          color: NSColor(calibratedRed: 0.94, green: 0.53, blue: 0.26, alpha: 0.34)
        )
      ]
    )
    horizonGlow.name = "WorldHorizonGlow"
    horizonGlow.position = SIMD3<Float>(stageCenter.x, 0.18, minZ - 2.22)
    root.addChild(horizonGlow)

    let sideMaterial = SimpleMaterial(
      color: NSColor(calibratedRed: 0.045, green: 0.048, blue: 0.052, alpha: 1),
      roughness: 0.88,
      isMetallic: false
    )
    for side in [-1.0 as Float, 1.0 as Float] {
      let wall = ModelEntity(
        mesh: .generateBox(width: 0.4, height: 1.1, depth: stageDepth),
        materials: [sideMaterial]
      )
      wall.name = side < 0 ? "WorldLeftCanyonWall" : "WorldRightCanyonWall"
      wall.position = SIMD3<Float>(
        stageCenter.x + side * (stageWidth / 2 + 0.35), 0.32, stageCenter.z)
      root.addChild(wall)
    }

    let towerXOffsets: [Float] = [-0.42, -0.22, 0.0, 0.24, 0.46]
    for (index, offset) in towerXOffsets.enumerated() {
      let height = Float(index % 3) * 0.55 + 1.25
      let tower = ModelEntity(
        mesh: .generateBox(width: 0.34, height: height, depth: 0.34, cornerRadius: 0.035),
        materials: [
          SimpleMaterial(
            color: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.13, alpha: 0.96),
            roughness: 0.72,
            isMetallic: true
          )
        ]
      )
      tower.name = "WorldDistantShard-\(index)"
      tower.position = SIMD3<Float>(
        stageCenter.x + offset * stageWidth,
        height / 2 - 0.05,
        minZ + Float(index % 2) * 1.7
      )
      root.addChild(tower)
    }

    let focusPool = ModelEntity(
      mesh: .generateCylinder(height: 0.018, radius: 1.24),
      materials: [
        UnlitMaterial(
          color: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.22, alpha: 0.18)
        )
      ]
    )
    focusPool.name = "WorldFocusLightPool"
    focusPool.position = SIMD3<Float>(focus.x, -0.075, focus.z)
    root.addChild(focusPool)
  }

  private static func cameraPose(
    focus: SIMD3<Float>,
    route: [String],
    routeIndex: Int,
    lookup: [String: WorldNode],
    bounds: SceneBounds
  ) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
    let safeIndex = route.isEmpty ? 0 : min(max(routeIndex, 0), route.count - 1)
    let nextIndex = route.isEmpty ? 0 : min(safeIndex + 1, route.count - 1)
    let nextPosition =
      route.indices.contains(nextIndex)
      ? lookup[route[nextIndex]]?.position.simd ?? bounds.center
      : bounds.center
    var direction = nextPosition - focus
    direction.y = 0
    if simd_length(direction) < 0.1 {
      direction = SIMD3<Float>(0, 0, -1)
    }
    direction = simd_normalize(direction)
    let right = simd_normalize(SIMD3<Float>(-direction.z, 0, direction.x))
    let eye = focus - direction * 14 + right * 5.2 + SIMD3<Float>(0, 6.2, 0)
    let target = focus + direction * 1.6 + SIMD3<Float>(0, 0.82, 0)
    return (eye, target)
  }

  private static func addLights(
    to root: Entity,
    bounds: SceneBounds,
    focus: SIMD3<Float>
  ) {
    let key = DirectionalLight()
    key.name = "WorldKeyLight"
    key.light = DirectionalLightComponent(
      color: NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.54, alpha: 1),
      intensity: 3200
    )
    key.look(
      at: focus,
      from: focus + SIMD3<Float>(-5.2, 7.4, 4.5),
      relativeTo: nil
    )
    root.addChild(key)

    let rim = DirectionalLight()
    rim.name = "WorldRimLight"
    rim.light = DirectionalLightComponent(
      color: NSColor(calibratedRed: 0.42, green: 0.72, blue: 1.0, alpha: 1),
      intensity: 1150
    )
    rim.look(
      at: bounds.center,
      from: bounds.center + SIMD3<Float>(4, 5, -7),
      relativeTo: nil
    )
    root.addChild(rim)

    let lantern = PointLight()
    lantern.name = "WorldLantern"
    lantern.light = PointLightComponent(
      color: NSColor(calibratedRed: 1.0, green: 0.73, blue: 0.31, alpha: 1),
      intensity: 24_000,
      attenuationRadius: 20
    )
    lantern.position = focus + SIMD3<Float>(0, 2.4, 1.2)
    root.addChild(lantern)

    let ambientBeacon = PointLight()
    ambientBeacon.name = "WorldAmbientBeacon"
    ambientBeacon.light = PointLightComponent(
      color: NSColor(calibratedRed: 0.38, green: 0.72, blue: 0.92, alpha: 1),
      intensity: 8_000,
      attenuationRadius: max(bounds.width, bounds.depth) * 0.7
    )
    ambientBeacon.position = bounds.center + SIMD3<Float>(0, 4.4, 0)
    root.addChild(ambientBeacon)
  }

  private static func chamberEntity(
    for node: WorldNode,
    active: Bool,
    selected: Bool,
    inRoute: Bool,
    showLabel: Bool
  ) -> Entity {
    let group = Entity()
    group.name = node.id
    let position = node.position.simd

    let anchor = SIMD3<Float>(position.x, -0.055, position.z)
    let auraRadius: Float = active || selected ? 0.82 : (inRoute ? 0.62 : 0.42)
    let aura = ModelEntity(
      mesh: .generateCylinder(height: 0.018, radius: auraRadius),
      materials: [
        UnlitMaterial(
          color: color(
            for: node.kind,
            alpha: active || selected ? 0.3 : (inRoute ? 0.18 : 0.08)
          )
        )
      ]
    )
    aura.name = "WorldChamberLightWell-\(node.id)"
    aura.position = anchor
    group.addChild(aura)

    let plinth = ModelEntity(
      mesh: .generateCylinder(
        height: active || selected ? 0.18 : 0.12, radius: baseRadius(for: node.kind)),
      materials: [
        SimpleMaterial(
          color: NSColor(calibratedRed: 0.09, green: 0.085, blue: 0.074, alpha: 1),
          roughness: 0.78,
          isMetallic: true
        )
      ]
    )
    plinth.name = "WorldChamberPlinth-\(node.id)"
    plinth.position = anchor + SIMD3<Float>(0, 0.075, 0)
    group.addChild(plinth)

    let columnHeight = max(0.18, position.y - 0.05)
    let lightColumn = ModelEntity(
      mesh: .generateBox(width: 0.032, height: columnHeight, depth: 0.032),
      materials: [
        UnlitMaterial(
          color: color(
            for: node.kind,
            alpha: active || selected ? 0.42 : (inRoute ? 0.24 : 0.1)
          )
        )
      ]
    )
    lightColumn.name = "WorldChamberLightColumn-\(node.id)"
    lightColumn.position = SIMD3<Float>(position.x, columnHeight / 2, position.z)
    group.addChild(lightColumn)

    let mesh = mesh(for: node.kind, active: active || selected)
    let material = material(for: node.kind, active: active, selected: selected, inRoute: inRoute)
    let model = ModelEntity(mesh: mesh, materials: [material])
    model.position = position
    model.name = "WorldChamberBody-\(node.id)"
    model.components.set(InputTargetComponent())
    model.components.set(
      CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3<Float>(1, 1, 1))]))
    group.addChild(model)

    addChamberAccents(
      to: group,
      node: node,
      position: position,
      active: active,
      selected: selected,
      inRoute: inRoute
    )

    if active || selected {
      let glow = ModelEntity(
        mesh: .generateCylinder(height: 0.024, radius: active ? 0.72 : 0.56),
        materials: [
          UnlitMaterial(
            color: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.28, alpha: 0.2)
          )
        ]
      )
      glow.name = "WorldChamberHalo-\(node.id)"
      glow.position = SIMD3<Float>(position.x, max(0.04, position.y - 0.36), position.z)
      group.addChild(glow)
    }

    if showLabel {
      let label = labelEntity(node.label, position: position + SIMD3<Float>(-0.42, 0.72, 0))
      group.addChild(label)
    }

    return group
  }

  private static func addChamberAccents(
    to group: Entity,
    node: WorldNode,
    position: SIMD3<Float>,
    active: Bool,
    selected: Bool,
    inRoute: Bool
  ) {
    let accent = color(for: node.kind, alpha: active || selected ? 0.86 : (inRoute ? 0.52 : 0.28))
    let glow = color(for: node.kind, alpha: active || selected ? 0.42 : 0.2)

    switch node.kind {
    case .module:
      let slab = ModelEntity(
        mesh: .generateBox(width: 1.9, height: 0.08, depth: 1.45, cornerRadius: 0.03),
        materials: [
          SimpleMaterial(color: accent.withAlphaComponent(0.38), roughness: 0.64, isMetallic: true)
        ]
      )
      slab.name = "WorldModuleDistrict-\(node.id)"
      slab.position = SIMD3<Float>(position.x, 0.12, position.z)
      group.addChild(slab)

    case .file:
      for index in 0..<3 {
        let panel = ModelEntity(
          mesh: .generateBox(width: 0.72, height: 0.035, depth: 0.5, cornerRadius: 0.018),
          materials: [
            SimpleMaterial(color: accent.withAlphaComponent(0.5), roughness: 0.46, isMetallic: true)
          ]
        )
        panel.name = "WorldFileSlate-\(node.id)-\(index)"
        panel.position =
          position
          + SIMD3<Float>(
            0.05 * Float(index - 1), -0.02 + Float(index) * 0.075, -0.08 * Float(index + 1))
        group.addChild(panel)
      }

    case .type:
      for side in [-1.0 as Float, 1.0 as Float] {
        let fin = ModelEntity(
          mesh: .generateBox(width: 0.055, height: 0.78, depth: 0.46, cornerRadius: 0.012),
          materials: [
            UnlitMaterial(color: glow)
          ]
        )
        fin.name = side < 0 ? "WorldTypeLeftFin-\(node.id)" : "WorldTypeRightFin-\(node.id)"
        fin.position = position + SIMD3<Float>(side * 0.48, 0.04, 0)
        group.addChild(fin)
      }

    case .function:
      let offsets: [SIMD3<Float>] = [
        SIMD3<Float>(0.48, 0.14, 0),
        SIMD3<Float>(-0.34, 0.1, 0.38),
        SIMD3<Float>(-0.22, -0.06, -0.42),
      ]
      for (index, offset) in offsets.enumerated() {
        let mote = ModelEntity(
          mesh: .generateSphere(radius: active || selected ? 0.07 : 0.052),
          materials: [UnlitMaterial(color: glow)]
        )
        mote.name = "WorldFunctionMote-\(node.id)-\(index)"
        mote.position = position + offset
        group.addChild(mote)
      }

    case .branch:
      for side in [-1.0 as Float, 1.0 as Float] {
        let jamb = ModelEntity(
          mesh: .generateBox(width: 0.08, height: 0.82, depth: 0.12, cornerRadius: 0.015),
          materials: [UnlitMaterial(color: glow)]
        )
        jamb.name = side < 0 ? "WorldBranchLeftGate-\(node.id)" : "WorldBranchRightGate-\(node.id)"
        jamb.position = position + SIMD3<Float>(side * 0.46, 0.08, 0)
        group.addChild(jamb)
      }
      let lintel = ModelEntity(
        mesh: .generateBox(width: 1.0, height: 0.08, depth: 0.14, cornerRadius: 0.015),
        materials: [UnlitMaterial(color: glow)]
      )
      lintel.name = "WorldBranchGateLintel-\(node.id)"
      lintel.position = position + SIMD3<Float>(0, 0.52, 0)
      group.addChild(lintel)

    case .loop:
      let loopOffsets: [SIMD3<Float>] = [
        SIMD3<Float>(0.43, 0.04, 0),
        SIMD3<Float>(0, 0.04, 0.43),
        SIMD3<Float>(-0.43, 0.04, 0),
        SIMD3<Float>(0, 0.04, -0.43),
      ]
      for (index, offset) in loopOffsets.enumerated() {
        let marker = ModelEntity(
          mesh: .generateCylinder(height: 0.045, radius: 0.075),
          materials: [UnlitMaterial(color: glow)]
        )
        marker.name = "WorldLoopOrbit-\(node.id)-\(index)"
        marker.position = position + offset
        group.addChild(marker)
      }

    case .switchCase:
      for index in 0..<3 {
        let shard = ModelEntity(
          mesh: .generateBox(width: 0.11, height: 0.58, depth: 0.11, cornerRadius: 0.018),
          materials: [SimpleMaterial(color: accent, roughness: 0.36, isMetallic: true)]
        )
        shard.name = "WorldSwitchShard-\(node.id)-\(index)"
        shard.position = position + SIMD3<Float>((Float(index) - 1) * 0.34, 0.08, -0.2)
        group.addChild(shard)
      }

    case .errorPath:
      let flare = ModelEntity(
        mesh: .generateBox(width: 0.18, height: 1.05, depth: 0.18, cornerRadius: 0.02),
        materials: [
          UnlitMaterial(
            color: NSColor(
              calibratedRed: 1.0, green: 0.22, blue: 0.12, alpha: active || selected ? 0.62 : 0.34)
          )
        ]
      )
      flare.name = "WorldErrorFlare-\(node.id)"
      flare.position = position + SIMD3<Float>(0, 0.18, 0)
      group.addChild(flare)

    case .unresolvedPassage:
      let veil = ModelEntity(
        mesh: .generateBox(width: 0.95, height: 0.02, depth: 0.95, cornerRadius: 0.04),
        materials: [
          UnlitMaterial(
            color: NSColor(calibratedRed: 0.58, green: 0.62, blue: 0.68, alpha: 0.18)
          )
        ]
      )
      veil.name = "WorldUnknownVeil-\(node.id)"
      veil.position = position + SIMD3<Float>(0, -0.18, 0)
      group.addChild(veil)
    }
  }

  private static func corridorEntity(
    from source: SIMD3<Float>,
    to target: SIMD3<Float>,
    kind: WorldEdgeKind,
    highlighted: Bool
  ) -> Entity {
    let group = Entity()
    group.name = highlighted ? "WorldRouteRibbon" : "WorldAtmosphericCorridor"
    let start = source + SIMD3<Float>(0, -0.18, 0)
    let end = target + SIMD3<Float>(0, -0.18, 0)
    let delta = end - start
    let length = max(simd_length(delta), 0.08)
    let midpoint = (start + end) / 2
    if highlighted {
      let underlay = ModelEntity(
        mesh: .generateBox(width: 0.24, height: 0.016, depth: length),
        materials: [
          UnlitMaterial(
            color: NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.22, alpha: 0.18)
          )
        ]
      )
      underlay.name = "WorldRouteGlow"
      underlay.look(at: end, from: midpoint + SIMD3<Float>(0, -0.012, 0), relativeTo: nil)
      group.addChild(underlay)
    }

    let railWidth: Float = highlighted ? 0.075 : 0.012
    let railColor =
      highlighted
      ? NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.24, alpha: 1)
      : color(for: kind, alpha: 0.12)
    let rail = ModelEntity(
      mesh: .generateBox(width: railWidth, height: highlighted ? 0.032 : 0.01, depth: length),
      materials: [
        SimpleMaterial(
          color: railColor,
          roughness: highlighted ? 0.28 : 0.86,
          isMetallic: highlighted
        )
      ]
    )
    rail.name = highlighted ? "WorldRouteCore" : "WorldCorridorCore"
    rail.look(at: end, from: midpoint, relativeTo: nil)
    group.addChild(rail)

    if highlighted, length > 1.2 {
      for fraction in [0.25 as Float, 0.5 as Float, 0.75 as Float] {
        let bead = ModelEntity(
          mesh: .generateSphere(radius: 0.055),
          materials: [
            UnlitMaterial(
              color: NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.36, alpha: 0.82)
            )
          ]
        )
        bead.name = "WorldRouteLightPulse"
        bead.position = start + delta * fraction + SIMD3<Float>(0, 0.08, 0)
        group.addChild(bead)
      }
    }

    return group
  }

  private static func routeBeaconEntity(
    for node: WorldNode,
    step: Int,
    active: Bool
  ) -> Entity {
    let group = Entity()
    group.name = "WorldRouteBeacon-\(node.id)"
    let position = node.position.simd
    let color =
      active
      ? NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.25, alpha: 1)
      : NSColor(calibratedRed: 0.96, green: 0.68, blue: 0.28, alpha: 0.78)
    let height: Float = active ? 0.62 : 0.42

    let stem = ModelEntity(
      mesh: .generateBox(width: 0.04, height: height, depth: 0.04),
      materials: [UnlitMaterial(color: color.withAlphaComponent(active ? 0.72 : 0.5))]
    )
    stem.name = "WorldRouteBeaconStem-\(node.id)"
    stem.position = position + SIMD3<Float>(0, 0.36 + height / 2, 0)
    group.addChild(stem)

    let marker = ModelEntity(
      mesh: .generateCylinder(height: 0.055, radius: active ? 0.23 : 0.17),
      materials: [UnlitMaterial(color: color)]
    )
    marker.name =
      active ? "WorldRouteBeaconActive-\(node.id)" : "WorldRouteBeaconVisited-\(node.id)"
    marker.position = position + SIMD3<Float>(0, 0.78 + height, 0)
    group.addChild(marker)

    let stepLabel = ModelEntity(
      mesh: .generateText(
        "\(step)",
        extrusionDepth: 0.004,
        font: .monospacedDigitSystemFont(ofSize: active ? 0.17 : 0.13, weight: .bold)
      ),
      materials: [
        UnlitMaterial(
          color: NSColor(calibratedRed: 0.12, green: 0.085, blue: 0.035, alpha: 0.95)
        )
      ]
    )
    stepLabel.name = "WorldRouteBeaconStep-\(step)"
    stepLabel.position = marker.position + SIMD3<Float>(active ? -0.045 : -0.035, 0.04, -0.04)
    group.addChild(stepLabel)

    let halo = ModelEntity(
      mesh: .generateCylinder(height: 0.018, radius: active ? 0.64 : 0.42),
      materials: [
        UnlitMaterial(
          color: color.withAlphaComponent(active ? 0.22 : 0.12)
        )
      ]
    )
    halo.name = active ? "WorldRoutePortalActive-\(node.id)" : "WorldRoutePortalVisited-\(node.id)"
    halo.position = position + SIMD3<Float>(0, -0.035, 0)
    group.addChild(halo)

    if active {
      for side in [-1.0 as Float, 1.0 as Float] {
        let post = ModelEntity(
          mesh: .generateBox(width: 0.06, height: 1.05, depth: 0.06, cornerRadius: 0.012),
          materials: [UnlitMaterial(color: color.withAlphaComponent(0.58))]
        )
        post.name =
          side < 0 ? "WorldRoutePortalLeftPost-\(node.id)" : "WorldRoutePortalRightPost-\(node.id)"
        post.position = position + SIMD3<Float>(side * 0.46, 0.58, -0.16)
        group.addChild(post)
      }

      let header = ModelEntity(
        mesh: .generateBox(width: 1.0, height: 0.06, depth: 0.06, cornerRadius: 0.012),
        materials: [UnlitMaterial(color: color.withAlphaComponent(0.58))]
      )
      header.name = "WorldRoutePortalHeader-\(node.id)"
      header.position = position + SIMD3<Float>(0, 1.1, -0.16)
      group.addChild(header)
    }

    return group
  }

  private static func labelEntity(_ text: String, position: SIMD3<Float>) -> Entity {
    let clean = String(text.prefix(28))
    let entity = ModelEntity(
      mesh: .generateText(
        clean,
        extrusionDepth: 0.006,
        font: .monospacedSystemFont(ofSize: 0.18, weight: .medium)
      ),
      materials: [
        UnlitMaterial(
          color: NSColor(calibratedRed: 0.92, green: 0.86, blue: 0.72, alpha: 0.95)
        )
      ]
    )
    entity.position = position
    return entity
  }

  private static func baseRadius(for kind: WorldNodeKind) -> Float {
    switch kind {
    case .module: return 0.92
    case .file: return 0.58
    case .type: return 0.52
    case .function: return 0.48
    case .branch: return 0.58
    case .loop: return 0.54
    case .switchCase: return 0.56
    case .errorPath: return 0.52
    case .unresolvedPassage: return 0.5
    }
  }

  private static func mesh(for kind: WorldNodeKind, active: Bool) -> MeshResource {
    let scale: Float = active ? 1.08 : 1
    switch kind {
    case .module:
      return .generateBox(
        width: 1.55 * scale, height: 0.34 * scale, depth: 1.25 * scale, cornerRadius: 0.045)
    case .file:
      return .generateBox(
        width: 0.92 * scale, height: 0.22 * scale, depth: 0.7 * scale, cornerRadius: 0.03)
    case .type:
      return .generateBox(
        width: 0.68 * scale, height: 0.78 * scale, depth: 0.68 * scale, cornerRadius: 0.065)
    case .function:
      return .generateSphere(radius: 0.34 * scale)
    case .branch:
      return .generateBox(
        width: 0.78 * scale, height: 0.72 * scale, depth: 0.24 * scale, cornerRadius: 0.045)
    case .loop:
      return .generateCylinder(height: 0.54 * scale, radius: 0.34 * scale)
    case .switchCase:
      return .generateSphere(radius: 0.38 * scale)
    case .errorPath:
      return .generateBox(
        width: 0.66 * scale, height: 0.82 * scale, depth: 0.66 * scale, cornerRadius: 0.02)
    case .unresolvedPassage:
      return .generateBox(
        width: 0.62 * scale, height: 0.42 * scale, depth: 0.62 * scale, cornerRadius: 0.08)
    }
  }

  private static func material(
    for kind: WorldNodeKind,
    active: Bool,
    selected: Bool,
    inRoute: Bool
  ) -> SimpleMaterial {
    let color = color(
      for: kind,
      alpha: active || selected ? 1 : (inRoute ? 0.92 : 0.72)
    )
    return SimpleMaterial(
      color: color,
      roughness: active || selected ? 0.24 : 0.62,
      isMetallic: active || selected
    )
  }

  private static func color(for kind: WorldNodeKind, alpha: CGFloat) -> NSColor {
    switch kind {
    case .module:
      return NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.17, alpha: alpha)
    case .file:
      return NSColor(calibratedRed: 0.22, green: 0.43, blue: 0.48, alpha: alpha)
    case .type:
      return NSColor(calibratedRed: 0.43, green: 0.55, blue: 0.28, alpha: alpha)
    case .function:
      return NSColor(calibratedRed: 0.84, green: 0.58, blue: 0.24, alpha: alpha)
    case .branch:
      return NSColor(calibratedRed: 0.72, green: 0.28, blue: 0.18, alpha: alpha)
    case .loop:
      return NSColor(calibratedRed: 0.17, green: 0.58, blue: 0.43, alpha: alpha)
    case .switchCase:
      return NSColor(calibratedRed: 0.46, green: 0.34, blue: 0.65, alpha: alpha)
    case .errorPath:
      return NSColor(calibratedRed: 0.78, green: 0.18, blue: 0.12, alpha: alpha)
    case .unresolvedPassage:
      return NSColor(calibratedRed: 0.34, green: 0.36, blue: 0.39, alpha: alpha)
    }
  }

  private static func color(for kind: WorldEdgeKind, alpha: CGFloat) -> NSColor {
    switch kind {
    case .contains:
      return NSColor(calibratedRed: 0.48, green: 0.42, blue: 0.32, alpha: alpha)
    case .imports:
      return NSColor(calibratedRed: 0.28, green: 0.39, blue: 0.46, alpha: alpha)
    case .calls:
      return NSColor(calibratedRed: 0.66, green: 0.5, blue: 0.25, alpha: alpha)
    case .branches:
      return NSColor(calibratedRed: 0.75, green: 0.32, blue: 0.22, alpha: alpha)
    case .loops:
      return NSColor(calibratedRed: 0.18, green: 0.62, blue: 0.46, alpha: alpha)
    case .returns:
      return NSColor(calibratedRed: 0.42, green: 0.45, blue: 0.5, alpha: alpha)
    case .`throws`:
      return NSColor(calibratedRed: 0.78, green: 0.2, blue: 0.16, alpha: alpha)
    }
  }
}

extension WorldPosition {
  fileprivate var simd: SIMD3<Float> {
    SIMD3<Float>(x, y, z)
  }
}

import AppKit
import RealityKit
import SwiftUI
import simd

struct WorldTab: View {
  let repoURL: URL
  let workspace: CompassWorkspace?
  let isActive: Bool
  let onOpenInExplore: (String) -> Void

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
        ZStack(alignment: .bottomLeading) {
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

          WorldMiniMap(
            graph: graph,
            selectedNodeID: model.selectedNodeID,
            route: model.route,
            onSelect: model.selectNode
          )
          .frame(width: 190, height: 150)
          .padding(14)
        }

        WorldInspectorPanel(
          model: model,
          onOpenInExplore: onOpenInExplore
        )
        .frame(width: 300)
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

  private var loadedRepoPath: String?
  private var playbackTask: Task<Void, Never>?

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
  }

  func selectEntrypoint(_ id: String?) {
    selectedEntrypointID = id
    guard let graph else { return }
    route = WorldNavigator.route(in: graph, from: id)
    routeIndex = 0
    selectedNodeID = route.first ?? id
  }

  func selectNode(_ id: String) {
    selectedNodeID = id
    if let index = route.firstIndex(of: id) {
      routeIndex = index
    }
  }

  func selectBranch(_ id: String) {
    selectedNodeID = id
    if let index = route.firstIndex(of: id) {
      routeIndex = index
    } else {
      route.insert(id, at: min(routeIndex + 1, route.count))
      routeIndex = min(routeIndex + 1, route.count - 1)
    }
  }

  func stepForward() {
    guard !route.isEmpty else { return }
    routeIndex = min(routeIndex + 1, route.count - 1)
    selectedNodeID = route[routeIndex]
  }

  func stepBackward() {
    guard !route.isEmpty else { return }
    routeIndex = max(routeIndex - 1, 0)
    selectedNodeID = route[routeIndex]
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
}

struct WorldInspectorPanel: View {
  @ObservedObject var model: WorldTabViewModel
  let onOpenInExplore: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      controls
      branchChoices
      search
      Divider().overlay(.white.opacity(0.2))
      selectedNode
      Spacer()
    }
    .padding(14)
    .foregroundStyle(.white)
    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(.white.opacity(0.14), lineWidth: 1)
    )
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
        Picker("Entry", selection: Binding(
          get: { model.selectedEntrypointID ?? graph.entrypointIDs.first },
          set: { model.selectEntrypoint($0) }
        )) {
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
            onOpenInExplore(location.filePath)
          } label: {
            Label("Open in Explore", systemImage: "arrowshape.turn.up.right")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        }

        Label(node.confidence.rawValue.capitalized, systemImage: "gauge.with.dots.needle.bottom.50percent")
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
            with: .color(highlighted ? .yellow.opacity(0.7) : .white.opacity(0.2)),
            lineWidth: highlighted ? 2 : 1
          )
        }

        for node in graph.nodes {
          guard let point = points[node.id] else { continue }
          let radius: CGFloat = node.id == selectedNodeID ? 4.5 : 2.8
          let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
          context.fill(
            Path(ellipseIn: rect),
            with: .color(routeSet.contains(node.id) ? .yellow : .white.opacity(0.72))
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
    .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(.white.opacity(0.14), lineWidth: 1)
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

    return Dictionary(uniqueKeysWithValues: graph.nodes.map { node in
      let x = inset + ((CGFloat(node.position.x) - minX) / xSpan) * max(1, size.width - inset * 2)
      let y = inset + ((CGFloat(node.position.z) - minZ) / zSpan) * max(1, size.height - inset * 2)
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
  private static let maxSceneEdges = 650

  static func makeScene(
    graph: WorldGraph,
    selectedNodeID: String?,
    route: [String],
    routeIndex: Int
  ) -> Entity {
    let root = Entity()
    root.name = "CompassWorldRoot"

    let floor = ModelEntity(
      mesh: .generatePlane(width: 28, depth: 38),
      materials: [
        SimpleMaterial(
          color: NSColor(calibratedRed: 0.06, green: 0.055, blue: 0.05, alpha: 1),
          roughness: 0.95,
          isMetallic: false
        )
      ]
    )
    floor.position = SIMD3<Float>(0, -0.08, -12)
    root.addChild(floor)

    addLights(to: root)

    let routePrefix = Array(route.prefix(min(routeIndex + 1, route.count)))
    let routeSet = Set(routePrefix)
    let entrypointSet = Set(graph.entrypointIDs)
    let sceneNodes = prioritizedSceneNodes(
      in: graph,
      selectedNodeID: selectedNodeID,
      routeSet: routeSet
    )
    let visibleNodeIDs = Set(sceneNodes.map(\.id))
    let lookup = Dictionary(uniqueKeysWithValues: sceneNodes.map { ($0.id, $0) })
    let sceneEdges = prioritizedSceneEdges(
      graph.edges.filter { edge in
        edge.kind != .imports
          && visibleNodeIDs.contains(edge.sourceID)
          && visibleNodeIDs.contains(edge.targetID)
      },
      routeSet: routeSet
    )

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
    }

    let camera = PerspectiveCamera()
    camera.name = "WorldCamera"
    camera.look(
      at: SIMD3<Float>(0, 0.6, -8),
      from: SIMD3<Float>(0, 9.5, 10),
      relativeTo: nil
    )
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

  private static func prioritizedSceneEdges(_ edges: [WorldEdge], routeSet: Set<String>) -> [WorldEdge] {
    guard edges.count > maxSceneEdges else { return edges }
    return Array(
      edges.sorted { lhs, rhs in
        let lhsScore = sceneEdgeScore(lhs, routeSet: routeSet)
        let rhsScore = sceneEdgeScore(rhs, routeSet: routeSet)
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

  private static func sceneEdgeScore(_ edge: WorldEdge, routeSet: Set<String>) -> Int {
    var score = 0
    if routeSet.contains(edge.sourceID), routeSet.contains(edge.targetID) { score += 10_000 }
    switch edge.kind {
    case .branches, .loops, .calls, .`throws`: score += 600
    case .contains: score += 260
    case .returns: score += 160
    case .imports: score += 0
    }
    return score
  }

  private static func addLights(to root: Entity) {
    let key = DirectionalLight()
    key.name = "WorldKeyLight"
    key.light = DirectionalLightComponent(
      color: NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.54, alpha: 1),
      intensity: 2400
    )
    key.look(at: SIMD3<Float>(0, 0, -8), from: SIMD3<Float>(-5, 8, 4), relativeTo: nil)
    root.addChild(key)

    let lantern = PointLight()
    lantern.name = "WorldLantern"
    lantern.light = PointLightComponent(
      color: NSColor(calibratedRed: 1.0, green: 0.73, blue: 0.31, alpha: 1),
      intensity: 18_000,
      attenuationRadius: 18
    )
    lantern.position = SIMD3<Float>(0, 2.2, 2)
    root.addChild(lantern)
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

    let mesh = mesh(for: node.kind, active: active || selected)
    let material = material(for: node.kind, active: active, selected: selected, inRoute: inRoute)
    let model = ModelEntity(mesh: mesh, materials: [material])
    model.position = position
    model.components.set(InputTargetComponent())
    model.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3<Float>(1, 1, 1))]))
    group.addChild(model)

    if active || selected {
      let glow = ModelEntity(
        mesh: .generateSphere(radius: 0.58),
        materials: [
          UnlitMaterial(
            color: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.28, alpha: 0.24)
          )
        ]
      )
      glow.position = position
      group.addChild(glow)
    }

    if showLabel {
      let label = labelEntity(node.label, position: position + SIMD3<Float>(-0.42, 0.72, 0))
      group.addChild(label)
    }

    return group
  }

  private static func corridorEntity(
    from source: SIMD3<Float>,
    to target: SIMD3<Float>,
    kind: WorldEdgeKind,
    highlighted: Bool
  ) -> Entity {
    let start = source + SIMD3<Float>(0, -0.18, 0)
    let end = target + SIMD3<Float>(0, -0.18, 0)
    let delta = end - start
    let length = max(simd_length(delta), 0.08)
    let width: Float = highlighted ? 0.09 : 0.045
    let color = highlighted
      ? NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.23, alpha: 1)
      : color(for: kind, alpha: 0.56)

    let entity = ModelEntity(
      mesh: .generateBox(width: width, height: width, depth: length),
      materials: [
        SimpleMaterial(color: color, roughness: 0.68, isMetallic: false)
      ]
    )
    let midpoint = (start + end) / 2
    entity.look(at: end, from: midpoint, relativeTo: nil)
    return entity
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

  private static func mesh(for kind: WorldNodeKind, active: Bool) -> MeshResource {
    let scale: Float = active ? 1.2 : 1
    switch kind {
    case .module:
      return .generateBox(width: 1.55 * scale, height: 0.28 * scale, depth: 1.25 * scale, cornerRadius: 0.04)
    case .file:
      return .generateBox(width: 0.9 * scale, height: 0.18 * scale, depth: 0.68 * scale, cornerRadius: 0.025)
    case .type:
      return .generateBox(width: 0.72 * scale, height: 0.52 * scale, depth: 0.72 * scale, cornerRadius: 0.06)
    case .function:
      return .generateSphere(radius: 0.34 * scale)
    case .branch:
      return .generateBox(width: 0.78 * scale, height: 0.65 * scale, depth: 0.22 * scale, cornerRadius: 0.04)
    case .loop:
      return .generateCylinder(height: 0.46 * scale, radius: 0.34 * scale)
    case .switchCase:
      return .generateSphere(radius: 0.38 * scale)
    case .errorPath:
      return .generateBox(width: 0.68 * scale, height: 0.68 * scale, depth: 0.68 * scale, cornerRadius: 0.02)
    case .unresolvedPassage:
      return .generateBox(width: 0.62 * scale, height: 0.42 * scale, depth: 0.62 * scale, cornerRadius: 0.08)
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

private extension WorldPosition {
  var simd: SIMD3<Float> {
    SIMD3<Float>(x, y, z)
  }
}

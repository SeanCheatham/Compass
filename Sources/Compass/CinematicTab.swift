import AppKit
import RealityKit
import SwiftUI

struct CinematicTabPresentationState: Equatable {}

struct CinematicTab: View {
  @ObservedObject var project: CompassProject
  @Binding var presentationState: CinematicTabPresentationState

  var body: some View {
    ZStack {
      CinematicPlaceholderScene(phase: project.phase, isActive: project.isRunning)
        .ignoresSafeArea()

      VStack {
        Spacer()
        HStack(spacing: 12) {
          Circle()
            .fill(phaseColor(project.phase))
            .frame(width: 10, height: 10)
          Text(project.repoURL.lastPathComponent)
            .font(.headline)
          Text("·")
            .foregroundStyle(.secondary)
          Text(project.phase.rawValue)
            .font(.subheadline.monospaced())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .padding(.bottom, 24)
      }
    }
  }
}

private struct CinematicPlaceholderScene: View {
  var phase: LoopPhase
  var isActive: Bool

  var body: some View {
    RealityView { content in
      let sphere = ModelEntity(
        mesh: .generateSphere(radius: 0.25),
        materials: [SimpleMaterial(color: .gray, isMetallic: false)]
      )
      content.add(sphere)

      let light = PointLight()
      light.light.intensity = 8000
      light.position = SIMD3(0.6, 0.6, 0.6)
      content.add(light)
    } update: { content in
      guard let sphere = content.entities.first as? ModelEntity else { return }
      sphere.model?.materials = [SimpleMaterial(color: nsPhaseColor(phase), isMetallic: false)]
      sphere.transform.rotation = simd_quatf(
        angle: isActive ? .pi / 4 : 0,
        axis: SIMD3(0, 1, 0)
      )
    }
  }
}

private func phaseColor(_ phase: LoopPhase) -> Color {
  switch phase {
  case .idle: return .gray
  case .planning: return .orange
  case .developing: return .cyan
  case .verifying: return .blue
  case .paused: return .yellow
  case .failed: return .red
  case .succeeded: return .green
  case .cancelled: return .secondary
  }
}

private func nsPhaseColor(_ phase: LoopPhase) -> NSColor {
  switch phase {
  case .idle: return .gray
  case .planning: return .orange
  case .developing: return .cyan
  case .verifying: return .blue
  case .paused: return .yellow
  case .failed: return .red
  case .succeeded: return .green
  case .cancelled: return .darkGray
  }
}

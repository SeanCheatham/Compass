import AppKit
import SwiftUI

struct ProductTournamentMonitorWallView: View {
  var wall: ProductTournamentMonitorWall
  var selectedTileID: String?
  var onSelectTile: (ProductTournamentMonitorTile) -> Void

  private var selectedTile: ProductTournamentMonitorTile? {
    if let selectedTileID,
      let tile = wall.tiles.first(where: { $0.id == selectedTileID })
    {
      return tile
    }
    return wall.tiles.first
  }

  private let columns = [
    GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 14, alignment: .top)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if wall.isEmpty {
        ContentUnavailableView(
          "No Monitor Footage Yet",
          systemImage: "rectangle.grid.3x2",
          description: Text(
            "Run visual verification or tournament scenario evidence to populate the monitor wall."
          )
        )
        .frame(maxWidth: .infinity, minHeight: 180)
      } else {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
          ForEach(wall.tiles) { tile in
            MonitorTileButton(
              tile: tile,
              isSelected: selectedTile?.id == tile.id,
              action: { onSelectTile(tile) }
            )
          }
        }
        if let selectedTile {
          MonitorDetailLens(tile: selectedTile)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Tournament observatory monitor wall")
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Label("Tournament Observatory", systemImage: "rectangle.grid.3x2")
        .font(.headline)
      Spacer()
      HStack(spacing: 8) {
        ObservatoryStat(
          title: "Screens",
          value: "\(wall.screenshotCount)",
          systemImage: "display",
          tone: wall.screenshotCount > 0 ? .strong : .neutral
        )
        ObservatoryStat(
          title: "Evidence",
          value: "\(wall.evidenceCount)",
          systemImage: ProductIconRole.evidence.systemImage,
          tone: wall.evidenceCount > 0 ? .progressing : .neutral
        )
        ObservatoryStat(
          title: "Visual Proof",
          value: "\(wall.sessionScreenshotCount)",
          systemImage: ProductIconRole.useProof.systemImage,
          tone: wall.sessionScreenshotCount > 0 ? .strong : .neutral
        )
      }
    }
  }
}

private struct MonitorTileButton: View {
  var tile: ProductTournamentMonitorTile
  var isSelected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 8) {
        MonitorScreen(tile: tile, isSelected: isSelected)
          .aspectRatio(1.6, contentMode: .fit)
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
              .fill(tile.tone.compassColor)
              .frame(width: 7, height: 7)
            Text(tile.title)
              .font(.caption.weight(.semibold))
              .lineLimit(1)
            Spacer(minLength: 0)
          }
          Text(tile.subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          HStack(spacing: 6) {
            Text(tile.source.label)
            Text(tile.statusLabel)
          }
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }
      }
      .padding(8)
      .background(
        Color.secondary.opacity(isSelected ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? tile.tone.compassColor.opacity(0.8) : Color.secondary.opacity(0.14))
      )
    }
    .buttonStyle(.plain)
    .help(tile.detail)
  }
}

private struct MonitorScreen: View {
  var tile: ProductTournamentMonitorTile
  var isSelected: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6)
        .fill(Color.black)
      MonitorImage(url: tile.imageURL)
      if tile.imageURL == nil {
        VStack(spacing: 7) {
          Image(systemName: tile.systemImage)
            .font(.title2.weight(.semibold))
          Text("NO SCREENSHOT")
            .font(.caption2.monospaced().weight(.semibold))
        }
        .foregroundStyle(tile.tone.compassColor)
      }
      VStack {
        HStack {
          Text(tile.statusLabel.uppercased())
            .font(.caption2.monospaced().weight(.bold))
            .foregroundStyle(tile.tone.compassColor)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.64), in: Capsule())
          Spacer()
        }
        Spacer()
      }
      .padding(7)
    }
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(isSelected ? tile.tone.compassColor : Color.white.opacity(0.18), lineWidth: 1)
    )
  }
}

private struct MonitorImage: View {
  var url: URL?
  @State private var image: NSImage?
  @State private var loadFailed = false

  var body: some View {
    Color.clear
      .overlay {
        if let image {
          Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .transition(.opacity)
        } else if loadFailed {
          VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
              .font(.callout.weight(.semibold))
            Text("IMAGE FAILED")
              .font(.caption2.monospaced().weight(.semibold))
          }
          .foregroundStyle(.yellow)
        }
      }
      .onAppear(perform: loadImage)
      .onChange(of: url?.standardizedFileURL.path) { _, _ in
        loadImage()
      }
  }

  private func loadImage() {
    guard let url else {
      image = nil
      loadFailed = false
      return
    }
    guard FileManager.default.fileExists(atPath: url.path),
      let loadedImage = NSImage(contentsOf: url),
      loadedImage.isValid
    else {
      image = nil
      loadFailed = true
      return
    }
    image = loadedImage
    loadFailed = false
  }
}

private struct MonitorDetailLens: View {
  var tile: ProductTournamentMonitorTile

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Label(tile.title, systemImage: tile.systemImage)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
        Spacer()
        Text(tileDate(tile.timestamp))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Text(tile.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          MonitorMetadataChip(text: tile.source.label, systemImage: "rectangle.grid.3x2")
          if let roundLabel = tile.roundLabel {
            MonitorMetadataChip(text: roundLabel, systemImage: ProductIconRole.advance.systemImage)
          }
          if let scenarioID = tile.scenarioID {
            MonitorMetadataChip(text: scenarioID, systemImage: ProductIconRole.workflow.systemImage)
          }
          if let personaID = tile.personaID {
            MonitorMetadataChip(text: personaID, systemImage: ProductIconRole.pain.systemImage)
          }
          if let branchLabel = tile.branchLabel {
            MonitorMetadataChip(
              text: branchLabel, systemImage: "point.3.connected.trianglepath.dotted")
          }
          if let commitLabel = tile.commitLabel {
            MonitorMetadataChip(text: commitLabel, systemImage: "number")
          }
          if let artifactPath = tile.artifactPath {
            MonitorMetadataChip(text: artifactPath, systemImage: ProductIconRole.audit.systemImage)
          }
        }
      }
      if let url = tile.imageURL {
        Button {
          NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
          Label("Reveal Screenshot", systemImage: "arrow.up.forward.square")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
  }

  private func tileDate(_ timestamp: Double) -> String {
    guard timestamp > 0 else { return "No timestamp" }
    return Date(timeIntervalSince1970: timestamp).formatted(date: .abbreviated, time: .shortened)
  }
}

private struct MonitorMetadataChip: View {
  var text: String
  var systemImage: String

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: systemImage)
        .font(.caption2.weight(.semibold))
      Text(text)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .foregroundStyle(.secondary)
    .background(Color.secondary.opacity(0.08), in: Capsule())
  }
}

private struct ObservatoryStat: View {
  var title: String
  var value: String
  var systemImage: String
  var tone: ProductSignalTone

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: systemImage)
        .font(.caption2.weight(.bold))
        .foregroundStyle(tone.compassColor)
      Text(value)
        .font(.caption.monospacedDigit().weight(.semibold))
      Text(title)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .lineLimit(1)
  }
}

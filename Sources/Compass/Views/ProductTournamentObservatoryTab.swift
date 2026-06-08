import SwiftUI

struct ProductTournamentObservatoryTab: View {
  @ObservedObject var project: CompassProject
  @State private var selectedTileID: String?

  private var monitorWall: ProductTournamentMonitorWall {
    ProductTournamentMonitorWall.build(
      config: project.productTournamentConfig,
      evidenceIndex: project.productTournamentEvidenceIndex,
      workspace: project.workspace,
      sessions: project.allSessions,
      limit: 96
    )
  }

  var body: some View {
    ScrollView {
      ProductTournamentMonitorWallView(
        wall: monitorWall,
        selectedTileID: selectedTileID,
        onSelectTile: selectTile
      )
      .padding(.horizontal, 22)
      .padding(.vertical, 18)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func selectTile(_ tile: ProductTournamentMonitorTile) {
    selectedTileID = tile.id
  }
}

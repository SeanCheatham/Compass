import SwiftUI

struct OnboardingView: View {
  @ObservedObject private var localModelManager = LocalModelManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Compass", systemImage: "safari")
        .font(.largeTitle.weight(.semibold))

      Text("Local model setup is required before Compass can run agents.")
        .font(.title3)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 10) {
        LabeledContent("Model", value: localModelManager.snapshot.modelID)
        LabeledContent("Status", value: localModelManager.snapshot.statusLabel)
        LabeledContent("Storage", value: localModelManager.snapshot.directory.path)

        if let error = localModelManager.snapshot.errorMessage {
          Text(error)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let fraction = localModelManager.snapshot.progressFraction {
          ProgressView(value: fraction)
            .frame(maxWidth: 360)
        }
      }
      .textSelection(.enabled)

      HStack(spacing: 10) {
        Button {
          localModelManager.downloadBlessedModel()
        } label: {
          Label("Download Model", systemImage: "arrow.down.circle")
        }
        .disabled(localModelManager.isDownloadActive || localModelManager.snapshot.isRunnable)

        Button {
          localModelManager.refresh()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }

      Spacer()
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

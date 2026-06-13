import AppKit
import SwiftUI
import CompassCore

struct ShutdownView: View {
  var body: some View {
    VStack(spacing: 18) {
      ProgressView()
        .controlSize(.large)
      VStack(spacing: 6) {
        Text("Shutting down Compass")
          .font(.title3.weight(.semibold))
        Text("Stopping the containerized Linux runtime cleanly so it boots fast next time.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .transition(.opacity)
  }
}

func copyTextToPasteboard(_ text: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(text, forType: .string)
}

func copyRuntimeDiagnosticsToPasteboard(_ text: String) {
  copyTextToPasteboard(text)
}

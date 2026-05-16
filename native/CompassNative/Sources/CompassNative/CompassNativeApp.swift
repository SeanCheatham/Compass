import SwiftUI

@main
struct CompassNativeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1120, minHeight: 760)
                .task {
                    await model.bootstrap()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Compass") {
                Button("Refresh Workspace") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Run Iteration") {
                    Task { await model.runIteration() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.isRunning)
            }
        }
    }
}

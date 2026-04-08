import SwiftUI

@main
struct VibePromptApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: appState.status.icon)
        }
        .menuBarExtraStyle(.window)
    }
}

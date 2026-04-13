import SwiftUI

@main
struct VibePromptApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(appState: appState)
        }

        Window("Configuración Inicial", id: "onboarding") {
            OnboardingView(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private var menuBarIcon: String {
        switch appState.status {
        case .idle: "waveform"
        case .recording: "mic.fill"
        case .transcribing: "ellipsis.circle"
        case .success: "checkmark.circle"
        case .error: "exclamationmark.triangle"
        }
    }
}

import SwiftUI

struct MenuBarView: View {
    var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status
            HStack {
                Image(systemName: appState.status.icon)
                    .foregroundStyle(statusColor)
                Text(appState.status.label)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if !appState.lastTranscription.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Última transcripción")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(appState.lastTranscription.prefix(100) + (appState.lastTranscription.count > 100 ? "…" : ""))
                            .font(.caption)
                            .lineLimit(3)
                        Spacer()
                        Button("Copiar") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(appState.lastTranscription, forType: .string)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            // Settings
            VStack(alignment: .leading, spacing: 8) {
                Text("Configuración")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Servidor") {
                    TextField("http://localhost:8420", text: appState.config.$serverURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                LabeledContent("API Key") {
                    SecureField("sk-...", text: appState.config.$apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                Toggle("Auto-pegar", isOn: appState.config.$autoPaste)

                Picker("Modo", selection: appState.config.$hotkeyModeRaw) {
                    ForEach(HotkeyMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Button("Salir") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle: .secondary
        case .recording: .red
        case .transcribing: .orange
        case .success: .green
        case .error: .red
        }
    }
}

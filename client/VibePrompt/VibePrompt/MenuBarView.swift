import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    @State private var inputDevices: [AudioInputDevice] = AudioRecorder.availableInputDevices()

    private var config: AppConfig { appState.config }

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
                    TextField("http://localhost:8420", text: Binding(
                        get: { config.serverURL },
                        set: { config.serverURL = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                }

                LabeledContent("API Key") {
                    SecureField("sk-...", text: Binding(
                        get: { config.apiKey },
                        set: { config.apiKey = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                }

                LabeledContent("Micrófono") {
                    Picker("", selection: Binding(
                        get: { config.selectedMicrophoneUID },
                        set: { config.selectedMicrophoneUID = $0 }
                    )) {
                        Text("Por defecto del sistema").tag("")
                        ForEach(inputDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }

                Toggle("Auto-pegar", isOn: Binding(
                    get: { config.autoPaste },
                    set: { config.autoPaste = $0 }
                ))

                LabeledContent("Modo") {
                    Picker("", selection: Binding(
                        get: { config.hotkeyModeRaw },
                        set: { config.hotkeyModeRaw = $0 }
                    )) {
                        ForEach(HotkeyMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
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
        .onAppear { inputDevices = AudioRecorder.availableInputDevices() }
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

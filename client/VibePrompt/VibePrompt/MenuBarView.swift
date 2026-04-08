import SwiftUI

// MARK: - Main View

struct MenuBarView: View {
    @Bindable var appState: AppState
    @State private var inputDevices: [AudioInputDevice] = AudioRecorder.availableInputDevices()

    private var config: AppConfig { appState.config }

    var body: some View {
        VStack(spacing: 0) {
            // ── Status Header ──
            statusHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            separator

            // ── Content ──
            VStack(spacing: 14) {
                // Last transcription
                if !appState.lastTranscription.isEmpty {
                    transcriptionCard
                }

                // Audio section
                settingsGroup("Audio") {
                    pickerRow("Micrófono", icon: "mic", selection: Binding(
                        get: { config.selectedMicrophoneUID },
                        set: { config.selectedMicrophoneUID = $0 }
                    )) {
                        Text("Sistema").tag("")
                        ForEach(inputDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }

                    pickerRow("Modelo", icon: "cpu", selection: Binding(
                        get: { config.selectedModel },
                        set: { config.selectedModel = $0 }
                    )) {
                        if appState.availableModels.isEmpty {
                            Text("Por defecto").tag("")
                        }
                        ForEach(appState.availableModels) { model in
                            Text("\(model.name) (\(model.sizeMb) MB)").tag(model.id)
                        }
                    }
                }

                // Connection section
                settingsGroup("Conexión") {
                    fieldRow("Servidor", icon: "network", placeholder: "http://localhost:8420", text: Binding(
                        get: { config.serverURL },
                        set: { config.serverURL = $0 }
                    ))
                    secureRow("API Key", icon: "key", placeholder: "sk-...", text: Binding(
                        get: { config.apiKey },
                        set: { config.apiKey = $0 }
                    ))
                }

                // Behavior section
                settingsGroup("Comportamiento") {
                    pickerRow("Modo", icon: "command", selection: Binding(
                        get: { config.hotkeyModeRaw },
                        set: { config.hotkeyModeRaw = $0 }
                    )) {
                        ForEach(HotkeyMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }

                    toggleRow("Auto-pegar", icon: "doc.on.clipboard", isOn: Binding(
                        get: { config.autoPaste },
                        set: { config.autoPaste = $0 }
                    ))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            separator

            // ── Footer ──
            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Salir")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 320)
        .onAppear {
            inputDevices = AudioRecorder.availableInputDevices()
            appState.refreshModels()
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack(spacing: 10) {
            // Animated status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 28, height: 28)

                if appState.status == .recording {
                    Circle()
                        .fill(statusColor.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .scaleEffect(1.4)
                        .opacity(0.6)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: appState.status
                        )
                }

                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(appState.status.label)
                    .font(.system(size: 13, weight: .semibold))
                Text(statusSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Keyboard hint
            Text("Right \u{2318}")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Transcription Card

    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "text.quote")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("Última transcripción")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.lastTranscription, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copiar al portapapeles")
            }

            Text(appState.lastTranscription)
                .font(.system(size: 12))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Settings Group

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)
                .padding(.bottom, 6)

            VStack(spacing: 1) {
                content()
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Row Components

    private func pickerRow<S: Hashable, Content: View>(
        _ label: String,
        icon: String,
        selection: Binding<S>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Picker("", selection: selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 140)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func fieldRow(_ label: String, icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: 140)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func secureRow(_ label: String, icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: 140)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func toggleRow(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Separator

    private var separator: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 0.5)
    }

    // MARK: - Status Helpers

    private var statusIcon: String {
        switch appState.status {
        case .idle: "waveform"
        case .recording: "waveform"
        case .transcribing: "arrow.triangle.2.circlepath"
        case .success: "checkmark"
        case .error: "exclamationmark.triangle.fill"
        }
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

    private var statusSubtitle: String {
        switch appState.status {
        case .idle: "Presiona Right \u{2318} para grabar"
        case .recording: "Escuchando audio..."
        case .transcribing: "Procesando con Whisper..."
        case .success: "Texto copiado"
        case .error: "Revisa la configuración"
        }
    }
}

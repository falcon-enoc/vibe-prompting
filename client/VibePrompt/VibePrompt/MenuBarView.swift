import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    @State private var inputDevices: [AudioInputDevice] = AudioRecorder.availableInputDevices()
    @State private var showHistory = false
    @State private var showModels = false

    private var config: AppConfig { appState.config }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            separator

            VStack(spacing: 14) {
                if !appState.lastTranscription.isEmpty {
                    transcriptionCard
                }

                // Server section
                settingsGroup("Servidor") {
                    pickerRow("Activo", icon: "server.rack", selection: Binding(
                        get: { config.selectedServerID },
                        set: {
                            config.selectedServerID = $0
                            appState.refreshServerInfo()
                        }
                    )) {
                        ForEach(config.servers) { server in
                            Text(server.name).tag(server.id)
                        }
                    }

                    // Editable fields for active server
                    editableRow("Nombre", icon: "tag", value: Binding(
                        get: { config.activeServer.name },
                        set: { config.updateServer(id: config.selectedServerID, name: $0) }
                    ))
                    editableRow("URL", icon: "network", value: Binding(
                        get: { config.activeServer.url },
                        set: { config.updateServer(id: config.selectedServerID, url: $0) }
                    ), monospaced: true)
                    secureRow("API Key", icon: "key", value: Binding(
                        get: { config.activeServer.apiKey },
                        set: { config.updateServer(id: config.selectedServerID, apiKey: $0) }
                    ))

                    if isLocalServer && !appState.serverModels.isEmpty {
                        pickerRow("Modelo", icon: "cpu", selection: Binding(
                            get: { appState.serverCurrentModel },
                            set: { newModel in
                                guard newModel != appState.serverCurrentModel else { return }
                                appState.switchModel(to: newModel)
                            }
                        )) {
                            ForEach(appState.serverModels.filter(\.downloaded)) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .disabled(appState.switchingModel)
                    } else {
                        infoRow("Modelo", icon: "cpu", value: modelDisplayName)
                    }

                    // Model load status
                    HStack(spacing: 8) {
                        if appState.switchingModel {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16)
                            Text("Cargando modelo...")
                                .font(.system(size: 11))
                                .foregroundStyle(.blue)
                        } else {
                            Image(systemName: appState.modelLoaded ? "bolt.circle.fill" : "moon.zzz")
                                .font(.system(size: 11))
                                .foregroundStyle(appState.modelLoaded ? .green : .orange)
                                .frame(width: 16)
                            if appState.modelLoaded {
                                Text("En memoria")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.green)
                                Text("· idle \(appState.modelIdleSeconds)s")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text("En espera · recarga ~30s")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)

                    // Add / Remove
                    HStack(spacing: 12) {
                        Button(action: {
                            let server = ServerConfig(name: "Nuevo", url: "http://localhost:8420")
                            config.addServer(server)
                            config.selectedServerID = server.id
                        }) {
                            Label("Agregar", systemImage: "plus.circle")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)

                        if config.servers.count > 1 {
                            Button(action: {
                                config.removeServer(id: config.selectedServerID)
                                appState.refreshServerInfo()
                            }) {
                                Label("Eliminar", systemImage: "trash")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red.opacity(0.7))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
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
                }

                // Models section (collapsible)
                settingsGroup("Modelos") {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showModels.toggle() } }) {
                        HStack(spacing: 8) {
                            Image(systemName: showModels ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 16)
                            Text("\(appState.modelManager.models.filter(\.downloaded).count) de \(appState.modelManager.models.count) descargados")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showModels {
                        ForEach(appState.modelManager.models) { state in
                            HStack(spacing: 8) {
                                Image(systemName: state.downloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(state.downloaded ? .green : .secondary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(state.model.name)
                                        .font(.system(size: 12))
                                    Text("\(state.model.sizeMb) MB · \(state.model.backend)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if appState.modelManager.activeDownloadId == state.model.id {
                                    ProgressView(value: appState.modelManager.downloadProgress)
                                        .frame(width: 50)
                                } else if !state.downloaded {
                                    Button("Descargar") {
                                        Task {
                                            await appState.modelManager.download(
                                                modelId: state.model.id,
                                                hfToken: config.hfToken.isEmpty ? nil : config.hfToken
                                            )
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.blue)
                                } else {
                                    Button(action: { appState.modelManager.delete(modelId: state.model.id) }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.red.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                        }

                        if let error = appState.modelManager.errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                        }

                        secureRow("HF Token", icon: "key.fill", value: Binding(
                            get: { config.hfToken },
                            set: { config.hfToken = $0 }
                        ))
                    }
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

                // History
                if !config.transcriptionHistory.isEmpty {
                    settingsGroup("Historial") {
                        let items = Array(config.transcriptionHistory.prefix(showHistory ? 5 : 3))
                        ScrollView {
                            VStack(spacing: 1) {
                                ForEach(items) { entry in
                                    HStack(spacing: 6) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.text)
                                                .font(.system(size: 11))
                                                .lineLimit(1)
                                            Text("\(entry.serverName) · \(entry.timestamp, format: .dateTime.hour().minute())")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                        Button(action: {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(entry.text, forType: .string)
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                }
                            }
                        }
                        .frame(maxHeight: showHistory ? 120 : .infinity)

                        HStack(spacing: 12) {
                            if config.transcriptionHistory.count > 3 {
                                Button(showHistory ? "Menos" : "Ver más") {
                                    withAnimation { showHistory.toggle() }
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))
                                .foregroundStyle(.blue)
                            }

                            Button("Limpiar") {
                                config.clearHistory()
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.7))

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            separator

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
            appState.refreshServerInfo()
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack(spacing: 10) {
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
        _ label: String, icon: String, selection: Binding<S>, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
            Text(label).font(.system(size: 12))
            Spacer()
            Picker("", selection: selection) { content() }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 140)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private func editableRow(_ label: String, icon: String, value: Binding<String>, monospaced: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
            Text(label).font(.system(size: 12))
            Spacer()
            TextField("", text: value)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: monospaced ? .monospaced : .default))
                .frame(maxWidth: 140)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private func secureRow(_ label: String, icon: String, value: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
            Text(label).font(.system(size: 12))
            Spacer()
            SecureField("", text: value)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: 140)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private func infoRow(_ label: String, icon: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
            Text(label).font(.system(size: 12))
            Spacer()
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private func toggleRow(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
            Text(label).font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private var separator: some View {
        Rectangle().fill(.quaternary).frame(height: 0.5)
    }

    // MARK: - Helpers

    private var isLocalServer: Bool {
        let url = config.activeServer.url.lowercased()
        return url.contains("localhost") || url.contains("127.0.0.1")
    }

    private var modelDisplayName: String {
        if appState.serverCurrentModel.isEmpty { return "—" }
        return appState.serverModels.first(where: { $0.id == appState.serverCurrentModel })?.name
            ?? appState.serverCurrentModel.components(separatedBy: "/").last ?? "—"
    }

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
        case .transcribing: "Procesando con \(config.activeServer.name)..."
        case .success: "Texto copiado"
        case .error: "Revisa la configuración"
        }
    }
}

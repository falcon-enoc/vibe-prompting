import SwiftUI

// MARK: - Estado de prueba de conexión

enum ConnectionTestStatus {
    case untested, testing, success, failed(String)
}

// MARK: - Vista principal de Preferencias

struct PreferencesView: View {
    @Bindable var appState: AppState
    @State private var connectionStatuses: [UUID: ConnectionTestStatus] = [:]
    @State private var inputDevices: [AudioInputDevice] = AudioRecorder.availableInputDevices()

    private var activeServerIsLocal: Bool { appState.config.activeServerIsLocal }

    private var config: AppConfig { appState.config }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            audioTab
                .tabItem { Label("Audio", systemImage: "mic") }

            serversTab
                .tabItem { Label("Servidores", systemImage: "server.rack") }

            modelsTab
                .tabItem { Label("Modelos", systemImage: "cpu") }

            historyTab
                .tabItem { Label("Historial", systemImage: "clock") }
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 480, idealHeight: 520)
    }

    // MARK: - Tab 1: General

    private var generalTab: some View {
        Form {
            Section("Hotkey") {
                Picker("Modo de hotkey", selection: Binding(
                    get: { config.hotkeyModeRaw },
                    set: { config.hotkeyModeRaw = $0 }
                )) {
                    ForEach(HotkeyMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            }

            Section("Dictado") {
                Picker("Modo de dictado", selection: Binding(
                    get: { config.dictationMode },
                    set: { config.dictationMode = $0 }
                )) {
                    ForEach(DictationMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Picker("Idioma", selection: Binding(
                    get: { config.transcriptionLanguage },
                    set: { config.transcriptionLanguage = $0 }
                )) {
                    ForEach(TranscriptionLanguage.allCases, id: \.rawValue) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                Text("«Automático» = multilenguaje (autodetecta). Bloquear un idioma evita que el modelo traduzca fragmentos — funciona con Whisper; Parakeet no soporta forzar idioma.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Comportamiento") {
                Toggle("Auto-pegar transcripción", isOn: Binding(
                    get: { config.autoPaste },
                    set: { config.autoPaste = $0 }
                ))

                Toggle("Iniciar con macOS", isOn: Binding(
                    get: { config.launchAtLogin },
                    set: { config.launchAtLogin = $0 }
                ))

                Toggle("Indicador flotante al grabar", isOn: Binding(
                    get: { config.showRecordingOverlay },
                    set: { config.showRecordingOverlay = $0 }
                ))
                Text("Muestra una onda flotante sobre la pantalla mientras grabas y transcribes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Dictado en vivo", isOn: Binding(
                    get: { config.liveTranscriptionEnabled },
                    set: { config.liveTranscriptionEnabled = $0 }
                ))
                Text("Escribe el texto directamente donde tienes el cursor mientras dictas, en vez de pegarlo todo al final. Requiere permiso de Accesibilidad, el modelo Parakeet y modo de dictado «Texto limpio» — si algo falta, se usa el pegado normal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Margen al cortar", selection: Binding(
                    get: { config.recordingTailMs },
                    set: { config.recordingTailMs = $0 }
                )) {
                    Text("Ninguno").tag(0)
                    Text("0,15 s").tag(150)
                    Text("0,25 s").tag(250)
                    Text("0,5 s").tag(500)
                }
                Text("Sigue grabando un instante tras soltar/cortar para no perder el final de la frase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Tab 2: Audio

    private var audioTab: some View {
        Form {
            Section("Micrófono") {
                Picker("Dispositivo", selection: Binding(
                    get: { config.selectedMicrophoneUID },
                    set: { config.selectedMicrophoneUID = $0 }
                )) {
                    Text("Sistema (por defecto)").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
            }

            Section("Retroalimentación") {
                Toggle("Sonido al grabar", isOn: Binding(
                    get: { config.soundFeedback },
                    set: { config.soundFeedback = $0 }
                ))
            }
        }
        .padding()
        .onAppear {
            inputDevices = AudioRecorder.availableInputDevices()
        }
    }

    // MARK: - Tab 3: Servidores

    private var serversTab: some View {
        HSplitView {
            // Lista de servidores
            VStack(spacing: 0) {
                List(config.servers, selection: Binding(
                    get: { config.selectedServerID },
                    set: {
                        if let id = $0 {
                            config.selectedServerID = id
                            appState.onActiveServerChanged()
                        }
                    }
                )) {
                    Text($0.name)
                }
                .frame(minWidth: 150)

                Divider()

                HStack(spacing: 8) {
                    Button(action: {
                        let server = ServerConfig(name: "Nuevo", url: "http://127.0.0.1:8420")
                        config.addServer(server)
                        config.selectedServerID = server.id
                    }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)

                    Button(action: {
                        config.removeServer(id: config.selectedServerID)
                        appState.refreshServerInfo()
                    }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(config.servers.count <= 1)

                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 150, maxWidth: 200)

            // Detalle del servidor seleccionado
            Form {
                Section("Configuración") {
                    TextField("Nombre", text: Binding(
                        get: { config.activeServer.name },
                        set: { config.updateServer(id: config.selectedServerID, name: $0) }
                    ))

                    TextField("URL", text: Binding(
                        get: { config.activeServer.url },
                        set: { config.updateServer(id: config.selectedServerID, url: $0) }
                    ))
                    .font(.system(.body, design: .monospaced))

                    SecureField("API Key", text: Binding(
                        get: { config.activeServer.apiKey },
                        set: { config.updateServer(id: config.selectedServerID, apiKey: $0) }
                    ))

                    SecureField("Admin Token", text: Binding(
                        get: { config.activeServer.adminToken },
                        set: { config.updateServer(id: config.selectedServerID, adminToken: $0) }
                    ))

                    SecureField("HF Token", text: Binding(
                        get: { config.activeServer.hfToken },
                        set: { config.updateServer(id: config.selectedServerID, hfToken: $0) }
                    ))

                    if activeServerIsLocal {
                        Text("El servidor local no requiere API key ni admin token.")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Section("Conexión") {
                    HStack {
                        Button("Probar conexión") {
                            testConnection(serverId: config.selectedServerID)
                        }

                        Spacer()

                        connectionStatusView(for: config.selectedServerID)
                    }
                }

                if activeServerIsLocal {
                    localServerSection
                }
            }
            .padding()
        }
    }

    // MARK: - Sección: Servidor local

    private var downloadedModels: [ModelDownloadState] {
        appState.modelManager.models.filter(\.downloaded)
    }

    /// ¿El servidor local resuelto es el gestionado por la app (no un repo de dev)?
    private var usingManagedServer: Bool {
        config.resolvedProjectRoot == ServerInstaller.serverSupportDir.path
    }

    @ViewBuilder
    private var localServerSection: some View {
        Section("Servidor local") {
            if appState.serverInstaller.status.isInstalling {
                installControls
            } else if config.resolvedProjectRoot == nil {
                installControls
            } else {
                runningControls
            }

            // Override para desarrollo: apuntar a un checkout del repo.
            HStack(spacing: 6) {
                TextField("Ruta del proyecto (dev)", text: Binding(
                    get: { config.localServerProjectPath },
                    set: { config.localServerProjectPath = $0 }
                ))
                .font(.system(.caption, design: .monospaced))
                Button("Elegir…") { chooseProjectFolder() }
            }

            if config.localServerProjectPath.isEmpty, let auto = AppConfig.autodetectProjectRoot() {
                Text("Repo de desarrollo detectado: \(auto)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Controles cuando el entorno del servidor ya existe (gestionado o repo dev).
    @ViewBuilder
    private var runningControls: some View {
        HStack {
            Text("Estado")
            Spacer()
            localServerStatusView
        }

        HStack {
            switch appState.localServer.status {
            case .running:
                Button("Detener servidor") { appState.stopLocalServer() }
            case .starting:
                Button("Iniciando…") {}.disabled(true)
            default:
                Button("Iniciar servidor") { appState.startLocalServer() }
            }
            Spacer()
        }

        Picker("Modelo", selection: Binding(
            get: { config.localServerModelId },
            set: { newValue in
                config.localServerModelId = newValue
                // Si el servidor ya está arriba, cambiar el modelo en caliente.
                if appState.localServer.status.isUp {
                    appState.switchModel(to: newValue)
                }
            }
        )) {
            ForEach(downloadedModels) { state in
                Text(state.model.name).tag(state.model.id)
            }
        }

        if usingManagedServer {
            Button("Reinstalar / reparar servidor") {
                appState.stopLocalServer()
                appState.installLocalServer()
            }
            .font(.caption)
        }
    }

    /// Controles de instalación del servidor gestionado por la app.
    @ViewBuilder
    private var installControls: some View {
        switch appState.serverInstaller.status {
        case .installing(let phase):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Instalando servidor local…").font(.system(size: 12))
                    Text(phase).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("Descarga Python y las dependencias (~300–500 MB). Puede tardar unos minutos.")
                .font(.caption).foregroundStyle(.secondary)

        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(.red).lineLimit(5)
            Button("Reintentar instalación") { appState.installLocalServer() }

        case .notInstalled, .installed:
            // .installed sin ruta resuelta no debería pasar; se trata como no instalado.
            Text("El servidor local todavía no está instalado en este Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Instalar servidor local") { appState.installLocalServer() }
        }
    }

    @ViewBuilder
    private var localServerStatusView: some View {
        switch appState.localServer.status {
        case .stopped:
            Label("Detenido", systemImage: "stop.circle")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        case .starting:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Iniciando…").font(.system(size: 12)).foregroundStyle(.blue)
            }
        case .running:
            Label("Corriendo", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
        }
    }

    private func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir"
        panel.message = "Selecciona la carpeta del proyecto vibe-prompt (contiene .venv/ y server/)"
        if panel.runModal() == .OK, let url = panel.url {
            config.localServerProjectPath = url.path
        }
    }

    // MARK: - Tab 4: Modelos

    private var modelsTab: some View {
        VStack(spacing: 0) {
            List {
                ForEach(appState.modelManager.models) { state in
                    HStack {
                        Image(systemName: state.downloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                            .foregroundStyle(state.downloaded ? .green : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.model.name)
                                .font(.system(size: 13))
                            Text("\(state.model.sizeMb) MB - \(state.model.backend)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if appState.modelManager.activeDownloadId == state.model.id {
                            ProgressView(value: appState.modelManager.downloadProgress)
                                .frame(width: 80)
                        } else if !state.downloaded {
                            Button("Descargar") {
                                Task {
                                    await appState.modelManager.download(
                                        modelId: state.model.id,
                                        hfToken: config.hfToken.isEmpty ? nil : config.hfToken
                                    )
                                }
                            }
                        } else {
                            Button(role: .destructive) {
                                appState.modelManager.delete(modelId: state.model.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let error = appState.modelManager.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Text("HF Token")
                    .font(.system(size: 12))
                SecureField("Token de HuggingFace", text: Binding(
                    get: { config.hfToken },
                    set: { config.hfToken = $0 }
                ))
                .frame(maxWidth: 300)
            }
            .padding(12)
        }
    }

    // MARK: - Tab 5: Historial

    private var historyTab: some View {
        VStack(spacing: 0) {
            if config.transcriptionHistory.isEmpty {
                Spacer()
                Text("Sin transcripciones")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(config.transcriptionHistory) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.text)
                                    .font(.system(size: 13))
                                    .lineLimit(3)
                                HStack(spacing: 8) {
                                    Text(entry.serverName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Text(entry.timestamp, format: .dateTime.day().month().hour().minute())
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                    Text("\(Int(entry.durationMs))ms")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.text, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Limpiar historial", role: .destructive) {
                    config.clearHistory()
                }
                .disabled(config.transcriptionHistory.isEmpty)
                .padding(12)
            }
        }
    }

    // MARK: - Helpers de conexión

    private func testConnection(serverId: UUID) {
        guard let server = config.servers.first(where: { $0.id == serverId }) else { return }
        connectionStatuses[serverId] = .testing

        Task {
            do {
                _ = try await appState.transcriptionService.fetchHealth(server: server)
                await MainActor.run {
                    connectionStatuses[serverId] = .success
                }
            } catch {
                await MainActor.run {
                    connectionStatuses[serverId] = .failed(error.localizedDescription)
                }
            }
        }
    }

    @ViewBuilder
    private func connectionStatusView(for serverId: UUID) -> some View {
        switch connectionStatuses[serverId] ?? .untested {
        case .untested:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Conectado")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }
        case .failed(let msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}

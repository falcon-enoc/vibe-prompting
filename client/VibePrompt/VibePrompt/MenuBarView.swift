import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private var config: AppConfig { appState.config }

    var body: some View {
        VStack(spacing: 0) {
            if let issue = appState.startupIssue {
                startupIssueBanner(issue)
            }

            statusHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            separator

            VStack(spacing: 14) {
                if !appState.lastTranscription.isEmpty {
                    transcriptionCard
                }

                // Servidor activo (solo lectura) con estado del modelo
                settingsGroup("Servidor") {
                    HStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(config.activeServer.name)
                            .font(.system(size: 12))
                        Spacer()
                        modelStatusBadge
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)

                    if config.activeServerIsLocal {
                        localServerRow
                    }
                }

                // Toggle rápido: auto-pegar
                settingsGroup("Rápido") {
                    toggleRow("Auto-pegar", icon: "doc.on.clipboard", isOn: Binding(
                        get: { config.autoPaste },
                        set: { config.autoPaste = $0 }
                    ))
                }

                // 3 items más recientes del historial
                if !config.transcriptionHistory.isEmpty {
                    settingsGroup("Historial") {
                        let items = Array(config.transcriptionHistory.prefix(3))
                        ForEach(items) { entry in
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.text)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    Text("\(entry.serverName) \u{00B7} \(entry.timestamp, format: .dateTime.hour().minute())")
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            separator

            // Preferencias y Salir
            VStack(spacing: 0) {
                Button {
                    openSettings()
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        for window in NSApp.windows where window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Preferencias...")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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
        }
        .frame(width: 320)
        .onAppear {
            if appState.needsOnboarding {
                openWindow(id: "onboarding")
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            appState.startPolling()
        }
        .onDisappear {
            appState.stopPolling()
        }
    }

    // MARK: - Local Server Row

    @ViewBuilder
    private var localServerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            switch appState.localServer.status {
            case .running:
                Text("Servidor local activo").font(.system(size: 11)).foregroundStyle(.green)
                Spacer()
                Button("Detener") { appState.stopLocalServer() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.red)
            case .starting:
                Text("Iniciando servidor…").font(.system(size: 11)).foregroundStyle(.blue)
                Spacer()
                ProgressView().controlSize(.small)
            case .failed(let msg):
                Text(msg).font(.system(size: 10)).foregroundStyle(.red).lineLimit(1)
                Spacer()
                Button("Reintentar") { appState.startLocalServer() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.blue)
            case .stopped:
                Text("Servidor local detenido").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Iniciar") { appState.startLocalServer() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Model Status Badge

    @ViewBuilder
    private var modelStatusBadge: some View {
        HStack(spacing: 4) {
            switch appState.modelState {
            case .unknown:
                Image(systemName: "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                Text("Consultando...")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            case .unloaded:
                Image(systemName: "moon.zzz")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("En espera")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 12)
                Text("Cargando...")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
            case .loaded(let idle):
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text(loadedBadgeText(idle: idle))
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Text("Sin conexión")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
    }

    private func loadedBadgeText(idle: Int) -> String {
        var text = "En memoria · \(idle)s"
        if let mb = appState.modelMemoryMb, mb > 0 {
            text += mb >= 1024
                ? String(format: " · %.1f GB", mb / 1024)
                : String(format: " · %.0f MB", mb)
        }
        return text
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

    // MARK: - Startup Issue Banner

    private func startupIssueBanner(_ issue: AppState.StartupIssue) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            switch issue {
            case .serverUnreachable(let msg):
                Text("Servidor no disponible")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Button("Reintentar") { appState.checkServerConnectivity() }
                    .controlSize(.small)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.gradient, in: Rectangle())
    }

    // MARK: - Helpers

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

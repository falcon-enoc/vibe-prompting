import SwiftUI
import AVFoundation

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case server = 1
    case permissions = 2
    case finish = 3
}

struct OnboardingView: View {
    var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var step: OnboardingStep = .welcome

    // Server config state — initialized from existing config in .onAppear
    @State private var serverName = ""
    @State private var serverURL = ""
    @State private var serverAPIKey = ""
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var connectionError = ""

    // Permissions state
    @State private var hasMicPermission = AudioRecorder.hasPermission()
    @State private var hasAccessibilityPermission = AXIsProcessTrusted()
    @State private var permissionTimer: Timer?

    // Finish state
    @State private var launchAtLogin = false

    enum ConnectionStatus {
        case idle, testing, success, failed
    }

    private var isLocalURL: Bool {
        let url = serverURL.lowercased()
        return url.contains("127.0.0.1") || url.contains("localhost") || url.contains("192.168.") || url.contains("10.0.")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step indicators
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Content
            Group {
                switch step {
                case .welcome: welcomeStep
                case .server: serverStep
                case .permissions: permissionsStep
                case .finish: finishStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation
            HStack {
                if step != .welcome {
                    Button("Atrás") {
                        withAnimation { step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if step == .finish {
                    Button("Finalizar") { completeOnboarding() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Continuar") {
                        if step == .server { saveServerConfig() }
                        withAnimation { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .finish }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 440)
        .onAppear {
            // Pre-populate from existing server config
            let server = appState.config.activeServer
            serverName = server.name
            serverURL = server.url
            serverAPIKey = server.apiKey
        }
        .onDisappear {
            permissionTimer?.invalidate()
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("Bienvenido a VibePrompt")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "mic.fill", text: "Dicta texto con tu voz usando Right \u{2318}")
                featureRow(icon: "server.rack", text: "Transcripción por IA en tu propio servidor")
                featureRow(icon: "doc.on.clipboard", text: "El texto se pega automáticamente donde escribes")
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 13))
        }
    }

    // MARK: - Server Configuration

    private var serverStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)

            Text("Configura tu servidor")
                .font(.title3.weight(.semibold))

            Text("VibePrompt necesita un servidor con el modelo de transcripción. Si es local no necesitas API key; para servidores remotos sí.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(spacing: 10) {
                LabeledContent("Nombre") {
                    TextField("Local", text: $serverName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                LabeledContent("URL") {
                    TextField("http://127.0.0.1:8420", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                LabeledContent("API Key") {
                    SecureField(isLocalURL ? "No requerida para servidor local" : "Requerida para servidores remotos", text: $serverAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .disabled(false)
                }
                if isLocalURL {
                    Text("El servidor local no requiere API key ni admin token.")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 40)

            HStack(spacing: 8) {
                Button(action: testConnection) {
                    HStack(spacing: 4) {
                        if connectionStatus == .testing {
                            ProgressView().controlSize(.small)
                        }
                        Text("Probar conexión")
                    }
                }
                .disabled(connectionStatus == .testing || serverURL.isEmpty)

                connectionStatusView
            }
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionStatus {
        case .idle: EmptyView()
        case .testing: EmptyView()
        case .success:
            Label("Conectado", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .failed:
            Label(connectionError, systemImage: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    private func testConnection() {
        connectionStatus = .testing
        let server = ServerConfig(
            name: serverName,
            url: AppConfig.normalizeURL(serverURL),
            apiKey: serverAPIKey
        )
        Task {
            do {
                _ = try await appState.transcriptionService.fetchHealth(server: server)
                connectionStatus = .success
            } catch {
                connectionError = error.localizedDescription
                connectionStatus = .failed
            }
        }
    }

    private func saveServerConfig() {
        let config = appState.config
        let normalized = AppConfig.normalizeURL(serverURL)
        if let first = config.servers.first {
            config.updateServer(id: first.id, name: serverName, url: normalized, apiKey: serverAPIKey)
            config.selectedServerID = first.id
        } else {
            let server = ServerConfig(name: serverName, url: normalized, apiKey: serverAPIKey)
            config.addServer(server)
            config.selectedServerID = server.id
        }
    }

    // MARK: - Permissions

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)

            Text("Permisos necesarios")
                .font(.title3.weight(.semibold))

            Text("VibePrompt necesita estos permisos para funcionar correctamente.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    title: "Micrófono",
                    description: "Para grabar tu voz y transcribirla",
                    granted: hasMicPermission,
                    action: requestMicPermission
                )

                permissionRow(
                    icon: "hand.raised.fill",
                    title: "Accesibilidad",
                    description: "Para detectar Right \u{2318} y pegar texto automáticamente",
                    granted: hasAccessibilityPermission,
                    action: requestAccessibilityPermission
                )
            }
            .padding(.horizontal, 32)

            if !hasMicPermission || !hasAccessibilityPermission {
                Text("Puedes continuar y otorgar permisos después, pero la app no funcionará completamente.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding(.horizontal, 32)
        .onAppear { startPermissionPolling() }
        .onDisappear { permissionTimer?.invalidate() }
    }

    private func permissionRow(icon: String, title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Permitir") { action() }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func requestMicPermission() {
        Task {
            let granted = await AudioRecorder.requestPermission()
            await MainActor.run { hasMicPermission = granted }
        }
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            hasMicPermission = AudioRecorder.hasPermission()
            hasAccessibilityPermission = AXIsProcessTrusted()
        }
    }

    // MARK: - Finish

    private var finishStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Todo listo")
                .font(.title2.weight(.semibold))

            Text("VibePrompt está configurado. Presiona Right \u{2318} para empezar a dictar.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Toggle(isOn: $launchAtLogin) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                    Text("Iniciar VibePrompt con macOS")
                        .font(.system(size: 13))
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 60)
            .padding(.top, 8)

            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Puedes cambiar la configuración en cualquier momento desde el menú.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Actions

    private func completeOnboarding() {
        saveServerConfig()
        appState.config.launchAtLogin = launchAtLogin
        appState.config.hasCompletedOnboarding = true
        appState.completeSetup()
        dismiss()
    }
}

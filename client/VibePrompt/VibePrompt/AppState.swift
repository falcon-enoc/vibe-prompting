import SwiftUI
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "AppState")

enum AppStatus: Equatable {
    case idle
    case recording
    case transcribing
    case success
    case error(String)

    var label: String {
        switch self {
        case .idle: "Listo"
        case .recording: "Grabando..."
        case .transcribing: "Transcribiendo..."
        case .success: "Completado"
        case .error(let msg): "Error: \(msg)"
        }
    }
}

@Observable
final class AppState {
    var status: AppStatus = .idle
    var lastTranscription: String = ""
    var serverModels: [ServerModelInfo] = []
    var serverCurrentModel: String = ""
    var modelLoaded: Bool = false
    var modelIdleSeconds: Int = 0
    var idleUnloadMinutes: Int = 10
    var switchingModel: Bool = false

    let config = AppConfig()
    let modelManager = ModelManager()
    private let recorder = AudioRecorder()
    let transcriptionService = TranscriptionService()
    private let hotkeyManager = HotkeyManager()

    init() {
        Task { await requestPermissionsIfNeeded() }
        setupHotkey()
    }

    private func requestPermissionsIfNeeded() async {
        guard !AudioRecorder.hasPermission() else { return }
        let granted = await AudioRecorder.requestPermission()
        if !granted {
            await MainActor.run {
                status = .error("Permiso de micrófono denegado")
            }
        }
    }

    private func setupHotkey() {
        hotkeyManager.modeProvider = { [weak self] in self?.config.hotkeyMode ?? .pushToTalk }
        hotkeyManager.onStartRecording = { [weak self] in
            self?.startRecording()
        }
        hotkeyManager.onStopRecording = { [weak self] in
            self?.stopAndTranscribe()
        }
        hotkeyManager.start()
    }

    // MARK: - Server Info

    func switchModel(to modelId: String) {
        let server = config.activeServer
        Task { @MainActor in
            switchingModel = true
            modelLoaded = false
            do {
                try await transcriptionService.switchModel(
                    server: server,
                    modelId: modelId,
                    adminToken: server.apiKey
                )
                #if DEBUG
                log.info("Modelo cambiado a \(modelId)")
                #endif
            } catch {
                log.error("Error cambiando modelo: \(error.localizedDescription)")
            }
            switchingModel = false
            refreshServerInfo()
        }
    }

    func refreshServerInfo() {
        let server = config.activeServer
        Task { @MainActor in
            // Fetch models
            do {
                let response = try await transcriptionService.fetchModels(server: server)
                serverModels = response.models
                serverCurrentModel = response.current
            } catch {
                #if DEBUG
                log.warning("No se pudo consultar modelos: \(error.localizedDescription)")
                #endif
                serverModels = []
                serverCurrentModel = ""
            }
            // Fetch health
            do {
                let health = try await transcriptionService.fetchHealth(server: server)
                modelLoaded = health.modelLoaded
                modelIdleSeconds = health.idleSeconds
                idleUnloadMinutes = health.idleUnloadMinutes
            } catch {
                modelLoaded = false
                modelIdleSeconds = 0
            }
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard status == .idle || status == .success || { if case .error = status { return true }; return false }() else {
            log.warning("startRecording ignorado — estado actual: \(self.status.label)")
            return
        }
        let deviceUID = config.selectedMicrophoneUID.isEmpty ? nil : config.selectedMicrophoneUID
        #if DEBUG
        log.info("Iniciando grabación — server: \(self.config.activeServer.name), mic: \(deviceUID ?? "default")")
        #endif
        do {
            try recorder.startRecording(deviceUID: deviceUID)
            status = .recording
            Self.playSound("Tink")
        } catch {
            log.error("Error al iniciar grabación: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
        }
    }

    func stopAndTranscribe() {
        guard status == .recording else {
            log.warning("stopAndTranscribe ignorado — estado actual: \(self.status.label)")
            return
        }
        let audioData: Data
        do {
            audioData = try recorder.stopRecording()
        } catch {
            log.error("Error al detener grabación: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if case .error = status { status = .idle }
            }
            return
        }
        #if DEBUG
        log.info("Grabación detenida — \(audioData.count) bytes de audio")
        #endif
        status = .transcribing

        let server = config.activeServer

        Task { @MainActor in
            do {
                let response = try await transcriptionService.transcribe(
                    audioData: audioData,
                    server: server,
                    language: "es"
                )
                #if DEBUG
                log.info("Transcripción: \"\(response.text.prefix(80))\"")
                #endif
                lastTranscription = response.text

                config.addTranscription(TranscriptionEntry(
                    text: response.text,
                    serverName: server.name,
                    durationMs: response.durationMs
                ))

                if config.autoPaste && !response.text.isEmpty {
                    PasteService.paste(response.text)
                }
                status = .success
                try? await Task.sleep(for: .seconds(2))
                if status == .success { status = .idle }
            } catch {
                log.error("Error en transcripción: \(error.localizedDescription)")
                status = .error(error.localizedDescription)
                try? await Task.sleep(for: .seconds(3))
                if case .error = status { status = .idle }
            }
        }
    }

    private static func playSound(_ name: String) {
        // NSSound.play() is async and mixes with other audio
        guard let sound = NSSound(named: name) else {
            // Fallback: try direct file path
            guard let sound = NSSound(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff"), byReference: true) else { return }
            sound.volume = 0.5
            sound.play()
            return
        }
        sound.volume = 0.5
        sound.play()
    }
}

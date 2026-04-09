import SwiftUI
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "AppState")

enum ModelState: Equatable {
    case unknown
    case unloaded
    case loading
    case loaded(idleSeconds: Int)
    case error(String)
}

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
    var modelState: ModelState = .unknown
    var idleUnloadMinutes: Int = 10
    var switchingModel: Bool = false

    let config = AppConfig()
    let modelManager = ModelManager()
    private let recorder = AudioRecorder()
    let transcriptionService = TranscriptionService()
    private let hotkeyManager = HotkeyManager()

    init() {
        Task { await requestPermissionsIfNeeded() }
        recorder.warmup()
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
        hotkeyManager.onCancelRecording = { [weak self] in
            self?.cancelRecording()
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
            modelState = .loading
            do {
                try await transcriptionService.switchModel(
                    server: server,
                    modelId: modelId,
                    adminToken: server.adminToken
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
                idleUnloadMinutes = health.idleUnloadMinutes
                if health.modelLoaded {
                    modelState = .loaded(idleSeconds: health.idleSeconds)
                } else {
                    modelState = .unloaded
                }
            } catch {
                modelState = .error("Sin conexión")
            }
        }
    }

    // MARK: - Polling

    private var pollingTimer: Timer?

    func startPolling() {
        stopPolling()
        refreshServerInfo()
        let interval: TimeInterval = switchingModel ? 2 : 5
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshServerInfo()
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
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
            // Play sound BEFORE starting recorder — once the BT profile switches
            // from A2DP to HFP for mic input, the audio output device changes and
            // NSSound may not route correctly.
            if config.soundFeedback {
                Self.playSound("Tink")
            }
            try recorder.startRecording(deviceUID: deviceUID)
            status = .recording
        } catch {
            log.error("Error al iniciar grabación: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if case .error = self.status { self.status = .idle }
            }
        }
    }

    /// Cancel recording without transcribing (key combo detected).
    func cancelRecording() {
        guard status == .recording else { return }
        #if DEBUG
        log.info("Grabación cancelada (combo detectado)")
        #endif
        _ = try? recorder.stopRecording()
        status = .idle
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
                let processed = TextPostProcessor.process(response.text, mode: config.dictationMode)
                #if DEBUG
                log.info("Transcripción: \"\(processed.prefix(80))\"")
                #endif
                lastTranscription = processed

                config.addTranscription(TranscriptionEntry(
                    text: processed,
                    serverName: server.name,
                    durationMs: response.durationMs
                ))

                if config.autoPaste && !processed.isEmpty {
                    PasteService.paste(processed)
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

    /// Retain the sound object so ARC doesn't deallocate it mid-playback.
    /// NSSound.play() is async — without a strong reference, the sound
    /// gets destroyed before it finishes playing.
    private static var activeSound: NSSound?

    private static func playSound(_ name: String) {
        let sound: NSSound
        if let named = NSSound(named: name) {
            sound = named
        } else if let fromFile = NSSound(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff"), byReference: true) {
            sound = fromFile
        } else {
            return
        }
        activeSound?.stop()
        sound.volume = 0.5
        activeSound = sound
        sound.play()
    }
}

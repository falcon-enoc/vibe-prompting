import SwiftUI
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "AppState")

enum AppStatus: Equatable {
    case idle
    case recording
    case transcribing
    case success
    case error(String)

    var icon: String {
        switch self {
        case .idle: "mic.slash"
        case .recording: "mic.fill"
        case .transcribing: "ellipsis.circle"
        case .success: "checkmark.circle"
        case .error: "exclamationmark.triangle"
        }
    }

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

    let config = AppConfig()
    private let recorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()
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
        hotkeyManager.mode = config.hotkeyMode
        hotkeyManager.onStartRecording = { [weak self] in
            self?.startRecording()
        }
        hotkeyManager.onStopRecording = { [weak self] in
            self?.stopAndTranscribe()
        }
        hotkeyManager.start()
    }

    func startRecording() {
        guard status == .idle || status == .success else {
            log.warning("startRecording ignorado — estado actual: \(self.status.label)")
            return
        }
        let deviceUID = config.selectedMicrophoneUID.isEmpty ? nil : config.selectedMicrophoneUID
        #if DEBUG
        log.info("Iniciando grabación — serverURL: \(self.config.serverURL), apiKey: \(self.config.apiKey.prefix(8))..., mic: \(deviceUID ?? "default")")
        #endif
        do {
            try recorder.startRecording(deviceUID: deviceUID)
            status = .recording
            #if DEBUG
            log.info("Grabando...")
            #endif
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

        Task { @MainActor in
            do {
                let response = try await transcriptionService.transcribe(
                    audioData: audioData,
                    serverURL: config.serverURL,
                    apiKey: config.apiKey
                )
                #if DEBUG
                log.info("Transcripción recibida: \"\(response.text.prefix(80))\"")
                #endif
                lastTranscription = response.text
                if config.autoPaste && !response.text.isEmpty {
                    #if DEBUG
                    log.info("Pegando texto...")
                    #endif
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
}

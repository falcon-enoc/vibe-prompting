import SwiftUI

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
        setupHotkey()
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
        guard status == .idle || status == .success else { return }
        recorder.startRecording()
        status = .recording
    }

    func stopAndTranscribe() {
        guard status == .recording else { return }
        let audioData = recorder.stopRecording()
        status = .transcribing

        Task { @MainActor in
            do {
                let response = try await transcriptionService.transcribe(
                    audioData: audioData,
                    serverURL: config.serverURL,
                    apiKey: config.apiKey
                )
                lastTranscription = response.text
                if config.autoPaste && !response.text.isEmpty {
                    PasteService.paste(response.text)
                }
                status = .success
                try? await Task.sleep(for: .seconds(2))
                if status == .success { status = .idle }
            } catch {
                status = .error(error.localizedDescription)
                try? await Task.sleep(for: .seconds(3))
                if case .error = status { status = .idle }
            }
        }
    }
}

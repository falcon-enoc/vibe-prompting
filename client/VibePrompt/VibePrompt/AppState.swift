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
    var status: AppStatus = .idle {
        didSet { overlay.statusChanged(status) }
    }
    /// Nivel del micrófono (0–1) mientras se graba, para la onda del overlay.
    var audioLevel: Float = 0
    var lastTranscription: String = ""
    var serverModels: [ServerModelInfo] = []
    var serverCurrentModel: String = ""
    var modelState: ModelState = .unknown
    var idleUnloadMinutes: Int = 10
    var switchingModel: Bool = false
    /// RAM (MB) que el modelo consume mientras está cargado en memoria.
    var modelMemoryMb: Double?

    let config = AppConfig()
    let modelManager = ModelManager()
    let localServer = LocalServerManager()
    let serverInstaller = ServerInstaller()
    private let recorder = AudioRecorder()
    let transcriptionService = TranscriptionService()
    private let liveTranscriptionService = LiveTranscriptionService()
    private let axInjector = AXTextInjector()
    private var liveModeActive = false
    private var liveFinalContinuation: CheckedContinuation<LiveTranscriptionService.Event?, Never>?
    private let hotkeyManager = HotkeyManager()
    @ObservationIgnored private lazy var overlay = RecordingOverlayController(appState: self)
    var startupIssue: StartupIssue?
    private var setupCompleted = false

    enum StartupIssue: Equatable {
        case serverUnreachable(String)
    }

    var needsOnboarding: Bool { !config.hasCompletedOnboarding }

    init() {
        // Al salir de la app, detener el servidor local que hayamos lanzado
        // para no dejar procesos huérfanos.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.localServer.stop()
        }

        recorder.onLevel = { [weak self] level in
            self?.audioLevel = level
        }

        if config.hasCompletedOnboarding {
            performFullSetup()
        }
    }

    /// Called after onboarding completes, or on init if already onboarded.
    func completeSetup() {
        guard !setupCompleted else { return }
        performFullSetup()
    }

    private func performFullSetup() {
        setupCompleted = true
        Task { await requestPermissionsIfNeeded() }
        recorder.warmup()
        setupHotkey()
        syncLocalServer()
        checkServerConnectivity()
    }

    // MARK: - Servidor local

    /// Arranca o detiene el servidor local según el servidor activo.
    /// Se llama al iniciar la app y cada vez que cambia el servidor seleccionado.
    func syncLocalServer() {
        if config.activeServerIsLocal {
            startLocalServer()
        } else {
            localServer.stop()
        }
    }

    /// Instala el entorno del servidor local desde la app y, al terminar, lo arranca.
    func installLocalServer() {
        serverInstaller.install()
        Task { @MainActor in
            for _ in 0..<3600 { // hasta ~30 min (deps pesadas)
                switch serverInstaller.status {
                case .installed:
                    startLocalServer()
                    return
                case .failed:
                    return
                default:
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    func startLocalServer() {
        guard let root = config.resolvedProjectRoot else {
            // No hay entorno: hay que instalarlo desde Preferencias.
            localServer.setMissingProjectRoot()
            return
        }
        let modelId = config.localServerModelId
        let backend = supportedModels.first(where: { $0.id == modelId })?.backend ?? "parakeet"
        localServer.start(
            projectRoot: root,
            port: config.activeServerPort,
            modelId: modelId,
            backend: backend
        )
        // Reintentar la conectividad cuando el servidor esté listo.
        Task { @MainActor in
            for _ in 0..<60 {
                if localServer.status.isUp {
                    checkServerConnectivity()
                    refreshServerInfo()
                    return
                }
                if case .failed = localServer.status { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopLocalServer() {
        localServer.stop()
    }

    /// Llamar cuando el usuario cambia el servidor activo.
    func onActiveServerChanged() {
        syncLocalServer()
        refreshServerInfo()
        checkServerConnectivity()
    }

    func checkServerConnectivity() {
        let server = config.activeServer
        Task { @MainActor in
            do {
                _ = try await transcriptionService.fetchHealth(server: server)
                startupIssue = nil
            } catch {
                startupIssue = .serverUnreachable(error.localizedDescription)
            }
        }
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
                    modelMemoryMb = health.memoryMb
                } else {
                    modelState = .unloaded
                    modelMemoryMb = nil
                }
            } catch {
                modelState = .error("Sin conexión")
                modelMemoryMb = nil
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
            audioLevel = 0
            try recorder.startRecording(deviceUID: deviceUID)
            status = .recording
            beginLiveModeIfEligible()
        } catch {
            log.error("Error al iniciar grabación: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            if config.soundFeedback {
                Self.playSound("Basso")
            }
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
        recorder.onChunk = nil
        endLiveModeDiscarding()
        if config.soundFeedback {
            Self.playSound("Pop")
        }
        status = .idle
    }

    func stopAndTranscribe() {
        guard status == .recording else {
            log.warning("stopAndTranscribe ignorado — estado actual: \(self.status.label)")
            return
        }

        let server = config.activeServer
        let tailMs = config.recordingTailMs
        let language = config.transcriptionLanguage.code

        Task { @MainActor in
            // Margen: seguir grabando un instante para no cortar el final de la frase.
            if tailMs > 0 {
                try? await Task.sleep(for: .milliseconds(tailMs))
            }

            let audioData: Data
            do {
                audioData = try recorder.stopRecording()
            } catch AudioRecorderError.discardedTooShort {
                #if DEBUG
                log.info("Grabación descartada — muy corta o sin voz detectable")
                #endif
                recorder.onChunk = nil
                endLiveModeDiscarding()
                if config.soundFeedback {
                    Self.playSound("Pop")
                }
                status = .idle
                return
            } catch {
                log.error("Error al detener grabación: \(error.localizedDescription)")
                recorder.onChunk = nil
                endLiveModeDiscarding()
                status = .error(error.localizedDescription)
                if config.soundFeedback {
                    Self.playSound("Basso")
                }
                try? await Task.sleep(for: .seconds(3))
                if case .error = status { status = .idle }
                return
            }
            #if DEBUG
            log.info("Grabación detenida — \(audioData.count) bytes de audio")
            #endif
            recorder.onChunk = nil
            status = .transcribing

            if liveModeActive {
                let finalEvent = await awaitLiveFinal(timeoutMs: 4000)
                liveTranscriptionService.disconnect()
                #if DEBUG
                log.info("Live: al finalizar — didInject=\(self.axInjector.didInjectAnything, privacy: .public), degraded=\(self.axInjector.sessionDegraded, privacy: .public), gotFinal=\(finalEvent != nil, privacy: .public)")
                #endif

                if case .final(let text, let durationMs, _) = finalEvent,
                   axInjector.didInjectAnything, !axInjector.sessionDegraded {
                    // El texto en vivo ya está insertado — el final puede diferir
                    // levemente del último parcial, así que se aplica una vez más.
                    axInjector.replaceLiveText(with: text)
                    lastTranscription = text
                    config.addTranscription(TranscriptionEntry(
                        text: text, serverName: server.name, durationMs: durationMs
                    ))
                    axInjector.reset()
                    liveModeActive = false
                    status = .success
                    try? await Task.sleep(for: .seconds(2))
                    if status == .success { status = .idle }
                    return
                }

                // Modo live activo pero sin texto sostenido (cero parciales,
                // sesión degradada o timeout) — cae al flujo batch de siempre
                // usando el audio completo que ya se capturó igual.
                axInjector.reset()
                liveModeActive = false
            }

            do {
                let response = try await transcriptionService.transcribe(
                    audioData: audioData,
                    server: server,
                    language: language
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
                if config.soundFeedback {
                    Self.playSound("Basso")
                }
                try? await Task.sleep(for: .seconds(3))
                if case .error = status { status = .idle }
            }
        }
    }

    // MARK: - Live transcription

    /// Backend Parakeet activo (local o remoto) — solo ese backend soporta
    /// streaming; con Whisper el modo live simplemente no se activa.
    private var activeBackendIsParakeet: Bool {
        let modelId = config.activeServerIsLocal ? config.localServerModelId : serverCurrentModel
        return supportedModels.first(where: { $0.id == modelId })?.backend == "parakeet"
    }

    private var liveModeEligible: Bool {
        config.liveTranscriptionEnabled && config.dictationMode == .raw && activeBackendIsParakeet
    }

    /// Se llama justo después de que el motor de audio arranca: fija el
    /// campo de texto objetivo (si es elegible y AX lo permite) y conecta
    /// el WebSocket de streaming. Si algo no aplica, no hace nada — el
    /// dictado sigue como el flujo batch de siempre.
    private func beginLiveModeIfEligible() {
        liveModeActive = false
        recorder.onChunk = nil

        #if DEBUG
        log.info("Live: eligible=\(self.liveModeEligible, privacy: .public) (enabled=\(self.config.liveTranscriptionEnabled, privacy: .public), raw=\(self.config.dictationMode == .raw, privacy: .public), parakeet=\(self.activeBackendIsParakeet, privacy: .public))")
        #endif
        guard liveModeEligible else { return }
        let locked = axInjector.probeAndLock()
        #if DEBUG
        log.info("Live: probeAndLock=\(locked, privacy: .public)")
        #endif
        guard locked else { return }

        liveModeActive = true
        liveTranscriptionService.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .partial(let text):
                #if DEBUG
                log.info("Live: partial (\(text.count, privacy: .public) chars)")
                #endif
                DispatchQueue.main.async { self.axInjector.replaceLiveText(with: text) }
            case .final(let text, _, _):
                #if DEBUG
                log.info("Live: final (\(text.count, privacy: .public) chars)")
                #endif
                DispatchQueue.main.async {
                    self.liveFinalContinuation?.resume(returning: event)
                    self.liveFinalContinuation = nil
                }
            case .error(let detail):
                #if DEBUG
                log.error("Live: error del servidor — \(detail, privacy: .public)")
                #endif
                DispatchQueue.main.async {
                    self.liveFinalContinuation?.resume(returning: event)
                    self.liveFinalContinuation = nil
                }
            case .closed:
                #if DEBUG
                log.info("Live: socket cerrado")
                #endif
                DispatchQueue.main.async {
                    self.liveFinalContinuation?.resume(returning: event)
                    self.liveFinalContinuation = nil
                }
            }
        }
        liveTranscriptionService.connect(server: config.activeServer)
        recorder.onChunk = { [weak self] data in
            self?.liveTranscriptionService.sendChunk(data)
        }
    }

    /// Pide el resultado final de la sesión live y espera a que llegue (con
    /// timeout, por si el servidor no responde a "stop").
    private func awaitLiveFinal(timeoutMs: Int) async -> LiveTranscriptionService.Event? {
        liveTranscriptionService.sendStop()
        return await withCheckedContinuation { continuation in
            liveFinalContinuation = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(timeoutMs))
                if let pending = self.liveFinalContinuation {
                    self.liveFinalContinuation = nil
                    pending.resume(returning: nil)
                }
            }
        }
    }

    /// Cierra una sesión live sin usar su resultado (cancelación, o la
    /// grabación completa se descartó) y borra cualquier texto ya insertado.
    private func endLiveModeDiscarding() {
        guard liveModeActive else { return }
        liveTranscriptionService.sendStop()
        liveTranscriptionService.disconnect()
        axInjector.clearInjectedText()
        axInjector.reset()
        liveModeActive = false
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

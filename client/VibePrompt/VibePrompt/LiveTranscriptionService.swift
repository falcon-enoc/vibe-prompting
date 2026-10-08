import Foundation
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "LiveTranscriptionService")

/// Cliente WebSocket para /transcribe/stream. Envía audio PCM16LE mono 16kHz
/// a medida que se captura y recibe transcripciones parciales/finales en vivo.
/// El servidor cierra la conexión con código 1008 si el backend activo no
/// soporta streaming — pero `AppState` ya evita conectar en ese caso
/// filtrando por backend antes de llamar a `connect(server:)`, así que
/// aquí un cierre temprano no se distingue de un error de red: ambos se
/// reportan como `.closed` y el llamador cae al flujo batch por ausencia
/// de `.final`, sin necesitar saber la causa exacta.
final class LiveTranscriptionService {
    enum Event {
        /// `stableText` cubre solo los tokens finalizados (el modelo nunca
        /// los revisa); `text` es el mejor intento completo, incluyendo la
        /// cola en borrador que se re-decodifica en cada chunk y puede
        /// cambiar de palabras o de idioma hasta que finaliza.
        case partial(text: String, stableText: String)
        case final(text: String, durationMs: Double, processingMs: Double)
        case error(String)
        case closed
    }

    private var task: URLSessionWebSocketTask?
    var onEvent: ((Event) -> Void)?

    /// `sendChunk` llega desde el hilo del tap de audio y `sendStop` desde
    /// main — URLSessionWebSocketTask.send() no está documentado como seguro
    /// ante llamadas concurrentes desde varios hilos, y sin serializar acá el
    /// frame de "stop" podía perderse o corromper la sesión (el servidor
    /// nunca lo veía, el cliente esperaba el "final" y agotaba el timeout).
    /// También sirve para acumular chunks (ver `pendingAudio` abajo) sin
    /// carreras de datos.
    private let sendQueue = DispatchQueue(label: "cl.enocfalcon.vibeprompt.livetranscription.send")

    /// El tap de audio entrega buffers cada ~100-200ms — mandar cada uno
    /// como su propio mensaje WS satura al servidor: cada llamada a
    /// add_audio() en parakeet-mlx tiene un costo fijo no trivial (releer el
    /// contexto de atención), así que muchos chunks chicos por segundo dejan
    /// de alcanzar tiempo real (medido: ~4x más lento que agrupar en chunks
    /// más grandes). Acumulamos aquí y mandamos por lotes de ~700ms.
    private var pendingAudio = Data()
    private let flushThresholdBytes = 22400 // 700ms de PCM16 mono 16kHz (16000 * 0.7 * 2 bytes)

    func connect(server: ServerConfig) {
        guard let httpURL = URL(string: server.url),
              var components = URLComponents(url: httpURL, resolvingAgainstBaseURL: false) else { return }
        components.scheme = (components.scheme == "https") ? "wss" : "ws"
        components.path = "/transcribe/stream"
        guard let wsURL = components.url else { return }

        var request = URLRequest(url: wsURL)
        request.setValue(server.apiKey, forHTTPHeaderField: "X-API-Key")

        log.info("connect: \(wsURL.absoluteString, privacy: .public)")
        let newTask = URLSession.shared.webSocketTask(with: request)
        task = newTask
        newTask.resume()
        receiveLoop()
    }

    func sendChunk(_ data: Data) {
        sendQueue.async { [weak self] in
            guard let self else { return }
            self.pendingAudio.append(data)
            if self.pendingAudio.count >= self.flushThresholdBytes {
                self.flushPendingAudio()
            }
        }
    }

    func sendStop() {
        sendQueue.async { [weak self] in
            guard let self else { return }
            self.flushPendingAudio()
            self.task?.send(.string("stop")) { error in
                if let error {
                    log.error("Error enviando stop: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Debe llamarse solo desde `sendQueue`.
    private func flushPendingAudio() {
        guard !pendingAudio.isEmpty else { return }
        let toSend = pendingAudio
        pendingAudio.removeAll()
        task?.send(.data(toSend)) { error in
            if let error {
                log.error("Error enviando chunk: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onEvent = nil
        sendQueue.async { [weak self] in
            self?.pendingAudio.removeAll()
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                log.debug("WebSocket cerrado: \(error.localizedDescription, privacy: .public)")
                self.onEvent?(.closed)
            case .success(let message):
                if case .string(let text) = message, let data = text.data(using: .utf8) {
                    self.handleMessage(data)
                }
                self.receiveLoop()
            }
        }
    }

    private func handleMessage(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "partial":
            onEvent?(.partial(
                text: obj["text"] as? String ?? "",
                stableText: obj["stable_text"] as? String ?? ""
            ))
        case "final":
            onEvent?(.final(
                text: obj["text"] as? String ?? "",
                durationMs: obj["duration_ms"] as? Double ?? 0,
                processingMs: obj["processing_ms"] as? Double ?? 0
            ))
        case "error":
            onEvent?(.error(obj["detail"] as? String ?? "unknown"))
        default:
            break
        }
    }
}

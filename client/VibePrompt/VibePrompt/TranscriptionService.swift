import Foundation
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "TranscriptionService")

struct TranscribeResponse: Codable {
    let text: String
    let language: String?
    let durationMs: Double
    let processingMs: Double
    let model: String

    enum CodingKeys: String, CodingKey {
        case text, language, model
        case durationMs = "duration_ms"
        case processingMs = "processing_ms"
    }
}

struct ServerModelInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let backend: String
    let sizeMb: Int
    let downloaded: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, backend, downloaded
        case sizeMb = "size_mb"
    }
}

struct ModelsResponse: Codable {
    let models: [ServerModelInfo]
    let current: String
}

struct HealthResponse: Codable {
    let status: String
    let modelLoaded: Bool
    let model: String?
    let idleSeconds: Int
    let idleUnloadMinutes: Int

    enum CodingKeys: String, CodingKey {
        case status, model
        case modelLoaded = "model_loaded"
        case idleSeconds = "idle_seconds"
        case idleUnloadMinutes = "idle_unload_minutes"
    }
}

enum TranscriptionError: LocalizedError {
    case invalidURL
    case httpError(Int, String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "URL del servidor inválida."
        case .httpError(let code, let body): "Error HTTP \(code): \(body)"
        case .decodingError(let msg): "Error al decodificar respuesta: \(msg)"
        }
    }
}

final class TranscriptionService {

    // MARK: - Health

    func fetchHealth(server: ServerConfig) async throws -> HealthResponse {
        guard let url = URL(string: "\(server.url)/health") else {
            throw TranscriptionError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    // MARK: - Models

    func fetchModels(server: ServerConfig) async throws -> ModelsResponse {
        guard let url = URL(string: "\(server.url)/models") else {
            throw TranscriptionError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(server.apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, body)
        }
        return try JSONDecoder().decode(ModelsResponse.self, from: data)
    }

    func switchModel(server: ServerConfig, modelId: String, adminToken: String) async throws {
        guard let url = URL(string: "\(server.url)/models/switch?model_id=\(modelId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? modelId)") else {
            throw TranscriptionError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(adminToken, forHTTPHeaderField: "X-Admin-Token")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, body)
        }
    }

    // MARK: - Transcribe

    func transcribe(
        audioData: Data,
        server: ServerConfig,
        language: String? = nil
    ) async throws -> TranscribeResponse {
        #if DEBUG
        log.info("POST \(server.url)/transcribe — audio: \(audioData.count) bytes")
        #endif

        guard let url = URL(string: "\(server.url)/transcribe") else {
            throw TranscriptionError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(server.apiKey, forHTTPHeaderField: "X-API-Key")

        var body = Data()
        let crlf = "\r\n"

        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.wav\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(audioData)
        body.append(crlf.data(using: .utf8)!)

        if let language {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\(crlf)\(crlf)".data(using: .utf8)!)
            body.append(language.data(using: .utf8)!)
            body.append(crlf.data(using: .utf8)!)
        }
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.error("Error de red: \(error.localizedDescription)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.httpError(0, "No HTTP response")
        }

        let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
        #if DEBUG
        log.info("HTTP \(httpResponse.statusCode) — \(bodyStr.prefix(200))")
        #endif

        guard httpResponse.statusCode == 200 else {
            throw TranscriptionError.httpError(httpResponse.statusCode, bodyStr)
        }

        do {
            let decoded = try JSONDecoder().decode(TranscribeResponse.self, from: data)
            #if DEBUG
            log.info("Transcripción OK: \"\(decoded.text.prefix(80))\" (\(decoded.processingMs, format: .fixed(precision: 0))ms)")
            #endif
            return decoded
        } catch {
            log.error("Error decodificando JSON: \(error.localizedDescription)")
            throw TranscriptionError.decodingError(error.localizedDescription)
        }
    }
}

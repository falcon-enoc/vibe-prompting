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

struct WhisperModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let sizeMb: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case sizeMb = "size_mb"
    }
}

struct ModelsResponse: Codable {
    let models: [WhisperModel]
    let current: String
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

    // MARK: - Models

    func fetchModels(serverURL: String, apiKey: String) async throws -> ModelsResponse {
        guard let url = URL(string: "\(serverURL)/models") else {
            throw TranscriptionError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, body)
        }
        return try JSONDecoder().decode(ModelsResponse.self, from: data)
    }

    // MARK: - Transcribe

    func transcribe(
        audioData: Data,
        serverURL: String,
        apiKey: String,
        language: String? = nil,
        model: String? = nil
    ) async throws -> TranscribeResponse {
        #if DEBUG
        log.info("POST \(serverURL)/transcribe — audio: \(audioData.count) bytes, apiKey: \(apiKey.prefix(8))...")
        #endif

        guard let url = URL(string: "\(serverURL)/transcribe") else {
            log.error("URL inválida: \(serverURL)/transcribe")
            throw TranscriptionError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

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
        if let model, !model.isEmpty {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)".data(using: .utf8)!)
            body.append(model.data(using: .utf8)!)
            body.append(crlf.data(using: .utf8)!)
        }
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        request.httpBody = body

        #if DEBUG
        log.info("Enviando request (\(body.count) bytes)...")
        #endif

        let (data, response) : (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.error("Error de red: \(error.localizedDescription)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            log.error("Respuesta no HTTP")
            throw TranscriptionError.httpError(0, "No HTTP response")
        }

        let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
        #if DEBUG
        log.info("HTTP \(httpResponse.statusCode) — respuesta: \(bodyStr.prefix(200))")
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

import Foundation

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

enum TranscriptionError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "URL del servidor inválida."
        case .httpError(let code): "Error HTTP \(code)."
        case .decodingError(let msg): "Error al decodificar respuesta: \(msg)"
        }
    }
}

final class TranscriptionService {
    func transcribe(
        audioData: Data,
        serverURL: String,
        apiKey: String,
        language: String? = nil
    ) async throws -> TranscribeResponse {
        guard let url = URL(string: "\(serverURL)/transcribe") else {
            throw TranscriptionError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        var body = Data()
        let crlf = "\r\n"

        // Audio part
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.wav\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(audioData)
        body.append(crlf.data(using: .utf8)!)

        // Optional language part
        if let language {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\(crlf)\(crlf)".data(using: .utf8)!)
            body.append(language.data(using: .utf8)!)
            body.append(crlf.data(using: .utf8)!)
        }

        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.httpError(0)
        }
        guard httpResponse.statusCode == 200 else {
            throw TranscriptionError.httpError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(TranscribeResponse.self, from: data)
        } catch {
            throw TranscriptionError.decodingError(error.localizedDescription)
        }
    }
}

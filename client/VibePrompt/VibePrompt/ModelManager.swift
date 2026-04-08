import Foundation
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "ModelManager")

struct SupportedModel: Identifiable, Hashable {
    let id: String
    let name: String
    let backend: String
    let sizeMb: Int
    let files: [String]
}

let supportedModels: [SupportedModel] = [
    SupportedModel(
        id: "mlx-community/whisper-tiny-mlx",
        name: "Whisper Tiny",
        backend: "whisper",
        sizeMb: 39,
        files: ["config.json", "weights.npz"]
    ),
    SupportedModel(
        id: "mlx-community/whisper-base-mlx",
        name: "Whisper Base",
        backend: "whisper",
        sizeMb: 137,
        files: ["config.json", "weights.npz"]
    ),
    SupportedModel(
        id: "mlx-community/parakeet-tdt-0.6b-v3",
        name: "Parakeet TDT 0.6B",
        backend: "parakeet",
        sizeMb: 2300,
        files: ["config.json", "model.safetensors"]
    ),
]

@Observable
final class ModelManager {
    var models: [ModelDownloadState] = []
    var activeDownloadId: String?
    var downloadProgress: Double = 0
    var errorMessage: String?

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageURL = appSupport.appendingPathComponent("VibePrompt/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        refreshState()
    }

    func refreshState() {
        models = supportedModels.map { model in
            ModelDownloadState(
                model: model,
                downloaded: isDownloaded(model.id)
            )
        }
    }

    func isDownloaded(_ modelId: String) -> Bool {
        let dir = modelDir(modelId)
        let configExists = FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path)
        return configExists
    }

    func modelDir(_ modelId: String) -> URL {
        storageURL.appendingPathComponent(modelId.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    func download(modelId: String, hfToken: String?) async {
        guard let model = supportedModels.first(where: { $0.id == modelId }) else { return }
        let dir = modelDir(modelId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        await MainActor.run {
            activeDownloadId = modelId
            downloadProgress = 0
            errorMessage = nil
        }

        let totalFiles = model.files.count
        var failed = false
        for (index, file) in model.files.enumerated() {
            let fileURL = URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(file)")!
            var request = URLRequest(url: fileURL)
            if let token = hfToken, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (tempURL, response) = try await URLSession.shared.download(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let msg = code == 401 ? "Token HF inválido o requerido" : "HTTP \(code)"
                    await MainActor.run { errorMessage = "Error descargando \(file): \(msg)" }
                    failed = true
                    break
                }
                let dest = dir.appendingPathComponent(file)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)

                await MainActor.run {
                    downloadProgress = Double(index + 1) / Double(totalFiles)
                }
            } catch {
                await MainActor.run { errorMessage = "Error de red: \(error.localizedDescription)" }
                failed = true
                break
            }
        }

        if failed {
            // Clean up partial download
            try? FileManager.default.removeItem(at: dir)
        }

        await MainActor.run {
            activeDownloadId = nil
            downloadProgress = 0
            refreshState()
        }
    }

    func delete(modelId: String) {
        let dir = modelDir(modelId)
        try? FileManager.default.removeItem(at: dir)
        refreshState()
    }
}

struct ModelDownloadState: Identifiable, Hashable {
    var id: String { model.id }
    let model: SupportedModel
    let downloaded: Bool
}

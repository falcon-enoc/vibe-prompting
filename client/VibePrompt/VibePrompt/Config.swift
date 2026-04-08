import SwiftUI

enum HotkeyMode: String, CaseIterable {
    case pushToTalk = "push-to-talk"
    case toggle = "toggle"

    var label: String {
        switch self {
        case .pushToTalk: "Mantener para grabar"
        case .toggle: "Click para iniciar/parar"
        }
    }
}

struct ServerConfig: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var apiKey: String
    var hfToken: String

    init(id: UUID = UUID(), name: String = "Local", url: String = "http://localhost:8420", apiKey: String = "", hfToken: String = "") {
        self.id = id
        self.name = name
        self.url = url
        self.apiKey = apiKey
        self.hfToken = hfToken
    }
}

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
    let serverName: String
    let durationMs: Double

    init(text: String, serverName: String, durationMs: Double) {
        self.id = UUID()
        self.timestamp = Date()
        self.text = text
        self.serverName = serverName
        self.durationMs = durationMs
    }
}

@Observable
final class AppConfig {
    var servers: [ServerConfig] = {
        guard let data = UserDefaults.standard.data(forKey: "servers"),
              let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data),
              !decoded.isEmpty else {
            return [ServerConfig()]
        }
        return decoded
    }() {
        didSet { save("servers", try? JSONEncoder().encode(servers)) }
    }

    var selectedServerID: UUID = {
        guard let str = UserDefaults.standard.string(forKey: "selectedServerID"),
              let uuid = UUID(uuidString: str) else { return UUID() }
        return uuid
    }() {
        didSet { UserDefaults.standard.set(selectedServerID.uuidString, forKey: "selectedServerID") }
    }

    var autoPaste: Bool = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "autoPaste") }
    }

    var selectedMicrophoneUID: String = UserDefaults.standard.string(forKey: "selectedMicrophoneUID") ?? "" {
        didSet { UserDefaults.standard.set(selectedMicrophoneUID, forKey: "selectedMicrophoneUID") }
    }

    var hotkeyModeRaw: String = UserDefaults.standard.string(forKey: "hotkeyModeRaw") ?? HotkeyMode.pushToTalk.rawValue {
        didSet { UserDefaults.standard.set(hotkeyModeRaw, forKey: "hotkeyModeRaw") }
    }

    var transcriptionHistory: [TranscriptionEntry] = {
        guard let data = UserDefaults.standard.data(forKey: "transcriptionHistory"),
              let decoded = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) else { return [] }
        return decoded
    }() {
        didSet { save("transcriptionHistory", try? JSONEncoder().encode(transcriptionHistory)) }
    }

    // MARK: - Computed

    var hotkeyMode: HotkeyMode {
        get { HotkeyMode(rawValue: hotkeyModeRaw) ?? .pushToTalk }
        set { hotkeyModeRaw = newValue.rawValue }
    }

    var activeServer: ServerConfig {
        servers.first(where: { $0.id == selectedServerID }) ?? servers.first ?? ServerConfig()
    }

    // MARK: - Mutations

    func addServer(_ server: ServerConfig) {
        servers.append(server)
    }

    func removeServer(id: UUID) {
        servers.removeAll(where: { $0.id == id })
        if selectedServerID == id {
            selectedServerID = servers.first?.id ?? UUID()
        }
    }

    func addTranscription(_ entry: TranscriptionEntry) {
        transcriptionHistory.insert(entry, at: 0)
        if transcriptionHistory.count > 50 {
            transcriptionHistory = Array(transcriptionHistory.prefix(50))
        }
    }

    func clearHistory() {
        transcriptionHistory = []
    }

    private func save(_ key: String, _ data: Data?) {
        UserDefaults.standard.set(data, forKey: key)
    }
}

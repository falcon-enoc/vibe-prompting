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

    var hfToken: String = UserDefaults.standard.string(forKey: "hfToken") ?? "" {
        didSet { UserDefaults.standard.set(hfToken, forKey: "hfToken") }
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
        var s = server
        s.url = Self.normalizeURL(s.url)
        servers.append(s)
    }

    func updateServer(id: UUID, name: String? = nil, url: String? = nil, apiKey: String? = nil, hfToken: String? = nil) {
        guard let idx = servers.firstIndex(where: { $0.id == id }) else { return }
        if let name { servers[idx].name = name }
        if let url { servers[idx].url = Self.normalizeURL(url) }
        if let apiKey { servers[idx].apiKey = apiKey }
        if let hfToken { servers[idx].hfToken = hfToken }
    }

    func removeServer(id: UUID) {
        guard servers.count > 1 else { return }
        servers.removeAll(where: { $0.id == id })
        if selectedServerID == id {
            selectedServerID = servers.first?.id ?? UUID()
        }
    }

    static func normalizeURL(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty && !u.contains("://") {
            u = "http://\(u)"
        }
        if u.hasSuffix("/") { u = String(u.dropLast()) }
        return u
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

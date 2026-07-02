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

enum DictationMode: String, CaseIterable {
    case raw = "raw"
    case informal = "informal"
    case bullets = "bullets"
    case technical = "technical"

    var label: String {
        switch self {
        case .raw: "Texto limpio"
        case .informal: "Mensaje informal"
        case .bullets: "Nota con bullets"
        case .technical: "Comando técnico"
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable {
    case auto = "auto"
    case es = "es"
    case en = "en"
    case pt = "pt"
    case fr = "fr"
    case de = "de"
    case it = "it"

    var label: String {
        switch self {
        case .auto: "Automático"
        case .es: "Español"
        case .en: "English"
        case .pt: "Português"
        case .fr: "Français"
        case .de: "Deutsch"
        case .it: "Italiano"
        }
    }

    /// Código ISO 639-1 a enviar al servidor, o `nil` si es automático.
    var code: String? { self == .auto ? nil : rawValue }
}

struct ServerConfig: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var apiKey: String
    var hfToken: String
    var adminToken: String

    init(id: UUID = UUID(), name: String = "Local", url: String = "http://127.0.0.1:8420", apiKey: String = "", hfToken: String = "", adminToken: String = "") {
        self.id = id
        self.name = name
        self.url = url
        self.apiKey = apiKey
        self.hfToken = hfToken
        self.adminToken = adminToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        hfToken = try container.decode(String.self, forKey: .hfToken)
        adminToken = try container.decodeIfPresent(String.self, forKey: .adminToken) ?? ""
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

    var dictationModeRaw: String = UserDefaults.standard.string(forKey: "dictationModeRaw") ?? DictationMode.raw.rawValue {
        didSet { UserDefaults.standard.set(dictationModeRaw, forKey: "dictationModeRaw") }
    }

    var transcriptionLanguageRaw: String = UserDefaults.standard.string(forKey: "transcriptionLanguageRaw") ?? TranscriptionLanguage.auto.rawValue {
        didSet { UserDefaults.standard.set(transcriptionLanguageRaw, forKey: "transcriptionLanguageRaw") }
    }

    /// Margen (ms) que se sigue grabando tras pedir el corte, para no perder el final.
    var recordingTailMs: Int = UserDefaults.standard.object(forKey: "recordingTailMs") as? Int ?? 250 {
        didSet { UserDefaults.standard.set(recordingTailMs, forKey: "recordingTailMs") }
    }

    var soundFeedback: Bool = UserDefaults.standard.object(forKey: "soundFeedback") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundFeedback, forKey: "soundFeedback") }
    }

    var launchAtLogin: Bool = UserDefaults.standard.bool(forKey: "launchAtLogin") {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLoginManager.update(launchAtLogin)
        }
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

    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    /// Ruta del proyecto vibe-prompt desde donde se lanza el servidor local
    /// (debe contener `.venv/` y `server/`). Vacío = autodetectar.
    var localServerProjectPath: String = UserDefaults.standard.string(forKey: "localServerProjectPath") ?? "" {
        didSet { UserDefaults.standard.set(localServerProjectPath, forKey: "localServerProjectPath") }
    }

    /// Modelo con el que arranca el servidor local.
    var localServerModelId: String = UserDefaults.standard.string(forKey: "localServerModelId") ?? "mlx-community/parakeet-tdt-0.6b-v3" {
        didSet { UserDefaults.standard.set(localServerModelId, forKey: "localServerModelId") }
    }

    // MARK: - Computed

    var hotkeyMode: HotkeyMode {
        get { HotkeyMode(rawValue: hotkeyModeRaw) ?? .pushToTalk }
        set { hotkeyModeRaw = newValue.rawValue }
    }

    var dictationMode: DictationMode {
        get { DictationMode(rawValue: dictationModeRaw) ?? .raw }
        set { dictationModeRaw = newValue.rawValue }
    }

    var transcriptionLanguage: TranscriptionLanguage {
        get { TranscriptionLanguage(rawValue: transcriptionLanguageRaw) ?? .auto }
        set { transcriptionLanguageRaw = newValue.rawValue }
    }

    var activeServer: ServerConfig {
        servers.first(where: { $0.id == selectedServerID }) ?? servers.first ?? ServerConfig()
    }

    // MARK: - Servidor local

    /// ¿La URL apunta a un servidor en esta misma máquina?
    static func isLocalURL(_ url: String) -> Bool {
        let u = url.lowercased()
        return u.contains("127.0.0.1") || u.contains("localhost") || u.contains("0.0.0.0")
    }

    var activeServerIsLocal: Bool { Self.isLocalURL(activeServer.url) }

    /// Puerto del servidor activo (por defecto 8420).
    var activeServerPort: Int {
        URLComponents(string: activeServer.url)?.port ?? 8420
    }

    /// Ruta del proyecto resuelta: la configurada si es válida, si no autodetectada.
    var resolvedProjectRoot: String? {
        if !localServerProjectPath.isEmpty, Self.isValidProjectRoot(localServerProjectPath) {
            return localServerProjectPath
        }
        return Self.autodetectProjectRoot()
    }

    /// Una ruta es válida si contiene el venv y el paquete del servidor.
    static func isValidProjectRoot(_ path: String) -> Bool {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let fm = FileManager.default
        return fm.fileExists(atPath: root.appendingPathComponent(".venv/bin/python").path)
            && fm.fileExists(atPath: root.appendingPathComponent("server/src/vibe_prompt/main.py").path)
    }

    /// Busca el proyecto en ubicaciones habituales.
    static func autodetectProjectRoot() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/proyectos/vibe-prompt",
            "\(home)/Developer/vibe-prompt",
            "\(home)/vibe-prompt",
            "\(home)/Documents/vibe-prompt",
        ]
        return candidates.first(where: isValidProjectRoot)
    }

    // MARK: - Mutations

    func addServer(_ server: ServerConfig) {
        var s = server
        s.url = Self.normalizeURL(s.url)
        servers.append(s)
    }

    func updateServer(id: UUID, name: String? = nil, url: String? = nil, apiKey: String? = nil, hfToken: String? = nil, adminToken: String? = nil) {
        guard let idx = servers.firstIndex(where: { $0.id == id }) else { return }
        if let name { servers[idx].name = name }
        if let url { servers[idx].url = Self.normalizeURL(url) }
        if let apiKey { servers[idx].apiKey = apiKey }
        if let hfToken { servers[idx].hfToken = hfToken }
        if let adminToken { servers[idx].adminToken = adminToken }
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

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

@Observable
final class AppConfig {
    var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:8420" {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }

    var apiKey: String = UserDefaults.standard.string(forKey: "apiKey") ?? "" {
        didSet { UserDefaults.standard.set(apiKey, forKey: "apiKey") }
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

    var hotkeyMode: HotkeyMode {
        get { HotkeyMode(rawValue: hotkeyModeRaw) ?? .pushToTalk }
        set { hotkeyModeRaw = newValue.rawValue }
    }
}

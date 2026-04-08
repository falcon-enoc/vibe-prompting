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
    @ObservationIgnored
    @AppStorage("serverURL") var serverURL: String = "http://localhost:8420"

    @ObservationIgnored
    @AppStorage("apiKey") var apiKey: String = ""

    @ObservationIgnored
    @AppStorage("autoPaste") var autoPaste: Bool = true

    @ObservationIgnored
    @AppStorage("hotkeyModeRaw") var hotkeyModeRaw: String = HotkeyMode.pushToTalk.rawValue

    var hotkeyMode: HotkeyMode {
        get { HotkeyMode(rawValue: hotkeyModeRaw) ?? .pushToTalk }
        set { hotkeyModeRaw = newValue.rawValue }
    }
}

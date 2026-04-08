import AppKit
import CoreGraphics
import Foundation

enum PasteService {
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let keyVCode: CGKeyCode = 9 // 'v'
            guard
                let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyVCode, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyVCode, keyDown: false)
            else { return }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}

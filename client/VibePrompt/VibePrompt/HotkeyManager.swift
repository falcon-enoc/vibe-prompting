import Carbon
import CoreGraphics
import AppKit

final class HotkeyManager {
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var mode: HotkeyMode = .pushToTalk

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false

    // Right Command key
    private static let rightCommandKeyCode: UInt16 = 0x36

    func start() {
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            return
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        // We need to pass self as unretained pointer to the callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                manager.handleEvent(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else { return }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(_ event: CGEvent) {
        let flags = event.flags
        let rightCmdDown = flags.contains(.maskSecondaryFn) &&
            NSEvent.modifierFlags.contains(.command)
        // Better: check the actual keycode via NSEvent
        guard let nsEvent = NSEvent(cgEvent: event) else { return }
        let isRightCmd = nsEvent.keyCode == Self.rightCommandKeyCode

        switch mode {
        case .pushToTalk:
            if isRightCmd {
                let cmdDown = flags.contains(.maskCommand)
                if cmdDown && !isRecording {
                    isRecording = true
                    DispatchQueue.main.async { self.onStartRecording?() }
                } else if !cmdDown && isRecording {
                    isRecording = false
                    DispatchQueue.main.async { self.onStopRecording?() }
                }
            }
        case .toggle:
            if isRightCmd && flags.contains(.maskCommand) && !isRecording {
                isRecording = true
                DispatchQueue.main.async { self.onStartRecording?() }
            } else if isRightCmd && flags.contains(.maskCommand) && isRecording {
                isRecording = false
                DispatchQueue.main.async { self.onStopRecording?() }
            }
        }
    }
}

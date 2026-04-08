import Carbon
import CoreGraphics
import AppKit
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "HotkeyManager")

final class HotkeyManager {
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var mode: HotkeyMode = .pushToTalk

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false
    private var permissionTimer: Timer?

    private static let rightCommandKeyCode: UInt16 = 0x36

    func start() {
        guard AXIsProcessTrusted() else {
            #if DEBUG
            log.warning("Sin permiso de Accesibilidad — solicitando y esperando...")
            #endif
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            // Sondear cada segundo hasta que el permiso sea concedido
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self.permissionTimer = nil
                    #if DEBUG
                    log.info("Permiso de Accesibilidad concedido — registrando event tap")
                    #endif
                    self.registerTap()
                }
            }
            return
        }

        registerTap()
    }

    private func registerTap() {
        #if DEBUG
        log.info("Registrando event tap (modo: \(self.mode.rawValue))")
        #endif
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                manager.handleEvent(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            log.error("CGEvent.tapCreate falló — comprueba permiso de Accesibilidad")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        #if DEBUG
        log.info("Event tap activo ✓")
        #endif
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
        guard let nsEvent = NSEvent(cgEvent: event) else { return }
        let isRightCmd = nsEvent.keyCode == Self.rightCommandKeyCode

        switch mode {
        case .pushToTalk:
            if isRightCmd {
                let cmdDown = flags.contains(.maskCommand)
                if cmdDown && !isRecording {
                    #if DEBUG
                    log.info("Right Cmd DOWN → startRecording")
                    #endif
                    isRecording = true
                    DispatchQueue.main.async { self.onStartRecording?() }
                } else if !cmdDown && isRecording {
                    #if DEBUG
                    log.info("Right Cmd UP → stopAndTranscribe")
                    #endif
                    isRecording = false
                    DispatchQueue.main.async { self.onStopRecording?() }
                }
            }
        case .toggle:
            if isRightCmd && flags.contains(.maskCommand) {
                if !isRecording {
                    #if DEBUG
                    log.info("Right Cmd toggle → startRecording")
                    #endif
                    isRecording = true
                    DispatchQueue.main.async { self.onStartRecording?() }
                } else {
                    #if DEBUG
                    log.info("Right Cmd toggle → stopAndTranscribe")
                    #endif
                    isRecording = false
                    DispatchQueue.main.async { self.onStopRecording?() }
                }
            }
        }
    }
}

import Carbon
import CoreGraphics
import AppKit
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "HotkeyManager")

final class HotkeyManager {
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var modeProvider: () -> HotkeyMode = { .pushToTalk }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false
    private var permissionTimer: Timer?
    private var healthTimer: Timer?
    private var pendingAction: DispatchWorkItem?

    private static let rightCommandKeyCode: UInt16 = 0x36
    private static let activationDelay: TimeInterval = 0.25

    func start() {
        guard AXIsProcessTrusted() else {
            #if DEBUG
            log.warning("Sin permiso de Accesibilidad — solicitando y esperando...")
            #endif
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
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
        log.info("Registrando event tap (modo: \(self.modeProvider().rawValue))")
        #endif
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                // Re-enable tap if macOS disabled it
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let userInfo {
                        let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                        if let tap = mgr.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
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

        // Health check: re-enable tap if macOS disabled it silently
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                #if DEBUG
                log.warning("Event tap desactivado — re-habilitando")
                #endif
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }

        #if DEBUG
        log.info("Event tap activo ✓")
        #endif
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        pendingAction?.cancel()
        pendingAction = nil
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
        guard event.type == .flagsChanged else { return }

        let flags = event.flags
        guard let nsEvent = NSEvent(cgEvent: event) else { return }
        let isRightCmd = nsEvent.keyCode == Self.rightCommandKeyCode

        // If not Right Cmd, cancel any pending activation (another key in a combo)
        if !isRightCmd {
            pendingAction?.cancel()
            pendingAction = nil
            return
        }

        // Ignore if other modifiers are held (Shift, Ctrl, Alt = key combo like Cmd+Shift+Z)
        let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate]
        guard flags.intersection(otherModifiers).isEmpty else {
            pendingAction?.cancel()
            pendingAction = nil
            return
        }

        let cmdDown = flags.contains(.maskCommand)

        switch modeProvider() {
        case .pushToTalk:
            if cmdDown && !isRecording {
                scheduleStart()
            } else if !cmdDown && isRecording {
                // Stop immediately — no delay for stopping
                pendingAction?.cancel()
                pendingAction = nil
                #if DEBUG
                log.info("Right Cmd UP → stopAndTranscribe")
                #endif
                isRecording = false
                DispatchQueue.main.async { self.onStopRecording?() }
            }
        case .toggle:
            if cmdDown {
                if !isRecording {
                    scheduleStart()
                } else {
                    // Stop immediately
                    pendingAction?.cancel()
                    pendingAction = nil
                    #if DEBUG
                    log.info("Right Cmd toggle → stopAndTranscribe")
                    #endif
                    isRecording = false
                    DispatchQueue.main.async { self.onStopRecording?() }
                }
            }
        }
    }

    private func scheduleStart() {
        pendingAction?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.pendingAction != nil else { return }
            self.pendingAction = nil
            #if DEBUG
            log.info("Right Cmd → startRecording (tras \(Self.activationDelay)s)")
            #endif
            self.isRecording = true
            self.onStartRecording?()
        }
        pendingAction = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationDelay, execute: item)
    }
}

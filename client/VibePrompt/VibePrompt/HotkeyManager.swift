import Carbon
import CoreGraphics
import AppKit
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "HotkeyManager")

final class HotkeyManager {
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var modeProvider: () -> HotkeyMode = { .pushToTalk }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false
    private var permissionTimer: Timer?
    private var healthTimer: Timer?
    private var pendingStart: DispatchWorkItem?

    private static let rightCommandKeyCode: UInt16 = 0x36
    private static let comboDetectionDelay: TimeInterval = 0.15

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

        // .listenOnly: solo observamos flagsChanged (nunca consumimos/modificamos
        // el evento), así la app NO queda en la ruta de entrega síncrona del
        // teclado. Con .defaultTap, si la app se swapea por presión de RAM, cada
        // tecla modificadora (Shift/⌘) se retrasa y el teclado se "congela".
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
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
        pendingStart?.cancel()
        pendingStart = nil
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

        // If not Right Cmd, it's a combo — cancel pending start or active recording
        if !isRightCmd {
            cancelPending()
            return
        }

        // Other modifiers held = key combo (Cmd+Shift+Z etc)
        let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate]
        guard flags.intersection(otherModifiers).isEmpty else {
            cancelPending()
            return
        }

        let cmdDown = flags.contains(.maskCommand)

        switch modeProvider() {
        case .pushToTalk:
            if cmdDown && !isRecording {
                scheduleStart()
            } else if !cmdDown && isRecording {
                #if DEBUG
                log.info("Right Cmd UP → stopAndTranscribe")
                #endif
                isRecording = false
                DispatchQueue.main.async { self.onStopRecording?() }
            } else if !cmdDown && pendingStart != nil {
                // Key released before recording started — just cancel
                pendingStart?.cancel()
                pendingStart = nil
            }
        case .toggle:
            if cmdDown {
                if !isRecording && pendingStart == nil {
                    scheduleStart()
                } else if isRecording {
                    #if DEBUG
                    log.info("Right Cmd toggle → stopAndTranscribe")
                    #endif
                    isRecording = false
                    DispatchQueue.main.async { self.onStopRecording?() }
                }
            }
        }
    }

    /// Schedule recording start after a short delay to detect combos first.
    /// This prevents the audio engine from starting (and muting system audio) on key combos.
    private func scheduleStart() {
        pendingStart?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.pendingStart != nil else { return }
            self.pendingStart = nil
            #if DEBUG
            log.info("Right Cmd → startRecording (tras \(Self.comboDetectionDelay)s)")
            #endif
            self.isRecording = true
            self.onStartRecording?()
        }
        pendingStart = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.comboDetectionDelay, execute: item)
    }

    /// Cancel pending start or active recording (combo detected).
    private func cancelPending() {
        if pendingStart != nil {
            // Engine hasn't started yet — just cancel the pending start
            pendingStart?.cancel()
            pendingStart = nil
            return
        }
        if isRecording {
            #if DEBUG
            log.info("Combo detectado → cancelando grabación activa")
            #endif
            isRecording = false
            DispatchQueue.main.async { self.onCancelRecording?() }
        }
    }
}

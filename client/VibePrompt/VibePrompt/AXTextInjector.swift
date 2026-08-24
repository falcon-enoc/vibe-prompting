import Foundation
import ApplicationServices
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "AXTextInjector")

/// Inserta texto en vivo directamente en el campo de texto con foco al
/// iniciar la grabación, usando la Accessibility API. El elemento objetivo
/// se fija una sola vez (`probeAndLock`) y nunca se vuelve a consultar,
/// aunque el usuario cambie de ventana mientras sigue dictando.
///
/// Cada actualización reemplaza exactamente el tramo insertado la vez
/// anterior (`kAXSelectedTextRangeAttribute` + `kAXSelectedTextAttribute`),
/// el truco estándar de AX para "reemplazar y dejar el cursor al final".
final class AXTextInjector {
    private var targetElement: AXUIElement?
    private var lastInsertedLength: Int = 0
    private(set) var didInjectAnything = false
    private(set) var sessionDegraded = false

    /// Prueba barata de si el elemento con foco soporta edición vía AX.
    /// Debe llamarse una sola vez, al momento exacto en que arranca la
    /// grabación — no perezosamente en el primer texto parcial — para no
    /// descubrir a mitad de dictado que el campo no es compatible.
    func probeAndLock() -> Bool {
        guard AXIsProcessTrusted() else {
            log.info("probeAndLock: sin permiso de Accesibilidad")
            return false
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusedResult == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            log.info("probeAndLock: sin elemento con foco (AXError \(focusedResult.rawValue, privacy: .public))")
            return false
        }
        let element = focusedRef as! AXUIElement

        // No-op probe: leer el rango seleccionado actual y reescribirlo tal
        // cual, para confirmar que el atributo es legible Y escribible.
        var rangeRef: CFTypeRef?
        let readResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard readResult == .success, let rangeRef else {
            log.info("probeAndLock: elemento con foco no expone selected-text-range (AXError \(readResult.rawValue, privacy: .public))")
            return false
        }
        let writeResult = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeRef)
        guard writeResult == .success else {
            log.info("probeAndLock: selected-text-range no es escribible (AXError \(writeResult.rawValue, privacy: .public))")
            return false
        }

        targetElement = element
        lastInsertedLength = 0
        didInjectAnything = false
        sessionDegraded = false
        log.info("probeAndLock: OK")
        return true
    }

    /// Reemplaza el tramo insertado la última vez con `text`, dejando el
    /// cursor al final. Si algo falla (el campo cambió de forma inesperada,
    /// perdió el atributo, etc.), marca la sesión como degradada y deja de
    /// intentarlo — el llamador debe entonces caer al pegado normal al final.
    func replaceLiveText(with text: String) {
        guard let element = targetElement, !sessionDegraded else { return }
        guard let currentRange = currentSelectedRange(element) else {
            sessionDegraded = true
            return
        }

        let replaceLocation = max(0, currentRange.location - lastInsertedLength)
        var replaceRange = CFRange(location: replaceLocation, length: lastInsertedLength)
        guard let rangeValue = AXValueCreate(.cfRange, &replaceRange) else {
            sessionDegraded = true
            return
        }

        guard AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success else {
            log.info("Reemplazo de texto en vivo falló — sesión degradada")
            sessionDegraded = true
            return
        }

        let expectedLength = (text as NSString).length
        // Algunas apps (terminales como Ghostty/Terminal.app, ciertos
        // editores Electron/Chromium) devuelven éxito en el AXError sin
        // aplicar realmente el cambio — no basta con confiar en el código
        // de retorno, hay que releer el campo y confirmar que el cursor
        // avanzó lo esperado.
        guard let newRange = currentSelectedRange(element),
              newRange.location == replaceLocation + expectedLength,
              newRange.length == 0 else {
            log.info("Reemplazo de texto en vivo no se reflejó en el campo — sesión degradada")
            sessionDegraded = true
            return
        }

        lastInsertedLength = expectedLength
        didInjectAnything = true
    }

    /// Camino de cancelación: borra lo ya insertado en vez de dejarlo a medias.
    func clearInjectedText() {
        guard targetElement != nil, lastInsertedLength > 0 else { return }
        replaceLiveText(with: "")
    }

    func reset() {
        targetElement = nil
        lastInsertedLength = 0
        didInjectAnything = false
        sessionDegraded = false
    }

    private func currentSelectedRange(_ element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }
        var range = CFRange()
        guard AXValueGetValue((rangeRef as! AXValue), .cfRange, &range) else { return nil }
        return range
    }
}

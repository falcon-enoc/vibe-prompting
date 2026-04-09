import Foundation

/// Procesa el texto transcrito según el modo de dictado seleccionado
enum TextPostProcessor {
    static func process(_ text: String, mode: DictationMode) -> String {
        switch mode {
        case .raw: return text
        case .informal: return processInformal(text)
        case .bullets: return processBullets(text)
        case .technical: return processTechnical(text)
        }
    }

    // MARK: - Informal

    /// Minúscula inicial, sin punto final
    private static func processInformal(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        // Minúscula el primer carácter
        let first = result.prefix(1).lowercased()
        result = first + result.dropFirst()

        // Quitar punto final
        if result.hasSuffix(".") {
            result = String(result.dropLast())
        }

        return result
    }

    // MARK: - Bullets

    /// Divide por oraciones y prefija cada una con "- "
    private static func processBullets(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // Separar por ". " o ".\n"
        let parts = trimmed
            .replacingOccurrences(of: ".\n", with: ".\u{0000}")
            .replacingOccurrences(of: ". ", with: ".\u{0000}")
            .components(separatedBy: "\u{0000}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                var l = line
                if l.hasSuffix(".") { l = String(l.dropLast()) }
                return "- \(l)"
            }

        return parts.joined(separator: "\n")
    }

    // MARK: - Technical

    /// Elimina muletillas comunes y pasa a minúsculas
    private static func processTechnical(_ text: String) -> String {
        var result = text.lowercased()

        let fillerWords = [
            "eh", "um", "este", "bueno", "o sea", "pues", "digamos",
            "eh,", "um,", "este,", "bueno,", "o sea,", "pues,", "digamos,"
        ]

        for filler in fillerWords {
            // Reemplazar como palabra completa (con espacios alrededor)
            result = result.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b\\s*",
                with: "",
                options: .regularExpression
            )
        }

        // Limpiar espacios múltiples
        result = result.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

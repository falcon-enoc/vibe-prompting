import Foundation
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "ServerInstaller")

/// Instala el entorno Python del servidor local **desde la app**, sin que el
/// usuario tenga que clonar el repo ni instalar Python a mano.
///
/// Usa el binario `uv` empaquetado en el `.app` (`Contents/Resources/uv`) para:
///   1. Crear un venv en Application Support.
///   2. Descargar un Python 3.12 gestionado (macOS no trae 3.12).
///   3. Instalar el paquete del servidor y sus dependencias (MLX, FastAPI…).
///
/// El directorio resultante imita el layout del repo (`<root>/.venv` +
/// `<root>/server/src/vibe_prompt/main.py`), de modo que `AppConfig` y
/// `LocalServerManager` lo tratan igual que un checkout de desarrollo.
@Observable
final class ServerInstaller {
    enum Status: Equatable {
        case notInstalled
        case installing(phase: String)
        case installed
        case failed(String)

        var isInstalling: Bool {
            if case .installing = self { return true }
            return false
        }
    }

    private(set) var status: Status

    private let logFileURL: URL

    /// Versión del entorno instalado. Se bumpea cuando cambian las deps del
    /// servidor para forzar una reinstalación tras actualizar la app.
    private static let schemaVersion = "1"

    init() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/VibePrompt", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logFileURL = logsDir.appendingPathComponent("server-install.log")
        status = Self.isEnvironmentInstalled() ? .installed : .notInstalled
    }

    // MARK: - Rutas

    /// Raíz del servidor gestionado por la app.
    static var serverSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VibePrompt/server", isDirectory: true)
    }

    private static var venvDir: URL { serverSupportDir.appendingPathComponent(".venv", isDirectory: true) }
    private static var venvPython: URL { venvDir.appendingPathComponent("bin/python") }
    private static var sourceDir: URL { serverSupportDir.appendingPathComponent("server", isDirectory: true) }
    private static var markerURL: URL { serverSupportDir.appendingPathComponent(".installed-version") }

    /// Dónde uv guarda el Python gestionado y su cache (predecible y borrable).
    private static var uvHomeDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VibePrompt/uv", isDirectory: true)
    }

    // MARK: - Estado

    /// ¿Hay un venv válido y con la versión de esquema esperada?
    static func isEnvironmentInstalled() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: venvPython.path),
              fm.fileExists(atPath: sourceDir.appendingPathComponent("src/vibe_prompt/main.py").path)
        else { return false }
        let marker = (try? String(contentsOf: markerURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return marker == expectedMarker
    }

    private static var expectedMarker: String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "\(schemaVersion)-\(appVersion)"
    }

    // MARK: - Instalación

    /// Instala (o reinstala) el entorno del servidor. Idempotente.
    func install() {
        guard !status.isInstalling else { return }

        guard Self.isAppleSilicon else {
            status = .failed("El servidor local requiere un Mac con Apple Silicon (M1 o superior).")
            return
        }
        guard let uvURL = Self.bundledUV else {
            status = .failed("No se encontró el instalador (uv) dentro de la app. Reinstala VibePrompt.")
            return
        }
        guard let bundledSource = Self.bundledServerSource else {
            status = .failed("No se encontró el código del servidor dentro de la app. Reinstala VibePrompt.")
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.runInstall(uvURL: uvURL, bundledSource: bundledSource)
        }
    }

    private func runInstall(uvURL: URL, bundledSource: URL) async {
        let fm = FileManager.default
        Self.resetLog(at: logFileURL)
        appendLog("=== Instalación del servidor local — \(Self.expectedMarker) ===")

        do {
            // 1. Preparar directorios.
            await setPhase("Preparando…")
            try fm.createDirectory(at: Self.serverSupportDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: Self.uvHomeDir, withIntermediateDirectories: true)

            // 2. Copiar la fuente del servidor (fresca en cada install).
            if fm.fileExists(atPath: Self.sourceDir.path) {
                try fm.removeItem(at: Self.sourceDir)
            }
            try fm.copyItem(at: bundledSource, to: Self.sourceDir)
            appendLog("Fuente copiada a \(Self.sourceDir.path)")

            // 3. Crear el venv con un Python 3.12 gestionado por uv.
            await setPhase("Creando entorno (descarga Python)…")
            var code = try await runUV(
                uvURL: uvURL,
                arguments: ["venv", Self.venvDir.path, "--python", "3.12"]
            )
            guard code == 0 else { throw InstallError.step("No se pudo crear el entorno de Python", code) }

            // 4. Instalar el paquete del servidor + dependencias.
            await setPhase("Instalando dependencias (puede tardar)…")
            code = try await runUV(
                uvURL: uvURL,
                arguments: ["pip", "install", "--python", Self.venvPython.path, Self.sourceDir.path]
            )
            guard code == 0 else { throw InstallError.step("No se pudieron instalar las dependencias", code) }

            // 5. Marcar como instalado.
            try Self.expectedMarker.write(to: Self.markerURL, atomically: true, encoding: .utf8)
            appendLog("=== Instalación completada ===")
            log.info("Servidor local instalado en \(Self.serverSupportDir.path)")
            await MainActor.run { self.status = .installed }
        } catch {
            let detail: String
            if case InstallError.step(let msg, let c) = error {
                let tail = lastLogLines(8)
                detail = tail.isEmpty ? "\(msg) (código \(c))." : "\(msg).\n\(tail)"
            } else {
                detail = error.localizedDescription
            }
            appendLog("ERROR: \(detail)")
            log.error("Fallo instalando el servidor local: \(detail)")
            await MainActor.run { self.status = .failed(detail) }
        }
    }

    private enum InstallError: Error {
        case step(String, Int32)
    }

    // MARK: - Subprocesos

    /// Ejecuta `uv` redirigiendo stdout/stderr al log; devuelve el código de salida.
    private func runUV(uvURL: URL, arguments: [String]) async throws -> Int32 {
        appendLog("\n$ uv \(arguments.joined(separator: " "))")

        let proc = Process()
        proc.executableURL = uvURL
        proc.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        // Auto-contenido: uv usa SU propio Python (nunca el del sistema) y guarda
        // interprete + cache en un lugar predecible y borrable.
        env["UV_PYTHON_PREFERENCE"] = "only-managed"
        env["UV_PYTHON_INSTALL_DIR"] = Self.uvHomeDir.appendingPathComponent("python").path
        env["UV_CACHE_DIR"] = Self.uvHomeDir.appendingPathComponent("cache").path
        env["NO_COLOR"] = "1"
        proc.environment = env

        if let fh = try? FileHandle(forWritingTo: logFileURL) {
            fh.seekToEndOfFile()
            proc.standardOutput = fh
            proc.standardError = fh
        }

        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus)
            }
            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Bundle

    static var bundledUV: URL? {
        Bundle.main.url(forResource: "uv", withExtension: nil)
    }

    /// Carpeta `server/` empaquetada (contiene `pyproject.toml` + `src/`).
    static var bundledServerSource: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let dir = res.appendingPathComponent("server", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("pyproject.toml").path) ? dir : nil
    }

    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        // hw.optional.arm64 == 1 en Apple Silicon (incluye apps bajo Rosetta).
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 {
            return value == 1
        }
        return false
    }

    // MARK: - Log

    private func setPhase(_ phase: String) async {
        appendLog("• \(phase)")
        await MainActor.run { self.status = .installing(phase: phase) }
    }

    private static func resetLog(at url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    private func appendLog(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let fh = try? FileHandle(forWritingTo: logFileURL) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        }
    }

    private func lastLogLines(_ n: Int) -> String {
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else { return "" }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(n).joined(separator: "\n")
    }
}

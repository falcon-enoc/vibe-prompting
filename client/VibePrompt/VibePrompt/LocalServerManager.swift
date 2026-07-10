import Foundation
import os

private let log = Logger(subsystem: "cl.enocfalcon.vibeprompt", category: "LocalServer")

/// Lanza y detiene el servidor Python local (uvicorn) como subproceso.
///
/// La app no está en sandbox, así que puede ejecutar el intérprete del venv
/// del proyecto directamente. El modelo y el backend se pasan por variables de
/// entorno para no depender de la carga del `.env` (que es relativa al cwd).
@Observable
final class LocalServerManager {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case failed(String)

        var isBusy: Bool { self == .starting }
        var isUp: Bool { self == .running }
    }

    private(set) var status: Status = .stopped

    private var process: Process?
    /// True mientras detenemos a propósito, para no marcar la salida como error.
    private var intentionalStop = false
    private let logFileURL: URL

    init() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/VibePrompt", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logFileURL = logsDir.appendingPathComponent("local-server.log")
    }

    // MARK: - Ciclo de vida

    /// Arranca el servidor local. Si ya hay uno respondiendo en el puerto (por
    /// ejemplo un proceso huérfano o uno arrancado a mano), lo adopta en vez de
    /// intentar levantar otro.
    func start(projectRoot: String, port: Int, modelId: String, backend: String) {
        guard !(process?.isRunning ?? false) else { return }

        status = .starting
        Task { @MainActor in
            // ¿Ya hay un servidor vivo en ese puerto? Adoptarlo.
            if await isHealthy(port: port) {
                log.info("Servidor local ya activo en :\(port) — adoptado")
                status = .running
                return
            }
            spawn(projectRoot: projectRoot, port: port, modelId: modelId, backend: backend)
        }
    }

    private func spawn(projectRoot: String, port: Int, modelId: String, backend: String) {
        let root = URL(fileURLWithPath: projectRoot, isDirectory: true)
        let pythonURL = root.appendingPathComponent(".venv/bin/python")
        let serverDir = root.appendingPathComponent("server", isDirectory: true)

        guard FileManager.default.fileExists(atPath: pythonURL.path) else {
            status = .failed("No se encontró el venv en \(root.appendingPathComponent(".venv").path). Créalo con: make server-install")
            return
        }
        guard FileManager.default.fileExists(atPath: serverDir.appendingPathComponent("src/vibe_prompt/main.py").path) else {
            status = .failed("La ruta del proyecto no contiene el servidor (server/src/vibe_prompt). Revisa la ruta configurada.")
            return
        }

        let proc = Process()
        proc.executableURL = pythonURL
        proc.arguments = [
            "-m", "uvicorn", "vibe_prompt.main:app",
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--workers", "1",
        ]
        proc.currentDirectoryURL = serverDir

        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = serverDir.appendingPathComponent("src").path
        env["MODEL_ID"] = modelId
        env["MODEL_BACKEND"] = backend
        proc.environment = env

        // Redirigir stdout/stderr al log para poder diagnosticar fallos.
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        if let fh = try? FileHandle(forWritingTo: logFileURL) {
            proc.standardOutput = fh
            proc.standardError = fh
        }

        proc.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            Task { @MainActor in self?.handleTermination(code: code) }
        }

        do {
            intentionalStop = false
            try proc.run()
            process = proc
            log.info("Servidor local lanzado (PID \(proc.processIdentifier)) — modelo \(modelId)")
            waitForHealthy(port: port)
        } catch {
            status = .failed("No se pudo iniciar el servidor: \(error.localizedDescription)")
        }
    }

    /// Detiene el servidor local si lo lanzamos nosotros.
    func stop() {
        guard let proc = process, proc.isRunning else {
            process = nil
            if !status.isUp { status = .stopped } else { status = .stopped }
            return
        }
        intentionalStop = true
        log.info("Deteniendo servidor local (PID \(proc.processIdentifier))")
        proc.terminate()
        process = nil
        status = .stopped
    }

    private func handleTermination(code: Int32) {
        process = nil
        if intentionalStop {
            status = .stopped
            return
        }
        // Salida inesperada: reportar con las últimas líneas del log.
        let tail = lastLogLines(6)
        status = .failed(tail.isEmpty ? "El servidor se detuvo (código \(code))." : tail)
        log.error("Servidor local terminó inesperadamente (código \(code))")
    }

    /// No se pudo resolver la ruta del proyecto (ni configurada, ni autodetectada,
    /// ni instalada por la app).
    func setMissingProjectRoot() {
        status = .failed("El servidor local no está instalado. Instálalo en Preferencias › Servidores.")
    }

    // MARK: - Health

    private func waitForHealthy(port: Int) {
        Task { @MainActor in
            for _ in 0..<60 { // ~30s
                if process?.isRunning != true && !intentionalStop {
                    // Murió durante el arranque; handleTermination ya puso el estado.
                    return
                }
                if await isHealthy(port: port) {
                    status = .running
                    log.info("Servidor local listo en :\(port)")
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if !status.isUp {
                status = .failed("El servidor no respondió a tiempo. Revisa \(logFileURL.path).")
            }
        }
    }

    private func isHealthy(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    private func lastLogLines(_ n: Int) -> String {
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else { return "" }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(n).joined(separator: "\n")
    }
}

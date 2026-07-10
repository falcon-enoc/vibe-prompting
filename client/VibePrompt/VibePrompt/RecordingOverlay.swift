import AppKit
import SwiftUI

// MARK: - Controlador del panel flotante

/// HUD flotante que indica en pantalla el estado de grabación/transcripción.
/// Es un NSPanel sin bordes, no activante y transparente a clicks, que se
/// muestra sobre todas las ventanas (incluidas apps fullscreen) centrado
/// horizontalmente en el tercio inferior de la pantalla activa.
/// Todas las llamadas ocurren en el main thread (los callbacks de hotkey y
/// las transiciones de estado ya se despachan ahí).
final class RecordingOverlayController {
    private let appState: AppState
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// Tamaño del panel; deja aire alrededor de la píldora para su sombra.
    private static let panelSize = NSSize(width: 360, height: 110)

    init(appState: AppState) {
        self.appState = appState
    }

    func statusChanged(_ status: AppStatus) {
        guard appState.config.showRecordingOverlay else {
            hide()
            return
        }
        switch status {
        case .recording, .transcribing:
            hideTask?.cancel()
            hideTask = nil
            show()
        case .success:
            show()
            scheduleHide(after: .milliseconds(900))
        case .error:
            show()
            scheduleHide(after: .milliseconds(1800))
        case .idle:
            hide()
        }
    }

    private func scheduleHide(after delay: Duration) {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Reposicionar en cada show: la pantalla activa puede cambiar.
        // Centrado arriba, justo bajo la barra de menú.
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let f = screen.visibleFrame
            let origin = NSPoint(
                x: f.midX - Self.panelSize.width / 2,
                y: f.maxY - Self.panelSize.height - 6
            )
            panel.setFrame(NSRect(origin: origin, size: Self.panelSize), display: true)
        }

        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        hideTask?.cancel()
        hideTask = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: RecordingOverlayView(appState: appState)
        )
        return panel
    }
}

// MARK: - Vista del HUD

struct RecordingOverlayView: View {
    let appState: AppState

    var body: some View {
        pill
            .frame(
                width: RecordingOverlayController.panelWidth,
                height: RecordingOverlayController.panelHeight
            )
            .colorScheme(.dark)
    }

    private var pill: some View {
        HStack(spacing: 10) {
            switch appState.status {
            case .recording:
                OverlayWaveform(level: { appState.audioLevel })
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                Text("Transcribiendo…")
                    .font(.system(size: 13, weight: .medium))
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Listo")
                    .font(.system(size: 13, weight: .medium))
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Error")
                    .font(.system(size: 13, weight: .medium))
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(liquidGlass)
        .shadow(color: .black.opacity(0.30), radius: 14, y: 5)
        .animation(.easeInOut(duration: 0.2), value: appState.status)
    }

    /// Emulación de "liquid glass" (no hay API nativa en macOS 14):
    /// material translúcido + brillo especular superior + borde con
    /// gradiente que atrapa la luz arriba y se apaga abajo.
    private var liquidGlass: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.28), location: 0),
                                .init(color: .white.opacity(0.04), location: 0.45),
                                .init(color: .white.opacity(0.02), location: 0.8),
                                .init(color: .white.opacity(0.10), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension RecordingOverlayController {
    static var panelWidth: CGFloat { panelSize.width }
    static var panelHeight: CGFloat { panelSize.height }
}

// MARK: - Onda reactiva al micrófono

/// Suavizado del nivel entre frames: ataque rápido, caída lenta,
/// para que la onda respire en vez de saltar.
private final class LevelSmoother {
    private var value: Double = 0

    func update(target: Double) -> Double {
        if target > value {
            value += (target - value) * 0.45
        } else {
            value += (target - value) * 0.10
        }
        return value
    }
}

private struct OverlayWaveform: View {
    /// Nivel actual del micrófono (0–1). Closure para leerlo en cada frame
    /// sin depender del tracking de observación.
    let level: () -> Float

    @State private var smoother = LevelSmoother()
    private let barCount = 15
    private let barWidth: CGFloat = 3

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let lvl = smoother.update(target: Double(level()))
                let spacing = (size.width - CGFloat(barCount) * barWidth) / CGFloat(barCount - 1)
                let mid = Double(barCount - 1) / 2

                for i in 0..<barCount {
                    // Campana hacia el centro + onda viajera para el movimiento orgánico.
                    let envelope = exp(-pow((Double(i) - mid) / (mid * 0.72), 2))
                    let wave = 0.5 + 0.5 * sin(t * 7.5 - Double(i) * 0.9)
                    let amplitude = 0.10 + 0.90 * lvl
                    let h = max(barWidth, CGFloat(0.12 + wave * envelope * amplitude) * size.height)
                    let rect = CGRect(
                        x: CGFloat(i) * (barWidth + spacing),
                        y: (size.height - h) / 2,
                        width: barWidth,
                        height: h
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(.white.opacity(0.95))
                    )
                }
            }
        }
        .frame(width: 130, height: 28)
    }
}

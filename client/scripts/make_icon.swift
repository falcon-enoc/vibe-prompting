// Genera el icono de VibePrompt: squircle con gradiente violeta,
// anillos de onda sutiles y una waveform blanca con glow.
// Uso: swift make_icon.swift <outdir>
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func drawIcon(size: CGFloat) -> CGImage? {
    let scale = size / 1024.0
    guard let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.scaleBy(x: scale, y: scale)

    // Rejilla estándar de iconos macOS: canvas 1024, contenido 824 con esquinas ~185.
    let content = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: content, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Sombra suave del icono sobre el canvas transparente.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 36,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(red: 0.26, green: 0.13, blue: 0.62, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Gradiente diagonal: violeta luminoso arriba → índigo profundo abajo.
    let bg = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: 0.62, green: 0.42, blue: 0.98, alpha: 1),  // #9E6BFA
            CGColor(red: 0.44, green: 0.24, blue: 0.93, alpha: 1),  // #703DEE
            CGColor(red: 0.24, green: 0.10, blue: 0.66, alpha: 1),  // #3D1AA8
        ] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 250, y: 924), end: CGPoint(x: 774, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Brillo radial superior para dar profundidad.
    let glow = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.28),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 980), endRadius: 700, options: [])

    // Anillos concéntricos (ondas) emanando del centro.
    let center = CGPoint(x: 512, y: 512)
    for (radius, alpha) in [(300.0, 0.16), (400.0, 0.10), (500.0, 0.06)] {
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        ctx.setLineWidth(10)
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                     width: radius * 2, height: radius * 2))
    }

    // Waveform: 5 barras blancas con puntas redondeadas y glow.
    let heights: [CGFloat] = [200, 360, 520, 360, 200]
    let barWidth: CGFloat = 72
    let gap: CGFloat = 52
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = center.x - totalWidth / 2

    ctx.setShadow(offset: .zero, blur: 44,
                  color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    for h in heights {
        let bar = CGRect(x: x, y: center.y - h / 2, width: barWidth, height: h)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        x += barWidth + gap
    }
    ctx.fillPath()

    ctx.restoreGState()
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("No se pudo codificar PNG \(url.path)")
    }
    try! data.write(to: url)
}

let fm = FileManager.default
try! fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard let img = drawIcon(size: CGFloat(size)) else { fatalError("render \(size) falló") }
    writePNG(img, to: URL(fileURLWithPath: "\(outDir)/icon_\(size).png"))
    print("icon_\(size).png ✓")
}

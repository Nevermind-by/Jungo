import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"
let fileManager = FileManager.default
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = outputURL.deletingLastPathComponent().appendingPathComponent("Jungo.iconset", isDirectory: true)

try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fillGradient(_ path: NSBezierPath, colors: [NSColor], angle: CGFloat = 90) {
    (NSGradient(colors: colors) ?? NSGradient(starting: colors[0], ending: colors[0]))?.draw(in: path, angle: angle)
}

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "JungoIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать bitmap для иконки"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let u = CGFloat(size)
    let bounds = NSRect(x: 0, y: 0, width: u, height: u)
    let inset = u * 0.035
    let tile = roundedRect(bounds.insetBy(dx: inset, dy: inset), radius: u * 0.225)

    // Deep midnight glass base: rich and dimensional, without a neon frame.
    fillGradient(tile, colors: [
        color(0.075, 0.13, 0.21),
        color(0.035, 0.065, 0.12),
        color(0.055, 0.10, 0.17)
    ], angle: 90)
    // Keep the outer silhouette clean: no bright rim, no neon, no glow.

    // Three glass lanes sit at different depths/heights to give the mark
    // an intentional, slightly asymmetric silhouette at Dock size.
    let laneSpecs: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, top: NSColor, bottom: NSColor)] = [
        (0.205, 0.245, 0.165, 0.49, color(0.20, 0.29, 0.46, 0.88), color(0.10, 0.16, 0.29, 0.96)),
        (0.415, 0.17, 0.17, 0.62, color(0.31, 0.42, 0.61, 0.88), color(0.12, 0.20, 0.34, 0.97)),
        (0.63, 0.235, 0.165, 0.50, color(0.24, 0.35, 0.54, 0.88), color(0.10, 0.17, 0.30, 0.96))
    ]

    for (index, spec) in laneSpecs.enumerated() {
        let rect = NSRect(x: u * spec.x, y: u * spec.y, width: u * spec.w, height: u * spec.h)
        context.saveGraphicsState()

        // A tiny shared perspective lean gives the panels the same slanted
        // top edge as the approved reference while keeping the mark readable.
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: index == 1 ? -7 : -5)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()

        let lane = roundedRect(rect, radius: u * 0.055)
        fillGradient(lane, colors: [spec.top, spec.bottom], angle: 90)
        color(0.76, 0.86, 0.98, 0.18).setStroke()
        lane.lineWidth = max(0.65, u * 0.002)
        lane.stroke()

        // A narrow internal reflection suggests frosted glass; no outer glow.
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: rect.minX + u * 0.018, y: rect.minY + u * 0.055))
        highlight.line(to: NSPoint(x: rect.minX + u * 0.018, y: rect.maxY - u * 0.075))
        highlight.lineWidth = max(0.5, u * 0.003)
        color(0.86, 0.93, 1.0, 0.16).setStroke()
        highlight.stroke()
        context.restoreGraphicsState()
    }

    // The foreground task card is deliberately tilted, echoing the reference
    // concept's layered perspective without adding neon or an illuminated rim.
    let cardRect = NSRect(x: u * 0.285, y: u * 0.405, width: u * 0.43, height: u * 0.235)
    context.saveGraphicsState()
    let cardTransform = NSAffineTransform()
    cardTransform.translateX(by: cardRect.midX, yBy: cardRect.midY)
    cardTransform.rotate(byDegrees: -12)
    cardTransform.translateX(by: -cardRect.midX, yBy: -cardRect.midY)
    cardTransform.concat()

    let card = roundedRect(cardRect, radius: u * 0.055)
    let shadow = NSShadow()
    shadow.shadowColor = color(0.0, 0.015, 0.06, 0.24)
    shadow.shadowBlurRadius = u * 0.009
    shadow.shadowOffset = NSSize(width: 0, height: -u * 0.006)
    shadow.set()
    fillGradient(card, colors: [color(0.37, 0.66, 1.0), color(0.08, 0.31, 0.91)], angle: 90)

    // A restrained surface reflection, contained inside the card only.
    let sheen = NSBezierPath()
    sheen.move(to: NSPoint(x: cardRect.minX + u * 0.02, y: cardRect.maxY - u * 0.025))
    sheen.line(to: NSPoint(x: cardRect.maxX - u * 0.025, y: cardRect.maxY - u * 0.025))
    sheen.lineWidth = max(0.6, u * 0.002)
    color(0.90, 0.96, 1.0, 0.20).setStroke()
    sheen.stroke()
    context.restoreGraphicsState()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    bitmap.size = NSSize(width: size, height: size)
    guard let tiff = bitmap.tiffRepresentation,
          let pngBitmap = NSBitmapImageRep(data: tiff),
          let png = pngBitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "JungoIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось записать PNG иконки"])
    }
    return png
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    try drawIcon(size: variant.pixels).write(to: iconsetURL.appendingPathComponent(variant.name), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "JungoIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil завершился с ошибкой"])
}
try? fileManager.removeItem(at: iconsetURL)
print("Generated app icon: \(outputURL.path)")

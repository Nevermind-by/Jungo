import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"
let fileManager = FileManager.default
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = outputURL.deletingLastPathComponent().appendingPathComponent("Jungo.iconset", isDirectory: true)

try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func gradient(_ path: NSBezierPath, _ colors: [NSColor], angle: CGFloat = 90) {
    NSGradient(colors: colors)?.draw(in: path, angle: angle)
}

func stroke(_ path: NSBezierPath, _ color: NSColor, _ width: CGFloat) {
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "JungoIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать bitmap"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let u = CGFloat(size)
    let bounds = NSRect(x: 0, y: 0, width: u, height: u)

    // Deep ink-blue glass tile. The lighting is broad and internal, never a neon rim.
    let base = rounded(bounds.insetBy(dx: u * 0.035, dy: u * 0.035), u * 0.225)
    gradient(base, [c(0.105, 0.17, 0.28), c(0.045, 0.075, 0.15), c(0.075, 0.12, 0.22)], angle: 135)
    let baseReflection = rounded(NSRect(x: u * 0.08, y: u * 0.67, width: u * 0.84, height: u * 0.20), u * 0.10)
    context.saveGraphicsState()
    base.addClip()
    gradient(baseReflection, [c(0.42, 0.58, 0.78, 0.12), c(0.20, 0.33, 0.52, 0.0)], angle: 90)
    context.restoreGraphicsState()

    // Each column is built from a dark extruded side, a translucent body,
    // an inset face and a soft top-left reflection to create actual material depth.
    struct Panel {
        let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat
        let front: [NSColor]; let side: NSColor
        let angle: CGFloat
    }
    let panels = [
        Panel(x: 0.205, y: 0.245, w: 0.17, h: 0.49,
              front: [c(0.38,0.49,0.68,0.82), c(0.16,0.24,0.40,0.94)],
              side: c(0.055,0.095,0.18,0.96), angle: -4),
        Panel(x: 0.415, y: 0.17, w: 0.175, h: 0.62,
              front: [c(0.55,0.66,0.82,0.86), c(0.23,0.34,0.52,0.96)],
              side: c(0.075,0.12,0.22,0.98), angle: -5),
        Panel(x: 0.635, y: 0.235, w: 0.165, h: 0.50,
              front: [c(0.48,0.63,0.82,0.88), c(0.18,0.31,0.49,0.97)],
              side: c(0.06,0.12,0.23,0.98), angle: -4)
    ]

    for panel in panels {
        let rect = NSRect(x: u * panel.x, y: u * panel.y, width: u * panel.w, height: u * panel.h)
        context.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: panel.angle)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()

        // Extruded lower/right edge gives the panel a visible glass thickness.
        let sideRect = rect.offsetBy(dx: u * 0.018, dy: -u * 0.012)
        let sidePath = rounded(sideRect, u * 0.052)
        gradient(sidePath, [panel.side, c(0.025,0.045,0.09,0.98)], angle: 90)

        let face = rounded(rect, u * 0.052)
        let shadow = NSShadow()
        shadow.shadowColor = c(0.0, 0.008, 0.035, 0.36)
        shadow.shadowBlurRadius = u * 0.018
        shadow.shadowOffset = NSSize(width: u * 0.006, height: -u * 0.012)
        shadow.set()
        gradient(face, panel.front, angle: 90)
        NSShadow().set()

        // Inset pane: a soft diagonal plane creates the frosted, refractive look.
        context.saveGraphicsState()
        face.addClip()
        let facet = NSBezierPath()
        facet.move(to: NSPoint(x: rect.minX - u * 0.03, y: rect.minY + rect.height * 0.43))
        facet.line(to: NSPoint(x: rect.maxX + u * 0.05, y: rect.minY + rect.height * 0.67))
        facet.line(to: NSPoint(x: rect.maxX + u * 0.05, y: rect.maxY + u * 0.08))
        facet.line(to: NSPoint(x: rect.minX - u * 0.03, y: rect.maxY + u * 0.08))
        facet.close()
        gradient(facet, [c(0.82,0.91,1.0,0.14), c(0.70,0.82,0.98,0.015)], angle: 90)

        // Narrow internal bevels, not an external glow.
        let inner = rounded(rect.insetBy(dx: u * 0.009, dy: u * 0.009), u * 0.045)
        stroke(inner, c(0.88,0.95,1.0,0.24), max(0.6, u * 0.0022))
        let leftGlint = NSBezierPath()
        leftGlint.move(to: NSPoint(x: rect.minX + u * 0.018, y: rect.minY + u * 0.07))
        leftGlint.line(to: NSPoint(x: rect.minX + u * 0.018, y: rect.maxY - u * 0.09))
        stroke(leftGlint, c(0.96,0.98,1.0,0.30), max(0.5, u * 0.0028))
        context.restoreGraphicsState()
        context.restoreGraphicsState()
    }

    // Foreground card: bevelled cobalt glass, with a clearly visible darker
    // thickness on the lower edge and a diagonal reflection across its face.
    let cardRect = NSRect(x: u * 0.285, y: u * 0.405, width: u * 0.43, height: u * 0.235)
    context.saveGraphicsState()
    let cardTransform = NSAffineTransform()
    cardTransform.translateX(by: cardRect.midX, yBy: cardRect.midY)
    cardTransform.rotate(byDegrees: -12)
    cardTransform.translateX(by: -cardRect.midX, yBy: -cardRect.midY)
    cardTransform.concat()

    let cardSide = rounded(cardRect.offsetBy(dx: u * 0.006, dy: -u * 0.018), u * 0.052)
    gradient(cardSide, [c(0.035,0.20,0.61), c(0.025,0.12,0.43)], angle: 90)

    let card = rounded(cardRect, u * 0.052)
    let cardShadow = NSShadow()
    cardShadow.shadowColor = c(0.0,0.012,0.06,0.42)
    cardShadow.shadowBlurRadius = u * 0.02
    cardShadow.shadowOffset = NSSize(width: u * 0.008, height: -u * 0.014)
    cardShadow.set()
    gradient(card, [c(0.43,0.70,1.0), c(0.17,0.43,0.98), c(0.055,0.29,0.85)], angle: 90)
    NSShadow().set()

    context.saveGraphicsState()
    card.addClip()
    let cardFacet = NSBezierPath()
    cardFacet.move(to: NSPoint(x: cardRect.minX - u * 0.04, y: cardRect.midY + u * 0.045))
    cardFacet.line(to: NSPoint(x: cardRect.maxX + u * 0.04, y: cardRect.maxY + u * 0.025))
    cardFacet.line(to: NSPoint(x: cardRect.maxX + u * 0.04, y: cardRect.midY))
    cardFacet.line(to: NSPoint(x: cardRect.minX - u * 0.04, y: cardRect.midY - u * 0.035))
    cardFacet.close()
    gradient(cardFacet, [c(0.88,0.95,1.0,0.24), c(0.72,0.86,1.0,0.02)], angle: 90)
    let cardBevel = rounded(cardRect.insetBy(dx: u * 0.008, dy: u * 0.008), u * 0.044)
    stroke(cardBevel, c(0.91,0.97,1.0,0.30), max(0.6, u * 0.0024))
    context.restoreGraphicsState()
    context.restoreGraphicsState()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    bitmap.size = NSSize(width: size, height: size)
    guard let tiff = bitmap.tiffRepresentation,
          let pngBitmap = NSBitmapImageRep(data: tiff),
          let png = pngBitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "JungoIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось записать PNG"])
    }
    return png
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
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

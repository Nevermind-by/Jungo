import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"
let fileManager = FileManager.default
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = outputURL.deletingLastPathComponent().appendingPathComponent("Jungo.iconset", isDirectory: true)

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

    let unit = CGFloat(size)
    let bounds = NSRect(x: 0, y: 0, width: unit, height: unit)
    let inset = unit * 0.035
    let iconBounds = bounds.insetBy(dx: inset, dy: inset)

    // Deep indigo-to-blue glass-like base, designed to remain distinct at Dock size.
    let backgroundPath = NSBezierPath(
        roundedRect: iconBounds,
        xRadius: unit * 0.235,
        yRadius: unit * 0.235
    )
    let backgroundGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.075, green: 0.13, blue: 0.30, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.24, blue: 0.53, alpha: 1),
        NSColor(calibratedRed: 0.28, green: 0.22, blue: 0.62, alpha: 1)
    ])!
    backgroundGradient.draw(in: backgroundPath, angle: -42)

    // Subtle top highlight gives the icon depth without relying on tiny details.
    let highlight = NSBezierPath(
        roundedRect: NSRect(x: unit * 0.08, y: unit * 0.53, width: unit * 0.84, height: unit * 0.34),
        xRadius: unit * 0.16,
        yRadius: unit * 0.16
    )
    NSColor.white.withAlphaComponent(0.075).setFill()
    highlight.fill()

    let outerPadding = unit * 0.16
    let columnGap = unit * 0.045
    let columnWidth = (unit - outerPadding * 2 - columnGap * 2) / 3
    let columnY = unit * 0.22
    let columnHeight = unit * 0.56
    let columnRadius = unit * 0.055

    let statusColors = [
        NSColor(calibratedRed: 0.28, green: 0.72, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.28, green: 0.88, blue: 0.62, alpha: 1)
    ]

    for column in 0..<3 {
        let x = outerPadding + CGFloat(column) * (columnWidth + columnGap)
        let columnRect = NSRect(x: x, y: columnY, width: columnWidth, height: columnHeight)
        let columnPath = NSBezierPath(roundedRect: columnRect, xRadius: columnRadius, yRadius: columnRadius)
        NSColor.white.withAlphaComponent(0.13).setFill()
        columnPath.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        columnPath.lineWidth = max(0.6, unit * 0.004)
        columnPath.stroke()

        let dotSize = unit * 0.035
        let dotRect = NSRect(x: x + unit * 0.035, y: columnY + columnHeight - unit * 0.095, width: dotSize, height: dotSize)
        let dot = NSBezierPath(ovalIn: dotRect)
        statusColors[column].setFill()
        dot.fill()

        let lineX = x + unit * 0.035
        let lineWidth = columnWidth - unit * 0.07
        let lineHeight = max(1, unit * 0.018)
        for line in 0..<2 {
            let lineY = columnY + columnHeight - unit * (0.16 + CGFloat(line) * 0.055)
            let lineRect = NSRect(x: lineX, y: lineY, width: lineWidth * (line == 1 ? 0.68 : 1), height: lineHeight)
            let linePath = NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2)
            NSColor.white.withAlphaComponent(0.55).setFill()
            linePath.fill()
        }
    }

    // One clear foreground task card creates a recognizable focal point at small sizes.
    let cardRect = NSRect(x: unit * 0.28, y: unit * 0.27, width: unit * 0.44, height: unit * 0.25)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowBlurRadius = unit * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -unit * 0.012)
    shadow.set()
    let foregroundCard = NSBezierPath(roundedRect: cardRect, xRadius: unit * 0.045, yRadius: unit * 0.045)
    NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.0, alpha: 1).setFill()
    foregroundCard.fill()
    NSShadow().set()

    let accentRect = NSRect(x: cardRect.minX + unit * 0.045, y: cardRect.maxY - unit * 0.085, width: unit * 0.075, height: unit * 0.026)
    let accentPath = NSBezierPath(roundedRect: accentRect, xRadius: unit * 0.013, yRadius: unit * 0.013)
    NSColor(calibratedRed: 0.20, green: 0.46, blue: 1.0, alpha: 1).setFill()
    accentPath.fill()

    for line in 0..<2 {
        let lineRect = NSRect(
            x: cardRect.minX + unit * 0.045,
            y: cardRect.minY + unit * (0.075 + CGFloat(line) * 0.045),
            width: unit * (line == 0 ? 0.30 : 0.22),
            height: max(1, unit * 0.014)
        )
        let linePath = NSBezierPath(roundedRect: lineRect, xRadius: unit * 0.007, yRadius: unit * 0.007)
        NSColor(calibratedWhite: 0.60, alpha: 1).setFill()
        linePath.fill()
    }

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    // Explicitly set logical size so AppKit emits a correctly sized icon image
    // for each iconset representation, rather than relying on inferred DPI.
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

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"
let fileManager = FileManager.default
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = outputURL.deletingLastPathComponent().appendingPathComponent("Jungo.iconset", isDirectory: true)

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

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
    NSColor.clear.setFill()
    bounds.fill()

    let inset = unit * 0.035
    let background = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: unit * 0.23, yRadius: unit * 0.23)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.17, green: 0.38, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.39, green: 0.24, blue: 0.86, alpha: 1)
    ])!
    gradient.draw(in: background, angle: -38)

    let cardTop = unit * 0.72
    let cardHeight = unit * 0.43
    let cardWidth = unit * 0.235
    let gap = unit * 0.035
    let startX = unit * 0.19

    for column in 0..<3 {
        let x = startX + CGFloat(column) * (cardWidth + gap)
        let cardRect = NSRect(x: x, y: cardTop - cardHeight, width: cardWidth, height: cardHeight)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = unit * 0.018
        shadow.shadowOffset = NSSize(width: 0, height: -unit * 0.008)
        shadow.set()
        let card = NSBezierPath(roundedRect: cardRect, xRadius: unit * 0.035, yRadius: unit * 0.035)
        NSColor.white.withAlphaComponent(0.96).setFill()
        card.fill()
        NSShadow().set()

        let lineX = x + unit * 0.035
        let lineWidth = cardWidth - unit * 0.07
        let lineHeight = max(1, unit * 0.018)
        for line in 0..<3 {
            let lineY = cardRect.maxY - unit * (0.09 + CGFloat(line) * 0.065)
            let lineRect = NSRect(x: lineX, y: lineY, width: lineWidth * (line == 2 ? 0.62 : 1), height: lineHeight)
            let linePath = NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2)
            (line == 0 ? NSColor(calibratedRed: 0.25, green: 0.43, blue: 0.96, alpha: 0.9) : NSColor(calibratedWhite: 0.76, alpha: 1)).setFill()
            linePath.fill()
        }
    }

    let accentRect = NSRect(x: unit * 0.39, y: unit * 0.18, width: unit * 0.22, height: unit * 0.08)
    let accent = NSBezierPath(roundedRect: accentRect, xRadius: unit * 0.04, yRadius: unit * 0.04)
    NSColor.white.withAlphaComponent(0.92).setFill()
    accent.fill()

    NSGraphicsContext.restoreGraphicsState()

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

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"
let fileManager = FileManager.default
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = outputURL.deletingLastPathComponent().appendingPathComponent("Jungo.iconset", isDirectory: true)

// The requested output can live inside a not-yet-created app bundle.
// Ensure the parent exists before writing any iconset PNG files.
try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
// Create the iconset directory before the first PNG is written.
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
    let inset = unit * 0.035
    let iconBounds = bounds.insetBy(dx: inset, dy: inset)

    // Minimal Jungo mark: a calm warm-white tile, three dark Kanban lanes,
    // and one vivid blue task card. Avoid gradients, tiny lines, and layered
    // decoration so the silhouette stays clear in Dock and Spotlight.
    let backgroundPath = NSBezierPath(
        roundedRect: iconBounds,
        xRadius: unit * 0.225,
        yRadius: unit * 0.225
    )
    NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.99, alpha: 1).setFill()
    backgroundPath.fill()

    let laneColor = NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.31, alpha: 1)
    let laneY = unit * 0.22
    let laneHeight = unit * 0.56
    let laneWidth = unit * 0.17
    let laneGap = unit * 0.075
    let lanesWidth = laneWidth * 3 + laneGap * 2
    let laneStartX = (unit - lanesWidth) / 2
    let laneRadius = unit * 0.065

    for index in 0..<3 {
        let x = laneStartX + CGFloat(index) * (laneWidth + laneGap)
        let lane = NSBezierPath(
            roundedRect: NSRect(x: x, y: laneY, width: laneWidth, height: laneHeight),
            xRadius: laneRadius,
            yRadius: laneRadius
        )
        laneColor.setFill()
        lane.fill()
    }

    // A single floating task is the only accent and focal point.
    let cardRect = NSRect(x: unit * 0.29, y: unit * 0.39, width: unit * 0.42, height: unit * 0.23)
    let card = NSBezierPath(
        roundedRect: cardRect,
        xRadius: unit * 0.055,
        yRadius: unit * 0.055
    )
    NSColor(calibratedRed: 0.20, green: 0.43, blue: 0.98, alpha: 1).setFill()
    card.fill()
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

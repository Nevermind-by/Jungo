import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"
let fileManager = FileManager.default
let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = outputURL.deletingLastPathComponent().appendingPathComponent("Jungo.iconset", isDirectory: true)
let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let masterArtworkURL = projectRoot.appendingPathComponent("Resources/JungoIconMaster.png")

try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

guard fileManager.fileExists(atPath: masterArtworkURL.path),
      let masterArtwork = NSImage(contentsOf: masterArtworkURL) else {
    throw NSError(
        domain: "JungoIcon",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Не найден исходный арт иконки: \\(masterArtworkURL.path). Поместите утверждённый PNG в Resources/JungoIconMaster.png."]
    )
}

func drawIcon(size: Int) throws -> Data {
    let pixels = CGFloat(size)
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
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

    // Use the approved artwork itself, not a Swift approximation. The source
    // is square and is scaled directly into each standard macOS iconset size.
    masterArtwork.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: NSRect(origin: .zero, size: masterArtwork.size),
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )

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

import AppKit
import Foundation
import Darwin

private struct IconChunk {
    let type: String
    let pixels: Int
}

private let chunks = [
    IconChunk(type: "icp4", pixels: 16),
    IconChunk(type: "icp5", pixels: 32),
    IconChunk(type: "icp6", pixels: 64),
    IconChunk(type: "ic07", pixels: 128),
    IconChunk(type: "ic08", pixels: 256),
    IconChunk(type: "ic09", pixels: 512),
    IconChunk(type: "ic10", pixels: 1024),
]

private func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(2)
}

private func bigEndianBytes(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

private func pngData(from source: NSImage, pixels: Int) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fail("Unable to allocate \(pixels)x\(pixels) icon bitmap")
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fail("Unable to create icon graphics context")
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    source.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fail("Unable to encode \(pixels)x\(pixels) icon PNG")
    }
    return data
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: build_icns <input.png> <output.icns>")
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
guard let source = NSImage(contentsOfFile: inputPath) else {
    fail("Unable to load source icon: \(inputPath)")
}

var body = Data()
for chunk in chunks {
    let png = pngData(from: source, pixels: chunk.pixels)
    body.append(Data(chunk.type.utf8))
    body.append(bigEndianBytes(UInt32(png.count + 8)))
    body.append(png)
}

var output = Data("icns".utf8)
output.append(bigEndianBytes(UInt32(body.count + 8)))
output.append(body)

do {
    try output.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
} catch {
    fail("Unable to write ICNS: \(error.localizedDescription)")
}

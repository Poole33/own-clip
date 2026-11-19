import AppKit

/// Compile with Sources/UI/OwnClipIcon.swift so app and exports share one renderer.
@main
enum MakeIcon {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data("Usage: make-icon output.png [pixels] [--menu]\n".utf8))
            exit(1)
        }
        let pixel = arguments.count > 2 ? Int(arguments[2]) ?? 1024 : 1024
        guard pixel > 0, pixel <= 4096 else {
            FileHandle.standardError.write(Data("Image size must be 1–4096 pixels.\n".utf8))
            exit(1)
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        let rect = CGRect(x: 0, y: 0, width: pixel, height: pixel)
        if arguments.contains("--menu") {
            OwnClipIcon.drawTemplate(in: context, rect: rect)
        } else {
            OwnClipIcon.drawApplicationIcon(in: context, rect: rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
    }
}

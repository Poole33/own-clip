import AppKit

let pixel = 512
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let transform = NSAffineTransform()
transform.scale(by: CGFloat(pixel) / 128)
transform.concat()

let blue = NSColor(srgbRed: 0.18, green: 0.43, blue: 0.88, alpha: 1)
blue.setFill()
NSBezierPath(roundedRect: NSRect(x: 10, y: 10, width: 108, height: 108), xRadius: 25, yRadius: 25).fill()
NSColor.white.withAlphaComponent(0.30).setFill()
NSBezierPath(roundedRect: NSRect(x: 38, y: 31, width: 64, height: 63), xRadius: 9, yRadius: 9).fill()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 27, y: 26, width: 60, height: 72), xRadius: 10, yRadius: 10).fill()
blue.setFill()
NSBezierPath(roundedRect: NSRect(x: 42, y: 87, width: 30, height: 15), xRadius: 5, yRadius: 5).fill()
blue.withAlphaComponent(0.65).setFill()
for (y, width) in [(68, 31), (56, 31), (44, 20)] {
    NSBezierPath(roundedRect: NSRect(x: 41, y: CGFloat(y), width: CGFloat(width), height: 4), xRadius: 2, yRadius: 2).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

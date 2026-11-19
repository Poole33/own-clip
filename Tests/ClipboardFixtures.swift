import AppKit
import Foundation

extension SmokeTests {
    static func checkPNG() throws -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)
        guard let bitmap else { throw SmokeFailure(description: "Missing test bitmap") }
        bitmap.setColor(.blue, atX: 0, y: 0)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SmokeFailure(description: "Missing test PNG")
        }
        return png
    }

    static func requirePayload(_ board: NSPasteboard, fixture: String = "HEX") throws -> ClipboardPayload {
        guard let payload = ClipboardPayload.capture(from: board) else {
            throw SmokeFailure(description: "Missing \(fixture). Types: \(board.types?.map(\.rawValue) ?? [])")
        }
        return payload
    }
}

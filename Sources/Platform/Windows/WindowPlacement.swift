import CoreGraphics

struct WindowPlacement {
    static func frame(size: CGSize, in area: CGRect, offset: [Double]? = nil) -> CGRect {
        let origin: CGPoint
        if let offset, offset.count == 2, offset.allSatisfy(\.isFinite) {
            origin = CGPoint(x: area.minX + offset[0], y: area.minY + offset[1])
        } else {
            origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        }
        return CGRect(x: max(area.minX, min(origin.x, area.maxX - size.width)),
                      y: max(area.minY, min(origin.y, area.maxY - size.height)),
                      width: size.width, height: size.height)
    }

    static func stackFrame(size: CGSize, in area: CGRect, offset: [Double]? = nil) -> CGRect {
        let defaultOffset = [Double(area.width - size.width - 18), Double(area.height - size.height - 18)]
        return frame(size: size, in: area, offset: offset ?? defaultOffset)
    }

    static func settingsFrame(size: CGSize, in area: CGRect, above strip: CGRect?) -> CGRect {
        guard let strip, area.maxY - strip.maxY >= size.height else { return frame(size: size, in: area) }
        let available = CGRect(x: area.minX, y: strip.maxY, width: area.width, height: area.maxY - strip.maxY)
        return frame(size: size, in: available)
    }
}

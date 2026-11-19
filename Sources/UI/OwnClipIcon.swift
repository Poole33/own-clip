import AppKit

/// The approved “duplicate pages” mark; coordinates match the SVG masters.
enum OwnClipIcon {
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            drawTemplate(in: context, rect: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    static func drawApplicationIcon(in context: CGContext, rect: CGRect) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / 256, y: -rect.height / 256)
        // Match the existing macOS icon inset and preserve transparent outer corners.
        context.translateBy(x: 20, y: 20)
        context.scaleBy(x: 216.0 / 256, y: 216.0 / 256)
        context.setFillColor(NSColor.white.cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 256, height: 256),
                               cornerWidth: 56, cornerHeight: 56, transform: nil))
        context.fillPath()
        context.translateBy(x: 128, y: 125)
        context.scaleBy(x: 0.86, y: 0.86)
        context.translateBy(x: -128, y: -128)
        context.setFillColor(NSColor.black.cgColor)
        drawMark(in: context, small: false)
    }

    static func drawTemplate(in context: CGContext, rect: CGRect) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / 18, y: -rect.height / 18)
        context.setFillColor(NSColor.black.cgColor)
        drawMark(in: context, small: true)
    }

    private static func drawMark(in context: CGContext, small: Bool) {
        let rear = CGMutablePath()
        if small {
            // Slightly heavier 1.5 pt outline with 1 pt separation at 18 pt.
            rear.move(to: CGPoint(x: 8.8, y: 2))
            rear.addLine(to: CGPoint(x: 13.2, y: 2))
            rear.addArc(center: CGPoint(x: 13.2, y: 4.8), radius: 2.8,
                        startAngle: -.pi / 2, endAngle: 0, clockwise: false)
            rear.addLine(to: CGPoint(x: 16, y: 9.2))
            rear.addArc(center: CGPoint(x: 13.2, y: 9.2), radius: 2.8,
                        startAngle: 0, endAngle: .pi / 2, clockwise: false)
            rear.addLine(to: CGPoint(x: 13, y: 12))
            rear.addLine(to: CGPoint(x: 13, y: 10.5))
            rear.addLine(to: CGPoint(x: 13.2, y: 10.5))
            rear.addArc(center: CGPoint(x: 13.2, y: 9.2), radius: 1.3,
                        startAngle: .pi / 2, endAngle: 0, clockwise: true)
            rear.addLine(to: CGPoint(x: 14.5, y: 4.8))
            rear.addArc(center: CGPoint(x: 13.2, y: 4.8), radius: 1.3,
                        startAngle: 0, endAngle: -.pi / 2, clockwise: true)
            rear.addLine(to: CGPoint(x: 8.8, y: 3.5))
            rear.addArc(center: CGPoint(x: 8.8, y: 4.8), radius: 1.3,
                        startAngle: -.pi / 2, endAngle: -.pi, clockwise: true)
            rear.addLine(to: CGPoint(x: 7.5, y: 5))
            rear.addLine(to: CGPoint(x: 6, y: 5))
            rear.addLine(to: CGPoint(x: 6, y: 4.8))
            rear.addArc(center: CGPoint(x: 8.8, y: 4.8), radius: 2.8,
                        startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false)
        } else {
            rear.move(to: CGPoint(x: 124, y: 28))
            rear.addLine(to: CGPoint(x: 188, y: 28))
            rear.addArc(center: CGPoint(x: 188, y: 68), radius: 40,
                        startAngle: -.pi / 2, endAngle: 0, clockwise: false)
            rear.addLine(to: CGPoint(x: 228, y: 132))
            rear.addArc(center: CGPoint(x: 188, y: 132), radius: 40,
                        startAngle: 0, endAngle: .pi / 2, clockwise: false)
            rear.addLine(to: CGPoint(x: 184, y: 172))
            rear.addLine(to: CGPoint(x: 184, y: 152))
            rear.addLine(to: CGPoint(x: 188, y: 152))
            rear.addArc(center: CGPoint(x: 188, y: 132), radius: 20,
                        startAngle: .pi / 2, endAngle: 0, clockwise: true)
            rear.addLine(to: CGPoint(x: 208, y: 68))
            rear.addArc(center: CGPoint(x: 188, y: 68), radius: 20,
                        startAngle: 0, endAngle: -.pi / 2, clockwise: true)
            rear.addLine(to: CGPoint(x: 124, y: 48))
            rear.addArc(center: CGPoint(x: 124, y: 68), radius: 20,
                        startAngle: -.pi / 2, endAngle: -.pi, clockwise: true)
            rear.addLine(to: CGPoint(x: 104, y: 72))
            rear.addLine(to: CGPoint(x: 84, y: 72))
            rear.addLine(to: CGPoint(x: 84, y: 68))
            rear.addArc(center: CGPoint(x: 124, y: 68), radius: 40,
                        startAngle: .pi, endAngle: 1.5 * .pi, clockwise: false)
        }
        rear.closeSubpath()
        context.addPath(rear)
        context.fillPath()

        let front = CGMutablePath()
        let outer = small ? CGRect(x: 2, y: 6, width: 10, height: 10)
                          : CGRect(x: 28, y: 84, width: 144, height: 144)
        let inner = small ? CGRect(x: 3.5, y: 7.5, width: 7, height: 7)
                          : CGRect(x: 48, y: 104, width: 104, height: 104)
        front.addRoundedRect(in: outer, cornerWidth: small ? 2.8 : 40, cornerHeight: small ? 2.8 : 40)
        front.addRoundedRect(in: inner, cornerWidth: small ? 1.3 : 20, cornerHeight: small ? 1.3 : 20)
        context.addPath(front)
        context.drawPath(using: .eoFill)
    }
}

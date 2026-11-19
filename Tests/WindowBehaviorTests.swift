import AppKit
import Foundation

extension SmokeTests {
    static func testHistoryWheel() throws {
        func scroll(horizontal: Int32, vertical: Int32, flags: CGEventFlags = [], precise: Bool = false) throws -> NSEvent {
            guard let rawEvent = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2,
                                         wheel1: vertical, wheel2: horizontal, wheel3: 0) else {
                throw SmokeFailure(description: "Could not create a scroll fixture")
            }
            rawEvent.flags = flags
            guard let event = NSEvent(cgEvent: rawEvent) else { throw SmokeFailure(description: "Could not create a wheel event") }
            return event
        }

        let normal = try scroll(horizontal: 0, vertical: -1)
        let shifted = try scroll(horizontal: 0, vertical: -1, flags: .maskShift)
        let horizontal = try scroll(horizontal: -1, vertical: -1, flags: .maskShift)
        let precise = try scroll(horizontal: 0, vertical: 12, precise: true)
        let accessibilityZoom = try scroll(horizontal: 0, vertical: 1, flags: .maskControl)
        try check(HistoryWheel.horizontalDistance(for: normal) == -48, "Ordinary vertical wheel did not move history horizontally")
        // AppKit can turn Shift-wheel into a horizontal event during NSEvent conversion.
        let shiftedDistance: CGFloat? = shifted.scrollingDeltaX == 0 ? -48 : nil
        try check(HistoryWheel.horizontalDistance(for: shifted) == shiftedDistance, "Shift wheel was not routed using its reported axis")
        try check(HistoryWheel.horizontalDistance(for: horizontal) == nil, "Native horizontal input was processed twice")
        try check(HistoryWheel.horizontalDistance(for: precise) == precise.scrollingDeltaY, "Precise wheel input was treated as lines")
        try check(HistoryWheel.horizontalDistance(for: accessibilityZoom) == nil, "Control-wheel was intercepted")
    }

    static func testWindowPlacement() throws {
        let display = CGRect(x: -1600, y: 40, width: 1600, height: 920)
        let size = CGSize(width: 510, height: 470)
        let dragged = CGPoint(x: -1370, y: 340)
        try check(WindowPlacement.frame(size: size, in: display, offset: [230, 300]).origin == dragged,
                  "Floating history lost its saved display-relative position")
        let resized = CGRect(x: -1280, y: 40, width: 1280, height: 680)
        let recovered = WindowPlacement.frame(size: size, in: resized, offset: [1200, 700])
        try check(resized.contains(recovered), "Restored history appeared outside the resized display")
        let stackSize = CGSize(width: 440, height: 339)
        let initialStack = WindowPlacement.stackFrame(size: stackSize, in: display)
        try check(initialStack.maxX == display.maxX - 18 && initialStack.maxY == display.maxY - 18,
                  "Sequential paste did not default to the display's upper-right corner")
        let restoredStack = WindowPlacement.stackFrame(size: stackSize, in: display, offset: [230, 300])
        try check(restoredStack.origin == dragged, "Sequential paste lost its saved display-relative position")
        let recoveredStack = WindowPlacement.stackFrame(size: stackSize, in: resized, offset: [1200, 700])
        try check(resized.contains(recoveredStack), "Restored sequential paste appeared outside the resized display")
        let strip = CGRect(x: -1600, y: 40, width: 1600, height: 310)
        let settings = WindowPlacement.settingsFrame(size: CGSize(width: 560, height: 530), in: display, above: strip)
        try check(display.contains(settings) && settings.minY >= strip.maxY,
                  "Settings did not fit above the visible history strip")
    }
}

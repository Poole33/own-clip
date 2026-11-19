import AppKit

/// Owns the pasteboard revision so writes made by OwnClip are not captured again.
final class ClipboardMonitor {
    struct Change {
        let revision: Int
        let payload: ClipboardPayload?
    }

    private let board: NSPasteboard
    private(set) var revision = 0

    init(board: NSPasteboard = .general) { self.board = board }

    var changeCount: Int { board.changeCount }
    var isDenied: Bool {
        if #available(macOS 26.0, *) { return board.accessBehavior == .alwaysDeny }
        return false
    }

    func synchronize() { revision = changeCount }

    /// A change without a supported payload must still advance the revision.
    func poll() -> Change? {
        let observed = changeCount
        guard observed != revision, !isDenied else { return nil }
        let payload = capture()
        guard observed == changeCount else { return nil }
        revision = observed
        return Change(revision: observed, payload: payload)
    }

    func capture() -> ClipboardPayload? { ClipboardPayload.capture(from: board) }

    @discardableResult
    func write(_ payload: ClipboardPayload, plainText: Bool = false) -> Bool {
        guard payload.write(to: board, plainText: plainText) else { return false }
        synchronize()
        return true
    }
}

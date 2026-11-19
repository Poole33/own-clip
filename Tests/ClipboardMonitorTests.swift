import AppKit

extension SmokeTests {
    static func testClipboardMonitor() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(board: board)
        monitor.synchronize()
        try check(monitor.poll() == nil, "An unchanged clipboard was captured")

        board.clearContents()
        try check(board.setString("external copy", forType: .string), "Could not write a monitor fixture")
        let change = monitor.poll()
        try check(change?.payload?.plainText == "external copy", "An external copy was missed")
        try check(change?.revision == board.changeCount && monitor.poll() == nil, "A copy was captured more than once")

        guard let payload = change?.payload else { throw SmokeFailure(description: "Missing monitor payload") }
        try check(monitor.write(payload, plainText: true), "The monitor could not restore a clip")
        try check(monitor.poll() == nil, "OwnClip's own write was captured as a new copy")

        board.clearContents()
        guard let empty = monitor.poll() else { throw SmokeFailure(description: "An empty clipboard did not advance the revision") }
        try check(empty.payload == nil && monitor.poll() == nil, "An empty change was repeatedly polled")

        let concealed = NSPasteboardItem()
        concealed.setString("private", forType: .string)
        concealed.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.clearContents()
        try check(board.writeObjects([concealed]), "Could not write a concealed monitor fixture")
        let privateChange = monitor.poll()
        try check(privateChange != nil && privateChange?.payload == nil, "A concealed copy was captured")
        try check(monitor.poll() == nil, "A concealed copy did not advance the revision")
    }
}

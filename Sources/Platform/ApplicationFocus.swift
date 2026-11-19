import AppKit

enum ApplicationFocus {
    static func frontApplication() -> NSRunningApplication? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ownPID else { return nil }
        return front
    }
}

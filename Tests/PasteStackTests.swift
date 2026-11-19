import AppKit
import Foundation

extension SmokeTests {
    static func testPasteStack(_ clip: ClipSummary) throws {
        var stack = PasteStack()
        try check(stack.mode == .pop, "The stack did not default to pop mode")
        stack.append(clip)
        stack.append(clip)
        let first = stack.entries[0]
        let last = stack.entries[1]
        stack.finishPaste(first)
        try check(stack.next?.id == last.id, "Pop mode skipped the last entry")
        stack.finishPaste(last)
        try check(stack.isEmpty && stack.next == nil, "Pop mode did not remove the final pasted entry")

        stack.setMode(.loop)
        stack.append(clip)
        stack.append(clip)
        let start = stack.entries[0]
        let end = stack.entries[1]
        stack.finishPaste(start)
        try check(stack.entries.count == 2 && stack.pastedIDs == [start.id] && stack.next?.id == end.id,
                  "Loop mode did not retain the pasted entry and advance to the next one")
        stack.finishPaste(end)
        try check(stack.pastedIDs.isEmpty && stack.next?.id == start.id, "Loop mode did not reset after the final entry")
        stack.finishPaste(start)
        stack.removeAll { $0.id == end.id }
        try check(stack.pastedIDs.isEmpty && stack.next?.id == start.id, "Removing the last pending entry stalled the loop")
        stack.setMode(.pop)
        stack.finishPaste(start)
        try check(stack.isEmpty, "Switching back to pop mode did not consume the retained entry")
    }
}

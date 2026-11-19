import Foundation

enum StackPasteMode {
    case pop, loop
}

struct StackEntry: Identifiable {
    let id = UUID()
    let clip: ClipSummary
}

struct PasteStack {
    private(set) var mode: StackPasteMode = .pop
    private(set) var entries: [StackEntry] = []
    private(set) var pastedIDs: Set<UUID> = []

    var isEmpty: Bool { entries.isEmpty }
    var next: StackEntry? { entries.first { !pastedIDs.contains($0.id) } }

    mutating func setMode(_ mode: StackPasteMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        pastedIDs.removeAll()
    }

    mutating func append(_ clip: ClipSummary) {
        entries.append(StackEntry(clip: clip))
    }

    mutating func reverse() { entries.reverse() }

    mutating func removeAll(where shouldRemove: (StackEntry) -> Bool) {
        entries.removeAll(where: shouldRemove)
        if !pastedIDs.isEmpty {
            pastedIDs.formIntersection(entries.map(\.id))
            resetCompletedRound()
        }
    }

    mutating func finishPaste(_ entry: StackEntry) {
        switch mode {
        case .pop:
            removeAll { $0.id == entry.id }
        case .loop:
            pastedIDs.insert(entry.id)
            resetCompletedRound()
        }
    }

    private mutating func resetCompletedRound() {
        if pastedIDs.count == entries.count { pastedIDs.removeAll() }
    }
}

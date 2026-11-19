import AppKit

/// Tracks Finder's copy-then-move workflow without retaining stale file selections.
final class FinderMoveService {
    private let clipboard: ClipboardMonitor
    private var pendingRevision: Int?
    private var copyToken: UUID?

    var beforeCopy: (() -> Void)?
    var onCapture: ((ClipboardPayload) -> Void)?
    var onStatus: ((AppMessage) -> Void)?

    init(clipboard: ClipboardMonitor) { self.clipboard = clipboard }

    func cancel() {
        pendingRevision = nil
        copyToken = nil
    }

    func clearPendingMove() { pendingRevision = nil }

    func clipboardDidChange(to revision: Int) {
        if pendingRevision != revision { pendingRevision = nil }
    }

    func handle(_ event: CGEvent, in application: NSRunningApplication, shortcuts: ShortcutSettings) -> Bool {
        guard application.bundleIdentifier == "com.apple.finder" else { return false }
        let pid = application.processIdentifier
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if let cut = shortcuts[.finderCut], cut.matches(event),
           let focus = FinderFocus.inspect(pid: pid, requireSelection: true), focus.fileBrowser, focus.hasSelection {
            if !repeated { DispatchQueue.main.async { [weak self] in self?.cut(in: pid) } }
            return true
        }
        if let move = shortcuts[.finderMove], move.matches(event), pendingRevision == clipboard.changeCount,
           FinderFocus.inspect(pid: pid, requireSelection: false)?.fileBrowser == true {
            if !repeated { DispatchQueue.main.async { [weak self] in self?.move(in: pid, fallback: move) } }
            return true
        }
        return false
    }

    private func cut(in pid: pid_t) {
        guard ApplicationFocus.frontApplication()?.processIdentifier == pid else { return }
        beforeCopy?()
        let before = clipboard.changeCount
        pendingRevision = nil
        let token = UUID()
        copyToken = token
        guard ContextKeys.send(.systemCopy, to: pid) else { return }
        checkCopy(token, pid: pid, before: before, attempt: 0)
    }

    private func checkCopy(_ token: UUID, pid: pid_t, before: Int, attempt: Int) {
        guard copyToken == token else { return }
        let current = clipboard.changeCount
        if current != before {
            copyToken = nil
            guard ApplicationFocus.frontApplication()?.processIdentifier == pid,
                  let payload = clipboard.capture(), !payload.files.isEmpty,
                  current == clipboard.changeCount else { return }
            pendingRevision = current
            if current != clipboard.revision {
                clipboard.synchronize()
                onCapture?(payload)
            }
            onStatus?(AppMessage(AppText.text("已标记文件待移动")))
        } else if attempt < 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                self?.checkCopy(token, pid: pid, before: before, attempt: attempt + 1)
            }
        } else {
            copyToken = nil
        }
    }

    private func move(in pid: pid_t, fallback: KeyBinding) {
        guard ApplicationFocus.frontApplication()?.processIdentifier == pid else { return }
        guard pendingRevision == clipboard.changeCount,
              FinderFocus.inspect(pid: pid, requireSelection: false)?.fileBrowser == true else {
            _ = ContextKeys.send(fallback, to: pid)
            return
        }
        pendingRevision = nil
        _ = ContextKeys.send(.systemMove, to: pid)
    }
}

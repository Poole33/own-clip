import Foundation

private final class PasteHarness {
    var revision = 7
    var frontPID: pid_t?
    var active = false
    var terminated = false
    var allowSend = true
    var sent: [pid_t] = []
    var outcomes: [PasteService.Outcome] = []
    var pending: [() -> Void] = []

    lazy var service = PasteService(
        changeCount: { [unowned self] in revision },
        frontPID: { [unowned self] in frontPID },
        sendPaste: { [unowned self] pid in sent.append(pid); return allowSend },
        schedule: { [unowned self] _, work in pending.append(work) })

    func request() {
        let target = PasteService.Destination(pid: 42, isActive: { [unowned self] in active },
                                               isTerminated: { [unowned self] in terminated })
        service.pasteWhenFocused(target, revision: revision) { [unowned self] in outcomes.append($0) }
    }

    func step() { pending.removeFirst()() }

    func drain() throws {
        var checks = 0
        while !pending.isEmpty {
            try check(checks < 32, "Paste focus checks did not stop")
            step()
            checks += 1
        }
    }
}

extension SmokeTests {
    static func testPasteService() throws {
        let waiting = PasteHarness()
        waiting.request()
        waiting.step()
        try check(waiting.sent.isEmpty && waiting.outcomes.isEmpty, "Paste was sent before the target regained focus")
        waiting.frontPID = 42
        waiting.active = true
        try waiting.drain()
        try check(waiting.sent == [42] && waiting.outcomes == [.sent], "Paste did not resume after focus returned")

        let changed = PasteHarness()
        changed.frontPID = 42
        changed.active = true
        changed.request()
        changed.revision += 1
        try changed.drain()
        try check(changed.sent.isEmpty && changed.outcomes == [.clipboardChanged], "Stale clipboard content was pasted")

        let switched = PasteHarness()
        switched.frontPID = 99
        switched.active = true
        switched.request()
        try switched.drain()
        try check(switched.sent.isEmpty && switched.outcomes == [.manualPasteRequired], "Paste followed the user into another app")

        let cancelled = PasteHarness()
        cancelled.frontPID = 42
        cancelled.active = true
        cancelled.request()
        cancelled.service.cancel()
        try cancelled.drain()
        try check(cancelled.sent.isEmpty && cancelled.outcomes.isEmpty, "A cancelled request still pasted")

        let replaced = PasteHarness()
        replaced.frontPID = 42
        replaced.active = true
        replaced.request()
        replaced.request()
        try replaced.drain()
        try check(replaced.sent == [42] && replaced.outcomes == [.sent], "A superseded request still pasted")

        let timeout = PasteHarness()
        timeout.request()
        try timeout.drain()
        try check(timeout.sent.isEmpty && timeout.outcomes == [.manualPasteRequired], "A focus timeout did not fall back to manual paste")

        let terminated = PasteHarness()
        terminated.terminated = true
        terminated.request()
        try terminated.drain()
        try check(terminated.sent.isEmpty && terminated.outcomes == [.manualPasteRequired], "A terminated destination was retried")

        let denied = PasteHarness()
        denied.frontPID = 42
        denied.active = true
        denied.allowSend = false
        denied.request()
        try denied.drain()
        try check(denied.outcomes == [.sendFailed], "A failed keyboard event was reported as successful")
    }
}

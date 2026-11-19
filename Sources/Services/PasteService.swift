import AppKit

/// Waits for the intended app to regain focus before sending a paste shortcut.
/// Each new request cancels the previous one, including its scheduled checks.
final class PasteService {
    enum Outcome: Equatable {
        case sent, clipboardChanged, manualPasteRequired, sendFailed
    }

    struct Destination {
        let pid: pid_t
        let isActive: () -> Bool
        let isTerminated: () -> Bool
    }

    private let changeCount: () -> Int
    private let frontPID: () -> pid_t?
    private let sendPaste: (pid_t) -> Bool
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var pendingRequest: UUID?

    init(changeCount: @escaping () -> Int,
         frontPID: @escaping () -> pid_t? = { ApplicationFocus.frontApplication()?.processIdentifier },
         sendPaste: @escaping (pid_t) -> Bool = { ContextKeys.send(.systemPaste, to: $0) },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         }) {
        self.changeCount = changeCount
        self.frontPID = frontPID
        self.sendPaste = sendPaste
        self.schedule = schedule
    }

    func cancel() { pendingRequest = nil }

    func pasteWhenFocused(_ target: NSRunningApplication, revision: Int,
                          completion: @escaping (Outcome) -> Void) {
        let destination = Destination(pid: target.processIdentifier,
                                      isActive: { target.isActive }, isTerminated: { target.isTerminated })
        pasteWhenFocused(destination, revision: revision, completion: completion)
    }

    func pasteWhenFocused(_ target: Destination, revision: Int,
                          completion: @escaping (Outcome) -> Void) {
        let request = UUID()
        pendingRequest = request
        checkFocus(target, revision: revision, request: request, remainingChecks: 8, completion: completion)
    }

    private func checkFocus(_ target: Destination, revision: Int, request: UUID,
                            remainingChecks: Int, completion: @escaping (Outcome) -> Void) {
        schedule(0.06) { [weak self] in
            guard let self, pendingRequest == request else { return }
            let front = frontPID()
            if changeCount() != revision {
                finish(.clipboardChanged, completion: completion)
            } else if front == target.pid && target.isActive() {
                let sent = sendPaste(target.pid)
                finish(sent ? .sent : .sendFailed, completion: completion)
            } else if (front == nil || front == target.pid)
                        && !target.isTerminated() && remainingChecks > 1 {
                checkFocus(target, revision: revision, request: request,
                           remainingChecks: remainingChecks - 1, completion: completion)
            } else {
                finish(.manualPasteRequired, completion: completion)
            }
        }
    }

    private func finish(_ outcome: Outcome, completion: (Outcome) -> Void) {
        pendingRequest = nil
        completion(outcome)
    }
}

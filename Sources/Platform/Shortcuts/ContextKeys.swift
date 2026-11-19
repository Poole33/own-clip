import AppKit
import Carbon
import CoreGraphics
import Foundation

final class ContextKeys {
    static let ownEvent: Int64 = 0x4F574E434C4950
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onKeyDown: ((CGEvent) -> Bool)?

    var isRunning: Bool { tap != nil }

    @discardableResult func start() -> Bool {
        if isRunning { return true }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                             options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let listener = Unmanaged<ContextKeys>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = listener.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if type == .keyDown, event.getIntegerValueField(.eventSourceUserData) != ContextKeys.ownEvent,
                      listener.onKeyDown?(event) == true {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let newSource = CFMachPortCreateRunLoopSource(nil, newTap, 0)
        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    deinit { stop() }

    static func send(_ binding: KeyBinding, to pid: pid_t, directlyToProcess: Bool = false) -> Bool {
        guard CGPreflightPostEventAccess(), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: binding.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: binding.keyCode, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = binding.eventFlags
            event.setIntegerValueField(.eventSourceUserData, value: ownEvent)
            if directlyToProcess {
                event.postToPid(pid)
            } else {
                event.post(tap: .cgSessionEventTap)
            }
        }
        return true
    }
}

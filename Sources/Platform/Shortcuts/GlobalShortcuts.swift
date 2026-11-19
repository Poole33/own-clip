import AppKit
import Carbon
import CoreGraphics
import Foundation

final class GlobalShortcuts {
    private var handler: EventHandlerRef?
    private var registrations: [ShortcutAction: EventHotKeyRef] = [:]
    private var current: [ShortcutAction: KeyBinding] = [:]
    var onAction: ((ShortcutAction) -> Void)?
    private let signature: OSType = 0x4F434C50

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let receiver = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr, key.signature == receiver.signature,
                  let action = ShortcutAction(rawValue: Int(key.id)) else { return OSStatus(eventNotHandledErr) }
            receiver.onAction?(action)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        for ref in registrations.values { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    func tryApply(_ bindings: ShortcutSettings, actions: [ShortcutAction]) -> ShortcutAction? {
        let changed = actions.filter { current[$0] != bindings[$0] }
        let previous = current
        for action in changed { remove(action) }
        for action in changed {
            if let binding = bindings[action], !register(action, binding: binding) {
                for modified in changed { remove(modified) }
                for modified in changed {
                    if let old = previous[modified] { _ = register(modified, binding: old) }
                }
                return action
            }
        }
        return nil
    }

    func installIndividually(_ bindings: ShortcutSettings) -> [ShortcutAction] {
        ShortcutAction.allCases.filter { action in
            guard action.scope == .global, let binding = bindings[action] else { return false }
            return !register(action, binding: binding)
        }
    }

    private func register(_ action: ShortcutAction, binding: KeyBinding) -> Bool {
        guard handler != nil else { return false }
        let id = EventHotKeyID(signature: signature, id: UInt32(action.rawValue))
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(binding.keyCode), binding.carbonModifiers, id, GetApplicationEventTarget(),
                                         UInt32(kEventHotKeyExclusive), &reference)
        guard status == noErr, let reference else { return false }
        registrations[action] = reference
        current[action] = binding
        return true
    }

    private func remove(_ action: ShortcutAction) {
        if let ref = registrations.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        current.removeValue(forKey: action)
    }
}


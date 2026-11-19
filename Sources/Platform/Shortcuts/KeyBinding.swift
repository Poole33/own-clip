import AppKit
import Carbon
import CoreGraphics
import Foundation

struct KeyBinding: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt32
    let keyLabel: String

    private static let supportedFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
    private static let macFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    init(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = [], label: String) {
        self.keyCode = UInt16(keyCode)
        self.modifiers = UInt32(modifiers.intersection(Self.supportedFlags).rawValue)
        keyLabel = label
    }

    init?(event: NSEvent) {
        let namedKeys: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 71: "Clear", 76: "Enter",
            114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete", 119: "End", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
        ]
        let printable = event.charactersIgnoringModifiers?.uppercased()
        guard let label = namedKeys[event.keyCode] ?? printable, !label.isEmpty,
              !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        self.init(Int(event.keyCode), event.modifierFlags, label: label)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    var label: String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        return [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { flags.contains($0.0) }.map(\.1).joined() + keyLabel
    }

    var carbonModifiers: UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        return [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)]
            .reduce(0) { $0 | (flags.contains($1.0) ? UInt32($1.1) : 0) }
    }

    var eventFlags: CGEventFlags { CGEventFlags(rawValue: UInt64(modifiers)) }

    var isFunctionKey: Bool {
        keyLabel.hasPrefix("F") && Int(keyLabel.dropFirst()).map { (1...20).contains($0) } == true
    }

    func matches(_ event: NSEvent, allowKeypadEnter: Bool = false) -> Bool {
        let isReturnAlias = allowKeypadEnter && keyCode == kVK_Return && event.keyCode == kVK_ANSI_KeypadEnter
        return (event.keyCode == keyCode || isReturnAlias)
            && event.modifierFlags.intersection(Self.supportedFlags).rawValue == UInt(modifiers)
    }

    func matches(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventKeycode) == Int64(keyCode)
            && event.flags.intersection(Self.macFlags) == eventFlags
    }

    static let systemCopy = Self(kVK_ANSI_C, .command, label: "C")
    static let systemPaste = Self(kVK_ANSI_V, .command, label: "V")
    static let systemMove = Self(kVK_ANSI_V, [.command, .option], label: "V")
    static let systemClose = Self(kVK_ANSI_W, .command, label: "W")
    static let systemCancel = Self(kVK_Escape, label: "Esc")
}


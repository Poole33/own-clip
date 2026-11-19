import AppKit
import Foundation

extension SmokeTests {
    static func testShortcuts() throws {
        var settings = ShortcutSettings()
        try check(settings[.pastePlain]?.label == "⌘Return" && settings[.quick10]?.label == "⌘0", "Wrong default shortcut")
        let keypad = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .numericPad],
                                     timestamp: 0, windowNumber: 0, context: nil, characters: "\u{3}",
                                     charactersIgnoringModifiers: "\u{3}", isARepeat: false, keyCode: 76)
        guard let keypad else { throw SmokeFailure(description: "Could not create a keypad Enter fixture") }
        try check(settings[.pastePlain]?.matches(keypad, allowKeypadEnter: true) == true,
                  "Command–keypad Enter did not match the plain paste default")
        try check(settings[.pastePlain]?.matches(keypad) == false && settings[.paste]?.matches(keypad, allowKeypadEnter: true) == false,
                  "Keypad Enter bypassed exact key or modifier matching")
        try check(settings[.stackPaste] == KeyBinding.systemPaste && settings[.finderMove] == KeyBinding.systemPaste, "Wrong contextual keys")
        try check(settings.conflict(for: .finderMove, binding: .systemPaste) == nil, "Contextual sharing was rejected")
        if let paste = settings[.pastePlain] {
            try check(settings.conflict(for: .quick2, binding: paste) == .pastePlain, "Panel conflict was not detected")
        }
        settings.change(.quick10, to: nil)
        let replacement = KeyBinding(7, [.control, .option], label: "X")
        settings.change(.openHistory, to: replacement)
        let bytes = try JSONEncoder().encode(settings)
        var recovered = try JSONDecoder().decode(ShortcutSettings.self, from: bytes)
        try check(recovered[.quick10] == nil && recovered[.openHistory] == replacement, "Custom shortcuts failed to persist")
        recovered.restore(.quick10)
        try check(recovered[.quick10]?.label == "⌘0", "Default shortcut could not be restored")
    }
}

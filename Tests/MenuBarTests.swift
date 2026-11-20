import AppKit

extension SmokeTests {
    static func testMenuShortcuts() throws {
        _ = NSApplication.shared
        let controller = MenuBarController()
        var shortcuts = ShortcutSettings()
        var menu = controller.makeStatusMenu(shortcuts: shortcuts)
        try check(menu.items[0].keyEquivalent == "v" && menu.items[1].keyEquivalent == "c"
                  && menu.items.prefix(2).allSatisfy { $0.keyEquivalentModifierMask == [.command, .shift] },
                  "Menu did not show the default global shortcuts")

        shortcuts.change(.openHistory, to: KeyBinding(7, [.control, .option], label: "X"))
        shortcuts.change(.openStack, to: nil)
        let saved = try JSONEncoder().encode(shortcuts)
        let recovered = try JSONDecoder().decode(ShortcutSettings.self, from: saved)
        menu = controller.makeStatusMenu(shortcuts: recovered)
        try check(menu.items[0].keyEquivalent == "x" && menu.items[0].keyEquivalentModifierMask == [.control, .option],
                  "Menu ignored a saved custom shortcut")
        try check(menu.items[1].keyEquivalent.isEmpty && menu.items[1].keyEquivalentModifierMask.isEmpty,
                  "Disabled shortcut left a menu hint")
        var openedHistory = false
        var openedStack = false
        controller.onShowHistory = { openedHistory = true }
        controller.onShowStack = { openedStack = true }
        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 1)
        try check(openedHistory && openedStack, "Shortcut hints changed the menu click actions")

        shortcuts.restore(.openHistory)
        shortcuts.restore(.openStack)
        menu = controller.makeStatusMenu(shortcuts: shortcuts)
        try check(menu.items[0].keyEquivalent == "v" && menu.items[1].keyEquivalent == "c",
                  "Restoring shortcuts left stale menu hints")

        let specialKeys: [(KeyBinding, Int)] = [
            (KeyBinding(126, [.control], label: "↑"), NSUpArrowFunctionKey),
            (KeyBinding(111, label: "F12"), NSF12FunctionKey),
            (KeyBinding(36, [.option], label: "Return"), NSCarriageReturnCharacter),
            (KeyBinding(51, [.command], label: "Delete"), NSBackspaceCharacter)
        ]
        for (binding, character) in specialKeys {
            shortcuts.change(.openHistory, to: binding)
            let entry = controller.makeStatusMenu(shortcuts: shortcuts).items[0]
            try check(entry.keyEquivalent == String(UnicodeScalar(character)!)
                      && entry.keyEquivalentModifierMask.rawValue == UInt(binding.modifiers),
                      "Special key \(binding.label) did not use a native menu equivalent")
        }
    }
}

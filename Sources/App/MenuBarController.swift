import AppKit

/// Owns the status item and menus; actions are supplied by the app coordinator.
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var visibilityObservation: NSKeyValueObservation?
    private var statusMessage: AppMessage?
    private(set) var isTracking = false

    var onShowHistory: (() -> Void)?
    var onShowStack: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onCloseWindow: (() -> Void)?
    var onTrackingChange: ((Bool) -> Void)?
    var onVisibilityChange: ((Bool) -> Void)?

    func rebuild(shortcuts: ShortcutSettings) {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = OwnClipIcon.menuBarImage()
        item.button?.setAccessibilityLabel("OwnClip")
        item.button?.toolTip = statusMessage.map { "OwnClip · \($0.text)" } ?? "OwnClip"
        item.menu = makeStatusMenu(shortcuts: shortcuts)
        if statusItem == nil {
            statusItem = item
            item.behavior.insert(.removalAllowed)
            visibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                // AppKit can notify during layout. Read the latest value once back on the main queue.
                DispatchQueue.main.async { self?.publishVisibility() }
            }
            publishVisibility()
        }

        let mainMenu = NSMenu()
        mainMenu.addItem(NSMenuItem())
        let file = NSMenuItem(title: AppText.text("文件"), action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: file.title)
        let close = NSMenuItem(title: AppText.text("关闭窗口"), action: #selector(closeWindow), keyEquivalent: "w")
        close.target = self
        fileMenu.addItem(close)
        file.submenu = fileMenu
        mainMenu.addItem(file)
        NSApp.mainMenu = mainMenu
    }

    func setVisible(_ visible: Bool) {
        guard let statusItem else { return }
        statusItem.isVisible = visible
        publishVisibility()
    }

    private func publishVisibility() {
        guard let statusItem else { return }
        onVisibilityChange?(statusItem.isVisible)
    }

    func makeStatusMenu(shortcuts: ShortcutSettings) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        for (action, selector) in [(ShortcutAction.openHistory, #selector(showHistory)),
                                   (.openStack, #selector(showStack))] {
            let binding = shortcuts[action]
            let entry = NSMenuItem(title: action.title, action: selector, keyEquivalent: binding?.menuKeyEquivalent ?? "")
            entry.keyEquivalentModifierMask = binding.map { NSEvent.ModifierFlags(rawValue: UInt($0.modifiers)) } ?? []
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: AppText.text("设置…"), action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: AppText.text("退出 OwnClip"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        return menu
    }

    func contains(_ location: NSPoint) -> Bool {
        guard let statusItem, statusItem.isVisible,
              let button = statusItem.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(location)
    }

    func showStatus(_ message: AppMessage) {
        statusMessage = message
        statusItem?.button?.toolTip = "OwnClip · \(message.text)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.statusMessage = nil
            self?.statusItem?.button?.toolTip = "OwnClip"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isTracking = true
        onTrackingChange?(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        isTracking = false
        onTrackingChange?(false)
    }

    @objc private func showHistory() { onShowHistory?() }
    @objc private func showStack() { onShowStack?() }
    @objc private func showSettings() { onShowSettings?() }
    @objc private func closeWindow() { onCloseWindow?() }
}

import AppKit
import OSLog
import SwiftUI

/// Creates native windows and owns their placement, focus diagnostics and observers.
final class WindowCoordinator {
    private(set) var historyPanel: ClipPanel?
    private(set) var stackPanel: ClipPanel?
    private var settingsWindowController: NSWindowController?
    var settingsWindow: NSWindow? { settingsWindowController?.window }
    var isTrackingMenu: () -> Bool = { false }

    private let preferences: UserDefaults
    private var layout: HistoryLayout = .strip
    private var listPositions: [String: [Double]]
    private var stackPositions: [String: [Double]]
    private var placingHistory = false
    private var placingStack = false
    private var historyMoveObserver: NSObjectProtocol?
    private var stackMoveObserver: NSObjectProtocol?
    private var focusObservers: [NSObjectProtocol] = []
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let settingsFocusLogger = Logger(subsystem: "local.ownclip.OwnClip", category: "SettingsFocus")
    private var settingsFocusDiagnosticsID = 0
    private var pasteFeedbackPanel: ClipPanel?
    private var dismissPasteFeedback: DispatchWorkItem?

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        listPositions = preferences.dictionary(forKey: "historyListPositions") as? [String: [Double]] ?? [:]
        stackPositions = preferences.dictionary(forKey: "sequentialPastePositions") as? [String: [Double]] ?? [:]
    }

    func startObservingFocus() {
        stopObservingFocus()
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                guard let self, let window = event.object as? NSWindow,
                      settingsWindow?.isVisible == true || window === settingsWindow else { return }
                recordSettingsFocus("\(name.rawValue) window=\(window.windowNumber) class=\(String(describing: type(of: window)))")
            }
            focusObservers.append(observer)
        }
    }

    private func stopObservingFocus() {
        for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
        focusObservers.removeAll()
    }

    func stopObserving() {
        stopObservingFocus()
        if let historyMoveObserver { NotificationCenter.default.removeObserver(historyMoveObserver) }
        if let stackMoveObserver { NotificationCenter.default.removeObserver(stackMoveObserver) }
        historyMoveObserver = nil
        stackMoveObserver = nil
        dismissFeedback()
    }

    deinit { stopObserving() }

    func showHistory(model: AppController) {
        let panel = historyPanel ?? makeHistoryPanel(model: model)
        placeHistory(panel, layout: model.layout)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makeHistoryPanel(model: AppController) -> ClipPanel {
        let panel = makePanel()
        panel.title = AppText.History.windowTitle
        panel.contentView = NSHostingView(rootView: HistoryView(model: model))
        historyPanel = panel
        historyMoveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
                                                                     object: panel, queue: .main) { [weak self] _ in
            self?.rememberListPosition()
        }
        return panel
    }

    func placeHistory(_ panel: NSPanel, layout: HistoryLayout, on preferredScreen: NSScreen? = nil) {
        self.layout = layout
        guard let screen = preferredScreen ?? screenUnderPointer() else { return }
        placingHistory = true
        defer { placingHistory = false }
        let area = screen.visibleFrame
        panel.hasShadow = layout == .list
        panel.isMovable = layout == .list
        switch layout {
        case .strip:
            let bounds = screen.frame
            let height = min(HistoryStripLayout.panelHeight, area.height * 0.48)
            panel.setFrame(NSRect(x: bounds.minX, y: area.minY, width: bounds.width, height: height), display: true)
        case .list:
            let size = NSSize(width: min(510, max(area.width - 32, 300)), height: min(470, area.height - 32))
            let offset = displayKey(screen).flatMap { listPositions[$0] }
            panel.setFrame(WindowPlacement.frame(size: size, in: area, offset: offset), display: true)
        }
    }

    private func rememberListPosition() {
        guard layout == .list, !placingHistory, let panel = historyPanel, panel.isVisible,
              let screen = panel.screen, let key = displayKey(screen) else { return }
        let area = screen.visibleFrame
        listPositions[key] = [panel.frame.minX - area.minX, panel.frame.minY - area.minY]
        preferences.set(listPositions, forKey: "historyListPositions")
    }

    private func displayKey(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return number.stringValue
    }

    func showStack(model: AppController, requestFocus: Bool) {
        let panel: ClipPanel
        if let current = stackPanel {
            panel = current
        } else {
            panel = makePanel()
            panel.title = AppText.SequentialPaste.windowTitle
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.isMovable = true
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: StackView(model: model))
            stackPanel = panel
            stackMoveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
                                                                       object: panel, queue: .main) { [weak self] _ in
                self?.rememberStackPosition()
            }
        }
        if !panel.isVisible { placeStack(panel, interfaceLanguage: model.interfaceLanguage) }
        if requestFocus { panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
    }

    func placeStack(_ panel: NSPanel, interfaceLanguage: AppLanguage) {
        guard let screen = screenUnderPointer() else { return }
        placingStack = true
        defer { placingStack = false }
        let area = screen.visibleFrame
        let size = NSSize(width: min(interfaceLanguage == .english ? 560 : 440, area.width - 32), height: min(339, area.height - 32))
        let offset = displayKey(screen).flatMap { stackPositions[$0] }
        panel.setFrame(WindowPlacement.stackFrame(size: size, in: area, offset: offset), display: true)
    }

    private func rememberStackPosition() {
        guard !placingStack, let panel = stackPanel, panel.isVisible,
              let screen = panel.screen, let key = displayKey(screen) else { return }
        let area = screen.visibleFrame
        stackPositions[key] = [panel.frame.minX - area.minX, panel.frame.minY - area.minY]
        preferences.set(stackPositions, forKey: "sequentialPastePositions")
    }

    func showSettings(model: AppController, on screen: NSScreen?) {
        settingsFocusDiagnosticsID += 1
        recordSettingsFocus("settings.open.begin")
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 614),
                                    styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                    backing: .buffered, defer: false)
            window.title = AppText.text("OwnClip 设置")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
            window.contentView = NSHostingView(rootView: PreferencesView(model: model))
            let controller = NSWindowController(window: window)
            controller.shouldCascadeWindows = false
            settingsWindowController = controller
        }
        let movingBetweenSpaces = window.isVisible && !window.isOnActiveSpace
        if movingBetweenSpaces { window.orderOut(nil) }
        if let screen, !window.isVisible || window.screen != screen {
            let coveredStrip = model.layout == .strip && historyPanel?.isVisible == true && historyPanel?.screen == screen
                ? historyPanel?.frame : nil
            window.setFrameOrigin(WindowPlacement.settingsFrame(size: window.frame.size, in: screen.visibleFrame,
                                                                 above: coveredStrip).origin)
        }
        window.level = historyPanel?.isVisible == true ? .floating : .normal
        recordSettingsFocus("settings.open.beforePresentation")
        // Follow Maccy's Settings controller: activate, show and make key, then order front.
        NSApp.activate()
        recordSettingsFocus("settings.open.afterActivate")
        settingsWindowController?.showWindow(nil)
        recordSettingsFocus("settings.open.afterShowWindow")
        window.orderFrontRegardless()
        recordSettingsFocus("settings.open.afterOrderFront")
        let request = settingsFocusDiagnosticsID
        for delay in [0.05, 0.25, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, settingsFocusDiagnosticsID == request else { return }
                recordSettingsFocus("settings.open.after\(delay)s")
            }
        }
    }

    func recordSettingsFocus(_ phase: String) {
        // Temporary diagnostics: record lifecycle state only, never clipboard or typed text.
        let window = settingsWindow
        let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let event = NSApp.currentEvent
        let state = "diagnostics=2 phase=\(phase) request=\(settingsFocusDiagnosticsID)"
            + " uptime=\(ProcessInfo.processInfo.systemUptime)"
            + " appActive=\(NSApp.isActive) runningAppActive=\(NSRunningApplication.current.isActive)"
            + " foregroundPID=\(foregroundPID) ownPID=\(ownPID)"
            + " trackingMenu=\(isTrackingMenu())"
            + " settings=\(window?.windowNumber ?? -1) visible=\(window?.isVisible ?? false)"
            + " key=\(window?.isKeyWindow ?? false) main=\(window?.isMainWindow ?? false)"
            + " canBecomeKey=\(window?.canBecomeKey ?? false) sheet=\(window?.attachedSheet != nil)"
            + " appKey=\(NSApp.keyWindow?.windowNumber ?? -1) appMain=\(NSApp.mainWindow?.windowNumber ?? -1)"
            + " runLoop=\(RunLoop.current.currentMode?.rawValue ?? "none")"
            + " eventType=\(event.map { String($0.type.rawValue) } ?? "none")"
            + " eventWindow=\(event?.windowNumber ?? -1)"
        settingsFocusLogger.notice("\(state, privacy: .public)")
    }

    private func makePanel() -> ClipPanel {
        let panel = ClipPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        return panel
    }

    func screenUnderPointer() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    func dismissFeedback() {
        dismissPasteFeedback?.cancel()
        pasteFeedbackPanel?.orderOut(nil)
    }

    func showPasteFeedback(_ message: AppMessage, on screen: NSScreen?) {
        guard let area = (screen ?? screenUnderPointer())?.visibleFrame else { return }
        dismissPasteFeedback?.cancel()
        let panel = pasteFeedbackPanel ?? makePanel()
        let content = NSHostingView(rootView: PasteFeedbackView(message: message))
        let size = content.fittingSize
        panel.ignoresMouseEvents = true
        panel.contentView = content
        panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.minY + 23,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        pasteFeedbackPanel = panel
        let dismissal = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        dismissPasteFeedback = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: dismissal)
    }
}

import AppKit
import Combine
import CoreGraphics
import ServiceManagement
import SwiftUI

final class AppController: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var history: [ClipSummary] = []
    @Published var query = "" {
        didSet { selected = filtered.first?.id }
    }
    @Published var selected: String?
    @Published private(set) var historyPresentation = 0
    @Published private(set) var historyFocusRequest = 0
    @Published private(set) var stack = PasteStack()
    @Published private(set) var collecting = false
    @Published private(set) var language = AppText.language
    @Published private(set) var interfaceLanguage = AppText.resolvedLanguage
    @Published private(set) var layout: HistoryLayout = .strip
    @Published private(set) var days = 1
    @Published private(set) var loginItemStatus: SMAppService.Status = .notRegistered
    @Published private(set) var loginItemError: AppMessage?
    @Published private(set) var finderCutEnabled = false
    @Published private(set) var restartedForPaste = false
    @Published private(set) var contextKeysReady = false
    @Published private(set) var contextKeysWanted = false
    @Published var settingsTab: SettingsTab = .general
    @Published var notice: AppMessage?

    private let clipboard = ClipboardMonitor()
    private lazy var finderMoves = FinderMoveService(clipboard: clipboard)
    private lazy var permissions = PermissionService(clipboard: clipboard)
    private lazy var pasteService = PasteService(changeCount: { [clipboard] in clipboard.changeCount })
    private let windows = WindowCoordinator()
    private let menuBar = MenuBarController()
    private let shortcutService = ShortcutService()
    private var serviceObservations: Set<AnyCancellable> = []

    var shortcuts: ShortcutSettings { shortcutService.bindings }
    var recording: ShortcutAction? {
        get { shortcutService.recording }
        set { shortcutService.recording = newValue }
    }
    var shortcutError: AppMessage? { shortcutService.error }

    var directPaste: Bool { permissions.directPaste }
    var accessibilityTrusted: Bool { permissions.accessibilityTrusted }
    var pastePermissionReview: PastePermissionReview { permissions.pastePermissionReview }
    var restartingForPaste: Bool { permissions.restartingForPaste }
    var restartError: AppMessage? { permissions.restartError }
    var pasteboardDenied: Bool { permissions.pasteboardDenied }
    private var historyPanel: ClipPanel? { windows.historyPanel }
    private var stackPanel: ClipPanel? { windows.stackPanel }
    private var settingsWindow: NSWindow? { windows.settingsWindow }
    private var trackingStatusMenu: Bool { menuBar.isTracking }

    private let preferences = UserDefaults.standard
    private let contextKeys = ContextKeys()
    private let previewCache = PreviewCache()
    private let loginItem = SMAppService.mainApp
    private var store: HistoryStore?
    // Polling deadlines use uptime so wall clock changes cannot delay them.
    private var nextPurge: TimeInterval = 0
    private var pollTimer: Timer?
    private var localKeys: Any?
    private var pointerMonitor: Any?
    private var localeObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var windowObserver: NSObjectProtocol?
    private var lastApplication: NSRunningApplication?
    private var historyTarget: NSRunningApplication?
    private var queuedPastes: [(target: pid_t, fallback: KeyBinding)] = []
    private var pasteScheduled = false
    private var lastHotKey: (ShortcutAction, TimeInterval)?

    var filtered: [ClipSummary] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return history }
        return history.filter { clip in
            [clip.displayTitle, clip.searchable, clip.source, clip.kind.label].contains { $0.localizedStandardContains(text) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        localeObserver = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.refreshLanguage()
        }
        restartedForPaste = AppLaunch.reopenedForPaste
        layout = preferences.string(forKey: "layout").flatMap(HistoryLayout.init(rawValue:)) ?? .strip
        days = min(7, max(1, preferences.object(forKey: "retentionDays") as? Int ?? 1))
        finderCutEnabled = preferences.bool(forKey: "finderCut")
        clipboard.synchronize()
        rememberFrontApp()
        do {
            store = try HistoryStore.openDefault()
            prune()
            history = try store?.history() ?? []
        } catch { notice = .init(AppText.errorDescription(error)) }

        connectServices()
        menuBar.rebuild()
        shortcutService.start()
        contextKeys.onKeyDown = { [weak self] event in self?.intercept(event) == true }
        refreshPermissions()
        refreshLoginItemStatus()
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalKey(event) == true ? nil : event
        }
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = historyPanel, panel.isVisible, !trackingStatusMenu else { return }
            let location = NSEvent.mouseLocation
            guard !panel.frame.contains(location), !menuBar.contains(location),
                  !(settingsWindow?.isVisible == true && settingsWindow?.frame.contains(location) == true) else { return }
            hideHistory()
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                              object: nil, queue: .main) { [weak self] event in
            guard let self else { return }
            if settingsWindow?.isVisible == true {
                recordSettingsFocus("workspace.didActivateApplication")
            }
            if !trackingStatusMenu, let previous = historyTarget, let front = frontApplication(),
               front.processIdentifier != previous.processIdentifier, front.bundleIdentifier != "com.apple.controlcenter" {
                hideHistory()
            }
            rememberFrontApp()
            let active = event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            permissions.observeActiveApplication(active)
        }
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                                  object: nil, queue: .main) { [weak self] event in
            guard let self, event.object as? NSWindow === settingsWindow else { return }
            recordSettingsFocus("settings.willClose")
            recording = nil
            DispatchQueue.main.async { [weak self] in self?.restoreHistoryFocus() }
        }
        windows.startObservingFocus()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        let firstPermissionPrompt = !preferences.bool(forKey: "didShowPasteAccessOnboarding")
        if firstPermissionPrompt { preferences.set(true, forKey: "didShowPasteAccessOnboarding") }
        if restartedForPaste || !preferences.bool(forKey: "didShowSettings") || (firstPermissionPrompt && !directPaste) {
            preferences.set(true, forKey: "didShowSettings")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                showSettings()
                if firstPermissionPrompt && !restartedForPaste { showPasteAccessOnboarding() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard pollTimer != nil else { return false }
        showHistory()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard pollTimer != nil else { return }
        refreshLanguage()
        recordSettingsFocus("application.didBecomeActive")
        refreshPermissions()
        refreshLoginItemStatus()
    }

    func applicationDidResignActive(_ notification: Notification) {
        recordSettingsFocus("application.didResignActive")
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        contextKeys.stop()
        if let localKeys { NSEvent.removeMonitor(localKeys) }
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let localeObserver { NotificationCenter.default.removeObserver(localeObserver) }
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windows.stopObserving()
    }

    private func connectServices() {
        permissions.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &serviceObservations)
        shortcutService.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &serviceObservations)
        shortcutService.onAction = { [weak self] action in self?.globalAction(action) }
        shortcutService.onBindingsChange = { [weak self] in self?.refreshPermissions() }
        permissions.onAccessChange = { [weak self] in self?.updateContextKeys() }
        finderMoves.beforeCopy = { [weak self] in self?.pollClipboard() }
        finderMoves.onCapture = { [weak self] payload in self?.save(payload) }
        finderMoves.onStatus = { [weak menuBar] message in menuBar?.showStatus(message) }
        windows.isTrackingMenu = { [weak menuBar] in menuBar?.isTracking == true }
        menuBar.onShowHistory = { [weak self] in self?.showHistory() }
        menuBar.onShowStack = { [weak self] in self?.showStack() }
        menuBar.onShowSettings = { [weak self] in self?.showSettingsFromStatusMenu() }
        menuBar.onCloseWindow = { [weak self] in _ = self?.closeWindow(NSApp.keyWindow) }
        menuBar.onTrackingChange = { [weak self] tracking in
            self?.recordSettingsFocus(tracking ? "menu.willOpen" : "menu.didClose")
        }
    }

    private func globalAction(_ action: ShortcutAction) {
        if let recording, let binding = shortcuts[action], NSApp.keyWindow === settingsWindow {
            changeShortcut(recording, binding: binding)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastHotKey, lastHotKey.0 == action, now - lastHotKey.1 < 0.33 { return }
        lastHotKey = (action, now)
        switch action {
        case .openHistory:
            if historyPanel?.isVisible == true { hideHistory() } else { showHistory() }
        case .openStack:
            hideHistory()
            showStack()
        default:
            break
        }
    }

    @objc func showHistory() {
        pasteService.cancel()
        windows.dismissFeedback()
        rememberFrontApp()
        refreshPermissions()
        historyTarget = frontApplication() ?? lastApplication
        tick()
        prune()
        query = ""
        selected = filtered.first?.id
        windows.showHistory(model: self)
        historyPresentation += 1
    }

    func hideHistory() {
        historyPanel?.orderOut(nil)
        historyTarget = nil
    }

    @objc func showStack() {
        if trackingStatusMenu {
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                self?.presentStack(requestFocus: true)
            }
        } else {
            presentStack(requestFocus: true)
        }
    }

    private func presentStack(requestFocus: Bool) {
        rememberFrontApp()
        refreshPermissions()
        pollClipboard()
        if stackPanel?.isVisible != true || !collecting { collecting = true }
        windows.showStack(model: self, requestFocus: requestFocus)
        updateContextKeys()
    }

    func closeStack() {
        stackPanel?.orderOut(nil)
        collecting = false
        stack = PasteStack()
        queuedPastes.removeAll()
        updateContextKeys()
    }

    func addToStack(_ clip: ClipSummary) {
        presentStack(requestFocus: false)
        append(clip)
    }

    private func append(_ clip: ClipSummary) {
        stack.append(clip)
    }

    func setStackPasteMode(_ mode: StackPasteMode) { stack.setMode(mode) }

    func reverseStack() { stack.reverse() }

    func removeStackEntry(_ id: UUID) {
        stack.removeAll { $0.id == id }
        closeStackIfFinished()
    }

    private func closeStackIfFinished() {
        if stackPanel?.isVisible == true && stack.isEmpty && !collecting && !pasteScheduled { closeStack() }
    }

    func pasteNextFromPanel() {
        let target = frontApplication() ?? lastApplication
        if let target { enqueuePaste(to: target.processIdentifier, fallback: .systemPaste) }
    }

    private func showSettingsFromStatusMenu() {
        recordSettingsFocus("menu.settingsAction")
        let screen = screenUnderPointer()
        // Wait until AppKit leaves menu tracking before ordering the window.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            self?.recordSettingsFocus("menu.settingsAction.deferred")
            self?.openSettings(on: screen)
        }
    }

    func showSettings() {
        openSettings(on: screenUnderPointer())
    }

    func showSettingsFromHistory() {
        openSettings(on: historyPanel?.screen ?? screenUnderPointer())
    }

    private func openSettings(on screen: NSScreen?) {
        refreshPermissions()
        refreshLoginItemStatus()
        windows.showSettings(model: self, on: screen)
    }

    private func recordSettingsFocus(_ phase: String) { windows.recordSettingsFocus(phase) }

    private func restoreHistoryFocus() {
        let foreground = frontApplication()
        guard foreground == nil || foreground?.processIdentifier == historyTarget?.processIdentifier,
              settingsWindow?.isVisible != true,
              let panel = historyPanel, panel.isVisible, panel.isOnActiveSpace else { return }
        panel.makeKeyAndOrderFront(nil)
        historyFocusRequest += 1
    }

    func showPermissionSettings() {
        settingsTab = .general
        if historyPanel?.isKeyWindow == true { showSettingsFromHistory() } else { showSettings() }
    }

    private func screenUnderPointer() -> NSScreen? { windows.screenUnderPointer() }

    func setLanguage(_ value: AppLanguage) {
        guard language != value else { return }
        AppText.language = value
        value.save()
        language = value
        refreshLanguage(force: true)
    }

    private func refreshLanguage(force: Bool = false) {
        let resolved = AppText.resolvedLanguage
        guard force || interfaceLanguage != resolved else { return }
        interfaceLanguage = resolved
        menuBar.rebuild()
        settingsWindow?.title = AppText.text("OwnClip 设置")
        historyPanel?.title = AppText.History.windowTitle
        stackPanel?.title = AppText.SequentialPaste.windowTitle
        if let panel = stackPanel, panel.isVisible { windows.placeStack(panel, interfaceLanguage: interfaceLanguage) }
    }

    func setLayout(_ value: HistoryLayout) {
        layout = value
        preferences.set(value.rawValue, forKey: "layout")
        if let panel = historyPanel, panel.isVisible { windows.placeHistory(panel, layout: layout, on: panel.screen) }
    }

    var launchAtLogin: Bool { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil
        do {
            if enabled { try loginItem.register() } else { try loginItem.unregister() }
        } catch {
            loginItemError = .init(AppText.errorDescription(error))
        }
        refreshLoginItemStatus()
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    private func refreshLoginItemStatus() {
        let status = loginItem.status
        if loginItemStatus != status { loginItemStatus = status }
    }

    func setDays(_ value: Int) {
        days = min(7, max(1, value))
        preferences.set(days, forKey: "retentionDays")
        prune()
    }

    func setFinderCut(_ enabled: Bool) {
        finderCutEnabled = enabled
        preferences.set(enabled, forKey: "finderCut")
        if !enabled { finderMoves.cancel() }
        refreshPermissions()
    }

    func changeShortcut(_ action: ShortcutAction, binding: KeyBinding?) { shortcutService.change(action, binding: binding) }
    func restoreShortcut(_ action: ShortcutAction) { shortcutService.restore(action) }
    func restoreShortcuts() { shortcutService.restoreAll() }
    func recordShortcut(_ action: ShortcutAction?) { shortcutService.record(action) }

    private func handleLocalKey(_ event: NSEvent) -> Bool {
        let window = event.window ?? NSApp.keyWindow
        if KeyBinding.systemClose.matches(event) {
            return closeWindow(window)
        }
        if KeyBinding.systemCancel.matches(event) {
            if window === settingsWindow, recording != nil, window?.attachedSheet == nil {
                recording = nil
                return true
            }
            return closeWindow(window)
        }
        if window === settingsWindow, let recording {
            if let key = KeyBinding(event: event) { changeShortcut(recording, binding: key) }
            return true
        }
        for action in [ShortcutAction.openHistory, .openStack] where shortcuts[action]?.matches(event) == true {
            if !event.isARepeat { globalAction(action) }
            return true
        }
        if window === stackPanel, stackPanel?.isVisible == true {
            if shortcuts[.close]?.matches(event) == true { closeStack(); return true }
            if shortcuts[.stackReverse]?.matches(event) == true { reverseStack(); return true }
            if shortcuts[.stackPaste]?.matches(event) == true { pasteNextFromPanel(); return true }
        }
        guard window === historyPanel, historyPanel?.isVisible == true else { return false }
        let exact = ShortcutAction.allCases.first { action in
            (action.scope == .historyPanel || action.scope == .panel) && shortcuts[action]?.matches(event) == true
        }
        let keypadAlias = [ShortcutAction.paste, .pastePlain].first {
            shortcuts[$0]?.matches(event, allowKeypadEnter: true) == true
        }
        guard let action = exact ?? keypadAlias else { return false }
        if let index = action.quickIndex {
            let clips = filtered
            if clips.indices.contains(index) { paste(clips[index]) }
            return true
        }
        switch action {
        case .close:
            hideHistory()
        case .paste, .pastePlain:
            let clips = filtered
            if let clip = clips.first(where: { $0.id == selected }) ?? clips.first { paste(clip, plainText: action == .pastePlain) }
        case .previous, .next, .left, .right:
            if (action == .left || action == .right) && !query.isEmpty && window?.firstResponder is NSTextView {
                return false
            }
            moveSelection(by: action == .previous || action == .left ? -1 : 1)
        default:
            return false
        }
        return true
    }

    @discardableResult
    private func closeWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        let owner = window.sheetParent ?? window
        guard owner === historyPanel || owner === stackPanel || owner === settingsWindow else { return false }
        // Dismiss a confirmation first, preserving its parent and its cancel action.
        if let sheet = owner.attachedSheet {
            if let button = cancelButton(in: sheet.contentView) {
                button.performClick(nil)
            } else {
                owner.endSheet(sheet, returnCode: .cancel)
                sheet.orderOut(nil)
            }
        } else if owner === historyPanel {
            hideHistory()
        } else if owner === stackPanel {
            closeStack()
        } else {
            owner.performClose(nil)
        }
        return true
    }

    private func cancelButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.isEnabled, button.keyEquivalent == "\u{1b}" { return button }
        return view.subviews.lazy.compactMap { self.cancelButton(in: $0) }.first
    }

    private func moveSelection(by offset: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let position = list.firstIndex { $0.id == selected } ?? (offset < 0 ? list.count : -1)
        selected = list[min(list.count - 1, max(0, position + offset))].id
    }

    func shortcutForQuickItem(at index: Int) -> String? {
        guard index < 10, let action = ShortcutAction(rawValue: ShortcutAction.quick1.rawValue + index) else { return nil }
        return shortcuts[action]?.label
    }

    private func tick() {
        pollClipboard()
        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextPurge { prune() }
        permissions.refreshIfNeeded()
    }

    @discardableResult private func pollClipboard() -> ClipboardPayload? {
        guard let change = clipboard.poll() else { return nil }
        finderMoves.clipboardDidChange(to: change.revision)
        if let payload = change.payload { save(payload) }
        return change.payload
    }

    private func save(_ payload: ClipboardPayload) {
        guard let store else { return }
        let source = frontApplication()?.localizedName ?? lastApplication?.localizedName ?? ""
        let clip = payload.summary(source: source)
        do {
            try store.save(payload, summary: clip)
            history.removeAll { $0.id == clip.id }
            history.insert(clip, at: 0)
            if selected == nil { selected = filtered.first?.id }
            if collecting { append(clip) }
        } catch { notice = .init(AppText.errorDescription(error)) }
    }

    private func prune() {
        nextPurge = ProcessInfo.processInfo.systemUptime + 60
        guard let store else { return }
        do {
            let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
            let expired = try store.purge(before: cutoff)
            if !expired.isEmpty { removeFromViews(expired) }
        } catch { reloadAfterError(error) }
    }

    func removeHistory(_ clip: ClipSummary) {
        do {
            try store?.remove(clip.id)
            removeFromViews([clip.id])
        } catch { reloadAfterError(error) }
    }

    func clearHistory() {
        do {
            try store?.clear()
            removeFromViews(Set(history.map(\.id)))
        } catch { reloadAfterError(error) }
    }

    private func removeFromViews(_ ids: Set<String>) {
        history.removeAll { ids.contains($0.id) }
        stack.removeAll { ids.contains($0.clip.id) }
        previewCache.remove(ids)
        if let selected, ids.contains(selected) { self.selected = filtered.first?.id }
        closeStackIfFinished()
    }

    private func reloadAfterError(_ error: Error) {
        notice = .init(AppText.errorDescription(error))
        if let available = try? store?.history() {
            let remaining = Set(available.map(\.id))
            removeFromViews(Set(history.map(\.id)).subtracting(remaining))
            history = available
        }
    }

    func thumbnail(for clip: ClipSummary) async -> NSImage? {
        await previewCache.image(for: clip, payloadFile: store?.payloadFile(for: clip.id))
    }

    func copy(_ clip: ClipSummary, plainText: Bool = false) {
        pollClipboard()
        if write(clip, plainText: plainText) { hideHistory() }
    }

    func paste(_ clip: ClipSummary, plainText: Bool = false) {
        pollClipboard()
        refreshPermissions()
        let target = historyTarget ?? frontApplication() ?? lastApplication
        let screen = historyPanel?.screen
        guard write(clip, plainText: plainText) else { return }
        hideHistory()
        pasteService.cancel()
        guard let target, !target.isTerminated else {
            showPasteFeedback(AppText.text("已复制，按 ⌘V 手动粘贴"), on: screen)
            return
        }
        if frontApplication() == nil && !target.isActive {
            NSApp.yieldActivation(to: target)
            _ = target.activate()
        }
        guard directPaste else {
            showPasteFeedback(AppText.text("已复制，按 ⌘V 手动粘贴"), on: screen)
            return
        }
        pasteService.pasteWhenFocused(target, revision: clipboard.revision) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .sent:
                break
            case .clipboardChanged:
                showPasteFeedback(AppText.text("剪贴板已更新，请重新选择历史记录"), on: screen)
            case .sendFailed:
                refreshPermissions()
                showPasteFeedback(AppText.text("已复制，按 ⌘V 手动粘贴"), on: screen)
            case .manualPasteRequired:
                showPasteFeedback(AppText.text("已复制，按 ⌘V 手动粘贴"), on: screen)
            }
        }
    }

    private func write(_ clip: ClipSummary, plainText: Bool) -> Bool {
        do {
            guard let store else { return false }
            let payload = try store.read(clip.id)
            if !plainText, let missing = payload.missingFile {
                notice = .init(AppText.format("源文件已不可用：%@", missing.lastPathComponent))
                return false
            }
            if plainText, payload.plainText == nil {
                notice = .init(AppText.text("这条记录没有可粘贴的文本。"))
                return false
            }
            guard clipboard.write(payload, plainText: plainText) else {
                notice = .init(AppText.text("无法写入系统剪贴板。"))
                return false
            }
            finderMoves.clearPendingMove()
            notice = nil
            return true
        } catch {
            notice = .init(AppText.format("无法读取这条记录。%@", AppText.errorDescription(error)))
            return false
        }
    }

    private func enqueuePaste(to target: pid_t, fallback: KeyBinding) {
        queuedPastes.append((target, fallback))
        if !pasteScheduled { performQueuedPaste() }
    }

    private func performQueuedPaste() {
        guard !queuedPastes.isEmpty else {
            pasteScheduled = false
            closeStackIfFinished()
            return
        }
        pasteScheduled = true
        let request = queuedPastes.removeFirst()
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.performQueuedPaste() }
        }
        pollClipboard()
        guard frontApplication()?.processIdentifier == request.target else {
            notice = .init(AppText.text("请在目标应用中粘贴。"))
            return
        }
        guard let entry = stack.next else {
            if directPaste { _ = ContextKeys.send(request.fallback, to: request.target, directlyToProcess: true) }
            return
        }
        guard write(entry.clip, plainText: false) else { return }
        if directPaste {
            // The floating panel can be the key window even while the target app is frontmost.
            guard ContextKeys.send(.systemPaste, to: request.target, directlyToProcess: true) else {
                notice = .init(AppText.text("无法发送粘贴操作。可重试当前条目。"))
                return
            }
        } else {
            showStatus(AppText.text("已放入剪贴板，请手动粘贴"))
        }
        collecting = false
        // Keep the panel and event tap in place until the paste queue has drained.
        stack.finishPaste(entry)
    }

    private func intercept(_ event: CGEvent) -> Bool {
        guard historyPanel?.isVisible != true, let front = frontApplication() else { return false }
        let pid = front.processIdentifier
        let isRepeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if finderCutEnabled, accessibilityTrusted, finderMoves.handle(event, in: front, shortcuts: shortcuts) {
            return true
        }
        if !stack.isEmpty, shortcuts[.stackReverse]?.matches(event) == true {
            if !isRepeated { DispatchQueue.main.async { [weak self] in self?.reverseStack() } }
            return true
        }
        if let key = shortcuts[.stackPaste], key.matches(event),
           !stack.isEmpty || (collecting && clipboard.changeCount != clipboard.revision) {
            if !isRepeated { DispatchQueue.main.async { [weak self] in self?.enqueuePaste(to: pid, fallback: key) } }
            return true
        }
        return false
    }

    func requestAccessibility() { permissions.requestAccessibility() }

    func requestPasteAccess() {
        permissions.requestPasteAccess { showPermissionSettings() }
    }

    private func showPasteAccessOnboarding() {
        guard !directPaste, let window = settingsWindow else { return }
        let alert = NSAlert()
        alert.messageText = AppText.text("开启自动粘贴")
        alert.informativeText = AppText.History.pastePermission
        alert.addButton(withTitle: AppText.text("打开系统设置"))
        alert.addButton(withTitle: AppText.text("稍后"))
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.requestPasteAccess() }
        }
    }

    func reviewPasteAccess() { permissions.reviewPasteAccess() }
    func restartForPastePermission() { permissions.restartForPastePermission() }
    func requestInputMonitoring() { permissions.requestInputMonitoring() }
    func refreshPermissions() { permissions.refresh() }

    private func updateContextKeys() {
        let stackWantsKeys = stackPanel?.isVisible == true && (shortcuts[.stackPaste] != nil || shortcuts[.stackReverse] != nil)
        let finderWantsKeys = finderCutEnabled && (shortcuts[.finderCut] != nil || shortcuts[.finderMove] != nil)
        let wanted = stackWantsKeys || (finderWantsKeys && accessibilityTrusted)
        if contextKeysWanted != wanted { contextKeysWanted = wanted }
        if directPaste && wanted {
            contextKeys.start()
        } else {
            contextKeys.stop()
        }
        if contextKeysReady != contextKeys.isRunning { contextKeysReady = contextKeys.isRunning }
    }

    private func frontApplication() -> NSRunningApplication? { ApplicationFocus.frontApplication() }

    private func rememberFrontApp() {
        if let front = frontApplication() { lastApplication = front }
    }

    private func showStatus(_ text: @autoclosure @escaping () -> String) {
        menuBar.showStatus(AppMessage(text()))
    }

    private func showPasteFeedback(_ text: @autoclosure @escaping () -> String, on screen: NSScreen?) {
        windows.showPasteFeedback(AppMessage(text()), on: screen)
    }

}

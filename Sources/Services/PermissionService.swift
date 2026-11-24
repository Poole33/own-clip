import AppKit
import ApplicationServices
import Combine

enum PastePermissionReview {
    case idle, checking, restartSuggested, restartRequired
    var offersRestart: Bool { self == .restartSuggested || self == .restartRequired }
}

/// Owns permission polling and the review flow after returning from System Settings.
final class PermissionService: ObservableObject {
    @Published private(set) var directPaste = false
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var pastePermissionReview: PastePermissionReview = .idle
    @Published private(set) var restartingForPaste = false
    @Published private(set) var restartError: AppMessage?
    @Published private(set) var pasteboardDenied = false

    var onAccessChange: (() -> Void)?
    var onRestartRequired: (() -> Void)?
    private let clipboard: ClipboardMonitor
    private var nextCheck: TimeInterval = 0
    private var checkUntil: TimeInterval = 0
    private var requestID: UUID?
    private var restartPromptRequestID: UUID?
    private var settingsWasActive = false
    private var reviewInProgress = false

    init(clipboard: ClipboardMonitor) { self.clipboard = clipboard }

    func refreshIfNeeded() {
        if ProcessInfo.processInfo.systemUptime >= nextCheck { refresh() }
    }

    func refresh() {
        let canPost = CGPreflightPostEventAccess()
        let trusted = AXIsProcessTrusted()
        let now = ProcessInfo.processInfo.systemUptime
        nextCheck = now + (!canPost && now < checkUntil ? 1 : 5)
        if directPaste != canPost { directPaste = canPost }
        if canPost && pastePermissionReview != .idle {
            pastePermissionReview = .idle
            requestID = nil
            reviewInProgress = false
        }
        if accessibilityTrusted != trusted { accessibilityTrusted = trusted }
        if pasteboardDenied != clipboard.isDenied { pasteboardDenied = clipboard.isDenied }
        onAccessChange?()
    }

    func requestAccessibility() {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        openSystemPrivacy("Accessibility")
    }

    func requestPasteAccess(beforePrompt: () -> Void) {
        refresh()
        guard !directPaste else { return }
        pastePermissionReview = .checking
        requestID = UUID()
        reviewInProgress = false
        settingsWasActive = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
        let now = ProcessInfo.processInfo.systemUptime
        checkUntil = now + 90
        nextCheck = now
        restartError = nil
        beforePrompt()
        _ = CGRequestPostEventAccess()
        openSystemPrivacy("Accessibility")
    }

    func observeActiveApplication(_ active: NSRunningApplication?) {
        guard pastePermissionReview == .checking, let active else { return }
        if active.bundleIdentifier == "com.apple.systempreferences" {
            settingsWasActive = true
        } else if settingsWasActive {
            settingsWasActive = false
            reviewPasteAccess()
        }
    }

    func reviewPasteAccess() {
        refresh()
        guard !directPaste, !reviewInProgress, let request = requestID else { return }
        reviewInProgress = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, requestID == request else { return }
            refresh()
            guard !directPaste else { return }
            AppLaunch.checkPasteAccessInFreshProcess { [weak self] canPostAfterRestart in
                guard let self, requestID == request else { return }
                reviewInProgress = false
                refresh()
                if !directPaste {
                    pastePermissionReview = canPostAfterRestart ? .restartRequired : .restartSuggested
                    if canPostAfterRestart, restartPromptRequestID != request {
                        restartPromptRequestID = request
                        onRestartRequired?()
                    }
                }
            }
        }
    }

    func restartForPastePermission() {
        refresh()
        guard !directPaste, !restartingForPaste else { return }
        restartError = nil
        restartingForPaste = true
        do {
            try AppLaunch.scheduleRelaunch()
            NSApp.terminate(nil)
        } catch {
            restartingForPaste = false
            restartError = .init(AppText.text("未能重新打开 OwnClip。请从菜单栏退出后再打开应用。"))
        }
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        openSystemPrivacy("ListenEvent")
    }

    private func openSystemPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

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
    private let readAccess: () -> (canPost: Bool, trusted: Bool)
    private let checkFreshProcess: (@escaping (Bool) -> Void) -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let requestAuthorization: () -> Void
    private let restartApplication: () throws -> Void
    private var nextCheck: TimeInterval = 0
    private var checkUntil: TimeInterval = 0
    private var requestID: UUID?
    private var restartPromptRequestID: UUID?
    private var settingsWasActive = false
    private var reviewInProgress = false

    var needsAuthorizationPrompt: Bool { !directPaste && pastePermissionReview != .restartRequired }

    init(clipboard: ClipboardMonitor,
         readAccess: @escaping () -> (canPost: Bool, trusted: Bool) = {
             (CGPreflightPostEventAccess(), AXIsProcessTrusted())
         },
         checkFreshProcess: @escaping (@escaping (Bool) -> Void) -> Void = AppLaunch.checkPasteAccessInFreshProcess,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         },
         requestAuthorization: @escaping () -> Void = {
             _ = CGRequestPostEventAccess()
             PermissionService.openSystemPrivacy("Accessibility")
         },
         restartApplication: @escaping () throws -> Void = {
             try AppLaunch.scheduleRelaunch()
             NSApp.terminate(nil)
         }) {
        self.clipboard = clipboard
        self.readAccess = readAccess
        self.checkFreshProcess = checkFreshProcess
        self.schedule = schedule
        self.requestAuthorization = requestAuthorization
        self.restartApplication = restartApplication
    }

    func refreshIfNeeded() {
        if ProcessInfo.processInfo.systemUptime >= nextCheck { refresh() }
    }

    func refresh() {
        let (canPost, trusted) = readAccess()
        let previouslyHadAccess = directPaste
        let now = ProcessInfo.processInfo.systemUptime
        nextCheck = now + (!canPost && now < checkUntil ? 1 : 5)
        if directPaste != canPost { directPaste = canPost }
        if accessibilityTrusted != trusted { accessibilityTrusted = trusted }
        if pasteboardDenied != clipboard.isDenied { pasteboardDenied = clipboard.isDenied }
        // Track missing access even when authorization is started outside OwnClip.
        if !canPost {
            if requestID == nil || previouslyHadAccess {
                requestID = UUID()
                reviewInProgress = false
                pastePermissionReview = .idle
            }
        } else if let request = requestID {
            offerRestart(for: request)
        }
        onAccessChange?()
    }

    func requestAccessibility() {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        Self.openSystemPrivacy("Accessibility")
    }

    func requestPasteAccess(beforePrompt: () -> Void) {
        refresh()
        guard !directPaste else { return }
        if pastePermissionReview != .restartRequired { pastePermissionReview = .checking }
        settingsWasActive = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.systempreferences"
        let now = ProcessInfo.processInfo.systemUptime
        checkUntil = now + 90
        nextCheck = now
        restartError = nil
        beforePrompt()
        requestAuthorization()
    }

    func observeActiveApplication(_ bundleIdentifier: String?) {
        guard let bundleIdentifier else { return }
        if bundleIdentifier == "com.apple.systempreferences" {
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
        schedule(0.8) { [weak self] in
            guard let self, requestID == request else { return }
            refresh()
            guard !directPaste else { reviewInProgress = false; return }
            checkFreshProcess { [weak self] canPostAfterRestart in
                guard let self, requestID == request else { return }
                reviewInProgress = false
                refresh()
                guard !directPaste, requestID == request else { return }
                if canPostAfterRestart {
                    offerRestart(for: request)
                } else if pastePermissionReview == .restartRequired {
                    // A fresh denial starts a new authorization cycle.
                    requestID = UUID()
                    pastePermissionReview = .idle
                } else if pastePermissionReview == .checking {
                    pastePermissionReview = .restartSuggested
                }
            }
        }
    }

    private func offerRestart(for request: UUID) {
        if pastePermissionReview != .restartRequired { pastePermissionReview = .restartRequired }
        guard restartPromptRequestID != request else { return }
        restartPromptRequestID = request
        onRestartRequired?()
    }

    func restartForPastePermission() {
        guard !restartingForPaste else { return }
        restartError = nil
        restartingForPaste = true
        do {
            try restartApplication()
        } catch {
            restartingForPaste = false
            restartError = .init(AppText.text("未能重新打开 OwnClip。请从菜单栏退出后再打开应用。"))
        }
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        Self.openSystemPrivacy("ListenEvent")
    }

    private static func openSystemPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

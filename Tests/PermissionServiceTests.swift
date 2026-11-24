import AppKit

private final class PermissionHarness {
    var canPost = false
    var trusted = false
    var freshAccess = false
    var prompts = 0
    var authorizationRequests = 0
    var restarts = 0
    var failRestart = false
    var pending: [() -> Void] = []
    private let board = NSPasteboard.withUniqueName()

    lazy var service: PermissionService = {
        let service = PermissionService(
            clipboard: ClipboardMonitor(board: board),
            readAccess: { [unowned self] in (canPost, trusted) },
            checkFreshProcess: { [unowned self] completion in completion(freshAccess) },
            schedule: { [unowned self] _, work in pending.append(work) },
            requestAuthorization: { [unowned self] in authorizationRequests += 1 },
            restartApplication: { [unowned self] in
                restarts += 1
                if failRestart { throw SmokeFailure(description: "Simulated relaunch failure") }
            })
        service.onRestartRequired = { [unowned self] in prompts += 1 }
        return service
    }()

    deinit { board.releaseGlobally() }

    func returnFromSettings() throws {
        service.observeActiveApplication("com.apple.systempreferences")
        service.observeActiveApplication("local.ownclip.OwnClip")
        try drain()
    }

    func drain() throws {
        var checks = 0
        while !pending.isEmpty {
            try check(checks < 8, "Permission review did not finish")
            pending.removeFirst()()
            checks += 1
        }
    }
}

extension SmokeTests {
    static func testPermissionService() throws {
        // No stored first-run flag may suppress the prompt after reinstalling.
        for _ in 0..<2 {
            let launch = PermissionHarness()
            launch.service.refresh()
            try check(launch.service.needsAuthorizationPrompt && launch.prompts == 0,
                      "A launch without access must offer authorization")
        }

        let existing = PermissionHarness()
        existing.canPost = true
        existing.trusted = true
        existing.service.refresh()
        try existing.returnFromSettings()
        try check(!existing.service.needsAuthorizationPrompt && existing.prompts == 0,
                  "Access present at startup must not trigger onboarding or a restart prompt")

        let immediate = PermissionHarness()
        immediate.service.refresh()
        immediate.canPost = true
        immediate.trusted = true
        immediate.service.refresh()
        immediate.service.refresh()
        try check(immediate.prompts == 1 && immediate.service.pastePermissionReview == .restartRequired,
                  "Newly granted access must prompt once even when it takes effect immediately")
        immediate.service.restartForPastePermission()
        immediate.service.restartForPastePermission()
        try check(immediate.restarts == 1,
                  "Explicit restart must run after access takes effect and reject duplicate clicks")

        let manual = PermissionHarness()
        manual.service.refresh()
        manual.freshAccess = true
        try manual.returnFromSettings()
        try manual.returnFromSettings()
        try check(manual.prompts == 1 && manual.authorizationRequests == 0 &&
                  manual.service.pastePermissionReview == .restartRequired && !manual.service.needsAuthorizationPrompt,
                  "Manual authorization outside OwnClip must prompt for restart without repeated alerts")

        // Returning before enabling the switch must not stop future reviews.
        let delayed = PermissionHarness()
        delayed.service.requestPasteAccess(beforePrompt: {})
        try delayed.returnFromSettings()
        try check(delayed.prompts == 0 && delayed.service.pastePermissionReview == .restartSuggested,
                  "Denied access must not claim authorization succeeded")
        delayed.freshAccess = true
        try delayed.returnFromSettings()
        try check(delayed.prompts == 1 && delayed.service.pastePermissionReview == .restartRequired,
                  "A later authorization was missed after an unsuccessful review")

        manual.freshAccess = false
        try manual.returnFromSettings()
        try check(manual.service.needsAuthorizationPrompt,
                  "Revoked access must allow authorization again")
        manual.freshAccess = true
        try manual.returnFromSettings()
        try check(manual.prompts == 2, "A second grant after revocation must prompt again")

        existing.canPost = false
        existing.trusted = false
        existing.service.refresh()
        try check(existing.service.needsAuthorizationPrompt, "Revoked live access must offer authorization")
        existing.canPost = true
        existing.trusted = true
        existing.service.refresh()
        try check(existing.prompts == 1, "A new grant after revoking existing access was ignored")

        let superseded = PermissionHarness()
        superseded.service.reviewPasteAccess()
        superseded.canPost = true
        superseded.service.refresh()
        superseded.canPost = false
        superseded.service.refresh()
        superseded.freshAccess = true
        try superseded.drain()
        try check(superseded.prompts == 1 && superseded.service.needsAuthorizationPrompt,
                  "An old delayed review overwrote a newer denial")
        try superseded.returnFromSettings()
        try check(superseded.prompts == 2, "A new review did not resume after replacing an old one")

        let failed = PermissionHarness()
        failed.failRestart = true
        failed.service.restartForPastePermission()
        try check(failed.restarts == 1 && !failed.service.restartingForPaste && failed.service.restartError != nil,
                  "Relaunch failure must allow retry and report an error")
        failed.failRestart = false
        failed.service.restartForPastePermission()
        try check(failed.restarts == 2 && failed.service.restartingForPaste && failed.service.restartError == nil,
                  "Retrying relaunch did not clear the previous error")
    }
}

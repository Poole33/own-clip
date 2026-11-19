import CoreGraphics
import Darwin
import Foundation

private let permissionCheckArgument = "--check-paste-access"
private let relaunchArgument = "--relaunch-after"
private let reopenedArgument = "--reopened-for-paste"

enum AppLaunch {
    static var reopenedForPaste: Bool { CommandLine.arguments.contains(reopenedArgument) }

    static func runLaunchCommandIfRequested() {
        let arguments = CommandLine.arguments
        if arguments.dropFirst() == [permissionCheckArgument] {
            exit(CGPreflightPostEventAccess() ? 0 : 1)
        }
        guard arguments.count == 3, arguments[1] == relaunchArgument,
              let pid = pid_t(arguments[2]), pid > 0 else { return }

        let deadline = ProcessInfo.processInfo.systemUptime + 6
        while kill(pid, 0) == 0 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { exit(1) }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", "-a", Bundle.main.bundleURL.path, "--args", reopenedArgument]
        do {
            try open.run()
            open.waitUntilExit()
            exit(open.terminationStatus)
        } catch {
            exit(1)
        }
    }

    static func checkPasteAccessInFreshProcess(_ completion: @escaping (Bool) -> Void) {
        guard let executable = Bundle.main.executableURL else { completion(false); return }
        let process = Process()
        process.executableURL = executable
        process.arguments = [permissionCheckArgument]
        process.terminationHandler = { completed in
            let granted = completed.terminationReason == .exit && completed.terminationStatus == 0
            DispatchQueue.main.async { completion(granted) }
        }
        do {
            try process.run()
        } catch {
            completion(false)
        }
    }

    static func scheduleRelaunch() throws {
        guard let executable = Bundle.main.executableURL else { throw CocoaError(.fileNoSuchFile) }
        let helper = Process()
        helper.executableURL = executable
        helper.arguments = [relaunchArgument, String(ProcessInfo.processInfo.processIdentifier)]
        try helper.run()
    }
}

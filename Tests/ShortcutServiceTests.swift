import Foundation

extension SmokeTests {
    static func testShortcutService() throws {
        let suite = "OwnClip-ShortcutServiceTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ShortcutService(preferences: defaults)
        var commits = 0
        service.onBindingsChange = { commits += 1 }

        service.record(.quick10)
        service.change(.quick10, binding: .systemClose)
        try check(service.error != nil && service.recording == .quick10 && commits == 0,
                  "A reserved close key changed the shortcuts")
        try check(defaults.data(forKey: "shortcuts") == nil, "An invalid shortcut was persisted")

        service.change(.quick10, binding: nil)
        try check(service.bindings[.quick10] == nil && service.error == nil && service.recording == nil && commits == 1,
                  "Disabling a shortcut did not finish the recording flow")
        guard let data = defaults.data(forKey: "shortcuts") else { throw SmokeFailure(description: "Shortcut changes were not persisted") }
        let saved = try JSONDecoder().decode(ShortcutSettings.self, from: data)
        try check(saved[.quick10] == nil, "Shortcut persistence used a different preference key or format")

        service.restore(.quick10)
        try check(service.bindings[.quick10] == ShortcutAction.quick10.standard && commits == 2,
                  "Restoring a shortcut failed")
        service.change(.quick2, binding: service.bindings[.pastePlain])
        try check(service.error != nil && commits == 2, "A conflicting shortcut was committed")
        service.record(nil)
        try check(service.error == nil && service.recording == nil, "Cancelling recording left a stale error")
    }
}

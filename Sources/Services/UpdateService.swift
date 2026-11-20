import Combine
import Foundation

/// Checks GitHub Releases and publishes status for the General settings page.
final class UpdateService: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate, failed
        case available(version: String, pageURL: URL)
    }

    @Published private(set) var state: State = .idle
    let currentVersion: String?

    private static let endpoint = URL(string: "https://api.github.com/repos/Poole33/own-clip/releases/latest")!
    private static let cacheKey = "latestOwnClipRelease"
    private static let checkInterval: TimeInterval = 6 * 60 * 60
    private static let retryInterval: TimeInterval = 5 * 60

    private let preferences: UserDefaults
    private let session: URLSession
    private var cached: CheckResult?
    private var lastAttempt: Date?
    private var isChecking = false
    private var showResult = false

    init(preferences: UserDefaults = .standard, session: URLSession = .shared,
         currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) {
        self.preferences = preferences
        self.session = session
        self.currentVersion = currentVersion
        if let data = preferences.data(forKey: Self.cacheKey),
           let result = try? PropertyListDecoder().decode(CheckResult.self, from: data) {
            cached = result
            state = availableUpdate(for: result) ?? .idle
        }
    }

    func check(manual: Bool = false) {
        if isChecking {
            if manual {
                showResult = true
                state = .checking
            }
            return
        }

        let now = Date()
        if !manual {
            if let cached, (0..<Self.checkInterval).contains(now.timeIntervalSince(cached.checkedAt)) { return }
            if let lastAttempt, (0..<Self.retryInterval).contains(now.timeIntervalSince(lastAttempt)) { return }
        }

        lastAttempt = now
        isChecking = true
        showResult = manual
        if manual { state = .checking }

        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { [weak self] data, response, error in
            let release: Release?
            if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data {
                release = try? JSONDecoder().decode(Release.self, from: data)
            } else {
                release = nil
            }
            DispatchQueue.main.async { [weak self] in self?.finish(release) }
        }.resume()
    }

    private func finish(_ release: Release?) {
        isChecking = false
        guard let release, !release.draft, !release.prerelease,
              let installed = Self.versionParts(currentVersion), let published = Self.versionParts(release.version) else {
            if showResult { state = .failed }
            return
        }

        // A newly published release may not have its installer attached yet.
        if installed.lexicographicallyPrecedes(published), (!release.hasInstaller || !Self.isReleasePage(release.pageURL)) {
            if showResult { state = .failed }
            return
        }

        let result = CheckResult(version: release.version, pageURL: release.pageURL,
                                 hasInstaller: release.hasInstaller, checkedAt: Date())
        cached = result
        if let data = try? PropertyListEncoder().encode(result) { preferences.set(data, forKey: Self.cacheKey) }
        state = availableUpdate(for: result) ?? (showResult ? .upToDate : .idle)
    }

    private func availableUpdate(for result: CheckResult) -> State? {
        guard result.hasInstaller, Self.isReleasePage(result.pageURL),
              let installed = Self.versionParts(currentVersion), let published = Self.versionParts(result.version),
              installed.lexicographicallyPrecedes(published) else { return nil }
        return .available(version: result.version, pageURL: result.pageURL)
    }

    private static func versionParts(_ version: String?) -> [Int]? {
        guard let version else { return nil }
        let segments = version.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        let numbers = segments.compactMap { segment -> Int? in
            guard segment.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(segment)
        }
        return numbers.count == segments.count ? numbers : nil
    }

    private static func isReleasePage(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "github.com" && url.user == nil && url.password == nil && url.port == nil
            && url.path.lowercased().hasPrefix("/poole33/own-clip/releases/tag/")
    }

    private struct CheckResult: Codable {
        let version: String
        let pageURL: URL
        let hasInstaller: Bool
        let checkedAt: Date
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let state: String
            let size: Int
        }

        let tagName: String
        let pageURL: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case pageURL = "html_url"
            case draft, prerelease, assets
        }

        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }

        var hasInstaller: Bool {
            #if arch(x86_64)
            let architecture = "x86_64"
            #else
            let architecture = "arm64"
            #endif
            let installerNames = ["OwnClip.dmg", "OwnClip-\(version).dmg", "OwnClip-\(version)-\(architecture).dmg"]
            return assets.contains { asset in
                asset.state == "uploaded" && asset.size > 0 && installerNames.contains(asset.name)
            }
        }
    }
}

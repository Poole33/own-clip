import AppKit
import Foundation

extension SmokeTests {
    static func testLanguages(text: ClipboardPayload, image: ClipboardPayload) throws {
        let suite = "OwnClip-LanguageTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try check(AppLanguage.load(from: defaults) == .automatic, "Language must default to automatic")
        AppLanguage.english.save(to: defaults)
        try check(AppLanguage.load(from: defaults) == .english, "Language choice did not persist")
        defaults.set("unsupported", forKey: AppLanguage.preferenceKey)
        try check(AppLanguage.load(from: defaults) == .automatic, "Unknown preferences need an automatic fallback")
        let cases: [([String], AppLanguage)] = [
            (["zh-Hans-CN", "en-US"], .simplifiedChinese), (["zh_CN"], .simplifiedChinese),
            (["zh-SG"], .simplifiedChinese), (["en-GB", "zh-Hans"], .english),
            (["fr-FR", "zh-Hans"], .simplifiedChinese), (["zh-Hant-TW"], .english),
            (["zh-HK"], .english), (["ja-JP"], .english), ([], .english)
        ]
        for (languages, expected) in cases {
            try check(AppLanguage.automatic.resolved(preferredLanguages: languages) == expected,
                      "Wrong language resolution for \(languages)")
        }
        try check(AppLanguage.english.resolved(preferredLanguages: ["zh-Hans"]) == .english,
                  "Explicit English must override the system")
        try check(AppLanguage.simplifiedChinese.resolved(preferredLanguages: ["en"]) == .simplifiedChinese,
                  "Explicit Chinese must override the system")
        let original = AppText.language
        defer { AppText.language = original }
        let imageSummary = image.summary(source: "来源")
        let encoded = try PropertyListEncoder().encode(imageSummary)
        let notice = AppMessage(AppText.format("源文件已不可用：%@", "报告.txt"))
        let error = HistoryError(message: AppText.format("无法更新本地历史（%@）。", "SQLITE_BUSY"))
        AppText.language = .english
        try check(AppText.History.name == "Clipboard History" && imageSummary.displayTitle == "Image",
                  "Existing labels did not switch to English")
        try check(ShortcutAction.quick2.title == "Paste item 2" && ShortcutScope.global.title == "Global",
                  "Shortcut titles did not switch to English")
        try check(notice.text == "Source file is unavailable: 报告.txt" &&
                  AppText.errorDescription(error) == "Could not update local history (SQLITE_BUSY).",
                  "Stored notices must render in the current language")
        let userText = ClipboardPayload(items: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue,
                                                                        data: Data("图片".utf8))]])
        try check(userText.summary(source: "测试").displayTitle == "图片", "Translated the user's clipboard content")
        try check(text.plainText == "Rich text" && imageSummary.source == "来源" &&
                  PropertyListEncoder().encode(imageSummary) == encoded, "Localization changed stored content")
        AppText.language = .simplifiedChinese
        try check(AppText.History.name == "剪贴板历史" && imageSummary.displayTitle == "图片" &&
                  notice.text == "源文件已不可用：报告.txt", "Could not switch existing labels back to Chinese")
    }
}

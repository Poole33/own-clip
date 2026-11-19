import AppKit
import Foundation

extension SmokeTests {
    static func testHistory(at directory: URL, text: ClipboardPayload, image: ClipboardPayload) throws {
        let now = Date()
        let hour = 3_600.0
        let textSummary = text.summary(source: "旧来源", date: now.addingTimeInterval(-30 * hour))
        let imageSummary = image.summary(source: "图片", date: now.addingTimeInterval(-26 * hour))
        let latest = text.summary(source: "新来源", date: now)
        do {
            let store = try HistoryStore(directory: directory)
            try store.save(text, summary: textSummary)
            try store.save(image, summary: imageSummary)
            try store.save(text, summary: latest)
            try check(store.history().map(\.id) == [textSummary.id, imageSummary.id], "Deduplication or order failed")
        }
        let recovered = try HistoryStore(directory: directory)
        try check(recovered.history().first?.source == "新来源", "History failed to survive reopen")
        try check(recovered.read(textSummary.id).plainText == "Rich text", "Stored payload did not survive reopen")
        let cutoff = now.addingTimeInterval(-24 * hour)
        try check(recovered.purge(before: cutoff) == [imageSummary.id], "Purge removed the wrong history rows")
        try check(!FileManager.default.fileExists(atPath: recovered.payloadFile(for: imageSummary.id).path), "Expired payload is still present")
        try recovered.clear()
        try check(recovered.history().isEmpty, "Clear did not remove history")
        try check(!FileManager.default.fileExists(atPath: recovered.payloadFile(for: textSummary.id).path), "Clear left clipboard content")
    }
}

import AppKit
import Foundation
import UniformTypeIdentifiers

struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
}

func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw SmokeFailure(description: message) }
}

@main struct SmokeTests {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run() throws {
        let board = NSPasteboard.withUniqueName()
        let output = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally(); output.releaseGlobally() }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: work) }

        let rich = NSPasteboardItem()
        let rtf = Data("{\\rtf1\\ansi \\b Rich text\\b0}".utf8)
        rich.setData(rtf, forType: .rtf)
        board.clearContents()
        try check(board.writeObjects([rich]), "Could not create a rich-text fixture")
        guard let text = ClipboardPayload.capture(from: board) else { throw SmokeFailure(description: "Missing rich text") }
        try check(text.summary(source: "Test").kind == .richText, "Incorrect rich-text classification")
        try check(text.plainText == "Rich text", "RTF did not convert to text")
        try check(text.write(to: output) && output.data(forType: .rtf) == rtf, "Normal paste changed rich text")
        try check(text.write(to: output, plainText: true) && output.pasteboardItems?.first?.types == [.string],
                  "Plain paste did not write a text-only item")
        try check(output.string(forType: .string) == "Rich text", "Plain paste changed the text")

        board.clearContents()
        let hidden = NSPasteboardItem()
        hidden.setString("ignored", forType: .string)
        hidden.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        try check(board.writeObjects([hidden]) && ClipboardPayload.capture(from: board) == nil, "Captured concealed text")

        board.clearContents()
        let hex = NSPasteboardItem()
        hex.setString("#a1b2c3", forType: .string)
        try check(board.writeObjects([hex]), "Could not create a color fixture")
        let color = try requirePayload(board)
        try check(color.color?.hex == "#A1B2C3" && color.plainText == "#a1b2c3", "Hex color changed")
        board.declareTypes([.color], owner: nil)
        NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1).write(to: board)
        let nativeColor = try requirePayload(board, fixture: "native color")
        try check(nativeColor.color?.hex == "#336699" && nativeColor.plainText == "#336699", "Native color did not round-trip")
        try check(nativeColor.write(to: output) && NSColor(from: output) != nil, "Restored color is unreadable")

        board.clearContents()
        let png = NSPasteboardItem()
        let pngBytes = try checkPNG()
        png.setData(pngBytes, forType: .png)
        try check(board.writeObjects([png]), "Could not create an image fixture")
        let image = try requirePayload(board, fixture: "PNG")
        try check(image.summary(source: "Test").kind == .image && image.imageData == pngBytes, "Image payload changed")
        try check(image.write(to: output) && output.data(forType: .png) == pngBytes, "Restored image bytes changed")

        board.clearContents()
        let firstFile = work.appendingPathComponent("样例 A.txt")
        let videoFile = work.appendingPathComponent("Video.mov")
        try Data("first".utf8).write(to: firstFile)
        try Data("movie fixture".utf8).write(to: videoFile)
        try check(board.writeObjects([firstFile as NSURL, videoFile as NSURL]), "Could not create multi-file fixture")
        let files = try requirePayload(board, fixture: "file group")
        try check(files.files.map(\.path) == [firstFile.path, videoFile.path], "Multi-file order changed")
        try check(files.write(to: output) && output.pasteboardItems?.count == 2, "Failed to restore file references")
        try FileManager.default.removeItem(at: firstFile)
        try check(files.missingFile?.path == firstFile.path, "Missing file was not detected")
        board.clearContents()
        try check(board.writeObjects([videoFile as NSURL]), "Could not create single-video fixture")
        let reference = try requirePayload(board, fixture: "video reference")
        try check(reference.summary(source: "Finder").kind == .video && reference.video == nil, "Video file contents were copied")
        board.clearContents()
        let video = NSPasteboardItem()
        let movieBytes = Data("direct video fixture".utf8)
        let movieType = NSPasteboard.PasteboardType(UTType.quickTimeMovie.identifier)
        video.setData(movieBytes, forType: movieType)
        try check(board.writeObjects([video]), "Could not create direct-video fixture")
        let directVideo = try requirePayload(board, fixture: "direct video")
        try check(directVideo.video?.data == movieBytes && directVideo.write(to: output)
                  && output.data(forType: movieType) == movieBytes, "Direct video did not round-trip")

        try testHistory(at: work.appendingPathComponent("History"), text: text, image: image)
        try testPasteStack(text.summary(source: "Test"))
        try testLanguages(text: text, image: image)
        try testShortcuts()
        try testMenuShortcuts()
        try testWindowPlacement()
        try testHistoryWheel()
        try testClipboardMonitor()
        try testPasteService()
        try testShortcutService()
        try testPermissionService()
        print("PASS: clipboard formats, history retention, paste stack, shortcuts, menu shortcuts, window placement, history wheel routing, localization, clipboard monitoring, paste focus, shortcut service and permission lifecycle")
    }

}

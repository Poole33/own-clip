import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

final class PreviewCache {
    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 80
        cache.totalCostLimit = 18 * 1024 * 1024
    }

    func remove(_ ids: Set<String>) {
        for id in ids { cache.removeObject(forKey: id as NSString) }
    }

    func image(for clip: ClipSummary, payloadFile: URL?) async -> NSImage? {
        guard clip.kind == .image || clip.kind == .video else { return nil }
        let key = clip.id as NSString
        if let image = cache.object(forKey: key) { return image }
        let task = Task.detached(priority: .utility) {
            await Self.render(clip: clip, payloadFile: payloadFile)
        }
        let cgImage = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard !Task.isCancelled, let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    private static func render(clip: ClipSummary, payloadFile: URL?) async -> CGImage? {
        if Task.isCancelled { return nil }
        if let url = clip.files.first {
            if clip.kind == .video { return await videoFrame(url) }
            return downsample(CGImageSourceCreateWithURL(url as CFURL, nil))
        }
        guard let payloadFile, let bytes = try? Data(contentsOf: payloadFile, options: .mappedIfSafe),
              let payload = try? PropertyListDecoder().decode(ClipboardPayload.self, from: bytes) else { return nil }
        if clip.kind == .image, let image = payload.imageData {
            return downsample(CGImageSourceCreateWithData(image as CFData, nil))
        }
        guard let video = payload.video, !Task.isCancelled else { return nil }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let name = "Preview." + (UTType(video.type)?.preferredFilenameExtension ?? "mov")
        let file = work.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: work) }
            try video.data.write(to: file)
            return await videoFrame(file)
        } catch { return nil }
    }

    private static func downsample(_ source: CGImageSource?) -> CGImage? {
        guard let source else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceThumbnailMaxPixelSize: 360]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func videoFrame(_ file: URL) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.maximumSize = CGSize(width: 360, height: 240)
        generator.appliesPreferredTrackTransform = true
        return try? await generator.image(at: .zero).image
    }
}

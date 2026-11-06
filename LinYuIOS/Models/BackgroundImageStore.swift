import Foundation
import UIKit

/// BackgroundManager's file/decoded-image owner. All ImageIO and JPEG work runs off main.
actor BackgroundImageStore {
    struct PreparedImage {
        let fileName: String
        let themeColor: Int?
        let durationMilliseconds: UInt64
    }
    struct Metrics {
        var decodedImages = 0
        var cacheHits = 0
        var completedImports = 0
        var lastImportMilliseconds: UInt64 = 0
    }
    enum Failure: LocalizedError {
        case unreadable, storage, photoUnavailable
        var errorDescription: String? {
            switch self {
            case .photoUnavailable: return "照片读取失败。若来自 iCloud，请确认照片已下载及网络可用后重试。"
            case .unreadable: return "无法解码所选图片，请尝试 JPEG、PNG 或 HEIC 照片。"
            case .storage: return "背景图片保存失败，请检查可用存储空间及应用容器访问权限。"
            }
        }
    }

    let directory: URL
    private let cache = NSCache<NSString, UIImage>()
    private var metrics = Metrics()

    init(directory: URL) {
        self.directory = directory
        cache.countLimit = 2
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func prepare(source: URL, scope: BackgroundScope) throws -> PreparedImage {
        let start = DispatchTime.now().uptimeNanoseconds
        try Task.checkCancellation()
        let encoded: Data = try autoreleasepool {
            guard let image = OriginalBackgroundPalette.importedImage(at: source),
                  let jpeg = image.jpegData(compressionQuality: 0.95) else { throw Failure.unreadable }
            metrics.decodedImages += 1
            return jpeg
        }
        try Task.checkCancellation()
        let name = "\(scope.rawValue)-\(UUID().uuidString).jpg"
        let file = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoded.write(to: file, options: .atomic)
        } catch { throw Failure.storage }
        do {
            try Task.checkCancellation()
            // Cache the saved JPEG, so the displayed pixels and restored pixels agree.
            guard let image = OriginalBackgroundPalette.importedImage(encoded) else { throw Failure.unreadable }
            metrics.decodedImages += 1
            let color = OriginalBackgroundPalette.rgb(image: image)
            try Task.checkCancellation()
            cache.setObject(image, forKey: file.path as NSString, cost: Self.cost(image))
            let elapsed = (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            metrics.completedImports += 1
            metrics.lastImportMilliseconds = elapsed
            return PreparedImage(fileName: name, themeColor: color, durationMilliseconds: elapsed)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    func image(at url: URL) -> UIImage? {
        if let image = cache.object(forKey: url.path as NSString) {
            metrics.cacheHits += 1
            return image
        }
        return autoreleasepool {
            guard let image = OriginalBackgroundPalette.importedImage(at: url) else { return nil }
            metrics.decodedImages += 1
            cache.setObject(image, forKey: url.path as NSString, cost: Self.cost(image))
            return image
        }
    }

    func removeOwnedImage(at url: URL?) {
        guard let url else { return }
        cache.removeObject(forKey: url.path as NSString)
        // A migrated external path may be read, but only files in our private folder are deleted.
        guard url.standardizedFileURL.deletingLastPathComponent() == directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func snapshot() -> Metrics { metrics }
    private static func cost(_ image: UIImage) -> Int {
        (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
    }
}

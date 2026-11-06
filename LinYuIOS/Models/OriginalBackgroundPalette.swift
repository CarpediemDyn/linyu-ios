import UIKit
import ImageIO

/// BackgroundManager.extractThemeColor: 48×48, 32-step RGB histogram, original HSV bounds.
enum OriginalBackgroundPalette {
    static func importedImage(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2560,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
    static func importedImage(at url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2560,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    static func rgb(image: UIImage) -> Int? {
        guard let source = image.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: 48 * 48 * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 48, height: 48, bitsPerComponent: 8,
                bytesPerRow: 48 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: 48, height: 48))
            return true
        }
        guard rendered else { return nil }
        var counts: [Int: Int] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset] / 32) * 32
            let green = Int(pixels[offset + 1] / 32) * 32
            let blue = Int(pixels[offset + 2] / 32) * 32
            counts[(red << 16) | (green << 8) | blue, default: 0] += 1
        }
        for entry in counts.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }) {
            let color = UIColor(red: CGFloat((entry.key >> 16) & 255) / 255,
                                green: CGFloat((entry.key >> 8) & 255) / 255,
                                blue: CGFloat(entry.key & 255) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            guard color.getHue(&h, saturation: &s, brightness: &v, alpha: &a), s > 0.15, v > 0.20, v < 0.95 else { continue }
            let adjusted = UIColor(hue: h, saturation: min(0.75, max(0.35, s)), brightness: min(0.85, max(0.45, v)), alpha: 1)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            guard adjusted.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
            return (Int((r * 255).rounded()) << 16) | (Int((g * 255).rounded()) << 8) | Int((b * 255).rounded())
        }
        return nil
    }
}

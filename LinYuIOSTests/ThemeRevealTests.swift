import SwiftUI
import UIKit
import XCTest
@testable import LinYuIOS

@MainActor final class ThemeRevealTests: XCTestCase {
    func testOriginalBezierTimingAndEndpoints() {
        XCTAssertEqual(LinYuRevealTiming.easedProgress(elapsed: -1), 0)
        XCTAssertEqual(LinYuRevealTiming.easedProgress(elapsed: 0), 0)
        // Independently evaluated cubic-bezier(0.4, 0, 0.2, 1) at half duration.
        XCTAssertEqual(LinYuRevealTiming.easedProgress(elapsed: 0.325), 0.775561, accuracy: 0.00001)
        XCTAssertEqual(LinYuRevealTiming.easedProgress(elapsed: 0.65), 1)
        XCTAssertEqual(LinYuRevealTiming.easedProgress(elapsed: 2), 1)
    }

    func testPreviewWaitsForFirstDrawAndPaletteCommitAndCompletesOnce() {
        let view = LinYuRevealMaskView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        var previews = 0
        var completions = 0
        view.onPreview = { previews += 1 }
        view.onCompletion = { completions += 1 }
        view.advance(at: 100)
        XCTAssertEqual(previews, 0)
        // Draw the real overlay's initial frame before starting its clock.
        _ = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in view.draw(view.bounds) }
        view.advance(at: 101)
        view.advance(at: 101.1)
        XCTAssertEqual(previews, 0)
        view.advance(at: 101.65)
        XCTAssertEqual(previews, 1)
        XCTAssertEqual(view.progress, 0.2)
        XCTAssertEqual(completions, 0)
        view.advance(at: 102)
        XCTAssertEqual(previews, 1)
        XCTAssertEqual(view.progress, 0.2)
        view.previewApplied = true
        view.advance(at: 103)
        view.advance(at: 104)
        XCTAssertEqual(view.progress, 1)
        XCTAssertEqual(completions, 1)
    }

    func testCircleReachesAllWindowCornersForPortraitLandscapeAndNarrowWindows() {
        let sizes = [CGSize(width: 320, height: 568), CGSize(width: 440, height: 956),
                     CGSize(width: 344, height: 640), CGSize(width: 820, height: 1180),
                     CGSize(width: 1180, height: 820)]
        for size in sizes {
            for origin in [CGPoint.zero, CGPoint(x: size.width - 30, y: 90), CGPoint(x: 20, y: size.height - 30)] {
                let frame = LinYuRevealFrame(progress: 1, origin: origin)
                let center = frame.center(in: size)
                let radius = frame.circle(in: size).width / 2
                for corner in [CGPoint.zero, CGPoint(x: size.width, y: 0),
                               CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)] {
                    XCTAssertGreaterThan(radius, hypot(corner.x - center.x, corner.y - center.y))
                }
            }
        }
    }

    func testMaskStartThresholdMiddleAndEndCoverFullBoundsIncludingBottom() throws {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 1180, height: 820)] {
            for (name, color) in [("dark", UIColor(red: 14/255, green: 19/255, blue: 29/255, alpha: 1)),
                                  ("light", UIColor(red: 241/255, green: 245/255, blue: 249/255, alpha: 1))] {
                let center = CGPoint(x: size.width - 36, y: 48)
                for progress in [0.0, 0.2, 0.6, 1.0] {
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    format.opaque = false
                    let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                        LinYuRevealMaskView.draw(LinYuRevealFrame(progress: progress, origin: center),
                                               color: color, in: CGRect(origin: .zero, size: size))
                    }
                    let bottom = try rgba(image, at: CGPoint(x: 2, y: size.height - 2))
                    XCTAssertEqual(bottom[3], progress == 0 || progress == 1 ? 0 : 255)
                    if progress == 0.2 {
                        let expected = color.cgColor.components!
                        for channel in 0..<3 {
                            XCTAssertEqual(Double(bottom[channel]), Double(expected[channel]) * 255, accuracy: 1)
                        }
                    }
                    if progress > 0.2 {
                        XCTAssertEqual(try rgba(image, at: center)[3], 0)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "theme-mask-\(Int(size.width))x\(Int(size.height))-\(name)-\(progress)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    private func rgba(_ image: UIImage, at point: CGPoint) throws -> [UInt8] {
        let pixel = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: point.x, y: point.y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes
    }
}

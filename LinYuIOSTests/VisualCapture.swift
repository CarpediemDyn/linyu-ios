import SwiftUI
import UIKit
import XCTest

/// Mounts production views that contain UIScrollView or other UIKit-backed content.
@MainActor func captureHostedVisual<Content: View>(_ root: Content, size: CGSize, settle: UInt64 = 200_000_000, scrollToBottom: Bool = false) async throws -> UIImage {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first(where: \.isKeyWindow)
    let controller = UIHostingController(rootView: root)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: size)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; previous?.makeKey() }
    try await Task.sleep(nanoseconds: settle)
    let view = controller.view!
    view.layoutIfNeeded()
    if scrollToBottom {
        func scrollViews(in view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        func distance(_ scroll: UIScrollView) -> CGFloat {
            scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
        }
        let scroll = try XCTUnwrap(scrollViews(in: view).max { distance($0) < distance($1) })
        XCTAssertGreaterThan(distance(scroll), 0, "Short windows must offer vertical scrolling")
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: max(0, distance(scroll))), animated: false)
        await Task.yield()
        view.layoutIfNeeded()
    }
    let format = UIGraphicsImageRendererFormat(); format.scale = 2
    return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
        XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true))
    }
}

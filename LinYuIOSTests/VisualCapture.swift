import SwiftUI
import UIKit
import XCTest

/// Mounts production views that contain UIScrollView or other UIKit-backed content.
@MainActor func captureHostedVisual<Content: View>(_ root: Content, size: CGSize) async throws -> UIImage {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first(where: \.isKeyWindow)
    let controller = UIHostingController(rootView: root)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: size)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true; previous?.makeKey() }
    try await Task.sleep(nanoseconds: 200_000_000)
    let view = controller.view!
    view.layoutIfNeeded()
    let format = UIGraphicsImageRendererFormat(); format.scale = 2
    return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
        XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true))
    }
}

import SwiftUI
import UIKit
import XCTest
@testable import LinYuIOS

@MainActor final class ProfileVisualTests: XCTestCase {
    func testProfileCardsAndBackgroundAtTwoWidths() async throws {
        let suite = "LinYuVisualTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = OriginalPreferences(defaults: defaults)
        let profile = CampusProfile(name: "演示同学", studentNumber: "00000000", schoolName: "校园示例")
        for width: CGFloat in [375, 430] {
            for dark in [false, true] {
                let suffix = "\(dark ? "dark" : "light")-\(Int(width))"
                try capture("profile-account-room-" + suffix, width: width, dark: dark) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("我的账号").font(LinYuType.font(22, weight: .bold))
                        ProfileAccountCard(profile: profile, phone: "10000000000", onPhone: {}, onPassword: {})
                        ProfileBoundRoomCard(room: "龙川北苑-3号楼南-3层-320", onPick: {}, onClear: {})
                        Spacer()
                    }.padding(20)
                }
                try await captureHosted("background-default-" + suffix, width: width, dark: dark) {
                    ProfileBackgroundPage(preferences: preferences, onBack: {}).defaultAppStorage(defaults)
                }
            }
        }
    }

    private func captureHosted<Content: View>(_ name: String, width: CGFloat, dark: Bool,
                                              @ViewBuilder content: () -> Content) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let size = CGSize(width: width, height: 667)
        let root = content().frame(width: size.width, height: size.height)
            .environment(\.linYuColors, LinYuPalette(isDark: dark))
            .environment(\.colorScheme, dark ? .dark : .light)
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
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true), name)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func capture<Content: View>(_ name: String, width: CGFloat, dark: Bool,
                                        @ViewBuilder content: () -> Content) throws {
        let renderer = ImageRenderer(content: content().frame(width: width, height: 667)
            .background(LinYuPalette(isDark: dark).background)
            .environment(\.linYuColors, LinYuPalette(isDark: dark))
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, "Missing visual attachment: " + name)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

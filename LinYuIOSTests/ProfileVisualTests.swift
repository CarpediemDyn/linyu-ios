import SwiftUI
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
                try capture("background-default-" + suffix, width: width, dark: dark) {
                    ProfileBackgroundPage(preferences: preferences, onBack: {}).defaultAppStorage(defaults)
                }
            }
        }
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

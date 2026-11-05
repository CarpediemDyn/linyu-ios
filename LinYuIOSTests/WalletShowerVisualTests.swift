import SwiftUI
import XCTest
@testable import LinYuIOS

@MainActor final class WalletShowerVisualTests: XCTestCase {
    func testWalletAndTrendAtTwoWidths() async throws {
        let today = try XCTUnwrap(OriginalFormatting.billDate("2026-10-15 12:00:00"))
        let bills = [
            CampusBill(orderId: "fixture-1", consumeDate: "2026-10-15 09:41:12", consumeMoney: "2.18",
                       description: "热水器:热水器-龙川北苑-3号楼南-3层-320房"),
            CampusBill(orderId: "fixture-2", consumeDate: "2026-10-14 21:12:03", consumeMoney: "0.025",
                       description: "直饮:直饮冷水-龙川北苑-3号楼北-3层"),
            CampusBill(orderId: "fixture-3", consumeDate: "2026-10-11 21:44:01", consumeMoney: "1.36",
                       description: "热水器:热水器-龙川北苑-3号楼南-3层-320房"),
        ]
        for width in [375.0, 430.0] {
            for dark in [false, true] {
                for kind in ["LINE", "BAR"] {
                    try capture("wallet-\(kind.lowercased())", width: width, dark: dark) {
                        walletFixture(bills: bills, today: today, kind: kind)
                    }
                }
            }
        }
    }

    func testShowerRunningAndStoppingAtTwoWidths() async throws {
        for width in [375.0, 430.0] {
            for dark in [false, true] {
                for stopping in [false, true] {
                    try capture(stopping ? "shower-stopping" : "shower-running", width: width, dark: dark) {
                        OriginalShowerContent(emoji: "🚿", status: "正在沐浴中", location: "龙川北苑 3号楼南 320房",
                                              preDeduct: 5, elapsed: 214, countdown: 46, hasCustomBackground: false,
                                              stopping: stopping, stopDisabled: stopping, continuingSettlement: false,
                                              onBack: {}, onStop: {})
                    }
                }
            }
        }
    }

    private func walletFixture(bills: [CampusBill], today: Date, kind: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OriginalWalletBalanceCard(title: "一卡通余额", balance: 48.025,
                                      source: "来自校园卡账户的实时余额", onEdit: nil)
                .padding(.bottom, 24)
            OriginalSpendingTrendCard(bills: bills, loading: false, today: today, collapsed: .constant(false),
                                      range: .constant("LAST_7_DAYS"), chartType: .constant(kind))
                .padding(.bottom, 24)
            OriginalWalletBillsHeading()
            VStack(spacing: 8) {
                OriginalWalletBillRow(bill: bills[0], deduction: .init(processing: false, enabled: true, action: {}),
                                      onSelect: {})
                OriginalWalletBillRow(bill: bills[1], deduction: nil, onSelect: {})
            }.padding(.top, 12)
        }.padding(20).frame(maxHeight: .infinity, alignment: .top)
    }

    private func capture<Content: View>(_ state: String, width: CGFloat, dark: Bool,
                                        @ViewBuilder content: () -> Content) throws {
        let name = "\(state)-\(dark ? "dark" : "light")-\(Int(width))"
        let palette = LinYuPalette(isDark: dark)
        let size = CGSize(width: width, height: width == 375 ? 812 : 932)
        let canvas = content().frame(width: size.width, height: size.height)
            .background(palette.background)
            .environment(\.linYuColors, palette)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, "Missing visual attachment: " + name)
        XCTAssertEqual(image.size, size, name)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

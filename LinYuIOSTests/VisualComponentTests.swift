import SwiftUI
import XCTest
@testable import LinYuIOS

/// Actual simulator renderings of production components with transient display values.
@MainActor final class VisualComponentTests: XCTestCase {
    func testHomeCardsAndDialogsAtTwoWidths() async throws {
        let device = CampusDevice(deviceId: "fixture", deviceName: "热水器-龙川北苑-3号楼南-3层-320房",
                                  snCode: "001122334455", macAddress: "00:11:22:33:44:55", withholdMoney: 5)
        for width in [375.0, 430.0] {
            for dark in [false, true] {
                let name = "\(dark ? "dark" : "light")-\(Int(width))"
                try capture("home-components-" + name, width: width, dark: dark) {
                    VStack(alignment: .leading, spacing: 16) {
                        LinYuSectionTitle(title: "上次使用设备")
                        OriginalSavedDeviceRow(name: device.displayName, emoji: device.emoji,
                                               address: device.macAddress, active: false, onUse: {})
                        LinYuSectionTitle(title: "附近设备")
                        OriginalNearbyDeviceRow(name: device.displayName, emoji: device.emoji,
                                                 rssi: -76, address: device.macAddress)
                        OriginalNearbyDeviceRow(name: "龙川北苑 3号楼南 318房", emoji: "🪥",
                                                 rssi: -96, address: "00:11:22:33:44:66")
                        Spacer()
                        LinYuPillNavigation(selection: .constant(0)).frame(maxWidth: .infinity)
                    }.padding(20)
                }
                try capture("device-details-" + name, width: width, dark: dark) {
                    OriginalDeviceDetailContent(device: device, onConfirm: {}, onDismiss: {})
                }
                try capture("deduct-unknown-" + name, width: width, dark: dark) {
                    OriginalDeductConfirmDialog(amount: nil, detail: "共 1 笔", onConfirm: {}, onDismiss: {})
                }
            }
        }
    }

    private func capture<Content: View>(_ name: String, width: CGFloat, dark: Bool,
                                        @ViewBuilder content: () -> Content) throws {
        let canvas = content().frame(width: width, height: 667)
            .background(LinYuPalette(isDark: dark).background)
            .environment(\.linYuColors, LinYuPalette(isDark: dark))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, "Missing visual attachment: " + name)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

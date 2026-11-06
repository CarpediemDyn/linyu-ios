import SwiftUI
import XCTest
@testable import LinYuIOS

@MainActor final class ResponsiveVisualTests: XCTestCase {
    private let device = CampusDevice(deviceId: "42", deviceName: "热水器-龙川北苑-国际学生公寓-九号楼南区-五层-502房", snCode: "DDEEFF001122")
    private let bill = CampusBill(orderId: "fixture", consumeDate: "2026-10-15 09:41:12",
                                  consumeMoney: "12.35", description: "热水器:龙川北苑国际学生公寓九号楼五层502房")

    func testLoginAcrossWindowSizes() async throws {
        let auth = AuthManager(storage: .init(load: { nil }, save: { _ in false }, delete: {}))
        let sizes: [CGSize] = [
            .init(width: 320, height: 568), .init(width: 344, height: 720),
            .init(width: 390, height: 844), .init(width: 420, height: 912),
            .init(width: 440, height: 956), .init(width: 466, height: 678),
            .init(width: 626, height: 890), .init(width: 744, height: 1133),
            .init(width: 820, height: 1180), .init(width: 1032, height: 1376),
            .init(width: 844, height: 390), .init(width: 1180, height: 820),
        ]
        for size in sizes {
            try await capture("login", size: size, settle: 450_000_000) { AccountView(auth: auth) }
        }
    }

    func testPagesAndRecoveryInNarrowAndWideWindows() async throws {
        let auth = AuthManager(storage: .init(load: { nil }, save: { _ in false }, delete: {}))
        let model = OriginalAppModel(authentication: auth, cloudController: CloudShowerController(mqttEnabled: false))
        model.refreshing = true
        model.account = CampusAccountCache(ownerScope: "", lastDevice: device)
        model.balance = CampusBalanceSnapshot(ownerScope: "", campusBalance: 48.25)
        model.bills = [bill]
        for size in [CGSize(width: 344, height: 640), CGSize(width: 1024, height: 768)] {
            try await capture("home", size: size) {
                OriginalHomeView(model: model, onScan: {}, onStart: { _ in })
                    .safeAreaInset(edge: .bottom, spacing: 0) { LinYuNavigationInset(selection: .constant(0)) }
            }
            try await capture("wallet", size: size) { OriginalWalletView(model: model) }
            try await capture("profile", size: size) { OriginalProfileView(model: model) }
        }

        try await capture("devices-recovery-large-text", size: CGSize(width: 320, height: 568)) {
            ScrollView {
                VStack(spacing: 12) {
                    OriginalNearbyDeviceRow(name: device.deviceName, emoji: "🚿", rssi: -61, address: "DD:EE:FF:00:11:22")
                    OriginalSavedDeviceRow(name: device.deviceName, emoji: "🚿", address: "", active: false,
                                           status: "已关阀，服务器处理结果待核实", actionTitle: "继续结算", onUse: {})
                    OriginalSavedDeviceRow(name: device.deviceName, emoji: "🚿", address: "", active: false,
                                           status: "阀门状态待核实", actionTitle: "核实状态", onUse: {})
                }.padding(12)
            }.environment(\.dynamicTypeSize, .accessibility3)
        }
    }

    func testShowerScannerAndDialogsAtShortHeight() async throws {
        let landscape = CGSize(width: 812, height: 320)
        try await capture("shower-actions", size: landscape, scrollToBottom: true) {
            OriginalShowerContent(emoji: "🚿", status: "正在沐浴中", location: device.deviceName,
                                  preDeduct: 5, elapsed: 214, countdown: 46, hasCustomBackground: false,
                                  stopping: false, stopDisabled: false, continuingSettlement: false,
                                  onBack: {}, onStop: {})
        }
        try await capture("shower-settlement-large-text", size: CGSize(width: 320, height: 568)) {
            OriginalShowerContent(emoji: "🚿", status: "已关阀，服务器处理结果待核实", location: device.deviceName,
                                  preDeduct: 5, elapsed: 214, countdown: 0, hasCustomBackground: false,
                                  stopping: false, stopDisabled: false, continuingSettlement: true,
                                  onBack: {}, onStop: {})
                .environment(\.dynamicTypeSize, .accessibility3)
        }
        try await capture("scanner", size: landscape) { OriginalScannerView { _ in } }
        try await capture("device-dialog-actions", size: CGSize(width: 320, height: 310), scrollToBottom: true) {
            OriginalDeviceDetailContent(device: device, recovery: .unconfirmed, onConfirm: {}, onDismiss: {})
        }
        try await capture("long-error-actions", size: CGSize(width: 344, height: 290), scrollToBottom: true) {
            Color.clear.linYuModal(isPresented: .constant(true)) {
                LinYuDialogCard {
                    VStack(spacing: 16) {
                        Text("阀门状态待核实").font(.title2)
                        Text(String(repeating: "水表状态待核实，请靠近原设备后重试。", count: 12)).font(.body)
                        Button("返回") {}.buttonStyle(LinYuButtonStyle())
                    }
                }
            }.environment(\.dynamicTypeSize, .accessibility2)
        }
    }

    private func capture<Content: View>(_ name: String, size: CGSize, settle: UInt64 = 200_000_000,
                                        scrollToBottom: Bool = false,
                                        @ViewBuilder content: () -> Content) async throws {
        let canvas = content()
            .frame(width: size.width, height: size.height)
            .background(LinYuPalette(isDark: false).background)
            .environment(\.linYuWindow, LinYuWindowLayout(size: size))
            .environment(\.linYuColors, LinYuPalette(isDark: false))
            .ignoresSafeArea()
        let image = try await captureHostedVisual(canvas, size: size, settle: settle, scrollToBottom: scrollToBottom)
        XCTAssertEqual(image.size, size)
        let attachment = XCTAttachment(image: image)
        attachment.name = "responsive-\(name)-\(Int(size.width))x\(Int(size.height))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

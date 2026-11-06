import Foundation
import XCTest
import UserNotifications
import UIKit
@testable import LinYuIOS

@MainActor final class OriginalIntegrationTests: XCTestCase {
    func testContainerModeSnapshotRoundTripKeepsAccountAndActionNonce() async throws {
#if LINYU_LIVECONTAINER
        XCTAssertFalse(LinYuWidgetStorage.usesAppGroup)
        let key = "widget-snapshot"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        var snapshot = LinYuWidgetSnapshot(); snapshot.ownerScope = "fixture-owner"; snapshot.controlNonce = "fixture-nonce"
        LinYuWidgetStorage.save(snapshot)
        let restored = LinYuWidgetStorage.load()
        XCTAssertEqual(restored.ownerScope, "fixture-owner")
        XCTAssertEqual(restored.controlNonce, "fixture-nonce")
        let link = LinYuWidgetStorage.url(action: "stop", id: "order")
        XCTAssertEqual(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "nonce" }?.value, "fixture-nonce")
#else
        XCTAssertTrue(LinYuWidgetStorage.usesAppGroup)
#endif
    }

    func testBackgroundResetRestoresOnlySelectedScopeToOriginalDefaults() async {
        let name = "linyu-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = OriginalPreferences(defaults: defaults)
        prefs.opacity = 0.3; prefs.blur = 12; prefs.brightness = 0.5
        prefs.backgroundScope = "shower"
        prefs.opacity = 0.7; prefs.blur = 8; prefs.brightness = 1.3
        prefs.resetBackground(scope: "home")
        XCTAssertEqual(prefs.backgroundOpacity(shower: false), 1)
        XCTAssertEqual(prefs.backgroundBlur(shower: false), 0)
        XCTAssertEqual(prefs.backgroundBrightness(shower: false), 1)
        XCTAssertEqual(prefs.backgroundOpacity(shower: true), 0.7)
        XCTAssertEqual(prefs.backgroundBrightness(shower: true), 1.3)
    }

    func testBackgroundPaletteUsesOriginalQuantizationAndHSVLimits() async throws {
        func solid(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
            }
        }
        XCTAssertNil(OriginalBackgroundPalette.rgb(image: solid(.white)))
        XCTAssertNil(OriginalBackgroundPalette.rgb(image: solid(.black)))
        let rgb = try XCTUnwrap(OriginalBackgroundPalette.rgb(image: solid(.red)))
        let color = UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha))
        XCTAssertEqual(saturation, 0.75, accuracy: 0.01)
        XCTAssertEqual(brightness, 0.85, accuracy: 0.01)
    }

    func testOnlyServerRejectedOpeningOffersDeductibleBills() async {
        let bills = [CampusUnpaidBill(consumeDate: "fixture", consumeMoney: "1.25"), CampusUnpaidBill(consumeMoney: "4")]
        XCTAssertEqual(OriginalStartFailure(message: "拒绝", serverRejected: true).bills(in: bills).count, 1)
        XCTAssertTrue(OriginalStartFailure(message: "网络异常", serverRejected: false).bills(in: bills).isEmpty)
        XCTAssertTrue(OriginalStartFailure(message: "结果未知", serverRejected: false).bills(in: bills).isEmpty)
    }

    func testDeductionConfirmationDoesNotDisplayUnparseableMoneyAsZero() async {
        let failure = OriginalStartFailure(message: "拒绝", serverRejected: true)
        XCTAssertEqual(failure.total(for: [CampusUnpaidBill(consumeDate: "a", consumeMoney: "1.25"), CampusUnpaidBill(consumeDate: "b", consumeMoney: "2.50")]), 3.75)
        XCTAssertNil(failure.total(for: [CampusUnpaidBill(consumeDate: "a", consumeMoney: "unknown")]))
        XCTAssertNil(failure.total(for: [CampusUnpaidBill(consumeDate: "a", consumeMoney: "NaN")]))
    }

    func testNotificationBodyOpensUsageAndOnlyStopActionStops() async throws {
        var snapshot = LinYuWidgetSnapshot(); snapshot.ownerScope = "owner"; snapshot.controlNonce = "fixture-nonce"
        let url = LinYuWidgetStorage.url(action: "stop", id: "water-order", snapshot: snapshot)
        let body = try XCTUnwrap(LinYuWidgetStorage.notificationURL(url, actionIdentifier: UNNotificationDefaultActionIdentifier))
        let stop = try XCTUnwrap(LinYuWidgetStorage.notificationURL(url, actionIdentifier: "STOP_WATER"))
        XCTAssertEqual(body.host, "show")
        XCTAssertEqual(stop.host, "stop")
        XCTAssertEqual(URLComponents(url: body, resolvingAgainstBaseURL: false)?.queryItems, URLComponents(url: stop, resolvingAgainstBaseURL: false)?.queryItems)
    }

    func testWidgetURLKeepsAuthorizationOfDisplayedAccountSnapshot() async throws {
        var old = LinYuWidgetSnapshot(); old.ownerScope = "old-owner"; old.controlNonce = "old-nonce"
        var current = LinYuWidgetSnapshot(); current.ownerScope = "current-owner"; current.controlNonce = "current-nonce"
        let oldURL = LinYuWidgetStorage.url(action: "stop", id: "same-device", snapshot: old)
        let currentURL = LinYuWidgetStorage.url(action: "stop", id: "same-device", snapshot: current)
        func field(_ name: String, _ url: URL) -> String? { URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value }
        XCTAssertEqual(field("owner", oldURL), "old-owner")
        XCTAssertEqual(field("nonce", oldURL), "old-nonce")
        XCTAssertNotEqual(field("nonce", oldURL), field("nonce", currentURL))
    }

    func testWidgetBodyOnlyOpensAppAndExplicitControlsKeepTheirActions() {
        var snapshot = LinYuWidgetSnapshot(); snapshot.ownerScope = "fixture-owner"
        snapshot.lastDeviceID = "meter"
        XCTAssertEqual(LinYuWidgetStorage.bodyURL(snapshot: snapshot).host, "show")
        snapshot.orders = [.init(id: "order", title: "fixture", startedAt: .now, isBluetooth: true)]
        let body = LinYuWidgetStorage.bodyURL(snapshot: snapshot)
        XCTAssertEqual(body.host, "show")
        XCTAssertEqual(URLComponents(url: body, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value, "order")
        XCTAssertEqual(LinYuWidgetStorage.url(action: "stop", id: "order", snapshot: snapshot).host, "stop")
        XCTAssertEqual(LinYuWidgetStorage.url(action: "start", id: "meter", snapshot: snapshot).host, "start")
    }

    func testOriginalCardMigrationKeepsOneFunctionalSlotPerCard() async throws {
        let name = "linyu-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["使用码", "绑定寝室", "使用码"], forKey: "profileCardOrder")
        defaults.set(["使用码", "通知"], forKey: "settingsCardOrder")
        let prefs = OriginalPreferences(defaults: defaults)
        XCTAssertEqual(prefs.cardOrder, ["使用码", "绑定寝室", "账号信息"])
        XCTAssertFalse(prefs.settingsOrder.contains("使用码"))
        XCTAssertEqual(Set(prefs.cardOrder + prefs.settingsOrder).count, (prefs.cardOrder + prefs.settingsOrder).count)
    }

    func testHomeAndShowerBackgroundTuningRemainIndependent() async throws {
        let name = "linyu-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = OriginalPreferences(defaults: defaults)
        prefs.opacity = 0.2; prefs.blur = 3; prefs.brightness = 1.1
        prefs.backgroundScope = "shower"
        prefs.opacity = 0.8; prefs.blur = 15; prefs.brightness = 0.8
        XCTAssertEqual(prefs.backgroundOpacity(shower: false), 0.2)
        XCTAssertEqual(prefs.backgroundBlur(shower: false), 3)
        XCTAssertEqual(prefs.backgroundBrightness(shower: false), 1.1)
        XCTAssertEqual(prefs.backgroundOpacity(shower: true), 0.8)
        prefs.backgroundScope = "home"
        XCTAssertEqual(prefs.opacity, 0.2)
        XCTAssertEqual(prefs.backgroundOpacity(shower: true), 0.8)
    }
}

import XCTest

final class SettlementRecoveryTests: XCTestCase {
    @MainActor func testLegacyRecoveryChecksBillsOfflineWithoutAnIncreasingTimer() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["LINYU_LOGIN_FIXTURE"] = "settlement-offline"
        app.launch()

        let first = app.buttons["linyu.recovery.447"]
        let second = app.buttons["linyu.recovery.450"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(second.exists)
        first.tap()

        let duration = app.staticTexts["linyu.shower.duration"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        XCTAssertEqual(duration.label, "上次用水时长待核实")
        XCTAssertTrue(app.staticTexts["阀门状态待核实，服务器处理结果待核实"].exists)
        let retry = app.buttons["linyu.shower.stop"]
        let shower = app.scrollViews.firstMatch
        for _ in 0..<3 {
            if retry.isHittable { break }
            shower.swipeUp()
        }
        retry.tap()
        XCTAssertTrue(app.staticTexts["阀门状态待核实，服务器已记账，设备清账待确认"].waitForExistence(timeout: 8))
        XCTAssertEqual(duration.label, "上次用水时长待核实")
        XCTAssertTrue(retry.isEnabled)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "settlement-offline-server-confirmed"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let back = app.buttons["linyu.shower.back"]
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.tap()
        XCTAssertTrue(app.staticTexts["阀门状态待核实，服务器处理结果待核实"].waitForExistence(timeout: 5))
        XCTAssertEqual(duration.label, "上次用水时长待核实")
    }
}

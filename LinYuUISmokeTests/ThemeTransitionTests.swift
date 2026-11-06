import XCTest

/// Uses the existing simulator-only mock login. No account or BLE operation is involved.
final class ThemeTransitionTests: XCTestCase {
    @MainActor func testBothThemeDirectionsKeepNavigationAndSelectedPagesAccessible() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["LINYU_LOGIN_FIXTURE"] = "fast"
        app.launch()
        let phone = app.textFields["手机号"]
        XCTAssertTrue(phone.waitForExistence(timeout: 15))
        phone.tap()
        phone.typeText("00000000000")
        app.textFields["验证码"].tap()
        app.textFields["验证码"].typeText("123456")
        let login = app.buttons["登 录"]
        if !login.isHittable { app.swipeUp() }
        login.tap()
        XCTAssertTrue(app.buttons["linyu.tab.2"].waitForExistence(timeout: 10))
        app.buttons["linyu.tab.2"].tap()
        let toggle = app.buttons["linyu.theme.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let initial = toggle.value as? String
        XCTAssertTrue(initial == "浅色" || initial == "深色")
        for direction in 0..<2 {
            let expected = toggle.value as? String == "深色" ? "浅色" : "深色"
            // The synchronous lock accepts one transition during this rapid tap sequence.
            toggle.tap(withNumberOfTaps: 3, numberOfTouches: 1)
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ AND enabled == true", expected), object: toggle)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
            capture(app, "theme-profile-\(direction)")
            for tab in 0..<3 {
                let navigation = app.buttons["linyu.tab.\(tab)"]
                XCTAssertTrue(navigation.exists)
                guard ready(navigation, in: app) else { return }
                XCTAssertTrue(navigation.isHittable)
                XCTAssertTrue(app.frame.contains(navigation.frame))
                navigation.tap()
                capture(app, "theme-page-\(tab)-\(direction)")
            }
            app.buttons["打开设置"].tap()
            XCTAssertTrue(app.staticTexts["设置"].waitForExistence(timeout: 5))
            capture(app, "theme-settings-\(direction)")
            app.buttons["返回我的页面"].tap()
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            XCTAssertEqual(toggle.value as? String, expected)
        }
        XCTAssertEqual(toggle.value as? String, initial)
    }

    @MainActor private func ready(_ control: XCUIElement, in app: XCUIApplication) -> Bool {
        // Page changes animate the pill label and matched-geometry selection. A snapshot
        // immediately after the previous tap can land inside that transition.
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"), object: control)
        guard XCTWaiter.wait(for: [expectation], timeout: 5) == .completed else {
            capture(app, "theme-navigation-not-ready")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "theme-navigation-not-ready-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            XCTFail("The navigation must become hittable after the page transition: \(control)")
            return false
        }
        return true
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}

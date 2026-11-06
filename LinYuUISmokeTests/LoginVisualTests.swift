import XCTest
import CoreFoundation

/// Exercises the real login UI without using any account or calling the API.
final class LoginVisualTests: XCTestCase {
    @MainActor func testLoginModesAndInvalidPhone() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let mode = app.buttons["密码登录"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        capture(app, "login-sms")
        app.buttons["登 录"].tap()
        XCTAssertTrue(app.staticTexts["请输入手机号"].waitForExistence(timeout: 3))
        mode.tap()
        XCTAssertTrue(app.secureTextFields["密码"].exists)
        capture(app, "login-password")
        let phone = app.textFields["手机号"]
        XCTAssertTrue(phone.exists)
        phone.tap()
        phone.typeText("12")
        let login = app.buttons["登 录"]
        if !login.isHittable { app.swipeUp() }
        login.tap()
        XCTAssertTrue(app.staticTexts["请输入 11 位手机号"].waitForExistence(timeout: 5))
        capture(app, "login-invalid-phone")
        app.buttons["验证码登录"].tap()
        XCTAssertTrue(app.textFields["验证码"].exists)
        XCTAssertFalse(app.secureTextFields["密码"].exists)
        XCTAssertFalse(app.staticTexts["请输入 11 位手机号"].exists)
        phone.tap()
        phone.typeText("345678901")
        if !login.isHittable { app.swipeUp() }
        login.tap()
        XCTAssertTrue(app.staticTexts["请输入验证码"].waitForExistence(timeout: 3))
    }

    @MainActor func testLandscapeLoginActionRemainsReachableWithKeyboard() {
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }
        let app = launchFixture("fast")
        let phone = app.textFields["手机号"]
        guard reveal(phone, in: app) else { return }
        phone.tap()
        phone.typeText("12")
        device.orientation = .landscapeLeft
        let dismissKeyboard = app.buttons["收起键盘"]
        if dismissKeyboard.waitForExistence(timeout: 4) {
            let keyboard = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            keyboard.name = "responsive-keyboard-dismiss"
            keyboard.lifetime = .keepAlways
            add(keyboard)
            dismissKeyboard.tap()
        }
        let login = app.buttons["登 录"]
        let form = app.scrollViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            if login.isHittable { break }
            form.swipeUp()
        }
        XCTAssertEqual(phone.value as? String, "12")
        XCTAssertTrue(login.exists)
        login.tap()
        XCTAssertTrue(app.staticTexts["请输入 11 位手机号"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "responsive-login-keyboard-landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testFastAndOrdinaryMockLoginReachHome() {
        for scenario in ["fast", "ordinary"] {
            let app = launchFixture(scenario)
            guard let login = enterCredentials(in: app) else { return }
            login.tap()
            XCTAssertTrue(app.descendants(matching: .any)["linyu.home"].firstMatch.waitForExistence(timeout: 8))
            if scenario == "ordinary" {
                capture(app, "responsive-home-simulator")
                app.buttons["linyu.tab.1"].tap()
                XCTAssertTrue(app.staticTexts["账单"].firstMatch.exists)
                capture(app, "responsive-wallet-simulator")
                app.buttons["linyu.tab.2"].tap()
                let settings = app.buttons["打开设置"]
                XCTAssertTrue(settings.waitForExistence(timeout: 5))
                settings.tap()
                XCTAssertTrue(app.staticTexts["设置"].firstMatch.exists)
                capture(app, "responsive-settings-simulator")
            }
            app.terminate()
        }
    }

    @MainActor func testSlowMockLoginShowsDisabledLoadingAndReachesHome() {
        let app = launchFixture("slow")
        guard let login = enterCredentials(in: app) else { return }
        login.press(forDuration: 0.25)
        let loading = NSPredicate(format: "value == %@", "正在登录")
        let visible = XCTNSPredicateExpectation(predicate: loading, object: login)
        guard XCTWaiter.wait(for: [visible], timeout: 3) == .completed else {
            return XCTFail("The submit button must expose its visible loading state")
        }
        XCTAssertFalse(login.isEnabled)
        capture(app, "login-mock-loading")
        login.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        releaseFixtureResponse(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["linyu.home"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor func testFailedMockLoginRestoresButton() {
        let app = launchFixture("failure")
        guard let login = enterCredentials(in: app) else { return }
        login.tap()
        XCTAssertTrue(app.staticTexts["连接超时，请检查网络后重试"].waitForExistence(timeout: 8))
        XCTAssertTrue(login.isEnabled)
        XCTAssertNotEqual(login.value as? String, "正在登录")
        capture(app, "login-mock-failure")
    }

    @MainActor func testLoginIsDisabledWhileSMSRequestIsInFlight() {
        let app = launchFixture("slow")
        guard let login = enterCredentials(in: app) else { return }
        let send = app.buttons["发送"]
        XCTAssertTrue(send.isHittable)
        send.tap()
        XCTAssertFalse(login.isEnabled)
        releaseFixtureResponse(in: app)
    }

    @MainActor private func launchFixture(_ scenario: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["LINYU_LOGIN_FIXTURE"] = scenario
        if scenario == "slow" { app.launchEnvironment["LINYU_LOGIN_GATE"] = UUID().uuidString }
        app.launch()
        XCTAssertTrue(app.textFields["手机号"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func enterCredentials(in app: XCUIApplication) -> XCUIElement? {
        let phone = app.textFields["手机号"]
        guard reveal(phone, in: app) else { return nil }
        phone.tap()
        phone.typeText("00000000000")
        let code = app.textFields["验证码"]
        guard reveal(code, in: app) else { return nil }
        code.tap()
        code.typeText("123456")
        let login = app.buttons["登 录"]
        guard reveal(login, in: app) else { return nil }
        return login
    }

    @MainActor private func reveal(_ control: XCUIElement, in app: XCUIApplication) -> Bool {
        let form = app.scrollViews.firstMatch
        for upward in [true, false] {
            for _ in 0..<4 {
                if control.exists && control.isHittable { return true }
                guard form.exists else { break }
                if upward { form.swipeUp() } else { form.swipeDown() }
            }
        }
        if control.exists && control.isHittable { return true }
        capture(app, "login-control-not-hittable")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "login-control-not-hittable-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("The login control must remain reachable by normal scrolling: \(control)")
        return false
    }

    @MainActor private func releaseFixtureResponse(in app: XCUIApplication) {
        guard let token = app.launchEnvironment["LINYU_LOGIN_GATE"] else {
            return XCTFail("Missing explicit mock-response gate")
        }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(("org.linyu.fixture.login." + token) as CFString), nil, nil, true)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

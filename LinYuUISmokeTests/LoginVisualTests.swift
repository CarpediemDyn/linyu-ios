import XCTest

/// Exercises the real login UI without using any account or calling the API.
final class LoginVisualTests: XCTestCase {
    @MainActor func testLoginModesAndInvalidPhone() {
        let app = XCUIApplication()
        app.launch()
        let mode = app.buttons["密码登录"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        capture(app, "login-sms")
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
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

import Foundation
import XCTest
@testable import LinYuIOS

@MainActor final class WriteBackCryptoTests: XCTestCase {
    // Independent fixture: .NET Aes ECB/PKCS7, published protocol key, UTF-8 "fixture-01AB".
    private let cipher = "KMfKxMcIjUqzf2D2GbgF+w=="

    func testKnownAESResponseProducesExactWritebackBytes() async throws {
        XCTAssertEqual(KailuAES.decrypt(base64: cipher), "fixture-01AB")
        XCTAssertEqual(TransactionManager.decodeWriteBack(cipher), Data([0x01, 0xAB]))
    }

    func testInvalidWritebackTextCannotBecomeDeviceBytes() async throws {
        for plain in ["fixture-", "fixture-XYZ", "fixture-0", "fixture-00\n", "noSeparator"] {
            let base64 = Data(plain.utf8).base64EncodedString()
            XCTAssertNil(TransactionManager.decodeWriteBack(base64), plain)
        }
        XCTAssertNil(TransactionManager.decodeWriteBack("not base64!"))
    }
}

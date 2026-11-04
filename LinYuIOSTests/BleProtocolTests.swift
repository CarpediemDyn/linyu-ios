import Foundation
import XCTest
@testable import LinYuIOS

final class BleProtocolTests: XCTestCase {
    func testQueryWireFrameMatchesAndroid() {
        let wire = BleFrame.commandToWire(0x23, payload: Data([0]))
        XCTAssertEqual(String(data: wire!, encoding: .ascii), "#60000480230000A316\n")
        let parsed = BleFrame.parseWire(wire!)!
        XCTAssertEqual(BleFrame.command(parsed), 0x23)
        XCTAssertEqual(BleFrame.payload(parsed), Data([0]))
    }

    func testCorruptedCRCRejected() {
        let wire = Data("#60000480230000FF16\n".utf8)
        XCTAssertNil(BleFrame.parseWire(wire))
    }

    func testShortDeviceState() {
        var bytes = [UInt8](repeating: 0, count: 28)
        bytes[0] = 0x80; bytes[19] = 3
        bytes[21] = 0x12; bytes[22] = 0x34
        bytes[23] = 0x0A; bytes[24] = 0x0B
        let result = BleDeviceState.parse(Data(bytes))
        XCTAssertEqual(result?.randomNumber, "1234")
        XCTAssertEqual(result?.state, 3)
        XCTAssertEqual(result?.protocolType, "")
    }

    func testLongDeviceState() {
        var bytes = [UInt8](repeating: 0, count: 31)
        bytes[0] = 0x80; bytes[19] = 0x20
        bytes[24] = 0x12; bytes[25] = 0x34; bytes[26] = 0x56; bytes[27] = 0x78
        bytes[28] = 6; bytes[29] = 1; bytes[30] = 2
        let result = BleDeviceState.parse(Data(bytes))
        XCTAssertEqual(result?.randomNumber, "12345678")
        XCTAssertEqual(result?.protocolType, "20")
        XCTAssertEqual(result?.state, 6)
    }

    func testSignatureStableWithSortedKeys() {
        let a = KailuSigner.sign(sessionKey: "temporary-test", fields: ["a": "1", "b": "2"])
        let b = KailuSigner.sign(sessionKey: "temporary-test", fields: ["b": "2", "a": "1"])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a?.count, 32)
    }
}

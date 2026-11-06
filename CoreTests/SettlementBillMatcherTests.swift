import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import LinYuCore
#else
@testable import LinYuIOS
#endif

final class SettlementBillMatcherTests: XCTestCase {
    private var start: Date { Date(timeIntervalSince1970: 1_793_937_600) }
    private func match(_ rows: [[String: Any]], order: String = "order-A") -> [String: Any]? {
        SettlementBillMatcher.match(rows, orderNo: order, snCode: "meter-A",
            startedAt: start, closedAt: start.addingTimeInterval(120))
    }
    private func date(_ offset: TimeInterval) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: start.addingTimeInterval(offset))
    }

    func testExactOrderWinsOverNewerOtherDevice() {
        let rows: [[String: Any]] = [["orderNo": "order-A", "deviceSnCode": "meter-A", "consumeMoney": "0.41"],
                                   ["orderNo": "order-B", "deviceSnCode": "meter-B", "consumeMoney": "9.99"]]
        XCTAssertEqual(match(rows)?["consumeMoney"] as? String, "0.41")
    }
    func testExactOrderCannotOverrideContradictingDevice() {
        XCTAssertNil(match([["orderNo": "order-A", "deviceSnCode": "meter-B"]]))
    }
    func testDuplicateOrderRowsRemainAmbiguous() {
        XCTAssertNil(match([["orderNo": "order-A"], ["orderNo": "order-A"]]))
    }
    func testBillIDFallbackDoesNotOverrideDifferentExplicitOrder() {
        XCTAssertNil(match([["orderId": "order-A", "orderNo": "other", "deviceSnCode": "meter-A", "consumeDate": date(0)]]))
        XCTAssertNotNil(match([["orderId": "order-A", "deviceSnCode": "meter-A"]]))
    }
    func testTimeFallbackRequiresSameDeviceAndRetainsOriginalEarlierDateSlack() {
        XCTAssertNotNil(match([["deviceSnCode": "meter-A", "consumeDate": date(-2)]]))
        XCTAssertNil(match([["deviceSnCode": "meter-B", "consumeDate": date(-2)]]))
        XCTAssertNil(match([["consumeDate": date(-2)]]))
    }
    func testTimeFallbackRejectsLaterAndTooOldOrders() {
        XCTAssertNil(match([["deviceSnCode": "meter-A", "consumeDate": date(121)]]))
        XCTAssertNil(match([["deviceSnCode": "meter-A", "consumeDate": date(-181)]]))
    }
    func testTimeFallbackRejectsMultipleCandidatesAndMissingLocalOrder() {
        let bill: [String: Any] = ["deviceSnCode": "meter-A", "consumeDate": date(0)]
        XCTAssertNil(match([bill, bill]))
        XCTAssertNil(match([bill], order: ""))
    }
    func testProbeMetadataMustNotReferToAnotherOrderOrDevice() {
        XCTAssertFalse(SettlementBillMatcher.responseMatches(["orderNo": "other"], orderNo: "order-A", snCode: "meter-A"))
        XCTAssertFalse(SettlementBillMatcher.responseMatches(["deviceSnCode": "meter-B"], orderNo: "order-A", snCode: "meter-A"))
        XCTAssertTrue(SettlementBillMatcher.responseMatches(["orderNo": "order-A", "deviceSnCode": "meter-A"], orderNo: "order-A", snCode: "meter-A"))
        XCTAssertTrue(SettlementBillMatcher.responseMatches(["consumeMoney": 40], orderNo: "order-A", snCode: "meter-A"))
    }
}

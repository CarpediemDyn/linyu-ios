import Foundation
import XCTest
@testable import LinYuIOS

@MainActor final class CloudShowerTests: XCTestCase {
    private let auth = QzxySession(telephone: "13800138000", loginCode: "fixture-token",
                                  userId: "1", accountId: "2", projectId: "3")
    private let using = "/order/tcpDevice/query/rateOrder/using"
    private let rate = "/order/tcpDevice/downRate/rateOrder"
    private let result = "/order/tcpDevice/query/downRateResult"
    private let close = "/order/tcpDevice/closeOrder"
    private let consume = "/order/consumeOrder/result/query"
    private let bills = "/order/query/account/bill/list"

    func testExisting307IsResumedWithoutRateAndPreservesElapsedOnReload() async throws {
        let (api, session) = fixture([
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "existing", "isOwner": true]])
        ])
        defer { session.invalidateAndCancel() }
        let defaults = preferences()
        let manager = controller(api, defaults)
        try await manager.open(snCode: "one", name: "热水", mac: "AA", session: auth)
        let first = try XCTUnwrap(manager.active.first)
        XCTAssertEqual(first.orderNo, "existing")
        // Local duplicate does not issue a second financial request or add a second order.
        try await manager.open(snCode: "one", name: "热水", mac: "AA", session: auth)
        XCTAssertEqual(manager.active.count, 1)
        let restored = controller(api, defaults)
        restored.startMonitoring(session: auth)
        restored.stopMonitoring()
        XCTAssertEqual(restored.active.first?.startedAt, first.startedAt)
        XCTAssertEqual(restored.active.first?.orderNo, "existing")
    }

    func testOtherOwnerCannotResumeOrOpen() async throws {
        let (api, session) = fixture([
            Step(using, json: ["success": true, "data": ["orderNo": "other", "isOwner": false]])
        ])
        defer { session.invalidateAndCancel() }
        let manager = controller(api)
        do {
            try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
            XCTFail("Other-owner order was accepted")
        } catch CloudShowerError.inUseByOthers { }
        XCTAssertTrue(manager.active.isEmpty)
    }

    func test306IsPreservedForBluetoothFallback() async throws {
        let (api, session) = fixture([
            Step(using, json: ["success": true, "data": NSNull()]),
            Step(rate, json: ["success": false, "errorCode": 306, "displayMessage": "离线"])
        ])
        defer { session.invalidateAndCancel() }
        let manager = controller(api)
        do {
            try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
            XCTFail("306 was accepted")
        } catch let error as CloudShowerError { XCTAssertEqual(error.errorCode, 306) }
        XCTAssertTrue(manager.active.isEmpty)
    }

    func testOpenConfirmRetainsOrderNoAndAutoDeadlineAndMultipleDevices() async throws {
        let (api, session) = fixture([
            Step(using, json: ["success": true]),
            Step(rate, json: ["success": true, "data": ["autoDisConTime": 60]]),
            Step(result, json: ["success": true, "data": ["state": 1, "result": 0, "orderNo": "new", "autoDisConTime": 90]]),
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "second"]])
        ])
        defer { session.invalidateAndCancel() }
        let manager = controller(api)
        try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
        try await manager.open(snCode: "two", name: "B", mac: "BB", session: auth)
        XCTAssertEqual(manager.active.map(\.snCode), ["one", "two"])
        XCTAssertEqual(manager.active.first?.orderNo, "new")
        XCTAssertEqual(manager.active.first?.autoDisConTime, 90)
        XCTAssertEqual(manager.active.first?.autoDisconnectAt?.timeIntervalSince(manager.active[0].startedAt), 90)
        XCTAssertTrue((89...90).contains(manager.active[0].autoDisconRemain))
    }

    func testNineConfirmationFailuresNeverFabricateAnOrderOrRepeatRate() async throws {
        var steps = [Step(using, json: ["success": true]), Step(rate, json: ["success": true])]
        steps += (0..<9).map { _ in Step(result, json: ["success": true, "data": ["state": 1, "result": 1]]) }
        let (api, session) = fixture(steps)
        defer { session.invalidateAndCancel() }
        let manager = controller(api)
        do {
            try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
            XCTFail("Unconfirmed open was reported successful")
        } catch CloudShowerError.unconfirmed { }
        XCTAssertTrue(manager.active.isEmpty)
    }

    func testUnknownOpenPersistsAndRetryOnlyRechecksBeforeAnyNewRequest() async throws {
        let defaults = preferences()
        let (api, session) = fixture([
            Step(using, json: ["success": true]),
            Step(rate, failure: URLError(.timedOut)),
            Step(using, json: ["success": true])
        ])
        defer { session.invalidateAndCancel() }
        let manager = controller(api, defaults)
        do {
            try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
            XCTFail("A timeout must remain unconfirmed")
        } catch CloudShowerError.unconfirmed {}
        let restored = controller(api, defaults)
        do {
            try await restored.open(snCode: "one", name: "A", mac: "AA", session: auth)
            XCTFail("Rechecking must not issue a new open")
        } catch CloudShowerError.unconfirmed {}
        XCTAssertTrue(restored.active.isEmpty)
    }

    func testAcceptedCloseReturnsBeforeBillLookupAndPersistsPendingSettlement() async throws {
        let (api, session) = fixture([
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "old"]]),
            Step(close, json: ["success": true]),
            Step(consume, json: ["success": true, "data": ["consumeMoney": 40]])
        ])
        defer { session.invalidateAndCancel() }
        let defaults = preferences()
        let manager = controller(api, defaults)
        try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
        let trace = LatencyTrace("mock_cloud_close", report: { print($0) })
        trace.mark("confirmed_tap")
        try await manager.close(snCode: "one", session: auth, trace: trace)
        trace.finish("closing_indicator_ended")
        XCTAssertTrue(manager.active.isEmpty)
        XCTAssertNil(manager.latestSettlementYuan)
        let restored = controller(api, defaults)
        let settlement = LatencyTrace("mock_cloud_settlement", report: { print($0) })
        settlement.mark("bill_lookup")
        await restored.refresh(session: auth)
        settlement.finish("settled")
        XCTAssertTrue(restored.active.isEmpty)
        XCTAssertEqual(restored.latestSettlementYuan, Decimal(string: "0.04"))
    }

    func testAcceptedCloseDoesNotReviveStaleServerOrderAfterRelaunch() async throws {
        let stale = Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "old", "isOwner": true]])
        let (api, session) = fixture([stale, Step(close, json: ["success": true]), stale, stale])
        defer { session.invalidateAndCancel() }
        let defaults = preferences()
        let manager = controller(api, defaults)
        try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
        try await manager.close(snCode: "one", session: auth)

        let restored = controller(api, defaults)
        let availability = await restored.discover(snCode: "one", name: "A", mac: "AA", session: auth)
        XCTAssertEqual(availability, .unknown)
        XCTAssertTrue(restored.active.isEmpty)
        do {
            try await restored.open(snCode: "one", name: "A", mac: "AA", session: auth)
            XCTFail("An accepted close was revived as active use")
        } catch CloudShowerError.unconfirmed {}
        XCTAssertTrue(restored.active.isEmpty)
    }

    func testFailedCloseTransportRetainsOriginalStartedAt() async throws {
        let (api, session) = fixture([
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "old"]]),
            Step(close, failure: URLError(.notConnectedToInternet)),
            Step(using, failure: URLError(.notConnectedToInternet))
        ])
        defer { session.invalidateAndCancel() }
        let manager = controller(api)
        try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
        let before = manager.active
        do {
            try await manager.close(snCode: "one", session: auth)
            XCTFail("Offline close was reported successful")
        } catch CloudShowerError.unconfirmed { }
        XCTAssertEqual(manager.active, before)
    }

    func testOriginalMsgAlreadyClosingEnvelopeIsAccepted() async throws {
        let (api, session) = fixture([
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "old"]]),
            Step(close, json: ["success": false, "errorCode": 999, "msg": "设备已在关闭中"]),
            Step(consume, json: ["success": true, "data": ["consumeMoney": 40]])
        ])
        defer { session.invalidateAndCancel() }
        let manager = controller(api)
        try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
        try await manager.close(snCode: "one", session: auth)
        XCTAssertTrue(manager.active.isEmpty)
        await manager.refresh(session: auth)
        XCTAssertEqual(manager.latestSettlementYuan, Decimal(string: "0.04"))
    }

    func testSettlementAmountsRemainAttachedToTheirOwnDevicesAndResetOnAccountChange() async throws {
        let (api, session) = fixture([
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "first"]]),
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "second"]]),
            Step(close, json: ["success": true]),
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "second"]]),
            Step(consume, json: ["success": true, "data": ["consumeMoney": 40]]),
            Step(close, json: ["success": true]),
            Step(consume, json: ["success": true, "data": ["consumeMoney": 80]])
        ])
        defer { session.invalidateAndCancel() }
        let manager = controller(api)
        try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
        try await manager.open(snCode: "two", name: "B", mac: "BB", session: auth)
        let first = try XCTUnwrap(manager.active.first { $0.snCode == "one" })
        let second = try XCTUnwrap(manager.active.first { $0.snCode == "two" })
        XCTAssertNil(manager.settlementAmount(for: first))
        try await manager.close(snCode: "one", session: auth)
        await manager.refresh(session: auth)
        XCTAssertEqual(manager.settlementAmount(for: first), Decimal(string: "0.04"))
        XCTAssertNil(manager.settlementAmount(for: second))
        try await manager.close(snCode: "two", session: auth)
        await manager.refresh(session: auth)
        XCTAssertEqual(manager.latestSettlementYuan, Decimal(string: "0.08"))
        XCTAssertEqual(manager.settlementAmount(for: first), Decimal(string: "0.04"))
        XCTAssertEqual(manager.settlementAmount(for: second), Decimal(string: "0.08"))
        XCTAssertEqual(manager.settlementYuanByOrder["one:first"], Decimal(string: "0.04"))
        XCTAssertEqual(manager.settlementYuanByOrder["two:second"], Decimal(string: "0.08"))
        manager.activate(session: QzxySession(telephone: auth.telephone, loginCode: "other",
                                             userId: "9", accountId: "9", projectId: "3"))
        XCTAssertTrue(manager.settlementYuanByOrder.isEmpty)
        XCTAssertNil(manager.settlementAmount(for: first))
        manager.activate(session: nil)
        XCTAssertTrue(manager.settlementYuanByOrder.isEmpty)
    }

    func testAlreadyClosing307SkipsStatusQueryAndSettles() async throws {
        let (api, session) = fixture([
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "old"]]),
            Step(close, json: ["success": false, "errorCode": 307, "displayMessage": "已在关闭中"]),
            Step(consume, json: ["success": true, "data": ["consumeMoney": "80"]])
        ])
        defer { session.invalidateAndCancel() }
        let manager = controller(api)
        try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
        try await manager.close(snCode: "one", session: auth)
        XCTAssertTrue(manager.active.isEmpty)
        await manager.refresh(session: auth)
        XCTAssertEqual(manager.latestSettlementYuan, Decimal(string: "0.08"))
    }

    func testZeroWithPlaceholderBillRemainsUnknownAndBillYuanIsNotDivided() async throws {
        let base = [
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "old"]]),
            Step(close, json: ["success": true]),
            Step(consume, json: ["success": true, "data": ["consumeMoney": 0]]),
            Step(consume, json: ["success": true, "data": ["consumeMoney": 0]]),
            Step(consume, json: ["success": true, "data": ["consumeMoney": 0]])
        ]
        for finalAmount in ["0.0", "0.41"] {
            let fallback = (0..<3).map { _ in Step(bills, json: ["success": true, "data": [["consumeBillDTO": ["orderNo": "old", "consumeMoney": finalAmount]]]]) }
            let (api, session) = fixture(base + fallback)
            let manager = controller(api)
            try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
            try await manager.close(snCode: "one", session: auth)
            await manager.refresh(session: auth)
            if finalAmount == "0.0" { XCTAssertNil(manager.latestSettlementYuan) }
            else { XCTAssertEqual(manager.latestSettlementYuan, Decimal(string: "0.41")) }
            session.invalidateAndCancel()
        }
    }

    func testDiscoveryFindsPhysicalUseCodeOrderAndAccountRecordsAreIsolated() async throws {
        let (api, session) = fixture([
            Step(using, json: ["success": true, "data": ["orderNo": "physical", "isOwner": true]]),
            Step(using, failure: URLError(.notConnectedToInternet))
        ])
        defer { session.invalidateAndCancel() }
        let defaults = preferences()
        let manager = controller(api, defaults)
        await manager.discover(snCode: "one", name: "A", mac: "AA", session: auth)
        let first = try XCTUnwrap(manager.active.first)
        await manager.refresh(session: QzxySession(telephone: auth.telephone, loginCode: "other", userId: "9", accountId: "9", projectId: "3"))
        XCTAssertTrue(manager.active.isEmpty)
        await manager.refresh(session: auth) // failure preserves the original order, not a fake finished state
        XCTAssertEqual(manager.active.first, first)
    }

    func testDiscoveryReportsOccupiedWithoutAdoptingAnotherAccountsOrder() async {
        let (api, session) = fixture([
            Step(using, json: ["success": true, "data": ["orderNo": "other-account", "isOwner": false]])
        ])
        defer { session.invalidateAndCancel() }
        let manager = controller(api, preferences())
        let status = await manager.discover(snCode: "one", name: "A", mac: "AA", session: auth)
        XCTAssertEqual(status, .occupied)
        XCTAssertTrue(manager.active.isEmpty)
    }

    func testConsumeParserExcludesBalancesAndRetainsUnknownVersusZero() async {
        XCTAssertNil(CloudShowerController.consumeYuan(QzxyResponse(json: ["success": true, "data": ["walletMoney": 5000, "preDeductMoney": 1000]])))
        XCTAssertEqual(CloudShowerController.consumeYuan(QzxyResponse(json: ["data": ["consumeMoney": 0]])), 0)
        XCTAssertEqual(CloudShowerController.consumeYuan(QzxyResponse(json: ["data": ["fee": 40]])), Decimal(string: "0.04"))
        XCTAssertNil(CloudShowerController.consumeYuan(QzxyResponse(json: ["data": ["consumeMoney": true]])))
        for invalid in ["40pending", "NaN", "Infinity", "1e999"] {
            XCTAssertNil(CloudShowerController.consumeYuan(QzxyResponse(json: ["data": ["consumeMoney": invalid]])))
        }
    }

    func testContradictingProbeAndBillCannotSettleAnotherDevice() async throws {
        let wrongProbe = Step(consume, json: ["success": true, "data": ["orderNo": "other", "deviceSnCode": "two", "consumeMoney": 990]])
        let wrongBill = Step(bills, json: ["success": true, "data": [["consumeBillDTO": ["orderNo": "old", "deviceSnCode": "two", "consumeMoney": "9.99"]]]])
        let (api, session) = fixture([
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "old"]]),
            Step(close, json: ["success": true]), wrongProbe, wrongProbe, wrongBill, wrongBill, wrongBill,
            Step(consume, json: ["success": true, "data": ["orderNo": "old", "deviceSnCode": "one", "consumeMoney": 40]])
        ])
        defer { session.invalidateAndCancel() }
        let manager = controller(api)
        try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
        let order = try XCTUnwrap(manager.active.first)
        try await manager.close(snCode: "one", session: auth)
        await manager.refresh(session: auth)
        XCTAssertNil(manager.settlementAmount(for: order))
        await manager.refresh(session: auth)
        XCTAssertEqual(manager.settlementAmount(for: order), Decimal(string: "0.04"), "Pending record must survive the mismatched response")
    }

    func testFailedProbeWithAmountCannotMarkSettlementComplete() async throws {
        let failure = Step(consume, json: ["success": false, "data": ["consumeMoney": 990]])
        let noBills = Step(bills, json: ["success": true, "data": []])
        let (api, session) = fixture([
            Step(using, json: ["success": false, "errorCode": 307, "data": ["orderNo": "old"]]),
            Step(close, json: ["success": true]), failure, failure, noBills, noBills, noBills
        ])
        defer { session.invalidateAndCancel() }
        let manager = controller(api)
        try await manager.open(snCode: "one", name: "A", mac: "AA", session: auth)
        try await manager.close(snCode: "one", session: auth)
        await manager.refresh(session: auth)
        XCTAssertNil(manager.latestSettlementYuan)
    }

    func testHistoricalPendingOrderQueriesItsOwnBillMonthBeforeCurrentMonth() async throws {
        struct Pending: Encodable { let order: CloudActiveOrder; let createdAt: Date }
        struct SavedFixture: Encodable {
            let orders: [String: CloudActiveOrder] = [:]
            let pending: [Pending]
        }
        let started = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01, Asia/Shanghai
        let order = CloudActiveOrder(snCode: "one", orderNo: "historical", deviceName: "fixture", deviceMac: "AA",
            startedAt: started, autoDisConTime: 0, autoDisconnectAt: nil)
        let defaults = preferences()
        let identity = [auth.projectId, auth.accountId, auth.userId, auth.telephone]
        let key = "cloud-original-orders." + Data(identity.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
        defaults.set(try JSONEncoder().encode(SavedFixture(pending: [.init(order: order, createdAt: started.addingTimeInterval(60))])), forKey: key)
        let unknown = Step(consume, json: ["success": true])
        let bill = Step(bills, json: ["success": true, "data": [["consumeBillDTO": ["orderNo": "historical", "deviceSnCode": "one", "consumeMoney": "0.41"]]]], expectedMonth: "2025-01")
        let (api, session) = fixture([unknown, unknown, bill])
        defer { session.invalidateAndCancel() }
        let manager = controller(api, defaults)
        await manager.refresh(session: auth)
        XCTAssertEqual(manager.settlementAmount(for: order), Decimal(string: "0.41"))
    }

    func testActivateImmediatelyRescopesAndLogoutClearsWithoutDeletingStoredOrders() async throws {
        struct SavedFixture: Encodable {
            let orders: [String: CloudActiveOrder]
            let pending: [String] = []
        }
        func storageKey(_ session: QzxySession) -> String {
            let identity = [session.projectId, session.accountId, session.userId, session.telephone]
            return "cloud-original-orders." + Data(identity.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
        }
        let other = QzxySession(telephone: "13900139000", loginCode: "other-token",
                               userId: "9", accountId: "8", projectId: "7")
        let first = CloudActiveOrder(snCode: "one", orderNo: "first-order", deviceName: "A", deviceMac: "AA",
                                     startedAt: Date(timeIntervalSince1970: 100), autoDisConTime: 60,
                                     autoDisconnectAt: Date(timeIntervalSince1970: 160))
        let second = CloudActiveOrder(snCode: "two", orderNo: "second-order", deviceName: "B", deviceMac: "BB",
                                      startedAt: Date(timeIntervalSince1970: 200), autoDisConTime: 0,
                                      autoDisconnectAt: nil)
        let defaults = preferences()
        let firstData = try JSONEncoder().encode(SavedFixture(orders: [first.snCode: first]))
        let secondData = try JSONEncoder().encode(SavedFixture(orders: [second.snCode: second]))
        defaults.set(firstData, forKey: storageKey(auth))
        defaults.set(secondData, forKey: storageKey(other))
        // Empty transport fixture guarantees activation never performs an HTTP request.
        let (api, session) = fixture([])
        defer { session.invalidateAndCancel() }
        let manager = controller(api, defaults)
        manager.activate(session: auth)
        XCTAssertEqual(manager.active, [first])
        manager.activate(session: other)
        XCTAssertEqual(manager.active, [second])
        manager.activate(session: nil)
        XCTAssertTrue(manager.active.isEmpty)
        XCTAssertNil(manager.lastMessage)
        XCTAssertNil(manager.latestSettlementYuan)
        XCTAssertFalse(manager.mqttConnected)
        XCTAssertEqual(defaults.data(forKey: storageKey(auth)), firstData)
        XCTAssertEqual(defaults.data(forKey: storageKey(other)), secondData)
        manager.activate(session: auth)
        XCTAssertEqual(manager.active, [first])
        manager.activate(session: nil)
        XCTAssertTrue(manager.active.isEmpty)
    }

    func testMQTTIncrementalParserAndBoundsAndOriginalTopics() async throws {
        XCTAssertEqual(OriginalMQTTClient.topics(phone: "phone"), ["app_downRate_phone", "app_shutdownOrder_phone", "app_uploadData_phone"])
        var parser = OriginalMQTTPacketParser()
        XCTAssertTrue(try parser.append(Data([0x20, 2, 0])).isEmpty)
        XCTAssertEqual(try parser.append(Data([0, 0xD0, 0])), [.init(header: 0x20, body: [0, 0]), .init(header: 0xD0, body: [])])
        var invalid = OriginalMQTTPacketParser()
        XCTAssertThrowsError(try invalid.append(Data([0x30, 0xFF, 0xFF, 0xFF, 0xFF])))
        var oversized = OriginalMQTTPacketParser()
        XCTAssertThrowsError(try oversized.append(Data(repeating: 0, count: 8193)))
    }

    private func preferences() -> UserDefaults { UserDefaults(suiteName: "CloudShowerTests." + UUID().uuidString)! }
    private func controller(_ api: QzxyAPI, _ defaults: UserDefaults? = nil) -> CloudShowerController {
        CloudShowerController(api: api, defaults: defaults ?? preferences(), pause: { _ in try Task.checkCancellation() })
    }
    private struct Step {
        let path: String; let json: [String: Any]; let failure: Error?; let expectedMonth: String?
        init(_ path: String, json: [String: Any], expectedMonth: String? = nil) {
            self.path = path; self.json = json; self.failure = nil; self.expectedMonth = expectedMonth
        }
        init(_ path: String, failure: Error) { self.path = path; self.json = [:]; self.failure = failure; self.expectedMonth = nil }
    }
    private func fixture(_ steps: [Step]) -> (QzxyAPI, URLSession) {
        let key = UUID().uuidString
        let queue = CloudFixtureQueue(steps.map { step in
            { request in
                XCTAssertEqual(request.url?.path, step.path)
                XCTAssertEqual(request.httpMethod, step.path == "/order/query/account/bill/list" ? "GET" : "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Config-Project"), "3")
                let fields = try cloudFixtureFields(request)
                if let month = step.expectedMonth { XCTAssertEqual(fields["month"], month) }
                XCTAssertEqual(fields["loginCode"], "fixture-token")
                XCTAssertEqual(fields["telephone"], "13800138000")
                XCTAssertEqual(fields["userId"], "1")
                XCTAssertEqual(fields["accountId"], "2")
                if step.path.contains("tcpDevice") {
                    XCTAssertNotNil(fields["snCode"])
                    if step.path.hasSuffix("using") || step.path.hasSuffix("rateOrder") {
                        XCTAssertEqual(fields["xfModel"], "0")
                    }
                }
                if step.path == "/order/tcpDevice/closeOrder" || step.path == "/order/consumeOrder/result/query" {
                    XCTAssertNotNil(fields["orderNo"])
                }
                if let failure = step.failure { throw failure }
                return try JSONSerialization.data(withJSONObject: step.json)
            }
        })
        CloudFixtureProtocol.install(queue, key: key)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CloudFixtureProtocol.self]
        config.httpAdditionalHeaders = ["X-Cloud-Fixture": key]
        let session = URLSession(configuration: config)
        return (QzxyAPI(session: session), session)
    }
}

private func cloudFixtureFields(_ request: URLRequest) throws -> [String: String] {
    if request.httpMethod == "GET" {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }
    var data = request.httpBody
    if data == nil, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        data = bytes
    }
    let body = try XCTUnwrap(String(data: try XCTUnwrap(data), encoding: .utf8))
    let items = URLComponents(string: "https://fixture.invalid/?" + body)?.queryItems ?? []
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

private final class CloudFixtureQueue {
    private let lock = NSLock()
    private var handlers: [(URLRequest) throws -> Data]
    init(_ handlers: [(URLRequest) throws -> Data]) { self.handlers = handlers }
    func next(_ request: URLRequest) throws -> Data {
        lock.lock()
        guard !handlers.isEmpty else { lock.unlock(); XCTFail("Unexpected HTTP request: \(request.url?.path ?? "")"); throw URLError(.unsupportedURL) }
        let handler = handlers.removeFirst()
        lock.unlock()
        return try handler(request)
    }
}

private final class CloudFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var queues: [String: CloudFixtureQueue] = [:]
    static func install(_ queue: CloudFixtureQueue, key: String) {
        lock.lock(); defer { lock.unlock() }; queues[key] = queue
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let queue = Self.queues[request.value(forHTTPHeaderField: "X-Cloud-Fixture") ?? ""]
        Self.lock.unlock()
        do {
            guard let queue else { throw URLError(.unsupportedURL) }
            let data = try queue.next(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

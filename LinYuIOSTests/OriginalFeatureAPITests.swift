import Foundation
import XCTest
@testable import LinYuIOS

/// All traffic is intercepted by the session's URLProtocol; these fixtures never reach a server.
@MainActor final class OriginalFeatureAPITests: XCTestCase {
    private let auth = QzxySession(telephone: "13800138000", loginCode: "fixture-token",
                                  userId: "7", accountId: "8", projectId: "9")

    func testProfileUsesAllOriginalIdentitySourcesAndProject() async throws {
        var paths = [String]()
        let client = fixture { request in
            paths.append(request.url!.path)
            switch request.url!.path {
            case "/account/info": return ["success": true, "data": ["name": NSNull(), "cardStatus": 1]]
            case "/account/card/getBindCardInfo": return ["success": true, "data": ["name": "卡片姓名"]]
            case "/settlement/campus/userInfo": return ["success": true, "data": ["studentNumber": "2026001"]]
            case "/project/info/triple": return ["success": true, "data": ["projectName": "测试学校"]]
            default: throw URLError(.unsupportedURL)
            }
        }
        defer { client.invalidateAndCancel() }
        let profile = try await QzxyAPI(session: client).profile(session: auth)
        XCTAssertEqual(profile.name, "卡片姓名")
        XCTAssertEqual(profile.studentNumber, "2026001")
        XCTAssertEqual(profile.cardStatus, 1)
        XCTAssertEqual(profile.schoolName, "测试学校")
        XCTAssertTrue(paths.contains("/account/card/getBindCardInfo"))
    }

    func testWalletUsesYuanStringAndCampusPriority() async throws {
        let client = fixture { request in
            if request.url!.path == "/account/wallet" {
                return ["success": true, "data": ["money": "55.460", "accountRealMoney": 55460]]
            }
            return ["success": true, "data": ["amount": "16.76", "signStatus": 1]]
        }
        defer { client.invalidateAndCancel() }
        let wallet = try await QzxyAPI(session: client).campusWallet(session: auth)
        XCTAssertEqual(wallet.walletBalance, 55.46)
        XCTAssertEqual(wallet.campusBalance, 16.76)
        XCTAssertEqual(wallet.balance, 16.76)
        XCTAssertEqual(wallet.title, "一卡通余额")
    }

    func testBillsNestedAndUnpaidFlatRemainDistinct() async throws {
        let client = fixture { request in
            if request.url!.path == "/order/query/account/bill/list" {
                let query = self.query(request)
                XCTAssertEqual(query["month"], "2026-11")
                XCTAssertEqual(query["billRequestType"], "2")
                return ["success": true, "data": [["consumeBillDTO": ["orderId": "9564403",
                    "consumeDate": "2026-11-04 09:30:00", "consumeMoney": "0.025", "description": "用水:热水表-3栋-3层-320房", "orderNo": "12345678901234567890"]]]]
            }
            XCTAssertEqual(request.url!.path, "/order/weixinScorePay/unPay/queryBill")
            XCTAssertEqual(request.httpMethod, "POST")
            return ["success": true, "data": [["orderId": 9564403, "consumeDate": "2026-11-04 09:30:00", "consumeMoney": "0.025"], ["orderId": "empty-date"]]]
        }
        defer { client.invalidateAndCancel() }
        let api = QzxyAPI(session: client)
        let bills = try await api.bills(month: "2026-11", session: auth)
        XCTAssertEqual(bills.first?.orderId, "9564403")
        XCTAssertEqual(bills.first?.orderNo, "12345678901234567890")
        XCTAssertEqual(bills.first?.amount, 0.025)
        let unpaid = try await api.unpaidBills(session: auth)
        XCTAssertEqual(unpaid.count, 2)
        XCTAssertEqual(unpaid.filter(\.isDeductible).count, 1)
    }

    func testBillDetailUsesBillIDAndConsumeDate() async throws {
        let client = fixture { request in
            XCTAssertEqual(request.url!.path, "/order/query/account/bill/detail")
            XCTAssertEqual(self.query(request)["orderId"], "9564403")
            XCTAssertEqual(self.query(request)["consumeDate"], "2026-11-04 09:30:00")
            return ["success": true, "data": ["orderId": "9564403", "consumeMoney": 0.025,
                "preDeductMoney": 5, "deviceSnCode": "00158304D300"]]
        }
        defer { client.invalidateAndCancel() }
        let detail = try await QzxyAPI(session: client).billDetail(orderId: "9564403", consumeDate: "2026-11-04 09:30:00", session: auth)
        XCTAssertEqual(detail.consumeMoney, 0.025)
        XCTAssertEqual(detail.preDeductMoney, 5)
    }

    func testDeductUsesExactOriginalJSONAndRequiresConfirmation() async throws {
        var requests = 0
        let client = fixture { request in
            requests += 1
            XCTAssertEqual(request.url!.path, "/order/thirdTrade/single/json/pay")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Config-Project"), "9")
            let json = try JSONSerialization.jsonObject(with: self.body(request)) as! [String: Any]
            XCTAssertEqual(Set(json.keys), Set(["deductType", "consumeDate", "projectId", "accountId", "loginCode", "userId", "phoneSystem"]))
            XCTAssertEqual(json["deductType"] as? Int, 7)
            XCTAssertEqual(json["phoneSystem"] as? String, "WeChat")
            XCTAssertEqual(json["consumeDate"] as? String, "date+one")
            XCTAssertEqual(json["projectId"] as? String, "9")
            XCTAssertEqual(json["accountId"] as? String, "8")
            XCTAssertEqual(json["loginCode"] as? String, "fixture-token")
            XCTAssertEqual(json["userId"] as? String, "7")
            return ["success": true]
        }
        defer { client.invalidateAndCancel() }
        let api = QzxyAPI(session: client)
        do {
            _ = try await api.requestDeduct(consumeDate: "date+one", confirmed: false, session: auth)
            XCTFail("unconfirmed deduction sent")
        } catch { }
        XCTAssertEqual(requests, 0)
        let result = try await api.requestDeduct(consumeDate: "date+one", confirmed: true, session: auth)
        XCTAssertEqual(result, .success)
        XCTAssertEqual(requests, 1)
    }

    func testDeductTransportFailureIsUnknownAndServerRejectionIsExplicit() async throws {
        let offline = fixture { _ in throw URLError(.timedOut) }
        defer { offline.invalidateAndCancel() }
        let unknown = try await QzxyAPI(session: offline).requestDeduct(consumeDate: "date", confirmed: true, session: auth)
        XCTAssertEqual(unknown, .unknown)
        let rejected = fixture { _ in ["success": false, "errorMessage": "余额不足"] }
        defer { rejected.invalidateAndCancel() }
        let failed = try await QzxyAPI(session: rejected).requestDeduct(consumeDate: "date", confirmed: true, session: auth)
        XCTAssertEqual(failed, .failed("余额不足"))
    }

    func testUseCodePreviewAndClaimAreSeparateCallsAndNullableCurrentCode() async throws {
        var paths = [String]()
        let client = fixture { request in
            let path = request.url!.path
            paths.append(path)
            switch path {
            case "/account/useCode/new": return ["success": true, "data": ["useCode": NSNull(), "resetAvailability": 0, "resetAvailabilityWarMark": "1天只能领取一次使用码"]]
            case "/account/useCode/new/generate": return ["success": true, "data": ["useCode": "123456", "remainTimes": 19]]
            case "/account/useCode/new/set":
                XCTAssertEqual(try self.form(request)["useCode"], "123456")
                return ["success": true]
            case "/account/useCode/new/status/update":
                XCTAssertEqual(try self.form(request)["useCodeStatus"], "0")
                return ["success": true]
            default: throw URLError(.unsupportedURL)
            }
        }
        defer { client.invalidateAndCancel() }
        let api = QzxyAPI(session: client)
        let current = try await api.useCode(session: auth)
        XCTAssertNil(current.useCode)
        let candidate = try await api.generateUseCode(session: auth)
        XCTAssertEqual(candidate.useCode, "123456")
        XCTAssertEqual(candidate.remainTimes, 19)
        XCTAssertFalse(paths.contains("/account/useCode/new/set"))
        try await api.claimUseCode(candidate.useCode, session: auth)
        try await api.updateUseCodeStatus(0, session: auth)
    }

    func testAccountSMSUsesNewPhoneType5AndForgetType2() async throws {
        var types = [String]()
        let client = fixture { request in
            let query = self.query(request)
            types.append(query["typeId"] ?? "")
            XCTAssertEqual(request.url!.path, "/user/verification/code/get")
            XCTAssertEqual(query["telephone"], "13900139001")
            XCTAssertEqual(query["secret"], KailuSigner.md5("1399001klcx"))
            XCTAssertNil(query["loginCode"])
            XCTAssertNil(query["telPhone"])
            return ["success": true]
        }
        defer { client.invalidateAndCancel() }
        let api = QzxyAPI(session: client)
        try await api.sendAccountSMS(to: "13900139001", purpose: .newPhone, session: auth)
        try await api.sendAccountSMS(to: "13900139001", purpose: .forgotPassword, session: auth)
        XCTAssertEqual(types, ["5", "2"])
    }

    func testPhoneAndPasswordRequestFieldsMatchOriginal() async throws {
        let client = fixture { request in
            let form = try self.form(request)
            XCTAssertEqual(form["telPhone"], "13800138000")
            switch request.url!.path {
            case "/user/phone/update":
                XCTAssertEqual(form["newTelephone"], "13900139001")
                XCTAssertEqual(form["code"], "123456")
            case "/user/password/update":
                XCTAssertEqual(form["oldPassword"], String(KailuSigner.md5("old password").suffix(10)).uppercased())
                XCTAssertEqual(form["password"], String(KailuSigner.md5("new password").suffix(10)).uppercased())
            case "/user/password/forget":
                XCTAssertNil(form["oldPassword"])
                XCTAssertEqual(form["password"], String(KailuSigner.md5("new password").suffix(10)).uppercased())
                XCTAssertEqual(form["code"], "123456")
            default: throw URLError(.unsupportedURL)
            }
            return ["success": true]
        }
        defer { client.invalidateAndCancel() }
        let api = QzxyAPI(session: client)
        try await api.updatePhone(newTelephone: "13900139001", code: "123456", session: auth)
        try await api.updatePassword(oldPassword: "old password", newPassword: "new password", session: auth)
        try await api.forgetPassword(password: "new password", code: "123456", session: auth)
    }

    func testDeviceLookupTriesOriginalThenDerivedMACAndDoesNotGuessBLEFromSmallType() async throws {
        var values = [String]()
        let client = fixture { request in
            XCTAssertEqual(request.url!.path, "/device/info/mac")
            let mac = self.query(request)["macAddress"]!
            values.append(mac)
            if values.count == 1 { return ["success": true, "data": NSNull()] }
            return ["success": true, "data": ["deviceId": 3145, "deviceName": "热水表-1栋-2层-201房", "snCode": "00158304D300", "macAddress": "00158304D300", "bigTypeId": 4, "smallTypeId": 1, "withholdMoney": 5]]
        }
        defer { client.invalidateAndCancel() }
        let found = try await QzxyAPI(session: client).deviceByMAC("C0158304D300", session: auth)
        let device = try XCTUnwrap(found)
        XCTAssertEqual(values, ["C0158304D300", "00158304d300"])
        XCTAssertNil(device.isBle)
        XCTAssertFalse(device.needsBluetoothControl)
        XCTAssertEqual(device.withholdMoney, 5)
        XCTAssertEqual(try device.ledgerDevice.deviceId, "3145")
    }

    func testRoomKeysQRMoneyDatesAndAccountScope() async throws {
        let shower = "热水表-龙川北苑-3号楼南-3层-320房"
        let basin = "洗手台54-龙川北苑-3号楼南-3层-320洗手台"
        let key = try XCTUnwrap(OriginalFormatting.roomKey(shower))
        XCTAssertEqual(key, OriginalFormatting.roomKey(basin))
        XCTAssertEqual(key, OriginalFormatting.roomKey(key))
        XCTAssertTrue(OriginalFormatting.inSameRoom("320房", deviceName: shower))
        XCTAssertFalse(OriginalFormatting.inSameRoom("320", deviceName: "热水表-3栋-3层-1320房"))
        XCTAssertEqual(OriginalFormatting.parseDeviceQR("KLCXKJ-Water,00:15:83:04:D3:00"), "00158304D300")
        XCTAssertNil(OriginalFormatting.parseDeviceQR("other,00158304D300"))
        XCTAssertNil(OriginalFormatting.parseDeviceQR("KLCXKJ-Water,00-15-83-04-D3-00"))
        XCTAssertEqual(OriginalFormatting.money(0.025), "0.025")
        XCTAssertEqual(OriginalFormatting.money(5), "5.00")
        XCTAssertNil(OriginalFormatting.billDate("2026-02-30 12:00:00"))
        XCTAssertNotNil(OriginalFormatting.billDate("2026-11-04T12:00:00"))
        XCTAssertNotNil(OriginalFormatting.billDate("2026-11-04 12:00:00.123"))
        var snapshot = CampusBalanceSnapshot(ownerScope: auth.ownerScope)
        snapshot.manualBalance = "10"
        snapshot.manualBalanceTime = OriginalFormatting.billDate("2026-11-04 08:00:00")!
        snapshot.bills = [CampusBill(orderId: "1", consumeDate: "2026-11-04 09:00:00", consumeMoney: "0.025", description: "")]
        XCTAssertEqual(snapshot.balance, 9.975, accuracy: 0.000001)
        snapshot.walletBalance = 55.46
        XCTAssertEqual(snapshot.balance, 55.46)
        snapshot.campusBalance = 16.76
        XCTAssertEqual(snapshot.balance, 16.76)
        XCTAssertTrue(snapshot.matches(auth))
        XCTAssertFalse(snapshot.matches(QzxySession(telephone: "x", loginCode: "x", userId: "other", accountId: "8", projectId: "9")))
        XCTAssertTrue(OriginalSessionFailure.isKickMessage("登录已失效"))
        XCTAssertFalse(OriginalSessionFailure.isKickMessage("设备不在线"))
        XCTAssertTrue(OriginalSessionFailure.isKickError(QzxyError.server("HTTP 401")))
    }

    func testWalletDoesNotTreatMilliYuanAsYuanWhenMoneyIsAbsent() async throws {
        let client = fixture { request in
            if request.url!.path == "/account/wallet" {
                return ["success": true, "data": ["accountRealMoney": 55460]]
            }
            return ["success": false, "errorCode": 12, "errorMessage": "无效支付配置"]
        }
        defer { client.invalidateAndCancel() }
        let wallet = try await QzxyAPI(session: client).campusWallet(session: auth)
        XCTAssertNil(wallet.balance)
        XCTAssertEqual(wallet.title, "余额")
    }

    func testExpiredSessionStopsProfileFallback() async throws {
        var requests = 0
        let client = fixture { _ in
            requests += 1
            return ["success": false, "msg": "登录已失效，请重新登录"]
        }
        defer { client.invalidateAndCancel() }
        do {
            _ = try await QzxyAPI(session: client).profile(session: auth)
            XCTFail("expired session was ignored")
        } catch {
            XCTAssertTrue(OriginalSessionFailure.isKickError(error))
        }
        XCTAssertEqual(requests, 1)
    }

    func testScannedSNUsesActualMACEndpointAndMissingTypesMapToZero() async throws {
        let client = fixture { request in
            XCTAssertEqual(request.url!.path, "/device/info/mac")
            XCTAssertEqual(self.query(request)["macAddress"], "00158304D300")
            return ["success": true, "data": ["deviceId": 3145, "deviceName": "热水表", "snCode": "00158304D300", "macAddress": "00158304D300", "isBle": true]]
        }
        defer { client.invalidateAndCancel() }
        let found = try await QzxyAPI(session: client).deviceBySN("00:15:83:04:D3:00", session: auth)
        let device = try XCTUnwrap(found)
        XCTAssertTrue(device.needsBluetoothControl)
        XCTAssertEqual(try device.ledgerDevice.bigTypeId, "0")
        XCTAssertEqual(try device.ledgerDevice.smallTypeId, "0")
    }

    func testVerifiedDisplayMetadataSurvivesRelaunchAndExpiresPerAccount() throws {
        let suite = "CampusMeterDisplayCacheTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let now = Date()
        let meter = CampusDevice(deviceId: "one", deviceName: "学生公寓 D7 四层 450", snCode: "fixture")
        var cache = CampusMeterDisplayCache(ownerScope: auth.ownerScope, defaults: defaults)
        cache.store(meter, for: id, now: now)

        let restored = CampusMeterDisplayCache(ownerScope: auth.ownerScope, defaults: defaults)
        let trace = LatencyTrace("mock_cached_identify", report: { print($0) })
        trace.mark("tap")
        XCTAssertEqual(restored.device(for: id, now: now.addingTimeInterval(10)), meter)
        trace.finish("display_cache_hit")
        XCTAssertNil(restored.device(for: id, now: now.addingTimeInterval(86_401)))
        XCTAssertNil(restored.device(for: UUID(), now: now))
        let other = CampusMeterDisplayCache(ownerScope: "another-account", defaults: defaults)
        XCTAssertNil(other.device(for: id, now: now))
    }

    func testDeviceLookupCoalescesConcurrentAndRecentRequests() async throws {
        let lookup = CampusDeviceLookup(ownerScope: auth.ownerScope)
        let meter = CampusDevice(deviceId: "one", deviceName: "测试水表", snCode: "fixture")
        var calls = 0
        let load: () async throws -> CampusDevice? = {
            calls += 1
            try await Task.sleep(nanoseconds: 30_000_000)
            return meter
        }
        let session = auth
        let first = Task { try await lookup.device(for: "CA:FE:12:34:56:78", session: session, load: load) }
        let second = Task { try await lookup.device(for: "cafe12345678", session: session, load: load) }
        let firstDevice = try await first.value
        let secondDevice = try await second.value
        let cached = try await lookup.device(for: "CAFE12345678", session: session, load: load)
        XCTAssertEqual(firstDevice, meter)
        XCTAssertEqual(secondDevice, meter)
        XCTAssertEqual(cached, meter)
        XCTAssertEqual(calls, 1)
    }

    func testDeviceCacheExpiresAndCannotCrossAccounts() async {
        var cache = CampusDeviceCache(ownerScope: auth.ownerScope)
        let now = Date()
        let device = CampusDevice(deviceId: "one")
        cache.store(device, for: "mac", session: auth, now: now)
        XCTAssertEqual(cache.device(for: "mac", session: auth, now: now.addingTimeInterval(59)), device)
        XCTAssertNil(cache.device(for: "mac", session: auth, now: now.addingTimeInterval(61)))
        cache.store(device, for: "mac", session: auth, now: now)
        let other = QzxySession(telephone: "other", loginCode: "other", userId: "other", accountId: "8", projectId: "9")
        XCTAssertNil(cache.device(for: "mac", session: other, now: now))
        XCTAssertNil(cache.device(for: "mac", session: auth, now: now))
    }

    nonisolated private func query(_ request: URLRequest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    nonisolated private func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { throw URLError(.cannotDecodeRawData) }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return data
    }

    nonisolated private func form(_ request: URLRequest) throws -> [String: String] {
        let text = String(decoding: try body(request), as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: text.split(separator: "&").map {
            let parts = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(parts[0]).removingPercentEncoding!, String(parts[1]).removingPercentEncoding!)
        })
    }

    private func fixture(_ handler: @escaping (URLRequest) throws -> [String: Any]) -> URLSession {
        let key = UUID().uuidString
        OriginalFeatureFixture.install(handler, key: key)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OriginalFeatureFixture.self]
        config.httpAdditionalHeaders = ["X-Original-Fixture": key]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        OriginalFeatureFixture.clear()
        super.tearDown()
    }
}

private final class OriginalFeatureFixture: URLProtocol {
    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest) throws -> [String: Any]] = [:]
    static func install(_ handler: @escaping (URLRequest) throws -> [String: Any], key: String) {
        lock.lock(); defer { lock.unlock() }; handlers[key] = handler
    }
    static func clear() { lock.lock(); defer { lock.unlock() }; handlers.removeAll() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handlers[request.value(forHTTPHeaderField: "X-Original-Fixture") ?? ""]
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let body = try JSONSerialization.data(withJSONObject: handler(request))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}


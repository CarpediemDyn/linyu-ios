import Foundation
import Combine
import SwiftUI
import UIKit
import XCTest
@testable import LinYuIOS

@MainActor final class QzxyAPITests: XCTestCase {
    private let auth = QzxySession(telephone: "13800138000", loginCode: "token+one",
                                  userId: "7", accountId: "8", projectId: "9")
    private let state = BleDeviceState(protocolType: "20", randomNumber: "ABCD",
                                       state: 0, deviceType: 0x0A, a1: 0x0B)
    private let device = LedgerDevice(deviceId: "12", snCode: "SN-12", name: "热水表",
                                      macAddress: "AABBCCDDEEFF", realMac: "112233445566",
                                      bigTypeId: "3", smallTypeId: "1")
    private var payload: Data { Data([0x80, 0xAB] + [UInt8](repeating: 0, count: 40)) }
    nonisolated private var ledgerJSON: [String: Any] {
        ["deviceId": 12, "snCode": "SN-12", "deviceName": "热水表",
         "macAddress": "AA:BB:CC:DD:EE:FF", "realMac": "11-22-33-44-55-66",
         "bigTypeId": 3, "smallTypeId": 1]
    }

    func testLedgerLookupNormalizesMACAndPreservesRequiredServerFields() async throws {
        let fixture = fixtureSession { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/device/info/mac")
            let fields = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(fields.first { $0.name == "macAddress" }?.value, "AABBCCDDEEFF")
            XCTAssertEqual(fields.first { $0.name == "loginCode" }?.value, "token+one")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Config-Project"), "9")
            return try self.response(["success": true, "errorCode": 0, "data": self.ledgerJSON])
        }
        defer { fixture.invalidateAndCancel() }
        let result = try await QzxyAPI(session: fixture).ledgerDevice(ledgerMAC: "aa:bb:cc:dd:ee:ff", session: auth)
        XCTAssertEqual(result, device)
    }

    func testLedgerLookupRefusesMissingOrEmptyRequiredFields() async throws {
        for key in ["deviceId", "snCode", "macAddress"] {
            for invalid in [nil, NSNull(), "", " \n", true] as [Any?] {
                var fields = ledgerJSON
                fields[key] = invalid
                let fixture = fixtureSession { _ in
                    try self.response(["success": true, "errorCode": 0, "data": fields])
                }
                do {
                    _ = try await QzxyAPI(session: fixture).ledgerDevice(ledgerMAC: "AABBCCDDEEFF", session: auth)
                    XCTFail("Accepted invalid ledger field: \(key)")
                } catch { }
                fixture.invalidateAndCancel()
            }
        }
    }

    func testLedgerTypesDefaultToZeroAsInOriginal() async throws {
        var fields = ledgerJSON
        fields.removeValue(forKey: "bigTypeId")
        fields.removeValue(forKey: "smallTypeId")
        let fixture = fixtureSession { _ in
            try self.response(["success": true, "errorCode": 0, "data": fields])
        }
        defer { fixture.invalidateAndCancel() }
        let result = try await QzxyAPI(session: fixture).ledgerDevice(ledgerMAC: "AABBCCDDEEFF", session: auth)
        XCTAssertEqual(result.bigTypeId, "0")
        XCTAssertEqual(result.smallTypeId, "0")
    }

    func testRateDefaultsAbsentTypesAndAllowsMissingConsumeDate() async throws {
        let fallback = LedgerDevice(deviceId: "12", snCode: "SN-12", name: "热水表",
                                    macAddress: "AABBCCDDEEFF", realMac: nil,
                                    bigTypeId: "", smallTypeId: "")
        for consumeDate in [nil, "", " \n"] as [String?] {
            let fixture = fixtureSession { request in
                let fields = try self.form(request)
                XCTAssertEqual(fields["bigTypeId"], "0")
                XCTAssertEqual(fields["smallTypeId"], "0")
                var data: [String: Any] = ["downData": "80"]
                data["consumeDate"] = consumeDate
                return try self.response(["success": true, "errorCode": 0, "data": data])
            }
            let grant = try await QzxyAPI(session: fixture).grantRate(device: fallback, state: state, session: auth)
            XCTAssertEqual(grant.downData, Data([0x80]))
            XCTAssertEqual(grant.consumeDate, consumeDate ?? "")
            fixture.invalidateAndCancel()
        }
    }

    func testRateRequestMatchesAndroidFieldsSignatureAndAuth() async throws {
        let fixture = fixtureSession { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/order/downRate/bluetooth/rateOrder")
            let fields = try self.form(request)
            XCTAssertEqual(fields["deviceId"], "12")
            XCTAssertEqual(fields["macAddress"], "112233445566")
            XCTAssertEqual(fields["macType"], "0a0b")
            XCTAssertEqual(fields["bigTypeId"], "3")
            XCTAssertEqual(fields["smallTypeId"], "1")
            XCTAssertEqual(fields["protocolType"], "20")
            XCTAssertEqual(fields["randomNumber"], "abcd")
            XCTAssertEqual(fields["xfModel"], "0")
            XCTAssertEqual(fields["signature"], "7a4971683c8e7b8453ba304edb84cd4a")
            self.assertAuth(request, fields: fields)
            return try self.response(["success": true, "errorCode": 0, "data": [
                "downData": "80aB", "consumeDate": "date", "orderNo": "", "liquidOrderNo": "fallback"
            ]])
        }
        defer { fixture.invalidateAndCancel() }
        let grant = try await QzxyAPI(session: fixture).grantRate(device: device, state: state, session: auth)
        XCTAssertEqual(grant, RateGrant(downData: Data([0x80, 0xAB]), consumeDate: "date", orderNo: "fallback"))
    }

    func testRateAcceptsMaximumFramePayloadAndPrimaryOrderNumber() async throws {
        let fixture = fixtureSession { _ in
            try self.response(["success": true, "errorCode": 0, "data": [
                "downData": String(repeating: "AB", count: 252), "consumeDate": "date",
                "orderNo": "primary", "liquidOrderNo": "secondary"
            ]])
        }
        defer { fixture.invalidateAndCancel() }
        let grant = try await QzxyAPI(session: fixture).grantRate(device: device, state: state, session: auth)
        XCTAssertEqual(grant.downData, Data(repeating: 0xAB, count: 252))
        XCTAssertEqual(grant.orderNo, "primary")
    }

    func testMalformedRateRemainsAmbiguousRatherThanExplicitlyRejected() async throws {
        let invalidData: [[String: Any]] = [
            ["downData": "", "consumeDate": "date"],
            ["downData": "0", "consumeDate": "date"],
            ["downData": "GG", "consumeDate": "date"],
            ["downData": String(repeating: "00", count: 253), "consumeDate": "date"]
        ]
        for data in invalidData {
            let fixture = fixtureSession { _ in try self.response(["success": true, "errorCode": 0, "data": data]) }
            await assertAmbiguous {
                _ = try await QzxyAPI(session: fixture).grantRate(device: self.device, state: self.state, session: self.auth)
            }
            fixture.invalidateAndCancel()
        }
    }

    func testRateExplicitServerRejectionIsDistinguishedFromAmbiguity() async throws {
        let fixture = fixtureSession { _ in
            try self.response(["success": false, "errorCode": 170, "displayMessage": "signature rejected"])
        }
        defer { fixture.invalidateAndCancel() }
        do {
            _ = try await QzxyAPI(session: fixture).grantRate(device: device, state: state, session: auth)
            XCTFail("Expected rejection")
        } catch WaterError.rejected(let message) {
            XCTAssertEqual(message, "signature rejected")
        }
    }

    func testRateTransportFailureIsNotRetried() async throws {
        var count = 0
        let fixture = fixtureSession { _ in
            count += 1
            throw URLError(.networkConnectionLost)
        }
        defer { fixture.invalidateAndCancel() }
        await assertAmbiguous {
            _ = try await QzxyAPI(session: fixture).grantRate(device: self.device, state: self.state, session: self.auth)
        }
        XCTAssertEqual(count, 1)
    }

    func testUploadPostsLowercaseConsumptionAndAcceptsAllAndroidAccountingCodes() async throws {
        for code in [0, 206, 209] {
            let fixture = fixtureSession { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/order/upload/bluetooth/data")
                let fields = try self.form(request)
                XCTAssertEqual(fields["xfData"], "80ab" + String(repeating: "00", count: 40))
                XCTAssertEqual(fields["randomNumber"], "abcd")
                XCTAssertEqual(fields["protocolType"], "20")
                XCTAssertEqual(fields["signature"], "9022644535cef1d3e6ff7ca9b5863ac4")
                self.assertAuth(request, fields: fields)
                return try self.response(["success": code == 0, "errorCode": code,
                                          "data": ["clData": "encoded+receipt", "upMoney": 123]])
            }
            let receipt = try await QzxyAPI(session: fixture).uploadConsumption(payload, state: state, session: auth)
            XCTAssertEqual(receipt, SettlementReceipt(clData: "encoded+receipt", amountRaw: "123"))
            fixture.invalidateAndCancel()
        }
    }

    func testUploadPreservesExtendedConsumptionBodyAsLowercaseHex() async throws {
        for length in [63, 80] {
            let extended = Data([0x80] + [UInt8](repeating: 0xAB, count: length - 1))
            let fixture = fixtureSession { request in
                let fields = try self.form(request)
                let expected = "80" + String(repeating: "ab", count: length - 1)
                XCTAssertEqual(fields["xfData"], expected)
                XCTAssertEqual(fields["signature"], KailuSigner.signUpload(loginCode: "token+one", telephone: "13800138000", xfData: expected))
                return try self.response(["errorCode": 209, "data": ["clData": ""]])
            }
            let receipt = try await QzxyAPI(session: fixture).uploadConsumption(extended, state: state, session: auth)
            XCTAssertEqual(receipt.clData, "")
            fixture.invalidateAndCancel()
        }
    }

    func testRecordedUploadKeepsEmptyOrAbsentWritebackInsteadOfLosingAccountingReceipt() async throws {
        for data in [["clData": "", "consumeMoney": "00123"], ["consumeMoney": "00123"]] {
            let fixture = fixtureSession { _ in try self.response(["errorCode": 209, "data": data]) }
            let receipt = try await QzxyAPI(session: fixture).uploadConsumption(payload, state: state, session: auth)
            XCTAssertEqual(receipt.clData, "")
            XCTAssertEqual(receipt.amountRaw, "00123")
            fixture.invalidateAndCancel()
        }
    }

    func testUploadExplicitRejectionIsNotRetried() async throws {
        var count = 0
        let fixture = fixtureSession { _ in
            count += 1
            return try self.response(["success": false, "errorCode": 170, "message": "rejected"])
        }
        defer { fixture.invalidateAndCancel() }
        do {
            _ = try await QzxyAPI(session: fixture).uploadConsumption(payload, state: state, session: auth)
            XCTFail("Expected rejection")
        } catch WaterError.rejected { }
        XCTAssertEqual(count, 1)
    }

    func testUncertainUploadResponsesRemainAmbiguousAndAreNotRetried() async throws {
        for kind in 0..<7 {
            var count = 0
            let fixture = fixtureSession { _ in
                count += 1
                switch kind {
                case 0: throw URLError(.timedOut)
                case 1: return (200, Data("not JSON".utf8))
                case 2: return (503, Data("unavailable".utf8))
                case 3: return try self.response(["success": true, "errorCode": 0])
                case 4: return try self.response(["success": true, "data": ["clData": "receipt"]])
                case 5: return try self.response(["success": true, "errorCode": false, "data": ["clData": "receipt"]])
                default: return try self.response(["success": true, "errorCode": 0.5, "data": ["clData": "receipt"]])
                }
            }
            await assertAmbiguous {
                _ = try await QzxyAPI(session: fixture).uploadConsumption(self.payload, state: self.state, session: self.auth)
            }
            XCTAssertEqual(count, 1)
            fixture.invalidateAndCancel()
        }
    }

    func testFailureReportEscapesLiteralPlusAndSignsOriginalTimestamp() async throws {
        let fixture = fixtureSession { request in
            XCTAssertEqual(request.url?.path, "/order/upload/bluetooth/fail")
            XCTAssertEqual(request.httpMethod, "POST")
            let fields = try self.form(request)
            XCTAssertEqual(fields["consumeDate"], "2026+11/04 12:00:00")
            XCTAssertEqual(fields["signature"], "4ad22c00c7517c17c75629303f3fc139")
            self.assertAuth(request, fields: fields)
            return try self.response(["success": true, "errorCode": 0])
        }
        defer { fixture.invalidateAndCancel() }
        try await QzxyAPI(session: fixture).reportFailure(consumeDate: "2026+11/04 12:00:00", session: auth)
    }

    func testFailureReportTransportFailureIsNotRetried() async throws {
        var count = 0
        let fixture = fixtureSession { _ in
            count += 1
            throw URLError(.timedOut)
        }
        defer { fixture.invalidateAndCancel() }
        await assertAmbiguous {
            try await QzxyAPI(session: fixture).reportFailure(consumeDate: "date", session: self.auth)
        }
        XCTAssertEqual(count, 1)
    }

    func testInvalidConsumptionAndEmptyFailureDateDoNotSubmitRequests() async throws {
        var count = 0
        let fixture = fixtureSession { _ in
            count += 1
            return try self.response(["success": true, "errorCode": 0, "data": [:]])
        }
        defer { fixture.invalidateAndCancel() }
        for invalid in [Data(), Data([0x80]), Data(repeating: 0, count: 42)] {
            do {
                _ = try await QzxyAPI(session: fixture).uploadConsumption(invalid, state: state, session: auth)
                XCTFail("Accepted invalid consumption")
            } catch WaterError.invalid { }
        }
        do {
            try await QzxyAPI(session: fixture).reportFailure(consumeDate: " \n", session: auth)
            XCTFail("Accepted empty failure timestamp")
        } catch WaterError.invalid { }
        XCTAssertEqual(count, 0)
    }

    func testLoginPublishesLoadingBeforeValidationAndDeduplicatesSubmission() async throws {
        let started = expectation(description: "Mock request started")
        let fixture = fixtureSession { request in
            XCTAssertEqual(request.url?.path, "/user/registerAndLogin")
            Thread.sleep(forTimeInterval: 0.15)
            return try self.response([
                "success": true, "data": ["loginCode": "fixture", "userId": 7,
                                           "userAccount": ["accountId": 8, "projectId": 9]]
            ])
        }
        defer { fixture.invalidateAndCancel() }
        let storage = LoginTestStorage()
        let manager = AuthManager(api: QzxyAPI(session: fixture), storage: storage.storage)
        defer { manager.logout() }

        let trace = LatencyTrace("mock_login_session", report: { print($0) })
        trace.onStage = { if $0 == "request_started" { started.fulfill() } }
        trace.mark("tap")
        let login = Task { await manager.login(phone: "13800138000", secret: "123456", usePassword: false, trace: trace) }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(manager.loading)
        XCTAssertNil(manager.session)
        XCTAssertNil(storage.data)
        await manager.login(phone: "13800138000", secret: "654321", usePassword: false)
        XCTAssertTrue(manager.loading)
        await login.value
        XCTAssertFalse(manager.loading)
        XCTAssertNotNil(manager.session)
        XCTAssertNotNil(storage.data)
        manager.homeAppeared()
    }

    func testRejectedLoginDoesNotPublishOrSaveSession() async {
        let fixture = fixtureSession { _ in
            try self.response(["success": false, "errorMessage": "验证码错误"])
        }
        defer { fixture.invalidateAndCancel() }
        let storage = LoginTestStorage()
        let manager = AuthManager(api: QzxyAPI(session: fixture), storage: storage.storage)
        defer { manager.logout() }
        await manager.login(phone: "13800138000", secret: "123456", usePassword: false)
        XCTAssertNil(manager.session)
        XCTAssertNil(storage.data)
        XCTAssertFalse(manager.loading)
        XCTAssertTrue(manager.activity.contains("验证码错误"))
    }

    func testFailedSecureStorageDoesNotPublishValidatedLogin() async {
        let fixture = fixtureSession { _ in
            try self.response(["success": true, "data": ["loginCode": "fixture", "userId": 7,
                                                           "userAccount": ["accountId": 8, "projectId": 9]]])
        }
        defer { fixture.invalidateAndCancel() }
        let storage = LoginTestStorage()
        storage.rejectsWrites = true
        let manager = AuthManager(api: QzxyAPI(session: fixture), storage: storage.storage)
        await manager.login(phone: "13800138000", secret: "123456", usePassword: false)
        XCTAssertNil(manager.session)
        XCTAssertNil(storage.data)
        XCTAssertFalse(manager.loading)
        XCTAssertTrue(manager.activity.contains("会话未能安全保存"))
    }

    @MainActor private final class LoginTestStorage {
        var data: Data?
        var rejectsWrites = false
        var storage: AuthManager.SessionStorage {
            AuthManager.SessionStorage(load: { self.data }, save: { data in
                guard !self.rejectsWrites else { return false }
                self.data = data
                return true
            }, delete: { self.data = nil })
        }
    }

    func testMockLoginThroughRealHomeWithCachedBills() async throws {
        let project = "9"
        let account = UUID().uuidString
        let owner = QzxySession(telephone: "13800138000", loginCode: "fixture", userId: "7",
                                accountId: account, projectId: project).ownerScope
        let cacheKey = "replica.\(owner).balance"
        let accountKey = "replica.\(owner).account"
        let cache = CampusBalanceSnapshot(ownerScope: owner, campusBalance: 10, bills: (0..<1_500).map { index in
            CampusBill(orderId: String(index), consumeDate: "2026-10-12 12:00:00", consumeMoney: "0.41", description: "测试账单")
        })
        UserDefaults.standard.set(try JSONEncoder().encode(cache), forKey: cacheKey)

        let fixture = fixtureSession { request in
            if request.url?.path == "/user/registerAndLogin" {
                Thread.sleep(forTimeInterval: 0.15)
                return try self.response([
                    "success": true, "data": ["loginCode": "fixture", "userId": 7,
                                               "userAccount": ["accountId": account, "projectId": project]]
                ])
            }
            Thread.sleep(forTimeInterval: 0.30)
            return try self.response(["success": true, "data": NSNull()])
        }
        let network = QzxyAPI(session: fixture)
        let storage = LoginTestStorage()
        let auth = AuthManager(api: network, storage: storage.storage)
        let cloud = CloudShowerController(api: network, mqttEnabled: false)
        let model = OriginalAppModel(authentication: auth, network: network, cloudController: cloud)
        let refreshCompleted = expectation(description: "Initial account refresh finished")
        var beganRefresh = false
        var finishedRefresh = false
        let refreshObservation = model.$refreshing.sink { refreshing in
            if refreshing { beganRefresh = true }
            else if beganRefresh && !finishedRefresh {
                finishedRefresh = true
                refreshCompleted.fulfill()
            }
        }
        defer { refreshObservation.cancel() }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: OriginalRootView(model: model))
        window.makeKeyAndVisible()
        defer {
            model.setForeground(false)
            auth.logout()
            window.isHidden = true
            previous?.makeKey()
            if finishedRefresh { fixture.invalidateAndCancel() }
            UserDefaults.standard.removeObject(forKey: cacheKey)
            UserDefaults.standard.removeObject(forKey: accountKey)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        let visible = expectation(description: "Production home appeared")
        let trace = LatencyTrace("mock_login_home", report: { print($0) })
        trace.onStage = { stage in
            if stage == "home_visible" {
                XCTAssertFalse(finishedRefresh)
                XCTAssertEqual(model.bills.count, 0)
                print("LATENCY mock_login_home_cache bills=\(model.bills.count)")
                visible.fulfill()
            }
        }
        trace.mark("tap")
        await auth.login(phone: "13800138000", secret: "123456", usePassword: false, trace: trace)
        await fulfillment(of: [visible], timeout: 5)
        XCTAssertEqual(auth.session?.ownerScope, owner)
        await fulfillment(of: [refreshCompleted], timeout: 10)
        XCTAssertEqual(model.balance?.campusBalance, 10)
    }

    func testSMSLoginKeepsLegacyFieldsAndDecodesSharedSession() async throws {
        let fixture = fixtureSession { request in
            XCTAssertEqual(request.url?.path, "/user/registerAndLogin")
            let fields = try self.form(request)
            XCTAssertEqual(fields["smsCode"], "12+34")
            XCTAssertEqual(fields["type"], "5")
            XCTAssertEqual(fields["phoneSystem"], "android")
            XCTAssertEqual(fields["version"], "6.5.28")
            return try self.response(["success": true, "data": [
                "loginCode": "token+one", "userId": 7,
                "userAccount": ["accountId": 8, "projectId": 9]
            ]])
        }
        defer { fixture.invalidateAndCancel() }
        let trace = LatencyTrace("mock_sms_response", report: { print($0) })
        trace.mark("tap")
        let result = try await QzxyAPI(session: fixture).loginWithSMS(phone: auth.telephone, code: "12+34", trace: trace)
        trace.finish("validated")
        XCTAssertEqual(result.ownerScope, "9:8:7")
        XCTAssertEqual(result.loginCode, "token+one")
    }

    private func assertAmbiguous(_ operation: () async throws -> Void,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await operation()
            XCTFail("Expected uncertain outcome", file: file, line: line)
        } catch WaterError.rejected {
            XCTFail("An uncertain result must not be treated as explicit rejection", file: file, line: line)
        } catch { }
    }

    nonisolated private func assertAuth(_ request: URLRequest, fields: [String: String],
                            file: StaticString = #filePath, line: UInt = #line) {
        for (key, value) in ["loginCode": "token+one", "telephone": "13800138000", "telPhone": "13800138000",
                             "userId": "7", "accountId": "8", "projectId": "9", "phoneSystem": "android", "version": "6.5.28"] {
            XCTAssertEqual(fields[key], value, file: file, line: line)
        }
        XCTAssertEqual(request.value(forHTTPHeaderField: "Config-Project"), "9", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Config-Keys"),
                       "module_list,advertise_type,question_list,service_phone_list,banner_list_app,activity_list_app,aliCard_popup_config",
                       file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded", file: file, line: line)
    }

    nonisolated private func form(_ request: URLRequest) throws -> [String: String] {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            body = bytes
        }
        let text = try XCTUnwrap(String(data: try XCTUnwrap(body), encoding: .utf8))
        return Dictionary(uniqueKeysWithValues: try text.split(separator: "&").map { field in
            let parts = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = try XCTUnwrap(String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding)
            let value = try XCTUnwrap(String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding)
            return (key, value)
        })
    }

    nonisolated private func response(_ json: [String: Any]) throws -> (Int, Data) {
        (200, try JSONSerialization.data(withJSONObject: json))
    }

    // The only replaced boundary is HTTP delivery. Each session gets its own fixture,
    // so tests cannot accidentally issue a request to the real service.
    private func fixtureSession(_ handler: @escaping (URLRequest) throws -> (Int, Data)) -> URLSession {
        let key = UUID().uuidString
        QzxyFixtureProtocol.install(handler, key: key)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QzxyFixtureProtocol.self]
        config.httpAdditionalHeaders = ["X-Qzxy-Fixture": key]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        QzxyFixtureProtocol.clear()
        super.tearDown()
    }
}

private final class QzxyFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest) throws -> (Int, Data)] = [:]

    static func install(_ handler: @escaping (URLRequest) throws -> (Int, Data), key: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers[key] = handler
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handlers[request.value(forHTTPHeaderField: "X-Qzxy-Fixture") ?? ""]
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                            headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { }
}

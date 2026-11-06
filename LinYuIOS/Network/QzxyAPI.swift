import Foundation
import CoreFoundation

struct QzxyResponse {
    let json: [String: Any]
    var explicitSuccess: Bool? {
        guard let value = json["success"] as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
    var success: Bool { explicitSuccess == true }
    var errorCode: Int? {
        guard let value = json["errorCode"] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return Int(value.stringValue)
    }
    var data: [String: Any]? { json["data"] as? [String: Any] }
    var message: String {
        (json["errorMessage"] as? String)
        ?? (json["msg"] as? String)
        ?? (json["displayMessage"] as? String)
        ?? (json["message"] as? String)
        ?? "服务端返回未知错误"
    }
}

enum QzxyError: LocalizedError {
    case invalidResponse
    case invalidLoginData
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "响应数据无法解析"
        case .invalidLoginData: return "服务端登录响应缺少必要字段"
        case .server(let detail): return detail
        }
    }
}

/// 仅使用原仓库公开记录的接口；不收集、更不会上传第三方分析服务。
struct QzxyAPI: WaterMeterService {
    private let baseURL = URL(string: "https://v3-api.china-qzxy.cn")!
    private let client: URLSession
    private let apiVersion = "6.5.28"
    private let configKeys = "module_list,advertise_type,question_list,service_phone_list,banner_list_app,activity_list_app,aliCard_popup_config"

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        client = session
    }

    func sendSMS(to phone: String) async throws {
        guard phone.count >= 7 else { throw QzxyError.server("请填写有效手机号") }
        let secret = KailuSigner.md5(String(phone.prefix(3)) + String(phone.suffix(4)) + "klcx")
        let r = try await request("/user/verification/code/get", query: [
            "telephone": phone, "secret": secret, "typeId": "3", "platform": "1"
        ])
        guard r.success else { throw QzxyError.server(r.message) }
    }

    func loginWithSMS(phone: String, code: String, trace: LatencyTrace? = nil) async throws -> QzxySession {
        let response = try await request("/user/registerAndLogin", post: [
            "telephone": phone, "smsCode": code, "type": "5",
            "phoneSystem": "android", "version": apiVersion
        ], trace: trace)
        let validated = try loginData(from: response, phone: phone)
        await trace?.mark("session_validated")
        return validated
    }

    func loginWithPassword(phone: String, password: String, trace: LatencyTrace? = nil) async throws -> QzxySession {
        let hash = String(KailuSigner.md5(password).suffix(10)).uppercased()
        let response = try await request("/user/login", post: [
            "telephone": phone, "password": hash, "phoneSystem": "android",
            "type": "0", "version": apiVersion
        ], trace: trace)
        let validated = try loginData(from: response, phone: phone)
        await trace?.mark("session_validated")
        return validated
    }

    func wallet(session: QzxySession) async throws -> QzxyResponse {
        let response = try await request("/account/wallet", session: session)
        guard response.success else { throw QzxyError.server(response.message) }
        return response
    }

    /// 原版使用 MAC 查台账；iOS 使用状态帧自报地址寻找同一台账设备。
    func findDevice(ledgerMAC: String, session: QzxySession) async throws -> QzxyResponse {
        let mac = ledgerMAC.replacingOccurrences(of: ":", with: "")
                           .replacingOccurrences(of: "-", with: "")
        guard mac.count == 12, mac.uppercased().allSatisfy({ "0123456789ABCDEF".contains($0) }) else {
            throw QzxyError.server("请填入 12 位十六进制台账 MAC")
        }
        let response = try await request("/device/info/mac", query: ["macAddress": mac], session: session)
        guard response.success else { throw QzxyError.server(response.message) }
        return response
    }

    /// 设备标识来自台账；类型缺失时与原版一样使用 0。
    @MainActor func ledgerDevice(ledgerMAC: String, session: QzxySession) async throws -> LedgerDevice {
        guard let requestedMAC = LedgerDevice.normalizeMAC(ledgerMAC) else {
            throw WaterError.invalid("请填入 12 位十六进制台账 MAC")
        }
        let response = try await findDevice(ledgerMAC: requestedMAC, session: session)
        guard let data = response.data,
              let deviceId = nonemptyText(data["deviceId"]),
              let snCode = nonemptyText(data["snCode"]),
              let macText = nonemptyText(data["macAddress"]),
              let mac = LedgerDevice.normalizeMAC(macText) else {
            throw WaterError.invalid("服务端台账缺少必要设备标识")
        }
        let realMac: String?
        if let raw = nonemptyText(data["realMac"]) {
            guard let normalized = LedgerDevice.normalizeMAC(raw) else {
                throw WaterError.invalid("服务端台账真实 MAC 无效")
            }
            realMac = normalized
        } else { realMac = nil }
        return LedgerDevice(deviceId: deviceId, snCode: snCode,
                            name: nonemptyText(data["deviceName"]) ?? snCode,
                            macAddress: mac, realMac: realMac,
                            bigTypeId: nonemptyText(data["bigTypeId"]) ?? "0",
                            smallTypeId: nonemptyText(data["smallTypeId"]) ?? "0")
    }

    @MainActor func grantRate(device: LedgerDevice, state: BleDeviceState,
                              session: QzxySession) async throws -> RateGrant {
        guard !device.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !device.snCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              LedgerDevice.normalizeMAC(device.macAddress) != nil,
              !device.apiMAC.isEmpty else { throw WaterError.identity }
        let response = try await rateOrder(session: session, deviceId: device.deviceId,
                                            mac: device.apiMAC,
                                            macType: KailuSigner.macType(deviceType: state.deviceType, a1: state.a1),
                                            bigTypeId: device.bigTypeId.isEmpty ? "0" : device.bigTypeId,
                                            smallTypeId: device.smallTypeId.isEmpty ? "0" : device.smallTypeId,
                                            state: state)
        try requireTransactionSuccess(response)
        guard let data = response.data,
              let hex = data["downData"] as? String,
              let bytes = Data(hex: hex), (1...252).contains(bytes.count) else {
            // A successful but malformed response may still have created an order.
            throw QzxyError.invalidResponse
        }
        return RateGrant(downData: bytes, consumeDate: text(data["consumeDate"]) ?? "",
                         orderNo: nonemptyText(data["orderNo"]) ?? nonemptyText(data["liquidOrderNo"]) ?? "")
    }

    @MainActor func uploadConsumption(_ payload: Data, state: BleDeviceState,
                                      session: QzxySession) async throws -> SettlementReceipt {
        guard payload.count >= 42, payload.first == 0x80 else {
            throw WaterError.invalid("设备消费数据无效，已停止上传")
        }
        let xfData = payload.hexLowercased
        guard let signature = KailuSigner.signUpload(loginCode: session.loginCode,
                                                      telephone: session.telephone, xfData: xfData) else {
            throw WaterError.invalid("签名参数不完整")
        }
        let response = try await request("/order/upload/bluetooth/data", post: [
            "protocolType": state.protocolType, "randomNumber": state.randomNumber.lowercased(),
            "xfData": xfData, "signature": signature
        ], session: session)
        guard let code = response.errorCode else {
            if response.explicitSuccess == false { throw WaterError.rejected(response.message) }
            throw QzxyError.invalidResponse
        }
        guard [0, 206, 209].contains(code) else { throw WaterError.rejected(response.message) }
        guard let data = response.data else { throw QzxyError.invalidResponse }
        // Accounting is confirmed independently of whether device writeback is possible.
        return SettlementReceipt(clData: data["clData"] as? String ?? "",
                                 amountRaw: text(data["upMoney"]) ?? text(data["consumeMoney"]))
    }

    @MainActor func hasRecordedConsumption(_ transaction: WaterTransaction, session: QzxySession) async throws -> Bool {
        guard transaction.binding.ownerScope == session.ownerScope, !session.loginCode.isEmpty else {
            throw WaterError.identity
        }
        let orderNo = transaction.orderNo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !orderNo.isEmpty else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM"
        let localDate = Self.settlementBillDate(transaction.consumeDate, timeZone: formatter.timeZone)
        let month = formatter.string(from: localDate ?? transaction.startedAt ?? transaction.updatedAt)
        let rows = try await bills(month: month, session: session)
        let exactOrders = rows.filter { $0.orderNo == orderNo }
        let matches = exactOrders.isEmpty
            ? rows.filter { OriginalJSON.nonempty($0.orderNo) == nil && $0.orderId == orderNo }
            : exactOrders
        guard matches.count == 1, let bill = matches.first, bill.amount.isFinite, bill.amount > 0 else {
            // Missing and zero-amount rows may be delayed or pending and never authorize replay.
            return false
        }
        let billDate = Self.settlementBillDate(bill.consumeDate, timeZone: formatter.timeZone)
        if let localDate, let billDate, abs(localDate.timeIntervalSince(billDate)) >= 1 { return false }

        let serial = transaction.binding.device.snCode
        if let billSerial = bill.deviceSnCode { return !serial.isEmpty && billSerial == serial }
        if localDate != nil, billDate != nil { return true }

        // If the timestamp cannot corroborate the order, require the existing read-only
        // detail response to link the bill to this meter before persisting a positive match.
        let detail = try await billDetail(orderId: bill.orderId, consumeDate: bill.consumeDate, session: session)
        return !serial.isEmpty && detail.deviceSnCode == serial
            && (detail.orderId == bill.orderId || detail.orderNo == orderNo)
    }

    private static func settlementBillDate(_ value: String, timeZone: TimeZone) -> Date? {
        if value.range(of: #"^[0-9]{12}$"#, options: .regularExpression) != nil {
            let parts = Array(value)
            let day = "20\(String(parts[0..<2]))-\(String(parts[2..<4]))-\(String(parts[4..<6]))"
            let time = "\(String(parts[6..<8])):\(String(parts[8..<10])):\(String(parts[10..<12]))"
            return OriginalFormatting.billDate("\(day) \(time)", timeZone: timeZone)
        }
        return OriginalFormatting.billDate(value, timeZone: timeZone)
    }

    @MainActor func reportFailure(consumeDate: String, session: QzxySession) async throws {
        guard !consumeDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let signature = KailuSigner.signFail(loginCode: session.loginCode,
                                                    telephone: session.telephone, consumeDate: consumeDate) else {
            throw WaterError.invalid("失败上报缺少消费时间或签名参数")
        }
        let response = try await request("/order/upload/bluetooth/fail", post: [
            "consumeDate": consumeDate, "signature": signature
        ], session: session)
        try requireTransactionSuccess(response)
    }

    /// 原始响应接口保留给现有调用方；事务流程使用 grantRate 校验载荷。
    func rateOrder(session: QzxySession, deviceId: String, mac: String,
                   macType: String, bigTypeId: String, smallTypeId: String,
                   state: BleDeviceState) async throws -> QzxyResponse {
        guard let signature = KailuSigner.signRateOrder(
            loginCode: session.loginCode, telephone: session.telephone,
            deviceId: deviceId, xfModel: "0", randomNumber: state.randomNumber
        ) else { throw QzxyError.server("签名参数不完整") }
        return try await request("/order/downRate/bluetooth/rateOrder", post: [
            "deviceId": deviceId, "macAddress": mac,
            "macType": macType, "bigTypeId": bigTypeId, "smallTypeId": smallTypeId,
            "protocolType": state.protocolType, "randomNumber": state.randomNumber.lowercased(),
            "xfModel": "0", "signature": signature
        ], session: session)
    }

    private func loginData(from response: QzxyResponse, phone: String) throws -> QzxySession {
        guard response.success else { throw QzxyError.server(response.message) }
        guard let data = response.data, let account = data["userAccount"] as? [String: Any],
              let token = data["loginCode"] as? String, !token.isEmpty,
              let userId = text(data["userId"]),
              let accountId = text(account["accountId"]),
              let projectId = text(account["projectId"]) else {
            throw QzxyError.invalidLoginData
        }
        return QzxySession(telephone: phone, loginCode: token, userId: userId,
                           accountId: accountId, projectId: projectId)
    }

    private func text(_ value: Any?) -> String? {
        if let v = value as? String { return v }
        if let v = value as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID() { return v.stringValue }
        return nil
    }

    private func nonemptyText(_ value: Any?) -> String? {
        guard let value = text(value), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func requireTransactionSuccess(_ response: QzxyResponse) throws {
        if response.success {
            if response.json["errorCode"] != nil, response.errorCode != 0 { throw QzxyError.invalidResponse }
            return
        }
        if response.explicitSuccess == false || response.errorCode.map({ $0 != 0 }) == true {
            throw WaterError.rejected(response.message)
        }
        throw QzxyError.invalidResponse
    }

    private func formEncoded(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = fields.keys.sorted().map { key in
            key.addingPercentEncoding(withAllowedCharacters: allowed)! + "="
                + fields[key]!.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    func originalRequest(_ path: String, query: [String: String] = [:],
                         post: [String: String]? = nil, session: QzxySession? = nil,
                         jsonBody: [String: Any]? = nil) async throws -> QzxyResponse {
        if let jsonBody {
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            request.httpMethod = "POST"; request.timeoutInterval = 15
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            if let session, !session.projectId.isEmpty, session.projectId != "0" {
                request.setValue(session.projectId, forHTTPHeaderField: "Config-Project")
                request.setValue(configKeys, forHTTPHeaderField: "Config-Keys")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            let (data, response) = try await client.data(for: request)
            if let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
                throw QzxyError.server("HTTP \(http.statusCode)")
            }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QzxyError.invalidResponse }
            return QzxyResponse(json: json)
        }
        return try await request(path, query: query, post: post, session: session)
    }

    private func request(_ path: String, query: [String: String] = [:],
                         post: [String: String]? = nil,
                         session: QzxySession? = nil, trace: LatencyTrace? = nil) async throws -> QzxyResponse {
        var fields = query
        let authentication: [String: String]
        if let session = session {
            authentication = ["loginCode": session.loginCode, "userId": session.userId,
                              "accountId": session.accountId, "projectId": session.projectId,
                              "telephone": session.telephone, "telPhone": session.telephone,
                              "phoneSystem": "android", "version": apiVersion]
        } else { authentication = [:] }
        if post == nil && !path.contains("verification") { fields.merge(authentication, uniquingKeysWith: { old, _ in old }) }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !fields.isEmpty { components.queryItems = fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw QzxyError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let session = session, !session.projectId.isEmpty, session.projectId != "0" {
            request.setValue(session.projectId, forHTTPHeaderField: "Config-Project")
            request.setValue(configKeys, forHTTPHeaderField: "Config-Keys")
        }
        if let post = post {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let merged = post.merging(authentication, uniquingKeysWith: { old, _ in old })
            request.httpBody = formEncoded(merged)
        }
        await trace?.mark("request_started")
        let (data, response) = try await client.data(for: request)
        await trace?.mark("response_received")
        if let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
            throw QzxyError.server("HTTP \(http.statusCode)")
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QzxyError.invalidResponse
        }
        return QzxyResponse(json: obj)
    }
}

import Foundation

extension QzxyAPI {
    /// The three original identity sources complement one another when a school has not synced a field.
    func profile(session: QzxySession) async throws -> CampusProfile {
        var profile = CampusProfile()
        if let data = try await optionalOriginalData("/account/info", session: session) {
            profile.name = OriginalJSON.nonempty(OriginalJSON.text(data["name"]))
            profile.studentNumber = OriginalJSON.nonempty(OriginalJSON.text(data["idCardNumber"]))
            profile.telephone = OriginalJSON.text(data["telephone"])
            profile.genderName = OriginalJSON.text(data["genderName"])
            profile.cardStatus = OriginalJSON.int(data["cardStatus"])
            profile.cardStatusName = OriginalJSON.text(data["cardStatusName"])
            profile.gradeName = OriginalJSON.text(data["gradeName"])
            profile.className = OriginalJSON.text(data["className"])
        }
        if profile.name == nil || profile.studentNumber == nil {
            if let data = try await optionalOriginalData("/account/card/getBindCardInfo", session: session) {
                profile.name = profile.name ?? OriginalJSON.nonempty(OriginalJSON.text(data["name"]))
                profile.studentNumber = profile.studentNumber ?? OriginalJSON.nonempty(OriginalJSON.text(data["idCardNumber"]))
            }
        }
        if let data = try await optionalOriginalData("/settlement/campus/userInfo", session: session) {
            profile.name = profile.name ?? OriginalJSON.nonempty(OriginalJSON.text(data["studentName"]))
            profile.studentNumber = profile.studentNumber ?? OriginalJSON.nonempty(OriginalJSON.text(data["studentNumber"]))
        }
        if let data = try await optionalOriginalData("/project/info/triple", session: session) {
            profile.schoolName = OriginalJSON.nonempty(OriginalJSON.text(data["projectName"]))
        }
        return profile
    }

    func campusWallet(session: QzxySession) async throws -> CampusWallet {
        var wallet = CampusWallet()
        if let data = try await optionalOriginalData("/account/wallet", session: session) {
            // accountRealMoney is in milli-yuan. The original app deliberately uses money in yuan.
            wallet.walletBalance = OriginalJSON.number(data["money"])
        }
        if let data = try await optionalOriginalData("/settlement/campus/userInfo", session: session) {
            wallet.campusBalance = OriginalJSON.number(data["amount"])
            wallet.signStatus = OriginalJSON.int(data["signStatus"])
        }
        return wallet
    }

    func bills(month: String, session: QzxySession) async throws -> [CampusBill] {
        let response = try await originalRequest("/order/query/account/bill/list", query: ["month": month, "billRequestType": "2"], session: session)
        try requireOriginalSuccess(response)
        guard let rows = response.json["data"] as? [[String: Any]] else {
            if response.json["data"] == nil || response.json["data"] is NSNull { return [] }
            throw QzxyError.invalidResponse
        }
        return try rows.map { row in
            guard let data = row["consumeBillDTO"] as? [String: Any],
                  let id = OriginalJSON.text(data["orderId"]), let date = OriginalJSON.text(data["consumeDate"]),
                  let money = OriginalJSON.text(data["consumeMoney"]), let description = OriginalJSON.text(data["description"]) else { throw QzxyError.invalidResponse }
            return CampusBill(orderId: id, consumeDate: date, consumeMoney: money, description: description,
                              orderNo: OriginalJSON.text(data["orderNo"]))
        }
    }

    func billDetail(orderId: String, consumeDate: String, session: QzxySession) async throws -> CampusBillDetail {
        let response = try await originalRequest("/order/query/account/bill/detail", query: ["orderId": orderId, "consumeDate": consumeDate], session: session)
        let data = try originalData(response)
        return CampusBillDetail(orderId: OriginalJSON.text(data["orderId"]), consumeDate: OriginalJSON.text(data["consumeDate"]),
            consumeMoney: OriginalJSON.number(data["consumeMoney"]) ?? 0, description: OriginalJSON.text(data["description"]),
            deviceSnCode: OriginalJSON.text(data["deviceSnCode"]), orderNo: OriginalJSON.text(data["orderNo"]),
            preDeductMoney: OriginalJSON.number(data["preDeductMoney"]) ?? 0)
    }

    func unpaidBills(session: QzxySession) async throws -> [CampusUnpaidBill] {
        let response = try await originalRequest("/order/weixinScorePay/unPay/queryBill", post: [:], session: session)
        try requireOriginalSuccess(response)
        guard let rows = response.json["data"] as? [[String: Any]] else {
            if response.json["data"] == nil || response.json["data"] is NSNull { return [] }
            throw QzxyError.invalidResponse
        }
        return rows.map { data in
            CampusUnpaidBill(orderId: OriginalJSON.text(data["orderId"]), orderNo: OriginalJSON.text(data["orderNo"]),
                consumeDate: OriginalJSON.text(data["consumeDate"]), consumeMoney: OriginalJSON.text(data["consumeMoney"]),
                description: OriginalJSON.text(data["description"]))
        }
    }

    /// Caller must hold its in-flight lock and requery unpaidBills after .unknown; never blindly retry.
    func requestDeduct(consumeDate: String, confirmed: Bool, session: QzxySession) async throws -> CampusDeductResult {
        guard confirmed else { throw WaterError.invalid("请先确认这笔账单的代扣") }
        guard OriginalJSON.nonempty(consumeDate) != nil else { throw WaterError.invalid("账单缺少消费日期") }
        do {
            // This H5 endpoint is JSON with exactly these fields, not the usual Android form body.
            let response = try await originalRequest("/order/thirdTrade/single/json/pay", session: session, jsonBody: [
                "deductType": 7, "consumeDate": consumeDate, "projectId": session.projectId,
                "accountId": session.accountId, "loginCode": session.loginCode, "userId": session.userId,
                "phoneSystem": "WeChat"
            ])
            if response.success { return .success }
            if response.explicitSuccess == false { return .failed(OriginalJSON.message(response)) }
            return .unknown
        } catch {
            // Timeouts, cancellation and invalid replies may all happen after the server has deducted.
            return .unknown
        }
    }

    func useCode(session: QzxySession) async throws -> CampusUseCode {
        let data = try originalData(await originalRequest("/account/useCode/new", session: session))
        return CampusUseCode(useCode: OriginalJSON.text(data["useCode"]), useCodeStatus: OriginalJSON.int(data["useCodeStatus"]),
            useCodeRandom: OriginalJSON.text(data["useCodeRandom"]), useCodeStartTime: OriginalJSON.text(data["useCodeStartTime"]),
            resetAvailability: OriginalJSON.int(data["resetAvailability"]), resetAvailabilityWarMark: OriginalJSON.text(data["resetAvailabilityWarMark"]))
    }

    /// Generates a three-minute candidate only; activation is exclusively claimUseCode.
    func generateUseCode(session: QzxySession) async throws -> CampusCodeCandidate {
        let data = try originalData(await originalRequest("/account/useCode/new/generate", post: [:], session: session))
        guard let code = OriginalJSON.nonempty(OriginalJSON.text(data["useCode"])) else { throw QzxyError.invalidResponse }
        return CampusCodeCandidate(useCode: code, remainTimes: OriginalJSON.int(data["remainTimes"]) ?? 0)
    }

    func claimUseCode(_ useCode: String, session: QzxySession) async throws {
        try requireOriginalSuccess(await originalRequest("/account/useCode/new/set", post: ["useCode": useCode], session: session))
    }

    func updateUseCodeStatus(_ status: Int, session: QzxySession) async throws {
        try requireOriginalSuccess(await originalRequest("/account/useCode/new/status/update", post: ["useCodeStatus": String(status)], session: session))
    }

    func sendAccountSMS(to phone: String, purpose: CampusSMSPurpose, session: QzxySession) async throws {
        guard phone.count >= 7 else { throw QzxyError.server("请填写有效手机号") }
        let secret = KailuSigner.md5(String(phone.prefix(3)) + String(phone.suffix(4)) + "klcx")
        try requireOriginalSuccess(await originalRequest("/user/verification/code/get", query: [
            "telephone": phone, "secret": secret, "typeId": String(purpose.rawValue), "platform": "1"
        ], session: session))
    }

    func updatePhone(newTelephone: String, code: String, session: QzxySession) async throws {
        try requireOriginalSuccess(await originalRequest("/user/phone/update", post: ["newTelephone": newTelephone, "code": code], session: session))
    }

    func updatePassword(oldPassword: String, newPassword: String, session: QzxySession) async throws {
        try requireOriginalSuccess(await originalRequest("/user/password/update", post: [
            "oldPassword": originalPassword(oldPassword), "password": originalPassword(newPassword)
        ], session: session))
    }

    func forgetPassword(password: String, code: String, session: QzxySession) async throws {
        try requireOriginalSuccess(await originalRequest("/user/password/forget", post: ["password": originalPassword(password), "code": code], session: session))
    }

    func deviceByMAC(_ mac: String, session: QzxySession) async throws -> CampusDevice? {
        guard OriginalJSON.nonempty(mac) != nil else { return nil }
        for candidate in OriginalFormatting.macLookupVariants(mac) {
            let response = try await originalRequest("/device/info/mac", query: ["macAddress": candidate], session: session)
            try requireOriginalSuccess(response)
            guard let data = response.data else {
                if response.json["data"] == nil || response.json["data"] is NSNull { continue }
                throw QzxyError.invalidResponse
            }
            return CampusDevice(deviceId: OriginalJSON.text(data["deviceId"]) ?? "", deviceName: OriginalJSON.text(data["deviceName"]) ?? "",
                snCode: OriginalJSON.text(data["snCode"]) ?? "", macAddress: OriginalJSON.text(data["macAddress"]) ?? "",
                withholdMoney: OriginalJSON.number(data["withholdMoney"]), onlineStatusId: OriginalJSON.int(data["onlineStatusId"]),
                bigTypeId: OriginalJSON.text(data["bigTypeId"]), bigTypeName: OriginalJSON.text(data["bigTypeName"]),
                smallTypeId: OriginalJSON.text(data["smallTypeId"]), smallTypeName: OriginalJSON.text(data["smallTypeName"]),
                isBle: OriginalJSON.bool(data["isBle"]), communicationTypeId: OriginalJSON.int(data["communicationTypeId"]),
                realMac: OriginalJSON.text(data["realMac"]))
        }
        return nil
    }

    /// Android names the QR result snCode, but passes that 12-hex address to /device/info/mac.
    /// There is no SN lookup endpoint in the pinned service.
    func deviceBySN(_ scannedCode: String, session: QzxySession) async throws -> CampusDevice? {
        guard let mac = OriginalFormatting.parseSnCode(scannedCode) else { throw WaterError.invalid("设备码需要为 12 位十六进制地址") }
        return try await deviceByMAC(mac, session: session)
    }

    private func originalPassword(_ password: String) -> String { String(KailuSigner.md5(password).suffix(10)).uppercased() }

    private func requireOriginalSuccess(_ response: QzxyResponse) throws {
        guard response.success else { throw QzxyError.server(OriginalJSON.message(response)) }
    }

    private func originalData(_ response: QzxyResponse) throws -> [String: Any] {
        try requireOriginalSuccess(response)
        guard let data = response.data else { throw QzxyError.invalidResponse }
        return data
    }

    /// Missing optional campus integrations do not suppress the other sources; an expired session does.
    private func optionalOriginalData(_ path: String, session: QzxySession) async throws -> [String: Any]? {
        try Task.checkCancellation()
        do {
            let response = try await originalRequest(path, session: session)
            if !response.success {
                let message = OriginalJSON.message(response)
                if OriginalSessionFailure.isKickMessage(message) { throw QzxyError.server(message) }
                return nil
            }
            return response.data
        } catch {
            if OriginalSessionFailure.isKickError(error) { throw error }
            if error is CancellationError { throw error }
            try Task.checkCancellation()
            return nil
        }
    }
}

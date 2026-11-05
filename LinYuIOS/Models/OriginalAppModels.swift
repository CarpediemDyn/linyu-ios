import Foundation
import CoreFoundation

struct CampusProfile: Codable, Equatable {
    var name: String? = nil
    var studentNumber: String? = nil
    var telephone: String? = nil
    var schoolName: String? = nil
    var genderName: String? = nil
    var cardStatus: Int? = nil
    var cardStatusName: String? = nil
    var gradeName: String? = nil
    var className: String? = nil
}

struct CampusWallet: Codable, Equatable {
    var campusBalance: Double? = nil
    var walletBalance: Double? = nil
    var signStatus: Int? = nil
    var balance: Double? { campusBalance ?? walletBalance }
    var title: String { campusBalance != nil ? "一卡通余额" : walletBalance != nil ? "趣智校园余额" : "余额" }
}

struct CampusBill: Codable, Equatable, Identifiable {
    var orderId: String
    var consumeDate: String
    var consumeMoney: String
    var description: String
    var orderNo: String? = nil
    var id: String { "\(orderId):\(consumeDate)" }
    var amount: Double { Double(consumeMoney) ?? 0 }
    var date: Date? { OriginalFormatting.billDate(consumeDate) }
    var displayDesc: String {
        let name = description.components(separatedBy: ":").dropFirst().joined(separator: ":")
        return OriginalFormatting.deviceName(name.isEmpty ? description : name)
    }
    var isDrinkingWater: Bool { ["饮水", "直饮", "冷水"].contains(where: description.contains) }
    var typeLabel: String { isDrinkingWater ? "饮水机" : description.contains("洗手台") ? "洗手台热水器" : "卫生间热水器" }
    var emoji: String { isDrinkingWater ? "🚰" : description.contains("洗手台") ? "🪥" : "🚿" }
}

struct CampusBillDetail: Codable, Equatable {
    var orderId: String? = nil
    var consumeDate: String? = nil
    var consumeMoney: Double = 0
    var description: String? = nil
    var deviceSnCode: String? = nil
    var orderNo: String? = nil
    var preDeductMoney: Double = 0
}

struct CampusUnpaidBill: Codable, Equatable, Identifiable {
    var orderId: String? = nil
    var orderNo: String? = nil
    var consumeDate: String? = nil
    var consumeMoney: String? = nil
    var description: String? = nil
    var id: String { "\(orderId ?? orderNo ?? ""):\(consumeDate ?? "")" }
    var amount: Double { Double(consumeMoney ?? "") ?? 0 }
    var isDeductible: Bool { OriginalJSON.nonempty(consumeDate) != nil }
}

/// Original MainScreen offers debt recovery only for an explicit server rejection.
struct OriginalStartFailure: Identifiable {
    let id = UUID()
    let message: String
    let serverRejected: Bool
    func bills(in unpaid: [CampusUnpaidBill]) -> [CampusUnpaidBill] {
        serverRejected ? unpaid.filter(\.isDeductible) : []
    }
    func total(for bills: [CampusUnpaidBill]) -> Double? {
        var total = 0.0
        for bill in bills {
            guard let text = bill.consumeMoney, let amount = Double(text), amount.isFinite else { return nil }
            total += amount
        }
        return total.isFinite ? total : nil
    }
}

enum CampusDeductResult: Equatable {
    case success
    case failed(String)
    case unknown
}

enum CampusSMSPurpose: Int { case newPhone = 5, forgotPassword = 2 }

struct CampusUseCode: Codable, Equatable {
    var useCode: String? = nil
    var useCodeStatus: Int? = nil
    var useCodeRandom: String? = nil
    var useCodeStartTime: String? = nil
    var resetAvailability: Int? = nil
    var resetAvailabilityWarMark: String? = nil
}

struct CampusCodeCandidate: Codable, Equatable {
    var useCode: String
    var remainTimes: Int
}

/// Optional server metadata stays optional; smallTypeId alone does not select Bluetooth.
enum OriginalDeviceAvailability: Equatable {
    case unknown, idle, running, occupied, pending

    init(bleState: UInt8?) {
        switch bleState {
        case 0: self = .idle
        case 1: self = .running
        case 3, 6: self = .pending
        default: self = .unknown
        }
    }
    var label: String {
        switch self {
        case .unknown: return "待确认"
        case .idle: return "空闲"
        case .running, .occupied: return "使用中"
        case .pending: return "有待结算记录"
        }
    }
}

struct CampusDevice: Codable, Equatable, Identifiable {
    var deviceId: String = ""
    var deviceName: String = ""
    var snCode: String = ""
    var macAddress: String = ""
    var withholdMoney: Double? = nil
    var onlineStatusId: Int? = nil
    var bigTypeId: String? = nil
    var bigTypeName: String? = nil
    var smallTypeId: String? = nil
    var smallTypeName: String? = nil
    var isBle: Bool? = nil
    var communicationTypeId: Int? = nil
    var realMac: String? = nil
    var id: String { deviceId.isEmpty ? snCode : deviceId }
    var displayName: String { OriginalFormatting.deviceName(deviceName) }
    var needsBluetoothControl: Bool { isBle == true }
    var isDrinkingWater: Bool {
        bigTypeId == "5" || bigTypeName?.contains("饮") == true ||
        ["饮水", "直饮", "开水机", "开水器", "冷水"].contains(where: deviceName.contains)
    }
    var isHotWater: Bool { deviceName.contains("热") || deviceName.contains("开水") || bigTypeName?.contains("热") == true }
    var typeLabel: String {
        isDrinkingWater ? (isHotWater ? "直饮水机 · 热水" : "直饮水机 · 冷水") :
            deviceName.hasPrefix("洗手台") ? "洗手台热水器" : "卫生间热水器"
    }
    var emoji: String { isDrinkingWater ? (isHotWater ? "♨️" : "❄️") : deviceName.hasPrefix("洗手台") ? "🪥" : "🚿" }
    var statusText: String { isDrinkingWater ? (isHotWater ? "正在接热水" : "正在接凉水") : deviceName.hasPrefix("洗手台") ? "正在洗漱中" : "正在沐浴中" }
    var ledgerDevice: LedgerDevice {
        get throws {
            guard let deviceId = OriginalJSON.nonempty(deviceId), let snCode = OriginalJSON.nonempty(snCode),
                  let mac = LedgerDevice.normalizeMAC(macAddress) else {
                throw WaterError.invalid("服务端台账缺少必要设备标识或类型")
            }
            let real: String?
            if let raw = OriginalJSON.nonempty(realMac) {
                guard let normalized = LedgerDevice.normalizeMAC(raw) else { throw WaterError.invalid("服务端台账真实 MAC 无效") }
                real = normalized
            } else { real = nil }
            return LedgerDevice(deviceId: deviceId, snCode: snCode, name: OriginalJSON.nonempty(deviceName) ?? snCode,
                                macAddress: mac, realMac: real, bigTypeId: OriginalJSON.nonempty(bigTypeId) ?? "0",
                                smallTypeId: OriginalJSON.nonempty(smallTypeId) ?? "0")
        }
    }
}

/// Store and read this snapshot under ownerScope; real balances always precede manual estimates.
struct CampusBalanceSnapshot: Codable, Equatable {
    var ownerScope: String
    var campusBalance: Double? = nil
    var walletBalance: Double? = nil
    var manualBalance: String = ""
    var manualBalanceTime: Date = Date(timeIntervalSince1970: 0)
    var bills: [CampusBill] = []
    var realBalance: Double? { campusBalance ?? walletBalance }
    var isEstimated: Bool { realBalance == nil }
    var title: String { campusBalance != nil ? "一卡通余额" : walletBalance != nil ? "趣智校园余额" : "余额" }
    var balance: Double {
        if let realBalance { return realBalance }
        guard !manualBalance.isEmpty else { return 0 }
        let spent = bills.filter { bill in guard let date = bill.date else { return false }; return date > manualBalanceTime }.reduce(0) { $0 + $1.amount }
        return (Double(manualBalance) ?? 0) - spent
    }
    var formattedBalance: String { realBalance == nil && manualBalance.isEmpty ? "¥ —" : "¥ \(OriginalFormatting.money(balance))" }
    func matches(_ session: QzxySession) -> Bool { ownerScope == session.ownerScope }
}

struct CampusAccountCache: Codable, Equatable {
    var ownerScope: String
    var profile = CampusProfile()
    var wallet = CampusWallet()
    var useCode = CampusUseCode()
    var lastDevice: CampusDevice? = nil
    var boundRoom: String = ""
    func matches(_ session: QzxySession) -> Bool { ownerScope == session.ownerScope }
}

/// Original device cache's 60-second / 64-entry policy, isolated per account on iOS.
struct CampusDeviceCache {
    var ownerScope: String
    private var entries: [(key: String, date: Date, device: CampusDevice)] = []
    init(ownerScope: String) { self.ownerScope = ownerScope }
    mutating func device(for key: String, session: QzxySession, now: Date = Date()) -> CampusDevice? {
        guard ownerScope == session.ownerScope else { entries.removeAll(); ownerScope = session.ownerScope; return nil }
        entries.removeAll { now.timeIntervalSince($0.date) > 60 }
        return entries.first { $0.key == key }?.device
    }
    mutating func store(_ device: CampusDevice, for key: String, session: QzxySession, now: Date = Date()) {
        if ownerScope != session.ownerScope { entries.removeAll(); ownerScope = session.ownerScope }
        entries.removeAll { $0.key == key }
        if entries.count >= 64 { entries.removeFirst() }
        entries.append((key, now, device))
    }
    mutating func clear() { entries.removeAll() }
}

enum OriginalFormatting {
    private static func replace(_ text: String, _ pattern: String, _ replacement: String = "") -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    static func deviceName(_ name: String) -> String {
        var value = name
        for pattern in ["^热水[器表变][- ]*", "^直饮[- ]*(开水|冷水|热水|温水)[- ]*", "^(开水|冷水|温水)[- ]*", "^(平衡|直饮水?机?)[- ]*", "^洗手台\\d*[- ]*", "[- ](直饮)?(开水|冷水|热水|温水)$"] {
            value = replace(value, pattern)
        }
        value = replace(value, "-\\d+层-", "-")
        value = replace(value, "洗手台$", "房").replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? name : value
    }
    static func roomKey(_ name: String) -> String? {
        var value = replace(name, "^(热水[器表变]|洗手台\\d*|直饮(?:开水|冷水|热水|温水)|开水机?|冷水|温水|平衡|直饮水?机?)[- ]*")
        value = replace(value, "[- ]*(?:热水器|热水表|洗手台|卫生间|洗漱台|浴室|淋浴间|淋浴|饮水机|直饮水|开水机|开水器|水龙头|水房)$")
        if value.hasSuffix("房") { value.removeLast() }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " 　-_")).lowercased()
        value = replace(value, "[-_\\s　]+", "-")
        return value.isEmpty ? nil : value
    }
    static func inSameRoom(_ boundKey: String, deviceName: String) -> Bool {
        guard let key = roomKey(boundKey), let device = roomKey(deviceName) else { return true }
        return key == device || device.hasSuffix("-" + key)
    }
    /// Source parseSnCode accepts the final segment; the camera's separate matcher requires the prefix.
    static func parseSnCode(_ raw: String) -> String? {
        let last = raw.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = last.replacingOccurrences(of: ":", with: "").uppercased()
        guard normalized.range(of: "^[0-9A-F]{12}$", options: .regularExpression) != nil else { return nil }
        return normalized
    }
    static func parseDeviceQR(_ raw: String) -> String? {
        guard raw.range(of: "KLCXKJ-Water", options: .caseInsensitive) != nil else { return nil }
        return parseSnCode(raw)
    }
    static func money(_ value: Double) -> String {
        let number = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
        return number.hasSuffix("0") ? String(number.dropLast()) : number
    }
    static func billDate(_ value: String, timeZone: TimeZone = .current) -> Date? {
        let format: String
        if value.range(of: "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}$", options: .regularExpression) != nil {
            format = "yyyy-MM-dd HH:mm:ss.SSS"
        } else if value.range(of: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$", options: .regularExpression) != nil {
            format = "yyyy-MM-dd'T'HH:mm:ss"
        } else if value.range(of: "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$", options: .regularExpression) != nil {
            format = "yyyy-MM-dd HH:mm:ss"
        } else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
    static func macLookupVariants(_ mac: String) -> [String] {
        let canon = mac.filter { $0.isLetter || $0.isNumber }.uppercased()
        guard canon.range(of: "^[0-9A-F]{12}$", options: .regularExpression) != nil,
              let first = UInt8(canon.prefix(2), radix: 16), first & 0xC0 != 0 else { return [mac] }
        let derived = (String(format: "%02X", first & 0x3F) + String(canon.dropFirst(2))).lowercased()
        return derived == mac ? [mac] : [mac, derived]
    }
}

enum OriginalSessionFailure {
    static func isKickMessage(_ message: String?) -> Bool {
        guard let message, !message.isEmpty else { return false }
        return ["登录", "token", "失效", "过期", "认证", "未登录", "请重新"].contains(where: message.contains)
    }
    static func isKickError(_ error: Error) -> Bool {
        let message = error.localizedDescription
        return ["401", "403", "Unauthorized", "Forbidden"].contains(where: message.contains) || isKickMessage(message)
    }
}

/// Kotlin/Gson accepts numeric identifiers and string money values; never turn Boolean into an ID.
enum OriginalJSON {
    static func text(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return value.stringValue }
        return nil
    }
    static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
    static func int(_ value: Any?) -> Int? { text(value).flatMap(Int.init) }
    static func number(_ value: Any?) -> Double? {
        guard let value = text(value).flatMap(Double.init), value.isFinite else { return nil }
        return value
    }
    static func bool(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
    static func message(_ response: QzxyResponse) -> String {
        text(response.json["errorMessage"]) ?? text(response.json["msg"]) ?? text(response.json["displayMessage"]) ?? text(response.json["message"]) ?? response.message
    }
}


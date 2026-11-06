import Foundation

struct QzxySession: Codable {
    let telephone: String
    let loginCode: String
    let userId: String
    let accountId: String
    let projectId: String
    var ownerScope: String { "\(projectId):\(accountId):\(userId)" }
}

enum WaterError: LocalizedError {
    case busy, disconnected, timeout, storage, identity, unsupportedIdentity, reconciliation
    case invalid(String), rejected(String), recovered(String)
    static let meterRecoveryGuidance = "当前未连接水表。可以先查询服务器结算记录；设备清账需要靠近原水表。"
    var errorDescription: String? {
        switch self {
        case .busy: return "已有操作或未结束订单，请先恢复处理"
        case .disconnected: return "蓝牙连接已断开，操作结果可能尚未确认"
        case .timeout: return "水表应答超时，请重新连接核实状态"
        case .storage: return "交易记录无法安全保存，已停止后续操作"
        case .identity: return "水表连接、台账或当前登录会话不匹配，请重新选择设备"
        case .unsupportedIdentity: return "无法读取水表自报地址，请重新连接"
        case .reconciliation: return "设备记录与本地会话不一致，请重新连接核实"
        case .invalid(let text), .rejected(let text), .recovered(let text): return text
        }
    }
}

struct LedgerDevice: Codable, Equatable {
    let deviceId: String
    let snCode: String
    let name: String
    let macAddress: String
    let realMac: String?
    let bigTypeId: String
    let smallTypeId: String

    static func normalizeMAC(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").uppercased()
        guard value.utf8.count == 12, value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) else { return nil }
        return value
    }
    var apiMAC: String { Self.normalizeMAC(realMac ?? "") ?? Self.normalizeMAC(macAddress) ?? "" }
}

struct WaterMeterIdentity: Codable, Equatable {
    let projectId: String
    let deviceId: String
    let accountId: String
    let macAddress: String
}

struct MeterBinding: Codable, Equatable, Identifiable {
    var id: UUID { peripheralID }
    let peripheralID: UUID
    let ownerScope: String
    let device: LedgerDevice
    let observedMAC: String
    let verifiedAt: Date
}

struct RateGrant: Equatable {
    let downData: Data
    let consumeDate: String
    let orderNo: String
}

struct SettlementReceipt: Codable, Equatable {
    let clData: String
    let amountRaw: String?
}

enum WaterPhase: String, Codable {
    case rateRequested, rateReady, opening, running, closing, closed, collected
    case uploading, uploadUnknown, serverRecorded, writeBackPending, completed, needsAttention, rateRejected, superseded
}
enum ValveFact: String, Codable { case unknown, open, closed }
enum ValveClosureEvidence: String, Codable { case closeAcknowledgement, verifiedDeviceState }

enum WaterUsageState: Equatable { case running, unconfirmed, settlementPending, archived }

struct WaterTransaction: Codable, Identifiable {
    let id: UUID
    let binding: MeterBinding
    var phase: WaterPhase
    var valve: ValveFact
    var protocolType: String
    var randomNumber: String
    var consumeDate: String
    var orderNo: String
    var consumption: Data?
    var receipt: SettlementReceipt?
    var writeBack: Data?
    var failureReportPending: Bool
    var lastError: String?
    var updatedAt: Date
    var writeBackAcknowledged = false
    var idleConfirmed = false
    var startedAt: Date? = nil
    var isPending: Bool { phase != .completed && phase != .rateRejected && phase != .superseded }
    var billConfirmed: Bool? = nil
    var closureEvidence: ValveClosureEvidence? = nil
    var closureConfirmedAt: Date? = nil
    var legacyUnverifiedSettlement: Bool? = nil

    var isSettlementRecovery: Bool {
        legacyUnverifiedSettlement == true || closureEvidence != nil || valve == .closed || receipt != nil || billConfirmed == true
            || [.closed, .collected, .uploading, .uploadUnknown, .serverRecorded, .writeBackPending, .needsAttention].contains(phase)
    }

    var usageState: WaterUsageState {
        guard isPending else { return .archived }
        if valve == .closed, closureEvidence != nil { return .settlementPending }
        if valve == .open, phase == .running { return .running }
        return .unconfirmed
    }

    func usageSeconds(at now: Date) -> Int? {
        guard let startedAt else { return nil }
        if usageState == .running { return max(0, Int(now.timeIntervalSince(startedAt))) }
        // A later state query proves the device is closed now, not when the water stopped.
        guard closureEvidence == .closeAcknowledgement, let closureConfirmedAt,
              closureConfirmedAt >= startedAt else { return nil }
        return Int(closureConfirmedAt.timeIntervalSince(startedAt))
    }

    var statusText: String {
        if phase == .rateRejected { return "服务器拒绝本次启动，未向水表写入费率" }
        if phase == .superseded { return "设备已空闲，本次未确认的启动记录已结束" }
        if phase == .completed {
            if billConfirmed == true { return "设备已空闲，账单已核实" }
            if writeBackAcknowledged { return "已关阀、已记账，设备写回已确认" }
            return idleConfirmed ? "已关阀、已记账，设备已空闲；写回回执未确认" : "已关阀、已记账"
        }
        let valveStatus = usageState == .settlementPending ? "已确认关阀" : "阀门状态待核实"
        if receipt != nil || billConfirmed == true { return "\(valveStatus)，服务器已记账，设备清账待确认" }
        if phase == .uploading || phase == .uploadUnknown { return "\(valveStatus)，服务器处理结果待核实" }
        if usageState == .settlementPending { return "已确认关阀，结算未完成" }
        if usageState == .running { return "用水中，尚未结算" }
        if phase == .closing { return "关闭未确认，请重试" }
        return "阀门状态未确认，请恢复核实"
    }
}

struct WaterJournal: Codable {
    var version = 1
    var bindings: [MeterBinding] = []
    var transactions: [WaterTransaction] = []
}

@MainActor protocol WaterMeterTransport: AnyObject {
    var peripheralID: UUID? { get }
    var connectionID: UUID { get }
    func isAvailableForRecovery(_ id: UUID) -> Bool
    func connectForTransaction(to id: UUID) async throws
    func reconnectForTransaction(to id: UUID) async throws
    func exchange(_ command: UInt8, payload: Data) async throws -> Data
    func disconnect()
}

@MainActor protocol WaterMeterService {
    func grantRate(device: LedgerDevice, state: BleDeviceState, session: QzxySession) async throws -> RateGrant
    func uploadConsumption(_ payload: Data, state: BleDeviceState, session: QzxySession) async throws -> SettlementReceipt
    func hasRecordedConsumption(_ transaction: WaterTransaction, session: QzxySession) async throws -> Bool
    func reportFailure(consumeDate: String, session: QzxySession) async throws
}

@MainActor protocol WaterJournalStore {
    func load() throws -> WaterJournal
    func save(_ journal: WaterJournal) throws
}

enum WaterProtocolIdentity {
    static func number(_ bytes: [UInt8], at offset: Int) -> String {
        String(bytes[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
    }
    /// Common self-reported prefix. Used to discover the ledger MAC on iOS,
    /// which does not expose Android's scanned Bluetooth address. This is not authentication.
    static func state(_ payload: Data) -> WaterMeterIdentity? {
        let b = Array(payload)
        guard b.count == 28 || b.count >= 31, b.first == 0x80 else { return nil }
        return WaterMeterIdentity(projectId: number(b, at: 1), deviceId: number(b, at: 5),
                                  accountId: number(b, at: 9), macAddress: Data(b[13..<19]).hexUppercased)
    }
    /// Upstream treats the consumption body as opaque, including extended records.
    static func validConsumption(_ payload: Data) -> Bool { payload.count >= 42 && payload.first == 0x80 }
}

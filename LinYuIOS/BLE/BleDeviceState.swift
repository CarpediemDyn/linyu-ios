import Foundation

/// 与原项目 DeviceQueryParser 保持偏移一致。
struct BleDeviceState: Equatable {
    let protocolType: String
    let randomNumber: String
    let state: UInt8
    let deviceType: UInt8
    let a1: UInt8
    /// Common prefix metadata supplies a self-reported MAC for iOS ledger discovery.
    /// It does not establish the owner of opaque consumption records.
    var identity: WaterMeterIdentity? = nil
    var faultCode: UInt8? = nil

    var summary: String {
        switch state {
        case 0: return "空闲"
        case 1: return "使用中（请勿重复开阀）"
        case 3, 6: return "有待结算记录（请勿直接开阀）"
        default: return "未知状态 \(state)"
        }
    }

    static let queryPayload = Data([0x00])

    static func parse(_ payload: Data) -> BleDeviceState? {
        let p = Array(payload)
        guard p.first == 0x80 else { return nil }
        if p.count == 28 {
            return BleDeviceState(
                protocolType: "",
                randomNumber: Data(p[21..<23]).hexUppercased,
                state: p[19], deviceType: p[23], a1: p[24], identity: WaterProtocolIdentity.state(payload), faultCode: p[20]
            )
        }
        if p.count >= 31 {
            return BleDeviceState(
                protocolType: Data([p[19]]).hexUppercased,
                randomNumber: Data(p[24..<28]).hexUppercased,
                state: p[28], deviceType: p[29], a1: p[30], identity: WaterProtocolIdentity.state(payload)
            )
        }
        return nil
    }
}

import Foundation

/// 原 LinYu `BleFrame.kt` 的无副作用移植；不向设备发送任何内容。
enum BleFrame {
    static let header: UInt8 = 0x60
    static let tail: UInt8 = 0x16
    static let wireStart: UInt8 = 0x23
    static let wireEnd: UInt8 = 0x0A

    static func build(command: UInt8, payload: Data = Data()) -> Data? {
        guard payload.count <= 252 else { return nil } // 单字节长度 data+3
        var frame: [UInt8] = [header, 0, UInt8(payload.count + 3), 0x80, command, 0]
        frame.append(contentsOf: payload)
        let crc = (payload.reduce(Int(0x80) + Int(command)) { $0 + Int($1) } & 0xFF)
        frame.append(UInt8(crc))
        frame.append(tail)
        return Data(frame)
    }

    static func toWire(_ frame: Data) -> Data {
        Data([wireStart]) + Data(frame.hexUppercased.utf8) + Data([wireEnd])
    }

    static func commandToWire(_ command: UInt8, payload: Data = Data()) -> Data? {
        guard let frame = build(command: command, payload: payload) else { return nil }
        return toWire(frame)
    }

    static func parseWire(_ wire: Data) -> Data? {
        let bytes = Array(wire)
        guard bytes.last == wireEnd else { return nil }
        let offset = bytes.first == wireStart ? 1 : 0
        guard bytes.count > offset + 1 else { return nil }
        let ascii = Data(bytes[offset..<(bytes.count - 1)])
        guard let text = String(data: ascii, encoding: .ascii),
              let frame = Data(hex: text), verify(frame) else { return nil }
        return frame
    }

    static func verify(_ frame: Data) -> Bool {
        let b = Array(frame)
        guard b.count >= 8, b[0] == header, b[b.count - 1] == tail,
              b.count == Int(b[2]) + 5, Int(b[2]) >= 3 else { return false }
        let count = Int(b[2]) - 3
        let expected = (b[6..<(6 + count)].reduce(Int(b[3]) + Int(b[4])) { $0 + Int($1) }) & 0xFF
        return b[b.count - 2] == UInt8(expected)
    }

    static func payload(_ frame: Data) -> Data? {
        guard verify(frame) else { return nil }
        let bytes = Array(frame)
        return Data(bytes[6..<(6 + Int(bytes[2]) - 3)])
    }

    static func command(_ frame: Data) -> UInt8? {
        guard verify(frame) else { return nil }
        return frame[4]
    }
}

extension Data {
    var hexUppercased: String { map { String(format: "%02X", $0) }.joined() }
    var hexLowercased: String { hexUppercased.lowercased() }

    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(trimmed.count / 2)
        let chars = Array(trimmed.utf8)
        for index in stride(from: 0, to: chars.count, by: 2) {
            func nibble(_ c: UInt8) -> UInt8? {
                switch c {
                case 48...57: return c - 48
                case 65...70: return c - 65 + 10
                case 97...102: return c - 97 + 10
                default: return nil
                }
            }
            guard let hi = nibble(chars[index]), let lo = nibble(chars[index + 1]) else { return nil }
            bytes.append((hi << 4) | lo)
        }
        self.init(bytes)
    }
}

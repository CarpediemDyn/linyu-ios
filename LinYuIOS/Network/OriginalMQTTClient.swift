import Foundation
import Network

/// Optional original MQTT 3.1.1 accelerator. HTTP remains the source of order truth.
@MainActor final class OriginalMQTTClient {
    var onMessage: ((String, Data) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    private(set) var connected = false
    private var connection: NWConnection?
    private var parser = OriginalMQTTPacketParser()
    private var timer: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var phone = ""
    private var awaitingPing = false
    private var generation = UUID()

    static func topics(phone: String) -> [String] {
        ["app_downRate_\(phone)", "app_shutdownOrder_\(phone)", "app_uploadData_\(phone)"]
    }

    func connect(phone: String) {
        if connected && self.phone == phone { onConnectionChange?(true); return }
        disconnect()
        guard !phone.isEmpty, phone.utf8.count <= 128,
              !phone.contains("#"), !phone.contains("+"), !phone.contains("\0") else { return }
        self.phone = phone
        let epoch = generation
        let stream = NWConnection(host: "47.107.37.60", port: 1883, using: .tcp)
        connection = stream
        stream.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.generation == epoch else { return }
                switch state {
                case .ready:
                    var body = Self.string("MQTT") + [4, 2, 0, 10] // clean session, keepalive 10s
                    body += Self.string("linyu-ios-" + UUID().uuidString)
                    self.send(Self.packet(header: 0x10, body: body))
                    self.receive(epoch: epoch)
                case .failed, .cancelled: self.disconnect()
                default: break
                }
            }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self, self.generation == epoch, !self.connected else { return }
            self.disconnect()
        }
        stream.start(queue: .main)
    }

    func disconnect() {
        generation = UUID()
        timer?.cancel(); timer = nil
        timeout?.cancel(); timeout = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        parser = OriginalMQTTPacketParser()
        awaitingPing = false
        connected = false
        onConnectionChange?(false)
    }

    private func receive(epoch: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, ended, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == epoch else { return }
                do {
                    if let data {
                        for frame in try self.parser.append(data) {
                            try self.handle(frame)
                        }
                    }
                    if error != nil || ended { self.disconnect() }
                    else { self.receive(epoch: epoch) }
                } catch { self.disconnect() }
            }
        }
    }

    private func handle(_ frame: OriginalMQTTPacketParser.Frame) throws {
        let bytes = frame.body
        switch frame.header >> 4 {
        case 2:
            guard frame.header == 0x20, bytes.count == 2, bytes[0] == 0, bytes[1] == 0, !connected else {
                throw OriginalMQTTPacketParser.ParseError.malformed
            }
            connected = true
            timeout?.cancel(); timeout = nil
            for (index, topic) in Self.topics(phone: phone).enumerated() {
                send(Self.packet(header: 0x82, body: [0, UInt8(index + 1)] + Self.string(topic) + [0]))
            }
            onConnectionChange?(true)
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                    guard let self, self.connected else { return }
                    if self.awaitingPing { self.disconnect(); return }
                    self.awaitingPing = true
                    self.send(Data([0xC0, 0]))
                }
            }
        case 3:
            guard connected, bytes.count >= 2 else { throw OriginalMQTTPacketParser.ParseError.malformed }
            let size = Int(bytes[0]) * 256 + Int(bytes[1])
            guard size > 0, bytes.count >= size + 2,
                  let topic = String(bytes: bytes[2..<(2 + size)], encoding: .utf8) else {
                throw OriginalMQTTPacketParser.ParseError.malformed
            }
            let qos = (frame.header >> 1) & 3
            var payloadOffset = 2 + size
            if qos == 1 {
                guard bytes.count >= payloadOffset + 2 else { throw OriginalMQTTPacketParser.ParseError.malformed }
                send(Data([0x40, 2, bytes[payloadOffset], bytes[payloadOffset + 1]]))
                payloadOffset += 2
            } else if qos != 0 { throw OriginalMQTTPacketParser.ParseError.malformed }
            if Self.topics(phone: phone).contains(topic) {
                onMessage?(topic, Data(bytes[payloadOffset...]))
            }
        case 9:
            guard frame.header == 0x90, bytes.count == 3, bytes[0] == 0,
                  (1...3).contains(bytes[1]), bytes[2] == 0 else {
                throw OriginalMQTTPacketParser.ParseError.malformed
            }
        case 13:
            guard frame.header == 0xD0, bytes.isEmpty else { throw OriginalMQTTPacketParser.ParseError.malformed }
            awaitingPing = false
        default: throw OriginalMQTTPacketParser.ParseError.malformed
        }
    }

    private func send(_ data: Data) {
        let epoch = generation
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == epoch else { return }
                    self.disconnect()
                }
            }
        })
    }

    private static func string(_ text: String) -> [UInt8] {
        let bytes = Array(text.utf8)
        return [UInt8(bytes.count >> 8), UInt8(bytes.count & 255)] + bytes
    }

    private static func packet(header: UInt8, body: [UInt8]) -> Data {
        var size = body.count
        var result = [header]
        repeat {
            var byte = UInt8(size % 128)
            size /= 128
            if size > 0 { byte |= 128 }
            result.append(byte)
        } while size > 0
        return Data(result + body)
    }
}

/// Incremental bounded decoder, independent of the socket for deterministic tests.
struct OriginalMQTTPacketParser {
    struct Frame: Equatable { let header: UInt8; let body: [UInt8] }
    enum ParseError: Error { case malformed, tooLarge }
    private var buffer: [UInt8] = []
    private let maximumPacket = 65_536

    mutating func append(_ data: Data) throws -> [Frame] {
        guard data.count <= 8192, buffer.count + data.count <= maximumPacket + 8197 else { throw ParseError.tooLarge }
        buffer.append(contentsOf: data)
        var frames: [Frame] = []
        while buffer.count >= 2 {
            var value = 0, multiplier = 1, offset = 1
            var complete = false
            for _ in 0..<4 {
                guard offset < buffer.count else { return frames }
                let byte = buffer[offset]; offset += 1
                value += Int(byte & 127) * multiplier
                guard value <= maximumPacket else { throw ParseError.tooLarge }
                if byte & 128 == 0 { complete = true; break }
                multiplier *= 128
            }
            guard complete else { throw ParseError.malformed }
            guard buffer.count >= offset + value else { return frames }
            frames.append(Frame(header: buffer[0], body: Array(buffer[offset..<(offset + value)])))
            buffer.removeFirst(offset + value)
        }
        return frames
    }
}

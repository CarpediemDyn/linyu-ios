import Foundation
import CoreBluetooth
import Combine

struct DiscoveredWaterMeter: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date
}

/// The wire protocol has no transaction sequence number. An uncertain exchange
/// retires its physical connection before another command can be accepted.
@MainActor final class BleCentral: NSObject, ObservableObject, WaterMeterTransport {
    static let serviceUUID = CBUUID(string: "FF00")
    static let notifyUUID = CBUUID(string: "FF01")
    static let writeUUID = CBUUID(string: "FF02")

    @Published private(set) var bluetoothStatus = "正在检查蓝牙…"
    @Published private(set) var scanning = false
    @Published private(set) var meters: [DiscoveredWaterMeter] = []
    @Published private(set) var connectionStatus = "未连接"
    @Published private(set) var ready = false
    @Published private(set) var deviceState: BleDeviceState?
    @Published private(set) var lastDiagnostic = "未执行状态查询"

    var peripheralID: UUID? { ready ? connected?.identifier : nil }
    private(set) var connectionID = UUID()

    private let managerDelegate = BleManagerDelegate()
    private var central: CBCentralManager!
    // Retain objects across scans so a journal UUID remains usable later.
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?
    private var retiring: CBPeripheral?
    private var retiringConnectionID: UUID?
    private var sessionDelegate: BleSessionDelegate?
    private var generation: UInt64 = 0
    private var service: CBService?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private var rxBytes = Data()
    private var rxCommandToken: UUID?
    private var scanToken: UUID?
    private var connectionOperation: UUID?
    private var diagnosticTask: Task<Void, Never>?

    private struct ConnectionWait {
        let token: UUID
        let generation: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }
    private struct DisconnectWait {
        let token: UUID
        let peripheral: CBPeripheral
        let continuation: CheckedContinuation<Void, Error>
    }
    private struct CommandWait {
        let token: UUID
        let generation: UInt64
        let command: UInt8
        let continuation: CheckedContinuation<Data, Error>
        var chunks: [Data]
        var writeStarted = false
        var writeInFlight = false
        var response: Data?
    }
    private var connectionWait: ConnectionWait?
    private var disconnectWait: DisconnectWait?
    private var commandWait: CommandWait?
    private var connectionDeadline: Task<Void, Never>?
    private var disconnectDeadline: Task<Void, Never>?
    private var commandDeadline: Task<Void, Never>?
    private var chunkDelay: Task<Void, Never>?

    override init() {
        super.init()
        managerDelegate.owner = self
        central = CBCentralManager(delegate: managerDelegate, queue: .main)
    }

    private var busy: Bool {
        connectionOperation != nil || commandWait != nil || diagnosticTask != nil
    }

    func startScan() {
        guard !busy else { lastDiagnostic = WaterError.busy.localizedDescription; return }
        guard central.state == .poweredOn else {
            bluetoothStatus = "请开启蓝牙并允许应用访问"
            return
        }
        meters = []
        // Some meters omit FF00 from their advertising packet.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanning = true
        let token = UUID()
        scanToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(6)) { [weak self] in
            guard let self = self, self.scanToken == token else { return }
            self.stopScanInternally()
        }
    }

    func stopScan() {
        guard !busy else { return }
        stopScanInternally()
    }

    private func stopScanInternally() {
        central.stopScan()
        scanning = false
        scanToken = nil
    }

    func connect(to id: UUID) {
        guard !busy else { lastDiagnostic = WaterError.busy.localizedDescription; return }
        diagnosticTask = Task { [weak self] in
            guard let self = self else { return }
            defer { self.diagnosticTask = nil }
            do { try await self.connectForTransaction(to: id) }
            catch { self.connectionStatus = error.localizedDescription }
        }
    }

    func disconnect() {
        // A diagnostic button cannot cancel a transaction midway through a write.
        guard !busy else { lastDiagnostic = WaterError.busy.localizedDescription; return }
        retireSession(error: WaterError.disconnected)
    }

    func queryState() {
        guard !busy else { lastDiagnostic = WaterError.busy.localizedDescription; return }
        diagnosticTask = Task { [weak self] in
            guard let self = self else { return }
            defer { self.diagnosticTask = nil }
            do {
                let payload = try await self.exchange(0x23, payload: BleDeviceState.queryPayload)
                guard let state = BleDeviceState.parse(payload) else {
                    self.lastDiagnostic = "状态载荷不支持（\(payload.count) 字节）"
                    return
                }
                self.deviceState = state
                self.lastDiagnostic = "状态读取成功（载荷 \(payload.count) 字节）"
            } catch { self.lastDiagnostic = error.localizedDescription }
        }
    }

    func connectForTransaction(to id: UUID) async throws {
        try await prepareConnection(to: id, forceReconnect: false)
    }

    func reconnectForTransaction(to id: UUID) async throws {
        try await prepareConnection(to: id, forceReconnect: true)
    }

    private func prepareConnection(to id: UUID, forceReconnect: Bool) async throws {
        guard connectionOperation == nil, commandWait == nil else { throw WaterError.busy }
        try Task.checkCancellation()
        guard central.state == .poweredOn else { throw WaterError.disconnected }
        if !forceReconnect, ready, connected?.identifier == id, connected?.state == .connected { return }
        let operation = UUID()
        connectionOperation = operation
        defer { if connectionOperation == operation { connectionOperation = nil } }
        stopScanInternally()
        if connected != nil { retireSession(error: WaterError.disconnected) }
        try await waitForPhysicalDisconnect()
        try Task.checkCancellation()
        guard central.state == .poweredOn else { throw WaterError.disconnected }
        guard let peripheral = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            throw WaterError.invalid("找不到已保存的水表，请先重新扫描")
        }
        peripherals[id] = peripheral
        let token = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                generation &+= 1
                connectionID = UUID()
                managerDelegate.activeConnectionID = connectionID
                connected = peripheral
                let delegate = BleSessionDelegate(owner: self, generation: generation)
                sessionDelegate = delegate
                peripheral.delegate = delegate
                connectionWait = ConnectionWait(token: token, generation: generation, continuation: continuation)
                connectionStatus = "正在连接…"
                deviceState = nil
                lastDiagnostic = "未执行状态查询"
                connectionDeadline = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                    guard let self = self, self.connectionWait?.token == token else { return }
                    self.retireSession(error: WaterError.timeout)
                }
                central.connect(peripheral, options: nil)
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                guard let self = self, self.connectionWait?.token == token else { return }
                self.retireSession(error: CancellationError())
            }
        })
        // Cancellation can race with notification subscription completing.
        if Task.isCancelled {
            retireSession(error: CancellationError())
            throw CancellationError()
        }
    }

    private func waitForPhysicalDisconnect() async throws {
        guard let old = retiring else { return }
        // CoreBluetooth may update state without delivering a terminal callback
        // after Bluetooth powers off. This is physical-state proof, not a timer.
        if old.state == .disconnected {
            retiring = nil
            retiringConnectionID = nil
            managerDelegate.activeConnectionID = nil
            return
        }
        let token = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                disconnectWait = DisconnectWait(token: token, peripheral: old, continuation: continuation)
                disconnectDeadline = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                    guard let self = self, self.disconnectWait?.token == token else { return }
                    // Timeout is not evidence that disconnection actually completed.
                    self.finishDisconnect(.failure(WaterError.timeout))
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                guard let self = self, self.disconnectWait?.token == token else { return }
                self.finishDisconnect(.failure(CancellationError()))
            }
        })
    }

    func exchange(_ command: UInt8, payload: Data) async throws -> Data {
        guard connectionOperation == nil, commandWait == nil else { throw WaterError.busy }
        try Task.checkCancellation()
        guard [UInt8(0x23), 0x21, 0x22, 0x85, 0x86].contains(command) else {
            throw WaterError.invalid("不支持的水表指令")
        }
        guard ready, connected?.state == .connected, let characteristic = writeCharacteristic,
              characteristic.properties.contains(.write) else { throw WaterError.disconnected }
        guard let wire = BleFrame.commandToWire(command, payload: payload) else {
            throw WaterError.invalid("水表指令帧生成失败")
        }
        let token = UUID()
        let response: Data = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                rxBytes.removeAll(keepingCapacity: true)
                rxCommandToken = token
                let chunks = stride(from: 0, to: wire.count, by: 20).map {
                    Data(wire[$0..<min($0 + 20, wire.count)])
                }
                commandWait = CommandWait(token: token, generation: generation, command: command,
                                          continuation: continuation, chunks: chunks)
                if command == 0x23 { deviceState = nil }
                lastDiagnostic = String(format: "等待 0x%02X 水表应答…", command)
                commandDeadline = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                    guard let self = self, self.commandWait?.token == token else { return }
                    self.retireSession(error: WaterError.timeout)
                }
                sendNextChunk()
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                guard let self = self, self.commandWait?.token == token else { return }
                self.retireSession(error: CancellationError())
            }
        })
        if Task.isCancelled {
            retireSession(error: CancellationError())
            throw CancellationError()
        }
        return response
    }

    private func sendNextChunk() {
        guard var pending = commandWait, pending.generation == generation,
              !pending.writeInFlight, !pending.chunks.isEmpty, ready,
              let peripheral = connected, let characteristic = writeCharacteristic else { return }
        guard peripheral.state == .connected else {
            retireSession(error: WaterError.disconnected)
            return
        }
        let bytes = pending.chunks.removeFirst()
        pending.writeStarted = true
        pending.writeInFlight = true
        commandWait = pending
        sessionDelegate?.activeCommandToken = pending.token
        peripheral.writeValue(bytes, for: characteristic, type: .withResponse)
    }

    private func finishCommandIfComplete() {
        guard let pending = commandWait, !pending.writeInFlight, pending.chunks.isEmpty,
              let response = pending.response else { return }
        commandWait = nil
        sessionDelegate?.activeCommandToken = nil
        commandDeadline?.cancel(); commandDeadline = nil
        chunkDelay?.cancel(); chunkDelay = nil
        if pending.command == 0x23 { deviceState = BleDeviceState.parse(response) }
        lastDiagnostic = String(format: "收到 0x%02X 应答（%d 字节）", pending.command, response.count)
        pending.continuation.resume(returning: response)
    }

    private func finishConnection(_ result: Result<Void, Error>) {
        let pending = connectionWait
        connectionWait = nil
        connectionDeadline?.cancel(); connectionDeadline = nil
        pending?.continuation.resume(with: result)
    }

    private func finishDisconnect(_ result: Result<Void, Error>) {
        let pending = disconnectWait
        disconnectWait = nil
        disconnectDeadline?.cancel(); disconnectDeadline = nil
        pending?.continuation.resume(with: result)
    }

    /// Clear continuations and identities before CoreBluetooth calls or resumes.
    private func retireSession(error: Error, physicallyDisconnected: Bool = false) {
        let old = connected
        let oldConnectionID = connectionID
        connected = nil
        generation &+= 1
        connectionID = UUID()
        old?.delegate = nil
        sessionDelegate?.activeCommandToken = nil
        sessionDelegate = nil
        ready = false
        service = nil
        notifyCharacteristic = nil
        writeCharacteristic = nil
        rxBytes.removeAll()
        rxCommandToken = nil
        deviceState = nil
        let pending = commandWait
        commandWait = nil
        commandDeadline?.cancel(); commandDeadline = nil
        chunkDelay?.cancel(); chunkDelay = nil
        if let old = old, !physicallyDisconnected {
            retiring = old
            retiringConnectionID = oldConnectionID
            managerDelegate.activeConnectionID = oldConnectionID
            central.cancelPeripheralConnection(old)
        } else if old != nil {
            managerDelegate.activeConnectionID = nil
        }
        connectionStatus = error.localizedDescription
        lastDiagnostic = error.localizedDescription
        finishConnection(.failure(error))
        pending?.continuation.resume(throwing: error)
    }

    fileprivate func managerStateChanged(_ manager: CBCentralManager, state: CBManagerState) {
        guard manager === central else { return }
        switch state {
        case .poweredOn: bluetoothStatus = "蓝牙已开启"
        case .poweredOff: bluetoothStatus = "蓝牙已关闭"
        case .unauthorized: bluetoothStatus = "蓝牙权限被拒绝，请在系统设置中允许"
        case .unsupported: bluetoothStatus = "此设备不支持蓝牙低功耗"
        case .resetting: bluetoothStatus = "蓝牙重置中"
        case .unknown: bluetoothStatus = "蓝牙状态未知"
        @unknown default: bluetoothStatus = "未知蓝牙状态"
        }
        if state != .poweredOn {
            stopScanInternally()
            retireSession(error: WaterError.disconnected)
            finishDisconnect(.failure(WaterError.disconnected))
        }
    }

    fileprivate func discovered(_ peripheral: CBPeripheral, advertisement: [String: Any], rssi: NSNumber) {
        guard scanning, connectionOperation == nil else { return }
        let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        guard name.localizedCaseInsensitiveContains("KLCXKJ-Water") else { return }
        peripherals[peripheral.identifier] = peripheral
        let entry = DiscoveredWaterMeter(id: peripheral.identifier, name: name, rssi: rssi.intValue, lastSeen: Date())
        if let index = meters.firstIndex(where: { $0.id == entry.id }) { meters[index] = entry }
        else { meters.append(entry) }
        meters.sort { $0.rssi > $1.rssi }
    }

    fileprivate func didConnect(_ peripheral: CBPeripheral, eventID: UUID?, state: CBPeripheralState) {
        guard state == .connected else { return }
        if retiring === peripheral, eventID == retiringConnectionID {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        guard connected === peripheral, eventID == connectionID,
              connectionWait?.generation == generation else { return }
        connectionStatus = "已连接，寻找 FF00 服务…"
        peripheral.discoverServices([Self.serviceUUID])
    }

    fileprivate func didEndConnection(_ peripheral: CBPeripheral, eventID: UUID?, state: CBPeripheralState, error: Error?) {
        guard state == .disconnected else { return }
        if retiring === peripheral {
            guard eventID == retiringConnectionID else { return }
            retiring = nil
            retiringConnectionID = nil
            managerDelegate.activeConnectionID = nil
            if disconnectWait?.peripheral === peripheral { finishDisconnect(.success(Void())) }
            return
        }
        guard connected === peripheral, eventID == connectionID else { return }
        retireSession(error: error ?? WaterError.disconnected, physicallyDisconnected: true)
    }

    private func accepts(_ peripheral: CBPeripheral, generation expected: UInt64) -> Bool {
        expected == generation && connected === peripheral && retiring == nil
    }

    fileprivate func servicesDiscovered(_ peripheral: CBPeripheral, generation expected: UInt64, error: Error?) {
        guard accepts(peripheral, generation: expected), connectionWait != nil, service == nil else { return }
        guard error == nil, let found = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            retireSession(error: error ?? WaterError.invalid("此设备没有 FF00 水控服务")); return
        }
        service = found
        peripheral.discoverCharacteristics([Self.notifyUUID, Self.writeUUID], for: found)
    }

    fileprivate func characteristicsDiscovered(_ peripheral: CBPeripheral, service found: CBService,
                                              generation expected: UInt64, error: Error?) {
        guard accepts(peripheral, generation: expected), service === found, connectionWait != nil,
              notifyCharacteristic == nil, writeCharacteristic == nil else { return }
        guard error == nil, let characteristics = found.characteristics,
              let notify = characteristics.first(where: { $0.uuid == Self.notifyUUID }),
              let write = characteristics.first(where: { $0.uuid == Self.writeUUID }),
              notify.properties.contains(.notify) || notify.properties.contains(.indicate),
              write.properties.contains(.write) else {
            retireSession(error: error ?? WaterError.invalid("FF01/FF02 特征不支持通知和有回执写入")); return
        }
        notifyCharacteristic = notify
        writeCharacteristic = write
        connectionStatus = "正在订阅 FF01 通知…"
        peripheral.setNotifyValue(true, for: notify)
    }

    fileprivate func notificationChanged(_ peripheral: CBPeripheral, characteristic: CBCharacteristic,
                                         generation expected: UInt64, isNotifying: Bool, error: Error?) {
        guard accepts(peripheral, generation: expected), notifyCharacteristic === characteristic else { return }
        guard error == nil, isNotifying else {
            retireSession(error: error ?? WaterError.disconnected); return
        }
        ready = writeCharacteristic != nil
        connectionStatus = "已就绪，可读取水表状态"
        finishConnection(.success(Void()))
    }

    fileprivate func writeCompleted(_ peripheral: CBPeripheral, characteristic: CBCharacteristic,
                                    generation expected: UInt64, commandToken: UUID?, error: Error?) {
        guard accepts(peripheral, generation: expected), writeCharacteristic === characteristic,
              var pending = commandWait, pending.generation == expected,
              pending.token == commandToken, pending.writeInFlight else { return }
        guard error == nil else { retireSession(error: error!); return }
        pending.writeInFlight = false
        commandWait = pending
        if pending.chunks.isEmpty { finishCommandIfComplete(); return }
        let token = pending.token
        chunkDelay = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
            guard let self = self, self.generation == expected, self.commandWait?.token == token,
                  self.connected === peripheral, self.writeCharacteristic === characteristic else { return }
            self.sendNextChunk()
        }
    }

    fileprivate func received(_ peripheral: CBPeripheral, characteristic: CBCharacteristic,
                              generation expected: UInt64, commandToken: UUID?, bytes: Data?, error: Error?) {
        guard accepts(peripheral, generation: expected), notifyCharacteristic === characteristic else { return }
        guard error == nil else { retireSession(error: error!); return }
        guard let bytes = bytes else { return }
        // Preserve callback-time provenance, including notifications queued before
        // the first write. Never join fragments across command boundaries.
        if rxCommandToken != commandToken {
            rxBytes.removeAll(keepingCapacity: true)
            rxCommandToken = commandToken
        }
        rxBytes.append(bytes)
        guard rxBytes.count <= 8192 else {
            retireSession(error: WaterError.invalid("通知数据超过接收缓存")); return
        }
        while let newline = rxBytes.firstIndex(of: 0x0A) {
            let end = rxBytes.index(after: newline)
            let wire = rxBytes.subdata(in: rxBytes.startIndex..<end)
            rxBytes.removeSubrange(rxBytes.startIndex..<end)
            guard let frame = BleFrame.parseWire(wire), let command = BleFrame.command(frame),
                  let payload = BleFrame.payload(frame) else {
                lastDiagnostic = "收到 CRC 或格式错误的应答帧"
                continue
            }
            guard var pending = commandWait, pending.generation == expected,
                  pending.writeStarted, pending.token == commandToken,
                  pending.command == command, pending.response == nil else {
                lastDiagnostic = String(format: "收到异步帧 0x%02X（%d 字节），未处理", command, payload.count)
                continue
            }
            pending.response = payload
            commandWait = pending
            finishCommandIfComplete()
        }
    }
}

// CoreBluetooth delegates are nonisolated Objective-C protocols in Swift 5.
// The manager uses .main; bridges enqueue in order onto the main actor. Each
// physical peripheral session gets a new delegate capturing its generation.
private final class BleManagerDelegate: NSObject, CBCentralManagerDelegate {
    weak var owner: BleCentral?
    // Main-queue provenance for callbacks enqueued across a disconnect/reconnect.
    var activeConnectionID: UUID?
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        DispatchQueue.main.async { [weak self] in self?.owner?.managerStateChanged(central, state: state) }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        DispatchQueue.main.async { [weak self] in
            self?.owner?.discovered(peripheral, advertisement: advertisementData, rssi: RSSI)
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let eventID = activeConnectionID
        let state = peripheral.state
        DispatchQueue.main.async { [weak self] in self?.owner?.didConnect(peripheral, eventID: eventID, state: state) }
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let eventID = activeConnectionID
        let state = peripheral.state
        DispatchQueue.main.async { [weak self] in
            self?.owner?.didEndConnection(peripheral, eventID: eventID, state: state, error: error)
        }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let eventID = activeConnectionID
        let state = peripheral.state
        DispatchQueue.main.async { [weak self] in
            self?.owner?.didEndConnection(peripheral, eventID: eventID, state: state, error: error)
        }
    }
}

private final class BleSessionDelegate: NSObject, CBPeripheralDelegate {
    weak var owner: BleCentral?
    let generation: UInt64
    // Read/written only on the manager's .main delegate queue / main actor.
    var activeCommandToken: UUID?
    init(owner: BleCentral, generation: UInt64) { self.owner = owner; self.generation = generation }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.owner?.servicesDiscovered(peripheral, generation: self.generation, error: error)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.owner?.characteristicsDiscovered(peripheral, service: service, generation: self.generation, error: error)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let isNotifying = characteristic.isNotifying
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.owner?.notificationChanged(peripheral, characteristic: characteristic, generation: self.generation,
                                            isNotifying: isNotifying, error: error)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let token = activeCommandToken
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.owner?.writeCompleted(peripheral, characteristic: characteristic, generation: self.generation,
                                       commandToken: token, error: error)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Snapshot now: characteristic.value may change before the actor runs.
        let bytes = characteristic.value
        let token = activeCommandToken
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.owner?.received(peripheral, characteristic: characteristic, generation: self.generation,
                                 commandToken: token, bytes: bytes, error: error)
        }
    }
}

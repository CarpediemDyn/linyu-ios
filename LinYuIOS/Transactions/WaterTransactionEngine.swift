import Foundation

/// Mirrors BleShowerController. The journal preserves observed facts and scopes
/// credentials to a local session; opaque meter records are never interpreted as ownership.
@MainActor final class WaterTransactionEngine {
    private(set) var journal: WaterJournal
    private(set) var busy = false
    private(set) var persistenceFailed = false
    var onChange: (() -> Void)?
    private let transport: WaterMeterTransport
    private let service: WaterMeterService
    private let store: WaterJournalStore
    private let decodeWriteBack: (String) -> Data?

    init(transport: WaterMeterTransport, service: WaterMeterService, store: WaterJournalStore,
         decodeWriteBack: @escaping (String) -> Data?) throws {
        self.transport = transport; self.service = service; self.store = store
        self.decodeWriteBack = decodeWriteBack
        journal = try store.load()
        guard journal.version == 1,
              Set(journal.transactions.map(\.id)).count == journal.transactions.count,
              journal.transactions.allSatisfy({ tx in
                  ![WaterPhase.serverRecorded, .writeBackPending, .completed].contains(tx.phase) || tx.receipt != nil
              }) else { throw WaterError.storage }
        for i in journal.transactions.indices where journal.transactions[i].phase == .uploading {
            journal.transactions[i].phase = .uploadUnknown
        }
    }

    private func begin() throws {
        guard !busy else { throw WaterError.busy }
        guard !persistenceFailed else { throw WaterError.storage }
        busy = true; onChange?()
    }
    private func end() { busy = false; onChange?() }

    private func persist(_ next: WaterJournal) throws {
        do { try store.save(next); journal = next; onChange?() }
        catch {
            journal = next; persistenceFailed = true; onChange?()
            throw WaterError.storage
        }
    }

    private func save(_ record: WaterTransaction) throws {
        var next = journal
        var updated = record; updated.updatedAt = Date()
        if let i = next.transactions.firstIndex(where: { $0.id == record.id }) { next.transactions[i] = updated }
        else { next.transactions.append(updated) }
        try persist(next)
    }

    private func record(_ id: UUID, session: QzxySession) throws -> WaterTransaction {
        guard let result = journal.transactions.first(where: { $0.id == id }),
              result.binding.ownerScope == session.ownerScope,
              !session.loginCode.isEmpty else { throw WaterError.identity }
        return result
    }

    private func sameDevice(_ lhs: MeterBinding, _ rhs: MeterBinding) -> Bool {
        lhs.peripheralID == rhs.peripheralID || lhs.device.snCode == rhs.device.snCode
    }

    private func pending(_ binding: MeterBinding, session: QzxySession) -> WaterTransaction? {
        journal.transactions.last { $0.isPending && $0.binding.ownerScope == session.ownerScope && sameDevice($0.binding, binding) }
    }

    func lookupMACs(_ address: String) -> [String] {
        guard let mac = LedgerDevice.normalizeMAC(address), let first = UInt8(mac.prefix(2), radix: 16) else { return [] }
        let derived = String(format: "%02X", first & 0x3F) + mac.dropFirst(2)
        return derived == mac ? [mac] : [mac, derived]
    }

    private func matches(_ identity: WaterMeterIdentity, device: LedgerDevice) -> Bool {
        let observed = lookupMACs(identity.macAddress)
        return lookupMACs(device.apiMAC).contains { observed.contains($0) }
    }

    private func query() async throws -> BleDeviceState {
        let payload = try await transport.exchange(0x23, payload: BleDeviceState.queryPayload)
        guard let state = BleDeviceState.parse(payload) else { throw WaterError.invalid("无法解析水表状态") }
        return state
    }

    private func verified(_ binding: MeterBinding, session: QzxySession) async throws -> BleDeviceState {
        guard binding.ownerScope == session.ownerScope, !session.loginCode.isEmpty else { throw WaterError.identity }
        try await transport.connectForTransaction(to: binding.peripheralID)
        guard transport.peripheralID == binding.peripheralID else { throw WaterError.identity }
        let state = try await query()
        guard let identity = state.identity else { throw WaterError.unsupportedIdentity }
        // UUID selects the connection; the self-reported MAC routes it to the ledger.
        // Project/device/account bytes are not a cryptographic identity or an ownership proof.
        guard matches(identity, device: binding.device), identity.macAddress == binding.observedMAC else { throw WaterError.identity }
        return state
    }

    /// Associates iOS discovery with a ledger response; callers perform this automatically.
    /// Kept as `pair` for existing callers, with no user-facing pairing ceremony.
    func pair(device: LedgerDevice, session: QzxySession) async throws -> MeterBinding {
        try begin(); defer { end() }
        guard !session.loginCode.isEmpty, let id = transport.peripheralID else { throw WaterError.disconnected }
        let state = try await query()
        guard let identity = state.identity else { throw WaterError.unsupportedIdentity }
        guard matches(identity, device: device) else { throw WaterError.identity }
        let binding = MeterBinding(peripheralID: id, ownerScope: session.ownerScope, device: device,
                                   observedMAC: identity.macAddress, verifiedAt: Date())
        var next = journal
        next.bindings.removeAll { $0.peripheralID == id && $0.ownerScope == session.ownerScope }
        next.bindings.append(binding)
        try persist(next)
        return binding
    }

    private func newRecord(binding: MeterBinding, state: BleDeviceState) -> WaterTransaction {
        WaterTransaction(id: UUID(), binding: binding, phase: state.state == 1 ? .running : .closed,
            valve: state.state == 1 ? .open : .closed, protocolType: state.protocolType,
            randomNumber: state.randomNumber, consumeDate: "", orderNo: "", consumption: nil, receipt: nil,
            writeBack: nil, failureReportPending: false, lastError: nil, updatedAt: Date())
    }

    func open(binding: MeterBinding, session: QzxySession) async throws {
        try begin(); defer { end() }
        try await transport.reconnectForTransaction(to: binding.peripheralID)
        let state = try await verified(binding, session: session)
        if [3, 6].contains(state.state) {
            var tx = pending(binding, session: session) ?? newRecord(binding: binding, state: state)
            try save(tx)
            try await settle(&tx, state: state, session: session)
            transport.disconnect()
            if tx.phase == .writeBackPending { throw WaterError.recovered(tx.lastError ?? "上一笔消费已记账，设备清账尚未完成，请重试恢复") }
            throw WaterError.recovered("已结清上一笔遗留账单，请重新点击开阀")
        }
        if state.state != 0 {
            // Original resumes only a local active order for this same device.
            guard var tx = pending(binding, session: session), tx.valve == .open || tx.phase == .running else {
                throw WaterError.invalid("设备正在使用中")
            }
            tx.phase = .running; tx.valve = .open; tx.lastError = nil
            if tx.startedAt == nil { tx.startedAt = Date() }
            try save(tx)
            return
        }
        // A fresh idle query allows another attempt on this device. Other devices'
        // active orders do not block it. Preserve server receipts rather than discarding them.
        if var previous = pending(binding, session: session) {
            previous.valve = .closed; previous.idleConfirmed = true
            previous.phase = previous.receipt == nil ? .superseded : .completed
            previous.failureReportPending = false
            try save(previous)
        }
        let connection = transport.connectionID
        var tx = newRecord(binding: binding, state: state)
        tx.phase = .rateRequested
        try save(tx)
        do {
            let grant = try await service.grantRate(device: binding.device, state: state, session: session)
            guard !grant.downData.isEmpty, grant.downData.count <= 252 else {
                throw WaterError.invalid("服务端费率数据无效，已停止启动")
            }
            tx.consumeDate = grant.consumeDate; tx.orderNo = grant.orderNo; tx.phase = .rateReady
            try save(tx)
            guard transport.peripheralID == binding.peripheralID, transport.connectionID == connection else {
                throw WaterError.disconnected
            }
            try Task.checkCancellation()
            tx.phase = .opening; tx.valve = .unknown
            try save(tx)
            let ack = try await transport.exchange(0x21, payload: grant.downData)
            guard ack.first == 0x80 else { throw WaterError.invalid("未能确认设备已开启，请确认水流状态后决定是否重试") }
            // Upstream's writeRate ACK is the successful open outcome; no extra query is required.
            tx.phase = .running; tx.valve = .open; tx.lastError = nil
            tx.startedAt = Date()
            try save(tx)
        } catch {
            tx.lastError = error.localizedDescription
            if tx.phase == .rateRequested, let problem = error as? WaterError, case .rejected = problem { tx.phase = .rateRejected }
            try save(tx)
            throw error
        }
    }

    func closeAndSettle(id: UUID, session: QzxySession) async throws {
        try begin(); defer { end() }
        var tx = try record(id, session: session)
        guard tx.isPending else { return }
        do {
            if [WaterPhase.uploadUnknown, .collected, .writeBackPending].contains(tx.phase) {
                try await transport.reconnectForTransaction(to: tx.binding.peripheralID)
            }
            var state = try await verified(tx.binding, session: session)
            if state.state == 1 {
                // A recorded receipt belongs to an earlier closed session, not new running usage.
                guard tx.receipt == nil else { throw WaterError.reconciliation }
                tx.phase = .closing; tx.valve = .unknown; tx.idleConfirmed = false; try save(tx)
                do {
                    let ack = try await transport.exchange(0x22, payload: Data([0]))
                    guard ack.first == 0x80 else { throw WaterError.invalid("关闭设备未确认，请重试") }
                } catch {
                    await reportFailureIfNeeded(&tx, session: session)
                    throw error
                }
                // The close ACK is a valve fact even if reconnection later fails.
                tx.valve = .closed; tx.phase = .closed; try save(tx)
                transport.disconnect()
                do { try await transport.reconnectForTransaction(to: tx.binding.peripheralID) }
                catch {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    try await transport.reconnectForTransaction(to: tx.binding.peripheralID)
                }
                state = try await verified(tx.binding, session: session)
            }
            guard [0, 3, 6].contains(state.state) else { throw WaterError.invalid("设备关闭状态未确认") }
            tx.valve = .closed; tx.idleConfirmed = state.state == 0; try save(tx)
            if state.state == 0, tx.receipt != nil {
                tx.phase = .completed; tx.lastError = nil; tx.failureReportPending = false; try save(tx)
                return
            }
            try await settle(&tx, state: state, session: session)
        } catch {
            tx.lastError = error.localizedDescription
            if tx.receipt != nil { tx.phase = .writeBackPending }
            try save(tx)
            throw error
        }
    }

    private func settle(_ tx: inout WaterTransaction, state: BleDeviceState, session: QzxySession) async throws {
        if tx.receipt == nil {
            do {
                let current = try await transport.exchange(0x85, payload: Data([0]))
                guard WaterProtocolIdentity.validConsumption(current) else {
                    throw WaterError.invalid("设备返回的消费数据无效，请靠近后重试")
                }
                // Reconnect retry uses the current opaque record and fresh challenge, as Android does.
                tx.consumption = current; tx.protocolType = state.protocolType; tx.randomNumber = state.randomNumber
                tx.phase = .collected; try save(tx)
                tx.phase = .uploading; try save(tx)
                do { tx.receipt = try await service.uploadConsumption(current, state: state, session: session) }
                catch {
                    tx.phase = .uploadUnknown
                    if let problem = error as? WaterError, case .rejected = problem { tx.phase = .collected }
                    throw error
                }
                tx.phase = .serverRecorded; tx.failureReportPending = false; try save(tx)
            } catch {
                // Original reports close/collection/upload failure, but never lets a failed
                // report replace the actual valve or accounting outcome.
                if !persistenceFailed { await reportFailureIfNeeded(&tx, session: session) }
                tx.lastError = error.localizedDescription; try save(tx)
                throw error
            }
        }
        try await finishWriteBack(&tx)
    }

    private func finishWriteBack(_ tx: inout WaterTransaction) async throws {
        guard let receipt = tx.receipt else { throw WaterError.invalid("服务端结算凭据缺失") }
        tx.phase = .writeBackPending; try save(tx)
        if tx.writeBack == nil {
            guard let bytes = decodeWriteBack(receipt.clData), !bytes.isEmpty, bytes.count <= 252 else {
                tx.lastError = "已关阀、已记账，写回数据无效；下次连接重试"
                try save(tx)
                return
            }
            tx.writeBack = bytes; try save(tx)
        }
        do {
            let ack = try await transport.exchange(0x86, payload: tx.writeBack!)
            guard ack.first == 0x80 else { throw WaterError.invalid("服务器已记账，设备清账未确认") }
            tx.writeBackAcknowledged = true
            tx.phase = .completed; tx.valve = .closed; tx.failureReportPending = false; tx.lastError = nil
            // A writeBack ACK clears the record in the original. Do not invent a final idle query.
        } catch {
            tx.phase = .writeBackPending
            tx.lastError = "已关阀、已记账，设备写回未确认；下次连接重试"
        }
        try save(tx)
    }

    func recover(id: UUID, session: QzxySession) async throws {
        try await closeAndSettle(id: id, session: session)
    }

    /// Keeps closing a known active session available when storage cannot be updated.
    func closeValveOnly(id: UUID, session: QzxySession) async throws {
        guard !busy else { throw WaterError.busy }
        busy = true; onChange?(); defer { end() }
        var tx = try record(id, session: session)
        guard tx.isPending else { return }
        let state = try await verified(tx.binding, session: session)
        if state.state == 1 {
            guard tx.receipt == nil else { throw WaterError.reconciliation }
            tx.valve = .unknown
            do { try save(tx) } catch { }
            do {
                let ack = try await transport.exchange(0x22, payload: Data([0]))
                guard ack.first == 0x80 else { throw WaterError.invalid("关阀未确认") }
            } catch {
                await reportFailureIfNeeded(&tx, session: session)
                throw error
            }
        } else if ![0, 3, 6].contains(state.state) { throw WaterError.invalid("关阀状态未确认") }
        tx.valve = .closed; tx.lastError = "仅确认关阀，结算与清账仍需恢复处理"
        do { try save(tx) } catch { }
    }

    func adoptPending(binding: MeterBinding, session: QzxySession) async throws -> UUID {
        try begin(); defer { end() }
        let state = try await verified(binding, session: session)
        if let existing = pending(binding, session: session) { return existing.id }
        // State 1 alone cannot establish that someone else's active usage is ours.
        guard [3, 6].contains(state.state) else { throw WaterError.invalid("设备没有可补结算的记录；用水中的设备需本地活跃订单") }
        let tx = newRecord(binding: binding, state: state)
        try save(tx)
        return tx.id
    }

    private func reportFailureIfNeeded(_ tx: inout WaterTransaction, session: QzxySession) async {
        guard !tx.consumeDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, tx.receipt == nil else { return }
        tx.failureReportPending = true
        do {
            try await service.reportFailure(consumeDate: tx.consumeDate, session: session)
            tx.failureReportPending = false
        } catch { }
    }

    func retryFailureReport(id: UUID, session: QzxySession) async throws {
        try begin(); defer { end() }
        var tx = try record(id, session: session)
        guard tx.failureReportPending, !tx.consumeDate.isEmpty, tx.receipt == nil else { throw WaterError.reconciliation }
        try await service.reportFailure(consumeDate: tx.consumeDate, session: session)
        tx.failureReportPending = false
        try save(tx)
    }
}

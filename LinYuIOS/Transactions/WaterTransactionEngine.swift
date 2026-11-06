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
                  ![WaterPhase.serverRecorded, .writeBackPending, .completed].contains(tx.phase)
                      || tx.receipt != nil || (tx.phase == .completed && tx.billConfirmed == true && tx.idleConfirmed)
              }) else { throw WaterError.storage }
        for i in journal.transactions.indices {
            var record = journal.transactions[i]
            if record.phase == .uploading { record.phase = .uploadUnknown }
            if record.phase == .superseded, !record.orderNo.isEmpty || !record.consumeDate.isEmpty || record.consumption != nil {
                record.phase = .needsAttention
                record.idleConfirmed = false
            }
            if record.isPending, record.isSettlementRecovery, record.closureEvidence == nil {
                record.legacyUnverifiedSettlement = true
                record.valve = .unknown
                record.idleConfirmed = false
            }
            journal.transactions[i] = record
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
        lhs.observedMAC == rhs.observedMAC
            && (lhs.peripheralID == rhs.peripheralID
                || (!lhs.device.snCode.isEmpty && lhs.device.snCode == rhs.device.snCode))
    }

    private func pending(_ binding: MeterBinding, session: QzxySession) -> WaterTransaction? {
        journal.transactions.last { $0.isPending && !$0.idleConfirmed && $0.binding.ownerScope == session.ownerScope && sameDevice($0.binding, binding) }
    }

    private func hasUsageEvidence(_ tx: WaterTransaction) -> Bool {
        tx.phase != .rateRejected
            && (tx.startedAt != nil || [.opening, .running, .closing].contains(tx.phase) || tx.isSettlementRecovery)
    }

    private func latestUnresolvedUsage(for binding: MeterBinding) -> WaterTransaction? {
        journal.transactions.last { $0.isPending && sameDevice($0.binding, binding) && hasUsageEvidence($0) }
    }

    private func hasNewerUsage(than tx: WaterTransaction) -> Bool {
        guard let index = journal.transactions.firstIndex(where: { $0.id == tx.id }) else { return false }
        return journal.transactions.dropFirst(index + 1).contains {
            sameDevice($0.binding, tx.binding) && hasUsageEvidence($0)
        }
    }

    private func mayCloseRunningValve(for tx: WaterTransaction) -> Bool {
        [.opening, .running, .closing].contains(tx.phase) && !tx.isSettlementRecovery && !hasNewerUsage(than: tx)
    }

    private func confirmClosure(_ tx: inout WaterTransaction, by evidence: ValveClosureEvidence) {
        tx.valve = .closed
        if tx.closureEvidence == nil {
            tx.closureEvidence = evidence
            tx.closureConfirmedAt = Date()
        }
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

    private func verified(_ binding: MeterBinding, session: QzxySession, reconnect: Bool = false,
                          trace: LatencyTrace? = nil) async throws -> BleDeviceState {
        guard binding.ownerScope == session.ownerScope, !session.loginCode.isEmpty else { throw WaterError.identity }
        trace?.mark(reconnect ? "reconnecting" : "connecting")
        if reconnect { try await transport.reconnectForTransaction(to: binding.peripheralID) }
        else { try await transport.connectForTransaction(to: binding.peripheralID) }
        guard transport.peripheralID == binding.peripheralID else { throw WaterError.identity }
        let connection = transport.connectionID
        trace?.mark("ble_ready")
        let state = try await query()
        guard transport.peripheralID == binding.peripheralID, transport.connectionID == connection else {
            throw WaterError.disconnected
        }
        trace?.mark("state_received")
        guard let identity = state.identity else { throw WaterError.unsupportedIdentity }
        // UUID selects the connection; the self-reported MAC routes it to the ledger.
        // Project/device/account bytes are not a cryptographic identity or an ownership proof.
        guard matches(identity, device: binding.device), identity.macAddress == binding.observedMAC else { throw WaterError.identity }
        return state
    }

    /// Proof of the observation used to select the server ledger, scoped to this BLE connection.
    /// Only the fresh command path can read a protocol challenge for controlling the valve.
    struct AssociationObservation {
        let peripheralID: UUID
        fileprivate let connectionID: UUID
        let identity: WaterMeterIdentity
        let state: UInt8?
    }

    private func observeAssociation() async throws -> AssociationObservation {
        guard let id = transport.peripheralID else { throw WaterError.disconnected }
        let connection = transport.connectionID
        let payload = try await transport.exchange(0x23, payload: BleDeviceState.queryPayload)
        guard transport.peripheralID == id, transport.connectionID == connection else { throw WaterError.disconnected }
        guard let identity = WaterProtocolIdentity.state(payload) else { throw WaterError.unsupportedIdentity }
        return AssociationObservation(peripheralID: id, connectionID: connection, identity: identity,
                                      state: BleDeviceState.parse(payload)?.state)
    }

    func readAssociation() async throws -> AssociationObservation {
        try begin(); defer { end() }
        return try await observeAssociation()
    }

    func pair(device: LedgerDevice, session: QzxySession, observation: AssociationObservation? = nil) async throws -> MeterBinding {
        try begin(); defer { end() }
        guard !session.loginCode.isEmpty else { throw WaterError.identity }
        let proof: AssociationObservation
        if let observation { proof = observation }
        else { proof = try await observeAssociation() }
        let id = proof.peripheralID
        let identity = proof.identity
        guard transport.peripheralID == id, transport.connectionID == proof.connectionID,
              matches(identity, device: device) else { throw WaterError.identity }
        let binding = MeterBinding(peripheralID: id, ownerScope: session.ownerScope, device: device,
                                   observedMAC: identity.macAddress, verifiedAt: Date())
        var next = journal
        next.bindings.removeAll { $0.peripheralID == id && $0.ownerScope == session.ownerScope }
        next.bindings.append(binding)
        try persist(next)
        return binding
    }

    private func newRecord(binding: MeterBinding, state: BleDeviceState) -> WaterTransaction {
        var tx = WaterTransaction(id: UUID(), binding: binding, phase: state.state == 1 ? .running : .closed,
            valve: state.state == 1 ? .open : .unknown, protocolType: state.protocolType,
            randomNumber: state.randomNumber, consumeDate: "", orderNo: "", consumption: nil, receipt: nil,
            writeBack: nil, failureReportPending: false, lastError: nil, updatedAt: Date())
        if [0, 3, 6].contains(state.state) { confirmClosure(&tx, by: .verifiedDeviceState) }
        return tx
    }

    func open(binding: MeterBinding, session: QzxySession, trace: LatencyTrace? = nil) async throws {
        try begin(); defer { end() }
        // An ambiguous write needs a new connection and a fresh status check before an explicit retry.
        let reconnect = pending(binding, session: session)?.valve == .unknown
        let state = try await verified(binding, session: session, reconnect: reconnect, trace: trace)
        if [3, 6].contains(state.state) {
            let unresolved = latestUnresolvedUsage(for: binding)
            if let unresolved, unresolved.binding.ownerScope != session.ownerScope {
                throw WaterError.reconciliation
            }
            var tx = unresolved ?? newRecord(binding: binding, state: state)
            guard !hasNewerUsage(than: tx) else { throw WaterError.reconciliation }
            confirmClosure(&tx, by: .verifiedDeviceState)
            try save(tx)
            defer { transport.disconnect() }
            if needsBillCheck(tx) { try await checkBill(&tx, session: session, trace: trace) }
            try await settleClosed(&tx, state: state, session: session, trace: trace, freshClose: false)
            if tx.phase == .writeBackPending { throw WaterError.recovered(tx.lastError ?? "上一笔消费已记账，设备清账尚未完成，请重试恢复") }
            throw WaterError.recovered("已结清上一笔遗留账单，请重新点击开阀")
        }
        if state.state != 0 {
            guard state.state == 1 else { throw WaterError.invalid("设备状态待核实，请重新连接") }
            // Original resumes only a local active order for this same device.
            guard var tx = pending(binding, session: session), tx.usageState == .running,
                  !hasNewerUsage(than: tx) else {
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
            confirmClosure(&previous, by: .verifiedDeviceState)
            previous.idleConfirmed = true
            if previous.receipt != nil || previous.billConfirmed == true {
                previous.phase = .completed
                previous.lastError = nil
                previous.failureReportPending = false
            } else if previous.phase != .uploadUnknown {
                previous.phase = .needsAttention
            }
            try save(previous)
        }
        let connection = transport.connectionID
        var tx = newRecord(binding: binding, state: state)
        tx.phase = .rateRequested; tx.valve = .unknown
        tx.closureEvidence = nil; tx.closureConfirmedAt = nil
        try save(tx)
        do {
            trace?.mark("rate_request")
            let grant = try await service.grantRate(device: binding.device, state: state, session: session)
            trace?.mark("rate_received")
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
            trace?.mark("open_sent")
            let ack = try await transport.exchange(0x21, payload: grant.downData)
            guard ack.first == 0x80 else { throw WaterError.invalid("未能确认设备已开启，请确认水流状态后决定是否重试") }
            trace?.mark("open_ack")
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

    func closeAndSettle(id: UUID, session: QzxySession, trace: LatencyTrace? = nil) async throws {
        try begin(); defer { end() }
        var tx = try record(id, session: session)
        guard tx.isPending else { return }
        var usedBluetooth = false
        defer {
            if usedBluetooth, tx.valve == .closed, transport.peripheralID == tx.binding.peripheralID {
                transport.disconnect()
            }
        }
        var stage = "核实服务器账单"
        do {
            let checkedBill = needsBillCheck(tx)
            if checkedBill { try await checkBill(&tx, session: session, trace: trace) }
            if tx.idleConfirmed, tx.closureEvidence != nil, tx.billConfirmed == true {
                try completeIdle(&tx)
                return
            }
            if tx.phase == .uploadUnknown, tx.usageState == .settlementPending, tx.billConfirmed != true {
                // An ambiguous charge cannot be resolved by inspecting a previously closed meter.
                throw WaterError.invalid("服务器结算结果待核实，请稍后再次查询账单")
            }
            if tx.isSettlementRecovery {
                stage = "核对本地订单"
                guard !hasNewerUsage(than: tx) else { throw WaterError.reconciliation }
                guard transport.isAvailableForRecovery(tx.binding.peripheralID) else {
                    stage = "等待原水表"
                    throw WaterError.invalid(WaterError.meterRecoveryGuidance)
                }
            }

            usedBluetooth = true
            stage = "连接水表并读取状态"
            trace?.mark("close_query")
            var state = try await verified(tx.binding, session: session, reconnect: tx.isSettlementRecovery, trace: trace)
            var closedOnThisConnection = false
            if state.state == 1 {
                // A settlement record cannot authorize stopping a later session.
                guard mayCloseRunningValve(for: tx) else { throw WaterError.reconciliation }
                stage = "确认关阀（0x22）"
                tx.phase = .closing; tx.valve = .unknown; tx.idleConfirmed = false; try save(tx)
                do {
                    trace?.mark("close_sent")
                    let ack = try await transport.exchange(0x22, payload: Data([0]))
                    guard ack.first == 0x80 else { throw WaterError.invalid("关闭设备未确认，请重试") }
                } catch {
                    trace?.mark("close_ack_missing")
                    await reportFailureIfNeeded(&tx, session: session)
                    trace?.mark("failure_report_finished")
                    throw error
                }
                closedOnThisConnection = true
                trace?.mark("close_ack")
                confirmClosure(&tx, by: .closeAcknowledgement)
                tx.phase = .closed; try save(tx)
                trace?.mark("closed_saved")
                stage = "关阀后重新连接水表"
                transport.disconnect()
                trace?.mark("reconnecting")
                do { try await transport.reconnectForTransaction(to: tx.binding.peripheralID) }
                catch {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    try await transport.reconnectForTransaction(to: tx.binding.peripheralID)
                }
                trace?.mark("ble_ready")
                stage = "重连后读取水表状态（0x23）"
                state = try await verified(tx.binding, session: session)
                trace?.mark("settle_state_received")
            }
            stage = "确认水表关闭状态（0x23）"
            guard [0, 3, 6].contains(state.state) else { throw WaterError.invalid("设备关闭状态未确认") }
            if state.state != 0, [.rateRequested, .rateReady].contains(tx.phase) {
                throw WaterError.reconciliation
            }
            let wasClosed = tx.closureEvidence != nil
            confirmClosure(&tx, by: .verifiedDeviceState)
            if state.state == 0, !closedOnThisConnection { tx.idleConfirmed = true }
            try save(tx)
            if !wasClosed { trace?.mark("closed_saved") }
            stage = "恢复结算"
            tx.lastError = nil
            if state.state == 0, !closedOnThisConnection, !checkedBill, needsBillCheck(tx) {
                stage = "核实服务器账单"
                try await checkBill(&tx, session: session, trace: trace)
                stage = "恢复结算"
            }
            try await settleClosed(&tx, state: state, session: session, trace: trace, freshClose: closedOnThisConnection)
        } catch {
            if !persistenceFailed {
                if stage != "恢复结算" || tx.lastError == nil {
                    tx.lastError = "\(stage)：\(error.localizedDescription)"
                }
                try save(tx)
            }
            throw error
        }
    }

    private func needsBillCheck(_ tx: WaterTransaction) -> Bool {
        tx.receipt == nil && tx.billConfirmed != true
            && (tx.phase == .uploadUnknown || tx.idleConfirmed || tx.legacyUnverifiedSettlement == true)
    }

    private func checkBill(_ tx: inout WaterTransaction, session: QzxySession, trace: LatencyTrace?) async throws {
        trace?.mark("bill_check")
        let recorded = try await service.hasRecordedConsumption(tx, session: session)
        trace?.mark(recorded ? "bill_recorded" : "bill_unconfirmed")
        if recorded {
            tx.billConfirmed = true
            try save(tx)
        }
    }

    private func completeIdle(_ tx: inout WaterTransaction) throws {
        tx.phase = .completed
        tx.idleConfirmed = true
        tx.lastError = nil
        tx.failureReportPending = false
        try save(tx)
    }

    private func settleClosed(_ tx: inout WaterTransaction, state: BleDeviceState, session: QzxySession,
                              trace: LatencyTrace?, freshClose: Bool) async throws {
        if state.state == 0, !freshClose {
            if tx.receipt != nil || tx.billConfirmed == true {
                try completeIdle(&tx)
                return
            }
            throw WaterError.invalid("水表当前空闲，服务器结算结果仍待核实")
        }
        if tx.phase == .uploadUnknown || tx.billConfirmed == true {
            throw WaterError.invalid(tx.billConfirmed == true
                ? "账单已核实，原水表仍有遗留数据，缺少清账凭据"
                : "服务器结算结果待核实，请稍后再次查询账单")
        }
        if !freshClose, tx.legacyUnverifiedSettlement == true, tx.consumption == nil {
            throw WaterError.invalid("无法把水表遗留数据与这笔历史订单对应，请在账单中核对")
        }
        if !freshClose, tx.receipt != nil {
            trace?.mark("verify_writeback_record")
            do {
                let current = try await transport.exchange(0x85, payload: Data([0]))
                guard current == tx.consumption, WaterProtocolIdentity.validConsumption(current) else {
                    throw WaterError.reconciliation
                }
            } catch {
                tx.lastError = "清账前核对水表消费数据（0x85）：\(error.localizedDescription)"
                try save(tx)
                throw error
            }
        }
        try await settle(&tx, state: state, session: session, trace: trace)
    }

    private func settle(_ tx: inout WaterTransaction, state: BleDeviceState, session: QzxySession, trace: LatencyTrace? = nil) async throws {
        if tx.receipt == nil {
            var stage = "采集水表消费数据（0x85）"
            do {
                trace?.mark("collect_sent")
                let current = try await transport.exchange(0x85, payload: Data([0]))
                trace?.mark("collect_received")
                guard WaterProtocolIdentity.validConsumption(current) else {
                    throw WaterError.invalid("设备返回的消费数据无效，请靠近后重试")
                }
                // Never attach a different meter record to an existing transaction.
                if let previous = tx.consumption, previous != current { throw WaterError.reconciliation }
                // Retry uses the meter's current protocol and fresh challenge.
                tx.consumption = current; tx.protocolType = state.protocolType; tx.randomNumber = state.randomNumber
                tx.phase = .collected; try save(tx)
                tx.phase = .uploading; try save(tx)
                stage = "上传消费数据"
                trace?.mark("upload_request")
                do {
                    tx.receipt = try await service.uploadConsumption(current, state: state, session: session)
                    trace?.mark("upload_received")
                }
                catch {
                    tx.phase = .uploadUnknown
                    if let problem = error as? WaterError, case .rejected = problem { tx.phase = .collected }
                    throw error
                }
                tx.phase = .serverRecorded; tx.failureReportPending = false; try save(tx)
            } catch {
                // Original reports close/collection/upload failure, but never lets a failed
                // report replace the actual valve or accounting outcome.
                if !persistenceFailed {
                    let mismatch: Bool
                    if let water = error as? WaterError, case .reconciliation = water { mismatch = true }
                    else { mismatch = false }
                    if tx.phase != .uploadUnknown, !mismatch { await reportFailureIfNeeded(&tx, session: session) }
                    tx.lastError = "\(stage)：\(error.localizedDescription)"
                    try save(tx)
                }
                throw error
            }
        }
        try await finishWriteBack(&tx, trace: trace)
    }

    private func finishWriteBack(_ tx: inout WaterTransaction, trace: LatencyTrace? = nil) async throws {
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
            trace?.mark("writeback_sent")
            let ack = try await transport.exchange(0x86, payload: tx.writeBack!)
            guard ack.first == 0x80 else { throw WaterError.invalid("服务器已记账，设备清账未确认") }
            trace?.mark("writeback_ack")
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
            guard mayCloseRunningValve(for: tx) else { throw WaterError.reconciliation }
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
        confirmClosure(&tx, by: state.state == 1 ? .closeAcknowledgement : .verifiedDeviceState)
        tx.phase = .closed; tx.lastError = "仅确认关阀，结算与清账仍需恢复处理"
        do { try save(tx) } catch { }
    }

    func adoptPending(binding: MeterBinding, session: QzxySession) async throws -> UUID {
        try begin(); defer { end() }
        let state = try await verified(binding, session: session)
        if let existing = latestUnresolvedUsage(for: binding) {
            guard existing.binding.ownerScope == session.ownerScope else { throw WaterError.reconciliation }
            return existing.id
        }
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

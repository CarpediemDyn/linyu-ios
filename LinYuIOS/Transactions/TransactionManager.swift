import Foundation
import Combine

@MainActor final class KeychainWaterJournal: WaterJournalStore {
    private let key = "water-journal-v1"
    func load() throws -> WaterJournal {
        guard let data = try KeychainStore.getChecked(key) else { return WaterJournal() }
        do { return try JSONDecoder().decode(WaterJournal.self, from: data) }
        catch { throw WaterError.storage }
    }
    func save(_ journal: WaterJournal) throws {
        let data = try JSONEncoder().encode(journal)
        guard KeychainStore.put(data, for: key) else { throw WaterError.storage }
    }
}

@MainActor final class TransactionManager: ObservableObject {
    @Published private(set) var journal = WaterJournal()
    @Published private(set) var working = false
    @Published private(set) var message = "请登录并连接水表，然后核对设备身份"
    @Published private(set) var storageBlocked = false
    @Published private(set) var failureMessage: String?
    @Published private(set) var serverRejected = false
    private let transport: WaterMeterTransport
    private weak var auth: AuthManager?
    private let api = QzxyAPI()
    private var engine: WaterTransactionEngine?

    init(transport: WaterMeterTransport, auth: AuthManager) {
        self.transport = transport
        self.auth = auth
        do {
            let value = try WaterTransactionEngine(transport: transport, service: api, store: KeychainWaterJournal(), decodeWriteBack: Self.decodeWriteBack)
            engine = value
            value.onChange = { [weak self, weak value] in
                guard let self, let value else { return }
                self.journal = value.journal
                self.storageBlocked = value.persistenceFailed
            }
            journal = value.journal
        } catch {
            storageBlocked = true
            message = "交易记录无法读取，未启用交易。请保留应用数据并通过官方应用核实用水状态。"
        }
    }

    static func decodeWriteBack(_ base64: String) -> Data? {
        guard let text = KailuAES.decrypt(base64: base64),
              let separator = text.firstIndex(of: "-"), separator != text.startIndex else { return nil }
        let hex = String(text[text.index(after: separator)...])
        guard !hex.isEmpty, hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return Data(hex: hex)
    }

    private func perform(_ action: (WaterTransactionEngine) async throws -> Void) async {
        guard !working, let engine else { return }
        working = true
        auth?.transactionInProgress = true
        defer {
            working = false; journal = engine.journal; storageBlocked = engine.persistenceFailed
            auth?.transactionInProgress = false
        }
        failureMessage = nil; serverRejected = false
        do { try await action(engine) }
        catch {
            message = error.localizedDescription
            if let water = error as? WaterError, case .rejected = water { serverRejected = true }
            if let water = error as? WaterError, case .recovered = water { failureMessage = nil }
            else { failureMessage = message }
            OriginalLogs.shared.add(message)
        }
    }

    func pair(session: QzxySession, ledgerMAC: String) async {
        await perform { engine in
            let payload = try await transport.exchange(0x23, payload: Data([0]))
            guard let identity = BleDeviceState.parse(payload)?.identity else { throw WaterError.unsupportedIdentity }
            let candidates = ledgerMAC.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? engine.lookupMACs(identity.macAddress) : [ledgerMAC]
            var lastError: Error = WaterError.identity
            for address in candidates {
                do {
                    let device = try await api.ledgerDevice(ledgerMAC: address, session: session)
                    _ = try await engine.pair(device: device, session: session)
                    message = "水表身份与台账已匹配：\(device.name)。每次操作前会重新核对。"
                    return
                } catch { lastError = error }
            }
            throw lastError
        }
    }

    func open(binding: MeterBinding, session: QzxySession, trace: LatencyTrace? = nil) async {
        await perform { engine in
            try await engine.open(binding: binding, session: session, trace: trace)
            message = "设备已确认进入用水状态；结束时请关阀并结算"
        }
    }

    func associate(device: LedgerDevice, session: QzxySession) async -> MeterBinding? {
        var result: MeterBinding?
        await perform { engine in result = try await engine.pair(device: device, session: session) }
        return result
    }

    func close(id: UUID, session: QzxySession, trace: LatencyTrace? = nil) async {
        await perform { engine in
            try await engine.closeAndSettle(id: id, session: session, trace: trace)
            message = engine.journal.transactions.first(where: { $0.id == id })?.statusText ?? "请核对交易状态"
        }
    }

    func recover(id: UUID, session: QzxySession) async {
        await perform { engine in
            try await engine.recover(id: id, session: session)
            message = engine.journal.transactions.first(where: { $0.id == id })?.statusText ?? "请核对交易状态"
        }
    }

    func recoverMeter(binding: MeterBinding, session: QzxySession) async {
        await perform { engine in
            let id = try await engine.adoptPending(binding: binding, session: session)
            try await engine.recover(id: id, session: session)
            message = engine.journal.transactions.first(where: { $0.id == id })?.statusText ?? "请核对交易状态"
        }
    }

    func closeOnly(id: UUID, session: QzxySession) async {
        await perform { engine in
            try await engine.closeValveOnly(id: id, session: session)
            message = "已确认关阀；结算和清账仍需恢复处理"
        }
    }

    func retryFailure(id: UUID, session: QzxySession) async {
        await perform { engine in
            try await engine.retryFailureReport(id: id, session: session)
            message = "故障上报已提交，请通过官方账单核对订单"
        }
    }
}

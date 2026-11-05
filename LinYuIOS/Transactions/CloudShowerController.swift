import Foundation
import Combine
import CoreFoundation

struct CloudActiveOrder: Codable, Equatable, Identifiable {
    var id: String { snCode }
    let snCode: String
    var orderNo: String
    let deviceName: String
    let deviceMac: String
    var startedAt: Date
    var autoDisConTime: Int
    var autoDisconnectAt: Date?
    var elapsedSeconds: Int { max(0, Int(Date().timeIntervalSince(startedAt))) }
    var autoDisconRemain: Int { autoDisconnectAt.map { max(0, Int(ceil($0.timeIntervalSinceNow))) } ?? 0 }
}

enum CloudShowerError: LocalizedError {
    case rejected(String, code: Int?)
    case inUseByOthers
    case unconfirmed(String)
    case busy
    case badDevice
    case sessionChanged
    var errorCode: Int? { if case .rejected(_, let code) = self { return code }; return nil }
    var errorDescription: String? {
        switch self {
        case .rejected(let text, _), .unconfirmed(let text): return text
        case .inUseByOthers: return "该设备正在被他人使用"
        case .busy: return "该设备操作正在进行，请稍候"
        case .badDevice: return "设备信息不完整"
        case .sessionChanged: return "账号已切换，请刷新用水状态"
        }
    }
}

/// Separate original TCP/cloud control path. Never use this for a Bluetooth-only meter.
@MainActor final class CloudShowerController: ObservableObject {
    @Published private(set) var active: [CloudActiveOrder] = []
    @Published private(set) var lastMessage: String?
    @Published private(set) var latestSettlementYuan: Decimal?
    @Published private(set) var settlementYuanByOrder: [String: Decimal] = [:]
    @Published private(set) var mqttConnected = false
    @Published private(set) var transportMessage = "HTTP 轮询确认设备状态"

    private struct PendingSettlement: Codable, Equatable {
        let order: CloudActiveOrder
        let createdAt: Date
    }
    private struct Saved: Codable {
        var orders: [String: CloudActiveOrder]
        var pending: [PendingSettlement]
    }
    private let api: QzxyAPI
    private let defaults: UserDefaults
    private let mqttEnabled: Bool
    private let mqtt = OriginalMQTTClient()
    private let pause: (UInt64) async throws -> Void
    private var accountKey: String?
    private var currentSession: QzxySession?
    private var pending: [PendingSettlement] = []
    private var busy: Set<String> = []
    private var refreshing = false
    private var monitor: Task<Void, Never>?
    private var orderPolls: [String: Task<Void, Never>] = [:]

    init(api: QzxyAPI? = nil, defaults: UserDefaults = .standard,
         mqttEnabled: Bool = false,
         pause: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        if let api { self.api = api } else { self.api = QzxyAPI() }
        self.defaults = defaults; self.mqttEnabled = mqttEnabled; self.pause = pause
        mqtt.onConnectionChange = { [weak self] connected in
            self?.mqttConnected = connected
            self?.transportMessage = connected ? "MQTT 已连接，HTTP 持续核对状态" : "MQTT 不可用，使用 HTTP 轮询"
        }
        mqtt.onMessage = { [weak self] _, _ in
            // Notifications can arrive late or refer to another order. Never apply their amounts/state directly.
            Task { @MainActor [weak self] in
                guard let self, let session = self.currentSession else { return }
                await self.refresh(session: session)
            }
        }
    }

    /// Immediately changes the visible account without discarding its persisted orders.
    /// Call synchronously on login/logout, before scheduling any asynchronous refresh.
    func activate(session: QzxySession?) {
        stopMonitoring()
        if let session {
            _ = use(session)
        } else {
            active = []
            pending = []
            busy = []
            refreshing = false
            accountKey = nil
            currentSession = nil
            latestSettlementYuan = nil
            settlementYuanByOrder = [:]
            lastMessage = nil
        }
    }

    func open(snCode: String, name: String, mac: String, session: QzxySession, trace: LatencyTrace? = nil) async throws {
        let key = use(session)
        guard !snCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudShowerError.badDevice
        }
        guard busy.insert(snCode).inserted else { throw CloudShowerError.busy }
        defer { if accountKey == key { busy.remove(snCode) } }
        // Original duplicate behavior: a local active device is resumed, other devices remain usable.
        if active.contains(where: { $0.snCode == snCode }) { lastMessage = "已恢复正在进行的用水"; return }
        let deadline = Date().addingTimeInterval(6)
        trace?.mark("prequery")
        let existing = try await query(snCode, session)
        trace?.mark("prequery_received")
        try check(key)
        if running(existing) == true {
            guard existing.data?["isOwner"] as? Bool != false else { throw CloudShowerError.inUseByOthers }
            ensure(snCode: snCode, name: name, mac: mac, orderNo: text(existing.data?["orderNo"]) ?? "",
                   auto: integer(existing.data?["autoDisConTime"]) ?? 0)
            lastMessage = "已恢复正在进行的用水"
            return
        }
        // This financial request is sent exactly once. Only read-only confirmation is polled.
        trace?.mark("rate_request")
        let sent = try await api.originalRequest("/order/tcpDevice/downRate/rateOrder",
                                                post: ["xfModel": "0", "snCode": snCode], session: session)
        try check(key)
        trace?.mark("rate_received")
        guard sent.success else { throw CloudShowerError.rejected(sent.message, code: sent.errorCode) }
        var auto = integer(sent.data?["autoDisConTime"]) ?? 0
        for attempt in 0...8 {
            if attempt > 0 && Date() >= deadline {
                lastMessage = "开阀结果尚未确认，请刷新设备状态，勿重复开启"
                throw CloudShowerError.unconfirmed(lastMessage!)
            }
            try await pause(700_000_000)
            try check(key)
            let result: QzxyResponse
            trace?.mark("confirm_poll")
            do {
                result = try await api.originalRequest("/order/tcpDevice/query/downRateResult",
                                                       post: ["snCode": snCode], session: session)
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
            try check(key)
            trace?.mark("confirm_received")
            let data = result.data
            if result.success && (integer(data?["state"]) == 0 || integer(data?["result"]) == 0 || text(data?["orderNo"]) != nil) {
                if let time = integer(data?["autoDisConTime"]), time > 0 { auto = time }
                ensure(snCode: snCode, name: name, mac: mac, orderNo: text(data?["orderNo"]) ?? "", auto: auto)
                lastMessage = "开阀已确认"
                fillOrderNo(snCode: snCode, session: session, key: key)
                return
            }
        }
        lastMessage = "开阀未确认成功，请确认热水器是否已开启"
        throw CloudShowerError.unconfirmed(lastMessage!)
    }

    func close(snCode: String, session: QzxySession, trace: LatencyTrace? = nil) async throws {
        let key = use(session)
        guard !snCode.isEmpty else { throw CloudShowerError.badDevice }
        guard busy.insert(snCode).inserted else { throw CloudShowerError.busy }
        defer { if accountKey == key { busy.remove(snCode) } }
        var order = active.first { $0.snCode == snCode }
        var number = order?.orderNo ?? ""
        if number.isEmpty {
            trace?.mark("prequery")
            let response = try await query(snCode, session)
            trace?.mark("prequery_received")
            try check(key)
            guard response.data?["isOwner"] as? Bool != false else { throw CloudShowerError.inUseByOthers }
            number = text(response.data?["orderNo"]) ?? ""
            if let index = active.firstIndex(where: { $0.snCode == snCode }), !number.isEmpty {
                active[index].orderNo = number; order = active[index]; save()
            }
        }
        trace?.mark("close_request")
        let response: QzxyResponse
        do {
            response = try await api.originalRequest("/order/tcpDevice/closeOrder",
                                                     post: ["snCode": snCode, "orderNo": number], session: session)
        } catch is CancellationError { throw CancellationError() }
        catch {
            // Actual original checks once, retains local state, and never claims success after a transport failure.
            _ = try? await query(snCode, session)
            try check(key)
            lastMessage = "关阀请求没发出去，设备可能还在用水：\(error.localizedDescription)"
            throw CloudShowerError.unconfirmed(lastMessage!)
        }
        try check(key)
        guard response.success || response.errorCode == 307 || response.message.contains("已在") else {
            throw CloudShowerError.rejected(response.message, code: response.errorCode)
        }
        trace?.mark("close_accepted")
        if response.success {
            trace?.mark("postquery")
            _ = try? await query(snCode, session); try check(key)
            trace?.mark("postquery_received")
        }
        // Current upstream deliberately does not poll closeOrder/result/query: accepted close is sufficient.
        active.removeAll { $0.snCode == snCode }
        orderPolls.removeValue(forKey: snCode)?.cancel()
        if var stopped = order {
            stopped.orderNo = number
            pending.removeAll { $0.order.snCode == snCode && $0.order.orderNo == number }
            pending.append(PendingSettlement(order: stopped, createdAt: Date()))
        }
        save()
        lastMessage = "关阀已受理，正在查询结算"
        if let order {
            trace?.mark("bill_lookup")
            latestSettlementYuan = try await settle(orderNo: number, order: order, session: session, key: key)
            trace?.mark("bill_lookup_finished")
            if let amount = latestSettlementYuan { settlementYuanByOrder[settlementKey(order)] = amount }
            lastMessage = latestSettlementYuan == nil ? "关阀已受理，结算中" : "用水已结束"
        }
    }

    /// Query at startup after a use-code/physical device is resolved. Does not issue an open request.
    @discardableResult
    func discover(snCode: String, name: String, mac: String, session: QzxySession) async -> OriginalDeviceAvailability {
        let key = use(session)
        guard !snCode.isEmpty, !busy.contains(snCode) else { return .unknown }
        do {
            let response = try await query(snCode, session)
            try check(key)
            if running(response) == true {
                if response.data?["isOwner"] as? Bool == false { lastMessage = "该设备正在被他人使用"; return .occupied }
                ensure(snCode: snCode, name: name, mac: mac, orderNo: text(response.data?["orderNo"]) ?? "",
                       auto: integer(response.data?["autoDisConTime"]) ?? 0)
                return .running
            }
            if running(response) == false { return .idle }
        } catch { if accountKey == key { lastMessage = error.localizedDescription } }
        return .unknown
    }

    func refresh(session: QzxySession) async {
        let key = use(session)
        guard !refreshing else { return }
        refreshing = true
        defer { if accountKey == key { refreshing = false } }
        for order in active where !busy.contains(order.snCode) {
            do {
                let response = try await query(order.snCode, session)
                try check(key)
                guard !busy.contains(order.snCode) else { continue }
                if running(response) == false || response.data?["isOwner"] as? Bool == false {
                    active.removeAll { $0.snCode == order.snCode }
                    if response.data?["isOwner"] as? Bool != false {
                        pending.append(PendingSettlement(order: order, createdAt: Date()))
                    }
                    save()
                } else if running(response) == true, let number = text(response.data?["orderNo"]), !number.isEmpty,
                          let index = active.firstIndex(where: { $0.snCode == order.snCode }) {
                    active[index].orderNo = number; save()
                }
            } catch is CancellationError { return }
            catch { if accountKey == key { lastMessage = "状态查询失败，保留用水记录：\(error.localizedDescription)" } }
            guard accountKey == key else { return }
        }
        // Pending includes uncertain zero-consumption conclusions for later bill reconciliation.
        for item in pending where !busy.contains(item.order.snCode) {
            do {
                if let amount = try await settle(orderNo: item.order.orderNo, order: item.order, session: session, key: key) {
                    latestSettlementYuan = amount
                    settlementYuanByOrder[settlementKey(item.order)] = amount
                }
            } catch is CancellationError { return }
            catch { }
            guard accountKey == key else { return }
        }
    }

    func startMonitoring(session: QzxySession) {
        _ = use(session)
        guard monitor == nil else { return }
        if mqttEnabled { mqtt.connect(phone: session.telephone) }
        monitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let current = self.currentSession else { return }
                await self.refresh(session: current)
                let nearest = self.active.compactMap(\.autoDisconnectAt).map { $0.timeIntervalSinceNow }.filter { $0 > 0 }.min() ?? 15
                do { try await Task.sleep(nanoseconds: UInt64(max(1, min(15, nearest))) * 1_000_000_000) } catch { return }
            }
        }
    }

    func stopMonitoring() {
        monitor?.cancel(); monitor = nil
        for task in orderPolls.values { task.cancel() }; orderPolls.removeAll()
        mqtt.disconnect()
    }

    /// A finished order's own amount, independent of another device settling later.
    func settlementAmount(for order: CloudActiveOrder) -> Decimal? {
        settlementYuanByOrder[settlementKey(order)]
    }

    private func settlementKey(_ order: CloudActiveOrder) -> String { order.snCode + ":" + order.orderNo }

    private func fillOrderNo(snCode: String, session: QzxySession, key: String) {
        guard active.first(where: { $0.snCode == snCode })?.orderNo.isEmpty == true else { return }
        orderPolls[snCode]?.cancel()
        orderPolls[snCode] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.accountKey == key { self.orderPolls[snCode] = nil } }
            for _ in 0...10 {
                do {
                    try await self.pause(800_000_000)
                    try self.check(key)
                    guard let index = self.active.firstIndex(where: { $0.snCode == snCode }), self.active[index].orderNo.isEmpty else { return }
                    let response = try await self.query(snCode, session)
                    try self.check(key)
                    if self.running(response) == true, response.data?["isOwner"] as? Bool != false,
                       let number = self.text(response.data?["orderNo"]), !number.isEmpty,
                       let current = self.active.firstIndex(where: { $0.snCode == snCode }) {
                        self.active[current].orderNo = number; self.save(); return
                    }
                } catch is CancellationError { return }
                catch CloudShowerError.sessionChanged { return }
                catch { }
            }
        }
    }

    private func query(_ snCode: String, _ session: QzxySession) async throws -> QzxyResponse {
        try await api.originalRequest("/order/tcpDevice/query/rateOrder/using",
                                      post: ["xfModel": "0", "snCode": snCode], session: session)
    }

    private func running(_ response: QzxyResponse) -> Bool? {
        if response.errorCode == 307 || (response.success && text(response.data?["orderNo"]) != nil) { return true }
        return response.success ? false : nil
    }

    private func ensure(snCode: String, name: String, mac: String, orderNo: String, auto: Int) {
        guard !active.contains(where: { $0.snCode == snCode }) else { return }
        let now = Date()
        active.append(CloudActiveOrder(snCode: snCode, orderNo: orderNo, deviceName: name, deviceMac: mac,
                                       startedAt: now, autoDisConTime: auto,
                                       autoDisconnectAt: auto > 0 ? now.addingTimeInterval(Double(auto)) : nil))
        save()
    }

    private func use(_ session: QzxySession) -> String {
        let identity = [session.projectId, session.accountId, session.userId, session.telephone]
        let key = "cloud-original-orders." + Data((identity.map { "\($0.utf8.count):\($0)" }.joined()).utf8).base64EncodedString()
        if accountKey != key {
            stopMonitoring()
            accountKey = key; busy = []; refreshing = false; latestSettlementYuan = nil; settlementYuanByOrder = [:]; lastMessage = nil
            let saved = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
            active = saved.map { Array($0.orders.values).sorted { $0.startedAt < $1.startedAt } } ?? []
            pending = saved?.pending ?? []
        }
        currentSession = session
        return key
    }

    private func check(_ key: String) throws {
        try Task.checkCancellation()
        guard accountKey == key else { throw CloudShowerError.sessionChanged }
    }

    private func save() {
        guard let accountKey,
              let data = try? JSONEncoder().encode(Saved(orders: Dictionary(uniqueKeysWithValues: active.map { ($0.snCode, $0) }), pending: pending)) else { return }
        defaults.set(data, forKey: accountKey)
    }

    private func text(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        return nil
    }
    private func integer(_ value: Any?) -> Int? { text(value).flatMap(Int.init) }

    // MARK: Original SettlementEngine probe/fallback semantics

    static func consumeYuan(_ response: QzxyResponse) -> Decimal? {
        let scopes = [response.data, response.json].compactMap { $0 }
        func amount(_ value: Any?) -> Decimal? {
            let raw: String
            if let string = value as? String { raw = string }
            else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { raw = number.stringValue }
            else { return nil }
            guard let decimal = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), !decimal.isNaN else { return nil }
            return decimal / 1000
        }
        for scope in scopes {
            for key in ["consumeMoney", "consumeMoneyStr", "money", "consumeAmount"] {
                if let value = amount(scope[key]) { return max(0, value) }
            }
        }
        for scope in scopes {
            for (key, raw) in scope {
                guard key.range(of: "consume|money|amount|fee|cost|pay|charge|price", options: [.regularExpression, .caseInsensitive]) != nil,
                      key.range(of: "balance|remain|surplus|account|wallet|pre|give|given|total|sum|count|id|no\\b|time|date|status|state", options: [.regularExpression, .caseInsensitive]) == nil,
                      let value = amount(raw), value > 0 else { continue }
                return value
            }
        }
        return nil
    }

    private func settle(orderNo: String, order: CloudActiveOrder, session: QzxySession, key: String) async throws -> Decimal? {
        var sawZero = false
        if !orderNo.isEmpty {
            for attempt in 0..<2 {
                let value = try await consumeProbe(orderNo, order.snCode, session, key)
                if let value, value > 0 { clearPending(order); return value }
                if value == 0 { sawZero = true; break }
                if attempt < 1 { try await pause(1_000_000_000); try check(key) }
            }
            if sawZero {
                for _ in 0..<2 {
                    try await pause(1_200_000_000); try check(key)
                    if let value = try await consumeProbe(orderNo, order.snCode, session, key), value > 0 {
                        clearPending(order); return value
                    }
                }
            }
        }
        var sawBill = false
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"
        for attempt in 0..<3 {
            do {
                let response = try await api.originalRequest("/order/query/account/bill/list",
                    query: ["month": formatter.string(from: Date()), "billRequestType": "2"], session: session)
                try check(key)
                if let bills = response.json["data"] as? [[String: Any]] {
                    let dtos = bills.compactMap { $0["consumeBillDTO"] as? [String: Any] }
                    let exact = orderNo.isEmpty ? nil : (dtos.first { text($0["orderNo"]) == orderNo } ?? dtos.first { text($0["orderId"]) == orderNo })
                    let time = DateFormatter(); time.locale = Locale(identifier: "en_US_POSIX"); time.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    let matched = exact ?? dtos.filter {
                        guard let raw = text($0["consumeDate"]), let date = time.date(from: raw) else { return false }
                        return date >= order.startedAt.addingTimeInterval(-180)
                    }.max { (text($0["consumeDate"]) ?? "") < (text($1["consumeDate"]) ?? "") }
                    if let matched {
                        sawBill = true
                        // Bill-list amounts already use yuan. Never divide them by 1000.
                        if let raw = text(matched["consumeMoney"]), let value = Decimal(string: raw), value > 0 {
                            clearPending(order); return value
                        }
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch CloudShowerError.sessionChanged { throw CloudShowerError.sessionChanged }
            catch { }
            if attempt < 2 { try await pause(1_200_000_000); try check(key) }
        }
        // Keep both unknown and inferred zero in pending for subsequent reconciliation, as upstream does.
        return sawZero && !sawBill ? 0 : nil
    }

    private func consumeProbe(_ orderNo: String, _ snCode: String, _ session: QzxySession, _ key: String) async throws -> Decimal? {
        do {
            let response = try await api.originalRequest("/order/consumeOrder/result/query",
                post: ["snCode": snCode, "orderNo": orderNo], session: session)
            try check(key)
            return Self.consumeYuan(response)
        } catch is CancellationError { throw CancellationError() }
        catch CloudShowerError.sessionChanged { throw CloudShowerError.sessionChanged }
        catch { return nil }
    }

    private func clearPending(_ order: CloudActiveOrder) {
        pending.removeAll { $0.order.snCode == order.snCode && $0.order.startedAt == order.startedAt }
        save()
    }
}

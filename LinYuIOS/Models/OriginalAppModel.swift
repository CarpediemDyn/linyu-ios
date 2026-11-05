import Foundation
import Combine
#if !LINYU_LIVECONTAINER
import WidgetKit
#endif

@MainActor final class OriginalAppModel: ObservableObject {
    let auth = AuthManager()
    let ble = BleCentral()
    let preferences = OriginalPreferences()
    let cloud = CloudShowerController(mqttEnabled: true)
    let logs = OriginalLogs.shared
    let api = QzxyAPI()
    let transactions: TransactionManager
    @Published var account: CampusAccountCache?
    @Published var balance: CampusBalanceSnapshot?
    @Published var bills: [CampusBill] = []
    @Published var unpaid: [CampusUnpaidBill] = []
    @Published var nearby: [UUID: CampusDevice] = [:]
    @Published var selectedDevice: CampusDevice?
    @Published var selectedPeripheral: UUID?
    @Published var showShower: UUID?
    @Published var showCloudShower: String?
    @Published var message = ""
    @Published var working = false
    @Published var refreshing = false
    @Published var codeCandidate: CampusCodeCandidate?
    @Published var candidateCreatedAt: Date?
    @Published var candidateClaimed = false
    @Published var billDetail: CampusBillDetail?
    @Published var candidateWorking = false
    @Published var manualBalance = ""
    @Published var pendingBluetoothFallback: CampusDevice?
    @Published var automaticFinish: OriginalFinishNotice?
    @Published var startFailure: OriginalStartFailure?
    private var deducing: Set<String> = []
    private var subscriptions = Set<AnyCancellable>()
    private var heartbeat: Task<Void, Never>?
    private var generation = UUID()
    private var foreground = false
    private var completedNotified = Set<String>()
    private var previousCloud: [String: CloudActiveOrder] = [:]
    private var endedCloud: [String: CloudActiveOrder] = [:]
    private var automaticallyEnded = Set<String>()
    private var userStoppingCloud = Set<String>()
    private var detailGeneration = UUID()
    private var unpaidRevision: UInt64 = 0
    private var refreshAgain = false
    private var deviceCache = CampusDeviceCache(ownerScope: "")
    private var lastWidgetPayload: Data?
    private var snapshotCleared = false

    init() {
        transactions = TransactionManager(transport: ble, auth: auth)
        for publisher in [auth.objectWillChange.eraseToAnyPublisher(), ble.objectWillChange.eraseToAnyPublisher(),
                          transactions.objectWillChange.eraseToAnyPublisher(), cloud.objectWillChange.eraseToAnyPublisher(),
                          preferences.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] _ in
                self?.objectWillChange.send()
                DispatchQueue.main.async { [weak self] in self?.publishSnapshot() }
            }.store(in: &subscriptions)
        }
        auth.$session.dropFirst().sink { [weak self] value in self?.accountChanged(value) }.store(in: &subscriptions)
        OriginalNotifications.shared.onAction = { [weak self] url in Task { await self?.handle(url) } }
        accountChanged(auth.session)
    }

    var activeBluetooth: [WaterTransaction] {
        transactions.journal.transactions.filter { $0.binding.ownerScope == auth.session?.ownerScope && $0.isPending }
    }
    var currentCloud: [CloudActiveOrder] { cloud.active }
    var filteredMeters: [DiscoveredWaterMeter] {
        ble.meters.filter { meter in
            guard let device = nearby[meter.id] else { return true }
            return OriginalFormatting.inSameRoom(account?.boundRoom ?? "", deviceName: device.deviceName)
        }
    }
    var selectedBinding: MeterBinding? {
        transactions.journal.bindings.first { $0.ownerScope == auth.session?.ownerScope && $0.device.deviceId == selectedDevice?.deviceId }
    }
    var isBusy: Bool { working || transactions.working || auth.transactionInProgress || !deducing.isEmpty }

    private func cacheKey(_ suffix: String, _ session: QzxySession) -> String { "replica.\(session.ownerScope).\(suffix)" }
    private func accountChanged(_ session: QzxySession?) {
        generation = UUID(); heartbeat?.cancel(); cloud.stopMonitoring()
        refreshing = false
        refreshAgain = false; unpaidRevision &+= 1
        candidateWorking = false; deducing = []; previousCloud = [:]; endedCloud = [:]
        automaticallyEnded = []
        lastWidgetPayload = nil; snapshotCleared = false
        OriginalNotifications.shared.clear()
        deviceCache = CampusDeviceCache(ownerScope: session?.ownerScope ?? "")
        billDetail = nil; manualBalance = ""; candidateClaimed = false
        automaticFinish = nil; pendingBluetoothFallback = nil; startFailure = nil
        cloud.activate(session: session)
        account = nil; balance = nil; bills = []; unpaid = []; nearby = [:]
        selectedDevice = nil; selectedPeripheral = nil; codeCandidate = nil; candidateCreatedAt = nil; showShower = nil; showCloudShower = nil
        guard let session else { publishSnapshot(); return }
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: cacheKey("account", session)), let cached = try? JSONDecoder().decode(CampusAccountCache.self, from: data), cached.matches(session) { account = cached }
        if let data = defaults.data(forKey: cacheKey("balance", session)), let cached = try? JSONDecoder().decode(CampusBalanceSnapshot.self, from: data), cached.matches(session) {
            balance = cached; bills = cached.bills; manualBalance = cached.manualBalance
        }
        if account == nil { account = CampusAccountCache(ownerScope: session.ownerScope) }
        if balance == nil { balance = CampusBalanceSnapshot(ownerScope: session.ownerScope) }
        Task { await refresh() }
        if foreground { Task { self.startForeground() } }
    }
    private func persist() {
        guard let session = auth.session else { return }
        if let account, account.matches(session), let data = try? JSONEncoder().encode(account) { UserDefaults.standard.set(data, forKey: cacheKey("account", session)) }
        if let balance, balance.matches(session), let data = try? JSONEncoder().encode(balance) { UserDefaults.standard.set(data, forKey: cacheKey("balance", session)) }
    }

    func refresh() async {
        guard let session = auth.session else { return }
        if refreshing { refreshAgain = true; return }
        refreshing = true; let token = generation
        let debtVersion = unpaidRevision
        defer {
            if generation == token {
                refreshing = false
                if refreshAgain { refreshAgain = false; Task { await self.refresh() } }
            }
        }
        async let profileResult = try? api.profile(session: session)
        async let walletResult = try? api.campusWallet(session: session)
        async let useCodeResult = try? api.useCode(session: session)
        async let unpaidResult = try? api.unpaidBills(session: session)
        let (profile, wallet, code, debts) = await (profileResult, walletResult, useCodeResult, unpaidResult)
        var fetched: [CampusBill] = []
        var successfulMonths = Set<String>()
        var requestedMonths = Set<String>()
        for offset in 0..<3 {
            let date = Calendar.current.date(byAdding: .month, value: -offset, to: Date())!
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM"
            let month = formatter.string(from: date)
            requestedMonths.insert(month)
            if let values = try? await api.bills(month: month, session: session) { fetched += values; successfulMonths.insert(month) }
        }
        guard generation == token else { return }
        if let profile {
            if let value = profile.name { account?.profile.name = value }
            if let value = profile.studentNumber { account?.profile.studentNumber = value }
            if let value = profile.schoolName { account?.profile.schoolName = value }
            if let value = profile.telephone { account?.profile.telephone = value }
            if let value = profile.cardStatusName { account?.profile.cardStatusName = value }
        }
        if let wallet {
            if let value = wallet.campusBalance { account?.wallet.campusBalance = value; balance?.campusBalance = value }
            if let value = wallet.walletBalance { account?.wallet.walletBalance = value; balance?.walletBalance = value }
            if let value = wallet.signStatus { account?.wallet.signStatus = value }
        }
        if let code { account?.useCode = code }
        if let debts, debtVersion == unpaidRevision { unpaid = debts }
        if !successfulMonths.isEmpty {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM"
            fetched += bills.filter { bill in guard let date = bill.date else { return false }; let month = formatter.string(from: date); return requestedMonths.contains(month) && !successfulMonths.contains(month) }
            var seen = Set<String>()
            bills = fetched.filter { seen.insert($0.id).inserted }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            balance?.bills = bills
        }
        persist(); await cloud.refresh(session: session)
        if let device = account?.lastDevice, !usesBluetooth(device), generation == token {
            await cloud.discover(snCode: device.snCode, name: device.deviceName, mac: device.macAddress, session: session)
        }
        if generation == token { publishSnapshot() }
    }

    func setForeground(_ value: Bool) {
        foreground = value
        if value { startForeground() } else { heartbeat?.cancel(); heartbeat = nil; cloud.stopMonitoring() }
    }
    private func startForeground() {
        heartbeat?.cancel(); guard let session = auth.session else { return }
        let token = generation
        cloud.startMonitoring(session: session)
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 25_000_000_000) } catch { return }
                guard let self, self.generation == token, self.auth.session?.loginCode == session.loginCode else { return }
                do { _ = try await self.api.useCode(session: session) }
                catch {
                    guard !Task.isCancelled, self.generation == token, self.auth.session?.loginCode == session.loginCode else { return }
                    if OriginalSessionFailure.isKickError(error) {
                        self.auth.expireSession("登录状态已失效，请重新登录"); return
                    }
                }
            }
        }
    }

    func choose(_ meter: DiscoveredWaterMeter, showDetail: Bool = true) async {
        guard let session = auth.session, !isBusy else { return }
        working = true; let token = generation; defer { working = false }
        do {
            try await ble.connectForTransaction(to: meter.id)
            let payload = try await ble.exchange(0x23, payload: Data([0]))
            guard let identity = WaterProtocolIdentity.state(payload), let device = try await cachedDevice(identity.macAddress, session: session) else { throw WaterError.invalid("没有查到这台设备的台账") }
            guard generation == token else { return }
            nearby[meter.id] = device; if showDetail { selectedDevice = device }; selectedPeripheral = meter.id
            setBluetooth(true, device: device)
            _ = await transactions.associate(device: try device.ledgerDevice, session: session)
            guard generation == token else { return }
            message = device.displayName
        } catch { report(error) }
    }

    func scanCode(_ sn: String) async {
        guard let session = auth.session, !isBusy else { return }
        working = true; let token = generation; defer { working = false }
        do {
            guard let device = try await cachedDevice(sn, session: session) else { throw WaterError.invalid("没有查到二维码对应的设备") }
            guard generation == token else { return }
            selectedDevice = device; selectedPeripheral = nearby.first(where: { $0.value.deviceId == device.deviceId })?.key
            if !usesBluetooth(device) { await cloud.discover(snCode: device.snCode, name: device.deviceName, mac: device.macAddress, session: session) }
        } catch { if generation == token { report(error) } }
    }

    func usesBluetooth(_ device: CampusDevice) -> Bool {
        device.needsBluetoothControl || UserDefaults.standard.bool(forKey: "ble-device.\(auth.session?.ownerScope ?? "").\(device.snCode)")
    }
    private func cachedDevice(_ mac: String, session: QzxySession) async throws -> CampusDevice? {
        if let value = deviceCache.device(for: mac, session: session) { return value }
        let value = try await api.deviceByMAC(mac, session: session)
        if let value, auth.session?.ownerScope == session.ownerScope { deviceCache.store(value, for: mac, session: session) }
        return value
    }
    func setBluetooth(_ value: Bool, device: CampusDevice) {
        UserDefaults.standard.set(value, forKey: "ble-device.\(auth.session?.ownerScope ?? "").\(device.snCode)")
        objectWillChange.send()
    }
    private func locate(_ device: CampusDevice, session: QzxySession) async throws -> MeterBinding {
        if let binding = transactions.journal.bindings.first(where: { $0.ownerScope == session.ownerScope && $0.device.deviceId == device.deviceId }) { return binding }
        if ble.meters.isEmpty {
            ble.startScan()
            for _ in 0..<70 { if !ble.scanning { break }; try await Task.sleep(nanoseconds: 100_000_000) }
        }
        let ids = selectedPeripheral.map { [$0] } ?? ble.meters.map(\.id)
        let expected = Set(OriginalFormatting.macLookupVariants(device.realMac ?? device.macAddress).compactMap(LedgerDevice.normalizeMAC))
        for id in ids {
            try Task.checkCancellation()
            do {
                try await ble.connectForTransaction(to: id)
                let raw = try await ble.exchange(0x23, payload: Data([0]))
                guard let reported = WaterProtocolIdentity.state(raw),
                      !expected.isDisjoint(with: OriginalFormatting.macLookupVariants(reported.macAddress).compactMap(LedgerDevice.normalizeMAC)) else { continue }
                if let binding = await transactions.associate(device: try device.ledgerDevice, session: session) { nearby[id] = device; return binding }
            } catch is CancellationError { throw CancellationError() } catch { logs.add("定位水表：\(error.localizedDescription)") }
        }
        throw WaterError.invalid("未在附近找到该水表，请开启蓝牙并靠近设备重试")
    }

    func start(_ device: CampusDevice) async {
        guard let session = auth.session, !isBusy else { return }
        working = true; let token = generation; defer { working = false; publishSnapshot() }
        do {
            if usesBluetooth(device) {
                let binding = try await locate(device, session: session)
                guard generation == token else { return }
                await transactions.open(binding: binding, session: session)
                message = transactions.message
                if let failure = transactions.failureMessage {
                    startFailure = OriginalStartFailure(message: failure, serverRejected: transactions.serverRejected)
                    return
                }
                if let record = activeBluetooth.last(where: { $0.binding.device.deviceId == device.deviceId }), record.valve != .closed { showShower = record.id }
            } else {
                try await cloud.open(snCode: device.snCode, name: device.deviceName, mac: device.macAddress, session: session)
                showCloudShower = device.snCode; message = cloud.lastMessage ?? "用水状态已更新"
            }
            if generation == token { account?.lastDevice = device; persist() }
        } catch {
            guard generation == token else { return }
            if let cloudError = error as? CloudShowerError, cloudError.errorCode == 306 { pendingBluetoothFallback = device }
            else {
                let rejected: Bool
                if let cloudError = error as? CloudShowerError, case .rejected = cloudError { rejected = true }
                else { rejected = false }
                startFailure = OriginalStartFailure(message: error.localizedDescription, serverRejected: rejected)
            }
            report(error)
        }
    }

    func endBluetooth(_ record: WaterTransaction) async {
        guard let session = auth.session, !isBusy else { return }
        working = true; defer { working = false; publishSnapshot() }
        if transactions.storageBlocked { await transactions.closeOnly(id: record.id, session: session) }
        else { await transactions.close(id: record.id, session: session) }
        message = transactions.message
        if let current = transactions.journal.transactions.first(where: { $0.id == record.id }), current.valve == .closed { showShower = nil }
        await refresh()
    }
    func endCloud(_ sn: String) async {
        guard let session = auth.session, !isBusy else { return }
        working = true; userStoppingCloud.insert(sn)
        defer { working = false; publishSnapshot(); userStoppingCloud.remove(sn) }
        do { try await cloud.close(snCode: sn, session: session); message = cloud.lastMessage ?? "用水已结束"; showCloudShower = nil; await refresh() }
        catch { report(error) }
    }
    func bindRoom(_ name: String) { account?.boundRoom = OriginalFormatting.roomKey(name) ?? ""; persist() }
    func setManualBalance() { balance?.manualBalance = manualBalance; balance?.manualBalanceTime = Date(); persist(); publishSnapshot() }

    func generateCode() async {
        guard let session = auth.session, !candidateWorking else { return }
        let token = generation
        candidateWorking = true; defer { if generation == token { candidateWorking = false } }
        do { let candidate = try await api.generateUseCode(session: session); guard generation == token else { return }; codeCandidate = candidate; candidateCreatedAt = Date(); candidateClaimed = false }
        catch { if generation == token { report(error) } }
    }
    func claimCode() async {
        guard let session = auth.session, let codeCandidate, !candidateWorking else { return }
        guard Date().timeIntervalSince(candidateCreatedAt ?? .distantPast) < 180 else { message = "候选码已过期，请重新获取"; return }
        let token = generation
        candidateWorking = true; defer { if generation == token { candidateWorking = false } }
        do { try await api.claimUseCode(codeCandidate.useCode, session: session); guard generation == token else { return }; self.codeCandidate = nil; candidateCreatedAt = nil; candidateClaimed = true; let code = try await api.useCode(session: session); guard generation == token else { return }; account?.useCode = code; persist() }
        catch { if generation == token { report(error) } }
    }
    func toggleCode(_ enabled: Bool) async {
        guard let session = auth.session else { return }
        let token = generation
        do { try await api.updateUseCodeStatus(enabled ? 1 : 0, session: session); let code = try await api.useCode(session: session); guard generation == token else { return }; account?.useCode = code; persist() }
        catch { if generation == token { report(error) } }
    }
    func loadDetail(_ bill: CampusBill) async {
        guard let session = auth.session else { return }; billDetail = nil
        let token = generation; let detailToken = UUID(); detailGeneration = detailToken
        do { let result = try await api.billDetail(orderId: bill.orderId, consumeDate: bill.consumeDate, session: session); guard generation == token, detailGeneration == detailToken else { return }; billDetail = result } catch { if generation == token, detailGeneration == detailToken { report(error) } }
    }
    func deduct(_ bill: CampusUnpaidBill) async {
        guard deducing.isEmpty else { message = "正在处理另一笔代扣，请稍候"; return }
        guard let session = auth.session, let date = bill.consumeDate else { return }
        let token = generation
        unpaidRevision &+= 1
        deducing.insert(date); objectWillChange.send()
        defer { if generation == token { deducing.remove(date); objectWillChange.send() } }
        do {
            let result = try await api.requestDeduct(consumeDate: date, confirmed: true, session: session)
            guard generation == token else { return }
            switch result { case .success: message = "代扣请求成功"; case .failed(let text): message = text; case .unknown: message = "代扣结果未确认，请先刷新账单，勿重复操作" }
            if result == .success { unpaid.removeAll { $0.consumeDate == date } }
            await reconcileUnpaid(session: session, token: token)
            await refresh()
        } catch { report(error) }
    }
    private func reconcileUnpaid(session: QzxySession, token: UUID) async {
        // Original reconcileUnpaid, followed by loadUnpaidBills only if the first fetch fails.
        for _ in 0..<2 {
            unpaidRevision &+= 1
            do { let list = try await api.unpaidBills(session: session); guard generation == token else { return }; unpaidRevision &+= 1; unpaid = list; return }
            catch { if generation != token { return } }
        }
    }
    func deductAll() async {
        guard let session = auth.session, deducing.isEmpty else { return }
        var seen = Set<String>()
        let dates = unpaid.compactMap { OriginalJSON.nonempty($0.consumeDate) }.filter { seen.insert($0).inserted }
        guard !dates.isEmpty else { return }
        let token = generation; deducing = Set(dates); objectWillChange.send()
        unpaidRevision &+= 1
        defer { if generation == token { deducing = []; objectWillChange.send() } }
        var success = 0; var failed = 0; var unknown = 0; var firstFailure: String?
        for date in dates {
            guard generation == token else { return }
            do {
                let result = try await api.requestDeduct(consumeDate: date, confirmed: true, session: session)
                guard generation == token else { return }
                switch result {
                case .success: success += 1; unpaid.removeAll { $0.consumeDate == date }
                case .failed(let reason): failed += 1; if firstFailure == nil { firstFailure = reason }
                case .unknown: unknown += 1
                }
            } catch { unknown += 1 }
        }
        guard generation == token else { return }
        await reconcileUnpaid(session: session, token: token)
        if unknown > 0 { message = "代扣结果：成功\(success)笔，失败\(failed)笔，\(unknown)笔结果未知，请刷新确认" }
        else if failed == 0 { message = "补扣成功，再试一次开阀" }
        else if success == 0 { message = firstFailure ?? "补扣失败，请到钱包页重试" }
        else { message = "代扣结果：成功\(success)笔，失败\(failed)笔" }
        await refresh()
    }
    func report(_ error: Error) {
        message = error.localizedDescription; logs.add(message)
        if error is CloudShowerError, preferences.notifyEnabled, preferences.notifyAlert {
            OriginalNotifications.shared.post(id: "device-alert", title: "用水状态提醒", text: message, url: nil)
        }
    }

    private func reloadWidgets() {
#if !LINYU_LIVECONTAINER
        WidgetCenter.shared.reloadAllTimelines()
#endif
    }

    func publishSnapshot() {
        guard let session = auth.session else {
            if !snapshotCleared { LinYuWidgetStorage.save(LinYuWidgetSnapshot()); reloadWidgets(); snapshotCleared = true }
            return
        }
        let previous = LinYuWidgetStorage.load()
        var snapshot = LinYuWidgetSnapshot(); snapshot.ownerScope = session.ownerScope
        if previous.ownerScope == session.ownerScope { snapshot.controlNonce = previous.controlNonce }
        snapshot.balance = balance?.formattedBalance ?? "¥ —"; snapshot.balanceTitle = balance?.title ?? "余额"
        snapshot.lastDevice = account?.lastDevice?.displayName ?? "暂无上次设备"; snapshot.lastDeviceID = account?.lastDevice?.deviceId ?? ""
        snapshot.orders = activeBluetooth.filter { $0.valve != .closed }.map { .init(id: $0.id.uuidString, title: $0.binding.device.name, startedAt: $0.startedAt ?? $0.updatedAt, isBluetooth: true) }
        snapshot.orders += cloud.active.map { .init(id: $0.snCode, title: $0.deviceName, startedAt: $0.startedAt, isBluetooth: false) }
        snapshot.bills = bills.prefix(3).map { .init(id: $0.id, title: $0.displayDesc, amount: OriginalFormatting.money($0.amount)) }
        var comparable = snapshot; comparable.updatedAt = .distantPast
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        if let payload = try? encoder.encode(comparable), payload != lastWidgetPayload {
            LinYuWidgetStorage.save(snapshot); reloadWidgets(); lastWidgetPayload = payload
        }
        let cloudNow = Dictionary(uniqueKeysWithValues: cloud.active.map { ($0.snCode, $0) })
        for (sn, order) in previousCloud where cloudNow[sn] == nil {
            endedCloud[sn + ":" + order.orderNo] = order
            OriginalNotifications.shared.remove(id: "inuse.\(sn)")
            if !userStoppingCloud.contains(sn) {
                automaticallyEnded.insert(sn + ":" + order.orderNo)
                if showCloudShower == sn { showCloudShower = nil }
                automaticFinish = OriginalFinishNotice(id: sn, title: order.deviceName, duration: Int(Date().timeIntervalSince(order.startedAt)), orderNumber: order.orderNo)
            }
        }
        previousCloud = cloudNow
        guard preferences.notifyEnabled else { OriginalNotifications.shared.clear(); return }
        if !preferences.notifyInUse { for order in snapshot.orders { OriginalNotifications.shared.remove(id: "inuse.\(order.id)") } }
        for (key, order) in endedCloud {
            let amount = cloud.settlementAmount(for: order).map { "，消费 ¥" + NSDecimalNumber(decimal: $0).stringValue } ?? "，结算中"
            let auto = automaticallyEnded.contains(key)
            if (auto && preferences.notifyAutoClose) || (!auto && preferences.notifyFinished) {
                OriginalNotifications.shared.post(id: "cloud-finished.\(key)", title: auto ? "热水器已自动关闭" : "用水已结束", text: order.deviceName + amount, url: nil)
            }
        }
        if let failure = transactions.failureMessage, preferences.notifyAlert { OriginalNotifications.shared.post(id: "ble-alert", title: "用水状态提醒", text: failure, url: nil) }
        for order in snapshot.orders where preferences.notifyInUse {
            OriginalNotifications.shared.post(id: "inuse.\(order.id)", title: "淋浴 · 正在用水", text: order.title, url: LinYuWidgetStorage.url(action: "stop", id: order.id), active: true)
        }
        for record in transactions.journal.transactions where record.binding.ownerScope == session.ownerScope && record.valve == .closed {
            let id = record.id.uuidString
            OriginalNotifications.shared.remove(id: "inuse.\(id)")
            if preferences.notifyFinished, record.receipt != nil, record.updatedAt > Date().addingTimeInterval(-1800), completedNotified.insert(id).inserted { OriginalNotifications.shared.post(id: "finished.\(id)", title: "用水已结束", text: record.binding.device.name, url: nil) }
        }
    }
    /// Expose only the amount already reconciled for this exact finished order.
    func confirmedFinishAmount(_ event: OriginalFinishNotice) -> Double? {
        guard let number = event.orderNumber, !number.isEmpty,
              let order = endedCloud[event.id + ":" + number],
              let amount = cloud.settlementAmount(for: order) else { return nil }
        let value = NSDecimalNumber(decimal: amount).doubleValue
        return value.isFinite ? value : nil
    }
    func handle(_ url: URL) async {
        guard url.scheme == "linyu", auth.session != nil else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let snapshot = LinYuWidgetStorage.load()
        guard items.first(where: { $0.name == "owner" })?.value == auth.session?.ownerScope,
              items.first(where: { $0.name == "nonce" })?.value == snapshot.controlNonce,
              snapshot.ownerScope == auth.session?.ownerScope else { return }
        let id = items.first(where: { $0.name == "id" })?.value ?? ""
        if url.host == "stop" {
            if let record = activeBluetooth.first(where: { $0.id.uuidString == id }) { await endBluetooth(record) }
            else if cloud.active.contains(where: { $0.snCode == id }) { await endCloud(id) }
        } else if url.host == "start", let device = account?.lastDevice, device.deviceId == id { await start(device) }
        else if url.host == "show" {
            if let record = activeBluetooth.first(where: { $0.id.uuidString == id }) { showShower = record.id }
            else if cloud.active.contains(where: { $0.snCode == id }) { showCloudShower = id }
        }
    }
}

struct OriginalFinishNotice: Identifiable {
    let id: String
    let title: String
    let duration: Int
    var orderNumber: String? = nil
}

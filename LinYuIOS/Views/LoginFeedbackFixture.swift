#if targetEnvironment(simulator)
import Foundation
import CoreFoundation

/// Drives the real login and home views from XCUITest without a real account.
@MainActor enum LoginFeedbackFixture {
    static func model() -> OriginalAppModel? {
        guard let scenario = ProcessInfo.processInfo.environment["LINYU_LOGIN_FIXTURE"] else { return nil }
        if let token = ProcessInfo.processInfo.environment["LINYU_LOGIN_GATE"] {
            LoginFixtureGate.configure(token)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginFeedbackURLProtocol.self]
        let api = QzxyAPI(session: URLSession(configuration: configuration))
        let session = QzxySession(telephone: "00000000000", loginCode: "fixture", userId: "7",
                                  accountId: "8", projectId: "9")
        var savedSession: Data? = scenario == "settlement-offline" ? try? JSONEncoder().encode(session) : nil
        let storage = AuthManager.SessionStorage(
            load: { savedSession },
            save: { savedSession = $0; return true },
            delete: { savedSession = nil }
        )
        let auth = AuthManager(api: api, storage: storage)
        let manager = scenario == "settlement-offline"
            ? TransactionManager(transport: UnavailableFixtureMeter(), auth: auth, service: api, store: FixtureJournal(session))
            : nil
        return OriginalAppModel(authentication: auth, network: api,
                                cloudController: CloudShowerController(api: api, mqttEnabled: false),
                                transactionManager: manager)
    }
}

@MainActor private final class FixtureJournal: WaterJournalStore {
    private var journal: WaterJournal

    init(_ session: QzxySession) {
        let started = Date(timeIntervalSince1970: 1_793_785_000)
        journal = WaterJournal(transactions: ["447", "450"].map { number in
            let mac = "C47F0E3E4C" + (number == "447" ? "A1" : "A2")
            let device = LedgerDevice(deviceId: number, snCode: number, name: "学生公寓 D7 四层 \(number)",
                                      macAddress: mac, realMac: nil, bigTypeId: "4", smallTypeId: "1")
            let binding = MeterBinding(peripheralID: UUID(), ownerScope: session.ownerScope, device: device,
                                       observedMAC: mac, verifiedAt: started)
            return WaterTransaction(id: UUID(), binding: binding, phase: .uploadUnknown, valve: .closed,
                protocolType: "1", randomNumber: "", consumeDate: "261104120000", orderNo: number,
                consumption: Data([0x80]), receipt: nil, writeBack: nil, failureReportPending: false,
                lastError: nil, updatedAt: started, startedAt: started)
        })
    }

    func load() throws -> WaterJournal { journal }
    func save(_ next: WaterJournal) throws { journal = next }
}

@MainActor private final class UnavailableFixtureMeter: WaterMeterTransport {
    let peripheralID: UUID? = nil
    let connectionID = UUID()
    func isAvailableForRecovery(_ id: UUID) -> Bool { false }
    func connectForTransaction(to id: UUID) async throws { throw WaterError.disconnected }
    func reconnectForTransaction(to id: UUID) async throws { throw WaterError.disconnected }
    func exchange(_ command: UInt8, payload: Data) async throws -> Data { throw WaterError.disconnected }
    func disconnect() {}
}

private final class LoginFeedbackURLProtocol: URLProtocol {
    private var delivery: DispatchWorkItem?
    private let deliveryID = UUID()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let scenario = ProcessInfo.processInfo.environment["LINYU_LOGIN_FIXTURE"]
        let delay: TimeInterval
        let body: String
        let isLogin = url.path == "/user/registerAndLogin"
        if isLogin {
            switch scenario {
            case "ordinary": delay = 0.55
            case "slow": delay = 6
            case "failure": delay = 1
            default: delay = 0
            }
            body = #"{"success":true,"data":{"loginCode":"fixture","userId":7,"userAccount":{"accountId":8,"projectId":9}}}"#
        } else if scenario == "settlement-offline", url.path == "/order/query/account/bill/list" {
            delay = 1
            body = #"{"success":true,"data":[{"consumeBillDTO":{"orderId":"bill-447","orderNo":"447","deviceSnCode":"447","consumeDate":"2026-11-04 12:00:00","consumeMoney":"0.41","description":"fixture"}}]}"#
        } else {
            delay = url.path == "/user/verification/code/get" ? 6 : 0
            body = #"{"success":true,"data":null}"#
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if isLogin, scenario == "failure" {
                let timeout = URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
                self.client?.urlProtocol(self, didFailWithError: timeout)
                return
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                            headerFields: ["Content-Type": "application/json"])!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(body.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        delivery = work
        if scenario == "slow", ProcessInfo.processInfo.environment["LINYU_LOGIN_GATE"] != nil,
           isLogin || url.path == "/user/verification/code/get" {
            LoginFixtureGate.hold(work, id: deliveryID)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    override func stopLoading() { delivery?.cancel(); LoginFixtureGate.remove(deliveryID) }
}

/// Simulator-only, cross-process test gate. UI automation can inspect/press the loading
/// button before explicitly releasing the mock response, without delaying real logins.
private enum LoginFixtureGate {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var name: String?
        var released = false
        var pending: [UUID: DispatchWorkItem] = [:]
    }
    private static let state = State()

    static func configure(_ token: String) {
        let name = "org.linyu.fixture.login." + token
        state.lock.lock()
        guard state.name != name else { state.lock.unlock(); return }
        let old = state.name
        state.name = name; state.released = false; state.pending = [:]
        state.lock.unlock()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(state).toOpaque()
        if let old { CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(old as CFString), nil) }
        CFNotificationCenterAddObserver(center, observer, { _, _, name, _, _ in
            if let name { LoginFixtureGate.release(name.rawValue as String) }
        }, name as CFString, nil, .deliverImmediately)
    }

    static func hold(_ work: DispatchWorkItem, id: UUID) {
        state.lock.lock()
        let released = state.released
        if !released { state.pending[id] = work }
        state.lock.unlock()
        if released { DispatchQueue.main.async(execute: work) }
    }

    static func release(_ name: String) {
        state.lock.lock()
        guard state.name == name else { state.lock.unlock(); return }
        state.released = true
        let jobs = Array(state.pending.values); state.pending = [:]
        state.lock.unlock()
        for work in jobs { DispatchQueue.main.async(execute: work) }
    }

    static func remove(_ id: UUID) {
        state.lock.lock(); defer { state.lock.unlock() }
        state.pending[id] = nil
    }
}
#endif

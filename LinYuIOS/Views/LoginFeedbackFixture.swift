#if targetEnvironment(simulator)
import Foundation

/// Drives the real login and home views from XCUITest without a real account.
@MainActor enum LoginFeedbackFixture {
    static func model() -> OriginalAppModel? {
        guard let scenario = ProcessInfo.processInfo.environment["LINYU_LOGIN_FIXTURE"] else { return nil }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    override func stopLoading() { delivery?.cancel() }
}
#endif

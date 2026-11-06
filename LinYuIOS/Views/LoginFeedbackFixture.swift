#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftUI

/// Drives the real login and home views from XCUITest without a real account.
@MainActor enum LoginFeedbackFixture {
    static func model() -> OriginalAppModel? {
        guard ProcessInfo.processInfo.environment["LINYU_LOGIN_FIXTURE"] != nil else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginFeedbackURLProtocol.self]
        let api = QzxyAPI(session: URLSession(configuration: configuration))
        var savedSession: Data?
        let storage = AuthManager.SessionStorage(
            load: { savedSession },
            save: { savedSession = $0; return true },
            delete: { savedSession = nil }
        )
        return OriginalAppModel(authentication: AuthManager(api: api, storage: storage), network: api,
                                cloudController: CloudShowerController(api: api, mqttEnabled: false))
    }
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
        } else {
            delay = url.path == "/user/verification/code/get" ? 6 : 0
            body = #"{"success":true,"data":null}"#
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if isLogin, scenario == "failure" {
                self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
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

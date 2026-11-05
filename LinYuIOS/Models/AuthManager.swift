import Foundation
import Combine

@MainActor final class AuthManager: ObservableObject {
    @Published private(set) var session: QzxySession?
    @Published var activity = ""
    @Published var deviceText = ""
    @Published var walletText = ""
    @Published var loading = false
    @Published var transactionInProgress = false

    private let api = QzxyAPI()
    private var loginTrace: LatencyTrace?

    func homeAppeared() {
        loginTrace?.finish("home_visible")
        loginTrace = nil
    }

    init() {
        if let data = KeychainStore.get("user-session") {
            session = try? JSONDecoder().decode(QzxySession.self, from: data)
        }
    }

    func sendSMS(phone: String) async {
        await perform {
            try await api.sendSMS(to: phone)
            activity = "短信请求已提交，请查看手机验证码"
        }
    }

    func login(phone: String, secret: String, usePassword: Bool, trace: LatencyTrace? = nil) async {
        await perform {
            defer { if session == nil { trace?.finish("failed") } }
            let result: QzxySession = usePassword
                ? try await api.loginWithPassword(phone: phone, password: secret, trace: trace)
                : try await api.loginWithSMS(phone: phone, code: secret, trace: trace)
            guard let data = try? JSONEncoder().encode(result), KeychainStore.put(data, for: "user-session") else {
                throw QzxyError.server("登录成功，但会话未能安全保存")
            }
            trace?.mark("session_saved")
            loginTrace = trace
            session = result
            activity = "登录成功，可查询学校设备台账"
        }
    }

    func fetchDevice(ledgerMAC: String) async {
        guard let session else { activity = "请先登录"; return }
        await perform {
            let result = try await api.findDevice(ledgerMAC: ledgerMAC, session: session)
            let data = result.data ?? [:]
            deviceText = "设备：\(data["deviceName"] ?? "未知")\nSN：\(data["snCode"] ?? "未知")\ndeviceId：\(data["deviceId"] ?? "未知")\n请人工核对台账 MAC 与蓝牙设备是否对应。"
        }
    }

    func fetchWallet() async {
        guard let session else { return }
        await perform {
            let result = try await api.wallet(session: session)
            // 仅展示必要的本地响应字段，不保存/上传完整钱包对象。
            if let data = result.data { walletText = "钱包响应字段：\(data.keys.sorted().joined(separator: "、"))" }
            else { walletText = "无钱包数据" }
        }
    }

    func logout() {
        guard !transactionInProgress else { activity = "用水操作处理中，请等待当前操作结束"; return }
        KeychainStore.delete("user-session")
        session = nil
        activity = "已退出登录"
        walletText = ""
        deviceText = ""
    }

    func replaceSession(_ value: QzxySession) throws {
        let data = try JSONEncoder().encode(value)
        guard KeychainStore.put(data, for: "user-session") else { throw WaterError.storage }
        session = value
    }

    func expireSession(_ message: String) {
        guard !transactionInProgress else { return }
        logout(); activity = message
    }

    private func perform(_ work: () async throws -> Void) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do { try await work() }
        catch { activity = "操作失败：\(error.localizedDescription)" }
    }
}

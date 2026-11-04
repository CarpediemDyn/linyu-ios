import SwiftUI

struct AccountView: View {
    @ObservedObject var auth: AuthManager
    @State private var phone = ""
    @State private var password = ""
    @State private var smsCode = ""
    @State private var usePassword = false
    @State private var ledgerMAC = ""

    var body: some View {
        NavigationStack {
            Form {
                if let session = auth.session {
                    Section("已登录") {
                        LabeledContent("手机号", value: maskedPhone(session.telephone))
                        LabeledContent("项目编号", value: session.projectId)
                        Button("退出登录", role: .destructive) { auth.logout() }
                            .disabled(auth.transactionInProgress)
                    }
                    Section("设备台账查询") {
                        TextField("台账 MAC（12 位 HEX）", text: $ledgerMAC)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button("查询台账（只读）") {
                            Task { await auth.fetchDevice(ledgerMAC: ledgerMAC) }
                        }.disabled(auth.loading)
                        if !auth.deviceText.isEmpty { Text(auth.deviceText).textSelection(.enabled) }
                        Text("iOS 无法直接读取 BLE MAC。请先通过水表标识/二维码等可信渠道核对台账地址，再与扫描到的设备 UUID 关联。仅凭 RSSI 无法证明二者相同。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("接口连通性") {
                        Button("测试钱包接口") { Task { await auth.fetchWallet() } }
                            .disabled(auth.loading)
                        if !auth.walletText.isEmpty { Text(auth.walletText) }
                    }
                } else {
                    Section("趣智校园登录") {
                        TextField("手机号", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                        Toggle("使用密码登录", isOn: $usePassword)
                        if usePassword {
                            SecureField("密码", text: $password)
                                .textContentType(.password)
                        } else {
                            TextField("短信验证码", text: $smsCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                            Button("发送验证码") { Task { await auth.sendSMS(phone: phone) } }
                                .disabled(auth.loading || phone.isEmpty)
                        }
                        Button("登录") {
                            Task { await auth.login(phone: phone,
                                                     secret: usePassword ? password : smsCode,
                                                     usePassword: usePassword) }
                        }
                        .disabled(auth.loading || phone.isEmpty || (usePassword ? password.isEmpty : smsCode.isEmpty))
                    }
                }
                Section("操作反馈") {
                    if auth.loading { ProgressView("正在请求…") }
                    if !auth.activity.isEmpty { Text(auth.activity) }
                }
            }
            .navigationTitle("校园账号")
        }
    }

    private func maskedPhone(_ text: String) -> String {
        guard text.count >= 7 else { return "***" }
        return "\(text.prefix(3))****\(text.suffix(4))"
    }
}

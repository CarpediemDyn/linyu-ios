import SwiftUI

/// LoginScreen.kt: this card intentionally stays white in both app themes.
@MainActor struct AccountView: View {
    @ObservedObject var auth: AuthManager
    @State private var phone = ""
    @State private var password = ""
    @State private var smsCode = ""
    @State private var usePassword = false
    @State private var error: String?
    @State private var countdown = 0
    @State private var countdownGeneration = UUID()
    @State private var sending = false
    @State private var loggingIn = false
    @State private var appeared = false
    private let blue = Color(linYuHex: 0x1A73E8)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [blue, Color(linYuHex: 0x0D47A1), Color(linYuHex: 0x051D40)], startPoint: .top, endPoint: .bottom)
                Circle().fill(.white.opacity(0.04)).frame(width: 280, height: 280).offset(x: -120, y: -80)
                Circle().fill(.white.opacity(0.06)).frame(width: 180, height: 180)
                    .position(x: geometry.size.width - 30, y: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom - 30)
                ScrollView {
                    VStack(spacing: 0) {
                        Image("OriginalLogo").resizable().frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 18))
                        Text("淋 浴").font(LinYuType.font(30, weight: .bold)).foregroundStyle(.white).frame(minHeight: 44).padding(.top, 16)
                        Text("Hualala · 校园热水").font(LinYuType.font(13)).foregroundStyle(.white.opacity(0.55)).frame(minHeight: 24)
                        loginCard.padding(.top, 20)
                    }.padding(.horizontal, 28).padding(.top, 90).padding(.bottom, 28)
                        .offset(y: -50).scaleEffect(appeared ? 1 : 0.8)
                }.scrollDismissesKeyboard(.interactively)
            }.ignoresSafeArea(.container)
        }.preferredColorScheme(.light)
            .onAppear { withAnimation(.easeInOut(duration: 0.4)) { appeared = true } }
            .onDisappear { countdownGeneration = UUID(); password = ""; smsCode = "" }
            .accessibilityIdentifier("linyu.login")
    }

    private var loginCard: some View {
        VStack(spacing: 0) {
            Text("欢迎回来").font(LinYuType.font(22, weight: .bold)).foregroundStyle(Color(linYuHex: 0x1A1A1A)).frame(minHeight: 32)
            Text("请使用校园账号登录").font(LinYuType.font(13)).foregroundStyle(.gray).frame(minHeight: 24).padding(.top, 4).padding(.bottom, 20)
            Button(usePassword ? "验证码登录" : "密码登录") {
                usePassword.toggle(); error = nil; password = ""; smsCode = ""
            }.font(LinYuType.font(13)).foregroundStyle(blue).frame(minHeight: 48).padding(.bottom, 16)
            Text(usePassword ? "未设置密码？请使用手机号验证码登录" : "未注册的手机号将自动创建账号")
                .font(LinYuType.font(12)).foregroundStyle(.gray).frame(minHeight: 24).padding(.bottom, 12)
            OriginalLoginField(title: "手机号", text: $phone, icon: "phone", kind: .phone)
            Group {
                if usePassword {
                    OriginalLoginField(title: "密码", text: $password, icon: "lock", kind: .password)
                } else {
                    HStack(spacing: 12) {
                        OriginalLoginField(title: "验证码", text: $smsCode, kind: .code)
                        Button(action: sendCode) { Text(countdown > 0 ? "\(countdown)s" : "发送").font(LinYuType.font(13)).lineLimit(1).frame(width: 84, height: 40) }
                            .foregroundStyle(.white).background(sending || countdown > 0 ? Color(linYuHex: 0x90CAF9) : blue, in: RoundedRectangle(cornerRadius: 14))
                            .buttonStyle(.plain).disabled(sending || countdown > 0 || auth.loading)
                    }
                }
            }.padding(.top, 14)
            Button(action: login) {
                Group {
                    if loggingIn { ProgressView().tint(.white).frame(width: 22, height: 22) }
                    else { Text("登 录").font(LinYuType.font(17, weight: .bold)) }
                }.frame(maxWidth: .infinity).frame(height: 52)
            }.buttonStyle(.plain).foregroundStyle(.white)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .circular).fill(loggingIn ? Color(linYuHex: 0x90CAF9) : blue)
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 3)
                }.disabled(loggingIn || auth.loading).padding(.top, 24)
            if let error {
                Text(error).font(LinYuType.font(13)).foregroundStyle(Color(linYuHex: 0xC62828)).multilineTextAlignment(.center)
                    .padding(12).background(Color(linYuHex: 0xFFEBEE), in: RoundedRectangle(cornerRadius: 8)).padding(.top, 16)
            }
        }.padding(28).frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .circular).fill(.white)
                    .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
            }
    }
    private func validPhone() -> Bool {
        guard !phone.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard phone.count == 11 else { error = "请输入 11 位手机号"; return false }
        return true
    }
    private func login() {
        guard validPhone(), !auth.loading, !(usePassword ? password : smsCode).isEmpty else { return }
        let mode = usePassword
        let secret = mode ? password : smsCode
        loggingIn = true; error = nil; auth.activity = ""
        Task {
            await auth.login(phone: phone, secret: secret, usePassword: mode)
            if mode { password = "" } else { smsCode = "" }
            loggingIn = false
            if auth.session == nil { error = loginError(auth.activity) }
        }
    }
    private func sendCode() {
        guard validPhone(), !sending, countdown == 0, !auth.loading else { return }
        sending = true; error = nil; auth.activity = ""; countdown = 60
        let token = UUID(); countdownGeneration = token
        Task {
            while countdown > 0, countdownGeneration == token {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, countdownGeneration == token else { return }
                countdown -= 1
            }
        }
        Task {
            await auth.sendSMS(phone: phone)
            sending = false
            if auth.activity.hasPrefix("操作失败：") {
                countdownGeneration = UUID(); countdown = 0; error = loginError(auth.activity)
            }
        }
    }
    private func loginError(_ message: String) -> String {
        let value = message.hasPrefix("操作失败：") ? String(message.dropFirst(5)) : message
        let lower = value.lowercased()
        if lower.contains("timed out") || lower.contains("timeout") { return "连接超时，请检查网络后重试" }
        if lower.contains("resolve host") || lower.contains("no address associated") || lower.contains("network is unreachable") || lower.contains("internet connection") { return "网络连接失败，请检查网络设置" }
        return value.isEmpty ? "登录失败" : value
    }
}

private enum OriginalLoginFieldKind { case phone, password, code }
private struct OriginalLoginField: View {
    let title: String
    @Binding var text: String
    var icon: String? = nil
    let kind: OriginalLoginFieldKind
    @FocusState private var focused: Bool
    private let blue = Color(linYuHex: 0x1A73E8)
    private var raised: Bool { focused || !text.isEmpty }
    var body: some View {
        HStack(spacing: 12) {
            if let icon { LinYuIcon(name: icon).foregroundStyle(blue) }
            Group {
                if kind == .password { SecureField("", text: $text).textContentType(.password) }
                else { TextField("", text: $text).keyboardType(kind == .phone ? .phonePad : .numberPad).textContentType(kind == .phone ? .username : .oneTimeCode) }
            }.font(LinYuType.font(16)).foregroundStyle(Color(linYuHex: 0x1A1A1A)).tint(blue)
                .focused($focused).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel(title)
            if kind != .code && !text.isEmpty {
                Button { text = "" } label: { Text("✕").foregroundStyle(.gray).frame(width: 28, height: 36) }.buttonStyle(.plain).accessibilityLabel("清空" + title)
            }
        }.padding(.horizontal, 16).frame(height: 56)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(focused ? blue : Color(linYuHex: 0xBFC7D5), lineWidth: focused ? 2 : 1))
            .overlay(alignment: .topLeading) {
                Text(title).font(LinYuType.font(raised ? 12 : 16)).foregroundStyle(focused ? blue : Color(linYuHex: 0x6B7280))
                    .padding(.horizontal, raised ? 4 : 0).background(raised ? .white : .clear)
                    .offset(x: raised ? 12 : (icon == nil ? 16 : 52), y: raised ? -8 : 18).allowsHitTesting(false)
            }.padding(.top, 8).animation(.easeOut(duration: 0.15), value: raised)
    }
}

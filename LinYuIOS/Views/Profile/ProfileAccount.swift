import SwiftUI
import UIKit

struct ProfileAccountCard: View {
    @Environment(\.linYuColors) private var colors
    @State private var expanded = false
    let profile: CampusProfile?
    let phone: String
    let onPhone: () -> Void
    let onPassword: () -> Void

    var body: some View {
        OriginalGlassCard {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    if let name = profile?.name, !name.isEmpty { row("姓名", name) }
                    row("手机号", phone)
                    row("学校", profile?.schoolName ?? "")
                    if let student = profile?.studentNumber, !student.isEmpty { row("学号", student) }
                }
                ProfileDivider().padding(.top, 12)
                ProfileDisclosure(title: "账号管理", expanded: $expanded)
                if expanded {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ProfileTextAction("更换手机号", size: 13, action: onPhone)
                        Spacer(minLength: 0)
                        ProfileTextAction("修改密码", size: 13, action: onPassword)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(colors.textSecondary)
            Spacer(minLength: 0)
            Text(value).font(LinYuType.font(16, weight: .medium))
                .foregroundStyle(colors.textPrimary).multilineTextAlignment(.trailing)
        }
        .font(LinYuType.font(16))
        .frame(minHeight: 26)
    }
}

@MainActor struct ProfileCredentialsDialog: View {
    enum Kind: Equatable { case phone, password }

    @ObservedObject var model: OriginalAppModel
    let kind: Kind
    @Binding var locked: Bool
    let onClose: () -> Void
    @Environment(\.linYuColors) private var colors
    @State private var telephone = ""
    @State private var code = ""
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var smsMode = false
    @State private var sending = false
    @State private var expires: Date?
    @State private var message: String?

    private var usesSMS: Bool { kind == .phone || smsMode }
    private var title: String { kind == .phone ? "更换手机号" : "修改密码" }
    private var currentTelephone: String { model.auth.session?.telephone ?? "" }

    var body: some View {
        LinYuDialogCard {
            VStack(alignment: .leading, spacing: 16) {
                ProfileDialogTitle(title)
                ViewThatFits(in: .vertical) {
                    form
                    ScrollView { form }
                }
                HStack(spacing: 0) {
                    Spacer()
                    ProfileTextAction("取消", action: onClose).disabled(locked)
                    ProfileTextAction(locked ? "提交中…" : "确定", action: submit)
                        .disabled(!canSubmit || locked || model.isBusy)
                }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            if kind == .phone {
                Text("当前手机号：\(currentTelephone)")
                    .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary).padding(.bottom, 2)
                ProfileOutlinedField("新手机号", text: trimmed($telephone), keyboard: .phonePad)
                verificationRow
            } else {
                if smsMode {
                    ProfileOutlinedField("手机号", text: trimmed($telephone), keyboard: .phonePad)
                    verificationRow
                } else {
                    ProfileOutlinedField("当前密码", text: $oldPassword, secure: true)
                }
                ProfileOutlinedField("新密码", text: $newPassword, secure: true)
                ProfileOutlinedField("确认新密码", text: $confirmation, secure: true)
                Button {
                    if !smsMode && telephone.isEmpty { telephone = currentTelephone }
                    smsMode.toggle()
                    message = nil
                } label: {
                    Text(smsMode ? "直接修改密码" : "短信验证修改密码")
                        .font(LinYuType.font(12)).foregroundStyle(colors.accent)
                        .padding(.vertical, 2).padding(.horizontal, 3)
                }
                .buttonStyle(.plain).disabled(locked)
            }
            if let message {
                Text(message).font(LinYuType.font(12)).foregroundStyle(colors.danger)
            }
        }
    }

    private var verificationRow: some View {
        HStack(spacing: 10) {
            ProfileOutlinedField("验证码", text: trimmed($code), keyboard: .numberPad, oneTimeCode: true)
                .layoutPriority(1)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(expires?.timeIntervalSince(context.date) ?? 0)))
                Button(action: send) {
                    Text(remaining > 0 ? "\(remaining)s" : "发送")
                        .font(LinYuType.font(13, weight: .medium)).lineLimit(1)
                        .foregroundStyle(colors.isDark ? Color(linYuHex: 0x062E6F) : .white)
                        .frame(width: 86, height: 40)
                        .background(colors.accent.opacity(canSend(remaining: remaining) ? 1 : 0.38),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canSend(remaining: remaining))
            }
            .frame(width: 86)
        }
    }

    private var canSubmit: Bool {
        switch kind {
        case .phone:
            return telephone.count == 11 && !code.isEmpty
        case .password:
            return !newPassword.isEmpty && !confirmation.isEmpty && (smsMode ? !code.isEmpty : !oldPassword.isEmpty)
        }
    }

    private func canSend(remaining: Int) -> Bool {
        !sending && !locked && !model.isBusy && remaining == 0 && telephone.count == 11
    }

    private func trimmed(_ input: Binding<String>) -> Binding<String> {
        Binding(get: { input.wrappedValue }, set: {
            input.wrappedValue = $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })
    }

    private func send() {
        guard canSend(remaining: max(0, Int(ceil(expires?.timeIntervalSinceNow ?? 0)))),
              let session = model.auth.session else { return }
        let phone = telephone
        let purpose: CampusSMSPurpose = kind == .phone ? .newPhone : .forgotPassword
        sending = true
        message = nil
        model.auth.transactionInProgress = true
        Task {
            defer {
                model.auth.transactionInProgress = false
                sending = false
            }
            do {
                try await model.api.sendAccountSMS(to: phone, purpose: purpose, session: session)
                expires = Date().addingTimeInterval(60)
            } catch {
                message = accountMessage(error, fallback: "验证码发送失败")
            }
        }
    }

    private func submit() {
        guard canSubmit, !locked, !model.isBusy, let session = model.auth.session else { return }
        if kind == .password && newPassword != confirmation {
            message = "两次输入的新密码不一致"
            return
        }
        let phone = telephone
        let verification = code
        let old = oldPassword
        let new = newPassword
        let useSMS = usesSMS
        locked = true
        message = nil
        model.auth.transactionInProgress = true
        Task {
            var succeeded = false
            defer {
                model.auth.transactionInProgress = false
                locked = false
                if succeeded { onClose() }
            }
            do {
                switch kind {
                case .phone:
                    try await model.api.updatePhone(newTelephone: phone, code: verification, session: session)
                    guard model.auth.session?.loginCode == session.loginCode else { return }
                    try model.auth.replaceSession(QzxySession(telephone: phone, loginCode: session.loginCode,
                                                              userId: session.userId, accountId: session.accountId,
                                                              projectId: session.projectId))
                    model.message = "手机号已更换"
                case .password:
                    if useSMS {
                        try await model.api.forgetPassword(password: new, code: verification, session: session)
                    } else {
                        try await model.api.updatePassword(oldPassword: old, newPassword: new, session: session)
                    }
                    model.message = "密码已修改"
                }
                oldPassword = ""
                newPassword = ""
                confirmation = ""
                code = ""
                succeeded = true
            } catch {
                message = accountMessage(error, fallback: kind == .phone ? "更换失败" : "修改失败")
            }
        }
    }

    private func accountMessage(_ error: Error, fallback: String) -> String {
        if let error = error as? QzxyError, case .server(let message) = error {
            return message.isEmpty ? fallback : message
        }
        if error is URLError { return "网络异常，请重试" }
        return error.localizedDescription
    }
}

private struct ProfileOutlinedField: View {
    @Environment(\.linYuColors) private var colors
    @FocusState private var focused: Bool
    let label: String
    @Binding var text: String
    var secure: Bool
    var keyboard: UIKeyboardType
    var oneTimeCode: Bool

    init(_ label: String, text: Binding<String>, secure: Bool = false, keyboard: UIKeyboardType = .default,
         oneTimeCode: Bool = false) {
        self.label = label
        _text = text
        self.secure = secure
        self.keyboard = keyboard
        self.oneTimeCode = oneTimeCode
    }

    var body: some View {
        let floats = focused || !text.isEmpty
        let prompt = Text(floats ? "" : label).foregroundColor(colors.textSecondary)
        Group {
            if secure {
                SecureField("", text: $text, prompt: prompt).textContentType(.password)
            } else {
                TextField("", text: $text, prompt: prompt)
                    .keyboardType(keyboard).textContentType(oneTimeCode ? .oneTimeCode : .telephoneNumber)
            }
        }
        .focused($focused)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(LinYuType.font(16))
        .foregroundStyle(colors.textPrimary)
        .tint(colors.accent)
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focused ? colors.accent : colors.textSecondary, lineWidth: focused ? 2 : 1)
        }
        .overlay(alignment: .topLeading) {
            if floats {
                Text(label).font(LinYuType.font(12))
                    .foregroundStyle(focused ? colors.accent : colors.textSecondary)
                    .padding(.horizontal, 4)
                    .background(colors.solidSurface)
                    .offset(x: 12, y: -8)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .padding(.top, 4)
        .accessibilityLabel(label)
    }
}

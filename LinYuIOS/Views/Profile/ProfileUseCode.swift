import SwiftUI

@MainActor struct ProfileUseCodeCard: View {
    @ObservedObject var model: OriginalAppModel
    let loaded: Bool
    let onRedeem: () -> Void
    @Environment(\.linYuColors) private var colors
    @State private var expanded = false
    @State private var requestedStatus: Bool?

    private var data: CampusUseCode? { model.account?.useCode }
    private var code: String { data?.useCode ?? "" }
    private var codeOn: Bool { requestedStatus ?? (data?.useCodeStatus == 1) }
    private var redeemTitle: String { code.isEmpty ? "领取使用码" : "重新领取" }

    var body: some View {
        OriginalGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text("使用码").font(LinYuType.font(13))
                    Spacer()
                    Text("后三位为手机号后三位").font(LinYuType.font(11))
                }
                .foregroundStyle(colors.textSecondary)
                Group {
                    if code.isEmpty {
                        Text(loaded ? "尚未领取" : "加载中...")
                            .foregroundStyle(loaded ? colors.textSecondary : colors.textPrimary)
                            .font(LinYuType.font(28, weight: .black)).tracking(6)
                    } else {
                        ProfileCodeText(code: code, size: 28, tracking: 6)
                    }
                }
                .padding(.top, 4)
                HStack(spacing: 4) {
                    Text(codeOn ? "使用码已开启" : "使用码已关闭")
                        .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                    Spacer()
                    ProfileSwitch(label: "使用码", isOn: Binding(get: { codeOn }, set: toggle), useCodeColors: true)
                        .disabled(model.isBusy || model.candidateWorking || requestedStatus != nil)
                }
                .padding(.top, 4)
                Text("在热水器物理键盘上输入此码")
                    .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                ProfileDivider().padding(.top, 12)
                ProfileDisclosure(title: redeemTitle, expanded: $expanded)
                if expanded {
                    if data?.resetAvailability == 0 {
                        if let warning = data?.resetAvailabilityWarMark {
                            Text(warning).font(LinYuType.font(11)).foregroundStyle(colors.textSecondary)
                                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        }
                        Spacer(minLength: 6)
                    }
                    Button(action: onRedeem) { Text(redeemTitle).frame(maxWidth: .infinity) }
                        .buttonStyle(LinYuButtonStyle(cornerRadius: 12))
                        .disabled(model.isBusy || model.candidateWorking || requestedStatus != nil)
                }
            }
        }
    }

    private func toggle(_ enabled: Bool) {
        guard requestedStatus == nil, !model.isBusy, !model.candidateWorking else { return }
        requestedStatus = enabled
        Task {
            await model.toggleCode(enabled)
            requestedStatus = nil
        }
    }
}

private struct ProfileCodeText: View {
    @Environment(\.linYuColors) private var colors
    let code: String
    let size: CGFloat
    let tracking: CGFloat
    var expired = false

    var body: some View {
        (
            Text(String(code.dropLast(3))).foregroundColor(expired ? colors.textSecondary : colors.textPrimary)
            + Text(String(code.suffix(3))).foregroundColor(expired ? colors.textSecondary : colors.accent)
        )
        .font(LinYuType.font(size, weight: .black))
        .tracking(tracking)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

@MainActor struct ProfileRedeemDialog: View {
    @ObservedObject var model: OriginalAppModel
    @Binding var locked: Bool
    let onClose: () -> Void
    @Environment(\.linYuColors) private var colors
    @State private var swapping = false
    @State private var issue: String?

    private var currentCode: String { model.account?.useCode.useCode ?? "" }
    private var blocked: Bool { model.account?.useCode.resetAvailability == 0 }
    private var title: String { blocked ? "无法领取" : (currentCode.isEmpty ? "领取使用码" : "重新领取使用码") }

    var body: some View {
        LinYuDialogCard {
            VStack(alignment: .leading, spacing: 16) {
                ProfileDialogTitle(title)
                if blocked {
                    Text(model.account?.useCode.resetAvailabilityWarMark ?? "1天只能领取一次使用码")
                        .font(LinYuType.font(14)).foregroundStyle(colors.textPrimary)
                    HStack {
                        Spacer()
                        ProfileTextAction("知道了", action: onClose)
                    }
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = remaining(at: context.date)
                        redeemContent(seconds: seconds)
                        HStack(spacing: 0) {
                            Spacer()
                            ProfileTextAction("取消", action: onClose).disabled(locked)
                            ProfileTextAction(locked ? "领取中…" : "确定领取", action: claim)
                                .disabled(model.codeCandidate == nil || seconds <= 0 || locked || swapping
                                          || model.isBusy || model.candidateWorking)
                        }
                    }
                }
            }
        }
        .task { if !blocked { swap() } }
    }

    private func redeemContent(seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !currentCode.isEmpty {
                HStack {
                    Text("当前使用码")
                    Spacer()
                    Text(currentCode).tracking(1)
                }
                .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                .padding(.bottom, 14)
            }
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("领取后替换为").font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                    if let candidate = model.codeCandidate {
                        ProfileCodeText(code: candidate.useCode, size: 24, tracking: 3, expired: seconds <= 0)
                    } else {
                        Text("— — — — — — — —")
                            .font(LinYuType.font(24, weight: .black)).tracking(3)
                            .foregroundStyle(colors.textSecondary).lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: swap) {
                    HStack(spacing: 4) {
                        LinYuIcon(name: "refresh", size: 18)
                        Text(swapping ? "换码中" : (model.codeCandidate == nil ? "获取" : "换一个"))
                            .font(LinYuType.font(13))
                    }
                    .foregroundStyle(colors.accent)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(swapping || locked || model.isBusy || model.candidateWorking)
            }
            if let candidate = model.codeCandidate {
                Text(seconds > 0 ? String(format: "请在 %d:%02d 内领取", seconds / 60, seconds % 60)
                     : "已超时，请重新换一个")
                    .font(LinYuType.font(11)).foregroundStyle(seconds > 0 ? colors.textSecondary : colors.danger)
                    .padding(.top, 6)
                Text("今日还能换 \(candidate.remainTimes) 次")
                    .font(LinYuType.font(11)).foregroundStyle(colors.textSecondary).padding(.top, 2)
            }
            if let issue {
                Text(issue).font(LinYuType.font(12)).foregroundStyle(colors.danger).padding(.top, 8)
            }
        }
    }

    private func remaining(at date: Date) -> Int {
        guard let created = model.candidateCreatedAt else { return 0 }
        return max(0, min(180, Int(ceil(180 - date.timeIntervalSince(created)))))
    }

    private func swap() {
        guard !swapping, !locked, !model.candidateWorking, !model.isBusy else { return }
        guard model.auth.session != nil else {
            issue = "当前无法换码"
            return
        }
        swapping = true
        issue = nil
        let previous = model.candidateCreatedAt
        Task {
            await model.generateCode()
            swapping = false
            if model.candidateCreatedAt == previous { issue = "换码失败，请重试" }
        }
    }

    private func claim() {
        guard model.codeCandidate != nil, remaining(at: .now) > 0,
              !locked, !swapping, !model.isBusy, !model.candidateWorking else { return }
        locked = true
        issue = nil
        Task {
            await model.claimCode()
            locked = false
            if model.candidateClaimed {
                model.message = "使用码已更新"
                onClose()
            } else {
                issue = "领取失败，请重试"
            }
        }
    }
}

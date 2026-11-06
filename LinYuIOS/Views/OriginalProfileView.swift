import SwiftUI

private enum ProfilePanel: Equatable {
    case phone, password, useCode, room, logs, logout
}

@MainActor struct OriginalProfileView: View {
    @ObservedObject var model: OriginalAppModel
    var onSettingsVisibilityChanged: (Bool) -> Void = { _ in }
    @Environment(\.linYuColors) private var colors
    @Environment(\.linYuWindow) private var window
    @State private var settings = false
    @State private var background = false
    @State private var editingProfile = false
    @State private var editingSettings = false
    @State private var panel: ProfilePanel?
    @State private var locked = false
    @State private var useCodeLoaded = false
    @StateObject private var releases = ProfileReleaseCatalog.shared

    private var preferences: OriginalPreferences { model.preferences }
    private var editing: Bool { settings ? editingSettings : editingProfile }
    private var hidesNavigation: Bool { settings || background || panel != nil }
    private var hasActiveOrders: Bool {
        !model.activeBluetooth.isEmpty || !model.unconfirmedBluetooth.isEmpty || !model.currentCloud.isEmpty
    }
    private var busy: Bool { model.isBusy || model.candidateWorking }

    var body: some View {
        Group {
            if background {
                ProfileBackgroundPage(preferences: preferences) { background = false }
            } else {
                cardsPage.id(settings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .linYuModal(isPresented: Binding(
            get: { panel != nil },
            set: { if !$0 { closePanel() } }
        ), canDismiss: !locked) {
            dialog
        }
        .onAppear { onSettingsVisibilityChanged(hidesNavigation) }
        .onChange(of: hidesNavigation) { onSettingsVisibilityChanged($0) }
        .onDisappear { onSettingsVisibilityChanged(false) }
        .task {
            if !model.refreshing { await model.refresh() }
            while model.refreshing && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if !Task.isCancelled { useCodeLoaded = true }
        }
    }

    private var cardsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 16)
                ForEach(cards, id: \.self) { name in
                    if editing || !hidden.contains(name) {
                        VStack(alignment: .leading, spacing: 4) {
                            if editing { editor(name) }
                            card(name).opacity(hidden.contains(name) ? 0.45 : 1)
                        }
                        .padding(.bottom, 16)
                    }
                }
                if settings {
                    Button { panel = .logout } label: { Text("退出登录").frame(maxWidth: .infinity) }
                        .buttonStyle(LinYuOutlinedButtonStyle(color: colors.danger, cornerRadius: 14))
                        .disabled(busy)
                    Text("Hualala \(ProfileReleaseCatalog.referenceVersion) · 哗啦啦啦啦让我去淋浴~")
                        .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                        .padding(.top, 8).padding(.bottom, 24)
                }
            }
            .padding(window.pageMargin)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            if settings {
                ProfileIconAction("arrow_back", label: "返回我的页面", color: colors.textPrimary) {
                    settings = false
                }
            }
            Text(settings ? "设置" : "我的账号")
                .font(LinYuType.font(22, weight: .bold)).foregroundStyle(colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            ProfileTextAction(editing ? "完成" : "编辑", horizontalPadding: 8) {
                if settings { editingSettings.toggle() } else { editingProfile.toggle() }
            }
            if !settings {
                LinYuThemeToggle(preferences: preferences)
                ProfileIconAction("settings", label: "打开设置", color: colors.textSecondary) {
                    editingSettings = false
                    settings = true
                }
            }
        }
    }

    private var cards: [String] { settings ? preferences.settingsOrder : preferences.cardOrder }
    private var hidden: Set<String> { settings ? preferences.hiddenSettings : preferences.hiddenCards }

    private func editor(_ name: String) -> some View {
        let isHidden = hidden.contains(name)
        let index = cards.firstIndex(of: name)
        let canMoveUp = index.map { $0 > 0 } ?? false
        let canMoveDown = index.map { $0 < cards.count - 1 } ?? false
        return HStack(spacing: 0) {
            Text(isHidden ? "\(name)（已隐藏）" : name)
                .font(LinYuType.font(13))
                .foregroundStyle(colors.textSecondary.opacity(isHidden ? 0.6 : 1))
            Spacer(minLength: 4)
            ProfileIconAction(settings ? "arrow_back" : "arrow_forward",
                              label: settings ? "移到我的页面" : "移到设置页面",
                              color: colors.accent, side: 34) { moveAcross(name) }
            ProfileIconAction("keyboard_arrow_up", label: "上移",
                              color: canMoveUp ? colors.accent : colors.textSecondary.opacity(0.3),
                              side: 34) { move(name, offset: -1) }
                .disabled(!canMoveUp)
            ProfileIconAction("keyboard_arrow_down", label: "下移",
                              color: canMoveDown ? colors.accent : colors.textSecondary.opacity(0.3),
                              side: 34) { move(name, offset: 1) }
                .disabled(!canMoveDown)
            ProfileIconAction(isHidden ? "ic_visibility" : "ic_visibility_off",
                              label: isHidden ? "显示" : "隐藏",
                              color: isHidden ? colors.success : colors.textSecondary, side: 34) {
                var next = hidden
                if isHidden { next.remove(name) } else { next.insert(name) }
                if settings { preferences.hiddenSettings = next } else { preferences.hiddenCards = next }
            }
        }
    }

    private func move(_ name: String, offset: Int) {
        var next = cards
        guard let index = next.firstIndex(of: name), next.indices.contains(index + offset) else { return }
        next.swapAt(index, index + offset)
        if settings { preferences.settingsOrder = next } else { preferences.cardOrder = next }
    }

    private func moveAcross(_ name: String) {
        preferences.hiddenCards.remove(name)
        preferences.hiddenSettings.remove(name)
        if settings {
            preferences.settingsOrder.removeAll { $0 == name }
            preferences.cardOrder = preferences.cardOrder.filter { $0 != name } + [name]
        } else {
            preferences.cardOrder.removeAll { $0 == name }
            preferences.settingsOrder = preferences.settingsOrder.filter { $0 != name } + [name]
        }
    }

    @ViewBuilder private func card(_ name: String) -> some View {
        switch name {
        case "账号信息":
            ProfileAccountCard(profile: model.account?.profile, phone: model.auth.session?.telephone ?? "",
                               onPhone: { panel = .phone }, onPassword: { panel = .password })
        case "使用码":
            ProfileUseCodeCard(model: model, loaded: useCodeLoaded) {
                guard !model.candidateWorking else { return }
                model.codeCandidate = nil
                model.candidateCreatedAt = nil
                model.candidateClaimed = false
                panel = .useCode
            }
        case "绑定寝室":
            ProfileBoundRoomCard(room: model.account?.boundRoom ?? "",
                                 onPick: { panel = .room }, onClear: { model.bindRoom("") })
        case "通知":
            ProfileNotificationCard(preferences: preferences)
        case "消费趋势":
            ProfileTrendSetting(preferences: preferences)
        case "背景装扮":
            ProfileShortcutCard(title: "背景装扮",
                                detail: preferences.homeBackground.isEmpty && preferences.showerBackground.isEmpty
                                    ? "使用自己的图片打造专属界面" : "已启用自定义背景",
                                actionTitle: "更换") { background = true }
        case "运行日志":
            ProfileShortcutCard(title: "运行日志", detail: "查看/导出运行日志，便于排查问题",
                                actionTitle: "查看") { panel = .logs }
        case "关于项目":
            ProfileAboutCard(catalog: releases)
        case "软件更新":
            ProfileUpdateCard(catalog: releases)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var dialog: some View {
        switch panel {
        case .phone:
            ProfileCredentialsDialog(model: model, kind: .phone, locked: $locked, onClose: closePanel)
        case .password:
            ProfileCredentialsDialog(model: model, kind: .password, locked: $locked, onClose: closePanel)
        case .useCode:
            ProfileRedeemDialog(model: model, locked: $locked, onClose: closePanel)
        case .room:
            ProfileRoomDialog(model: model, locked: $locked, onClose: closePanel)
        case .logs:
            ProfileLogDialog(logs: model.logs, onClose: closePanel)
        case .logout:
            LinYuDialogCard {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileDialogTitle(hasActiveOrders ? "无法退出" : "确认退出")
                    Text(hasActiveOrders ? "请结束用水或核实阀门状态后再退出" : "确定退出登录？")
                        .foregroundStyle(colors.textSecondary)
                    HStack(spacing: 0) {
                        Spacer()
                        if hasActiveOrders {
                            ProfileTextAction("返回", action: closePanel)
                        } else {
                            ProfileTextAction("取消", action: closePanel)
                            ProfileTextAction("退出", color: colors.danger, action: logout)
                                .disabled(busy)
                        }
                    }
                }
            }
        case nil:
            EmptyView()
        }
    }

    private func closePanel() {
        guard !locked else { return }
        panel = nil
    }

    private func logout() {
        guard !busy, !hasActiveOrders else { return }
        closePanel()
        model.auth.logout()
    }
}

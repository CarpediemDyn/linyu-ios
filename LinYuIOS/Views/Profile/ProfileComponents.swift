import SwiftUI
import UIKit
import UserNotifications

struct ProfileIconAction: View {
    let name: String
    let label: String
    let color: Color
    let side: CGFloat
    let action: () -> Void

    init(_ name: String, label: String, color: Color, side: CGFloat = 48, action: @escaping () -> Void) {
        self.name = name
        self.label = label
        self.color = color
        self.side = side
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            LinYuIcon(name: name).foregroundStyle(color)
                .frame(width: side, height: side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct ProfileTextAction: View {
    @Environment(\.linYuColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let title: String
    let size: CGFloat
    let color: Color?
    let horizontalPadding: CGFloat
    let action: () -> Void

    init(_ title: String, size: CGFloat = 14, color: Color? = nil, horizontalPadding: CGFloat = 12,
         action: @escaping () -> Void) {
        self.title = title
        self.size = size
        self.color = color
        self.horizontalPadding = horizontalPadding
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(LinYuType.font(size, weight: .medium))
                .foregroundStyle((color ?? colors.accent).opacity(enabled ? 1 : 0.38))
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ProfileDivider: View {
    @Environment(\.linYuColors) private var colors
    var body: some View { Rectangle().fill(colors.border).frame(height: 1) }
}

struct ProfileCardTitle: View {
    @Environment(\.linYuColors) private var colors
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(LinYuType.font(16, weight: .semibold)).foregroundStyle(colors.textPrimary)
    }
}

struct ProfileDialogTitle: View {
    @Environment(\.linYuColors) private var colors
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(LinYuType.font(24, weight: .bold)).foregroundStyle(colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ProfileDisclosure: View {
    @Environment(\.linYuColors) private var colors
    let title: String
    @Binding var expanded: Bool
    var alignedToEdges = false

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(title).font(LinYuType.font(13))
                if alignedToEdges { Spacer() }
                LinYuIcon(name: expanded ? "keyboard_arrow_up" : "keyboard_arrow_down",
                          size: alignedToEdges ? 20 : 18)
            }
            .foregroundStyle(colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? "已展开" : "已收起")
    }
}

struct ProfileSwitch: View {
    let label: String
    @Binding var isOn: Bool
    var useCodeColors = false

    var body: some View {
        Toggle(label, isOn: $isOn).toggleStyle(ProfileSwitchStyle(label: label, useCodeColors: useCodeColors))
    }
}

private struct ProfileSwitchStyle: ToggleStyle {
    @Environment(\.linYuColors) private var colors
    @Environment(\.isEnabled) private var enabled
    let label: String
    let useCodeColors: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        let offBorder = Color(linYuHex: colors.isDark ? 0x938F99 : 0x79747E)
        let offTrack = Color(linYuHex: colors.isDark ? 0x49454F : 0xE7E0EC)
        let onThumb = useCodeColors ? colors.accent : (colors.isDark ? Color(linYuHex: 0x062E6F) : .white)
        return Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? colors.accent.opacity(useCodeColors ? 0.5 : 1) : offTrack)
                .overlay(Capsule().strokeBorder(isOn ? .clear : offBorder, lineWidth: 2))
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(isOn ? onThumb : offBorder)
                        .frame(width: isOn ? 24 : 16, height: isOn ? 24 : 16)
                        .padding(.horizontal, isOn ? 4 : 8)
                }
                .frame(width: 52, height: 32)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.38)
                .animation(.easeInOut(duration: 0.1), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "开启" : "关闭")
    }
}

struct ProfileShortcutCard: View {
    @Environment(\.linYuColors) private var colors
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        OriginalGlassCard {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    ProfileCardTitle(title)
                    Text(detail).font(LinYuType.font(12)).foregroundStyle(colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(actionTitle, action: action).buttonStyle(LinYuButtonStyle(cornerRadius: 14))
            }
        }
    }
}

@MainActor struct ProfileNotificationCard: View {
    @ObservedObject var preferences: OriginalPreferences
    @Environment(\.linYuColors) private var colors
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var expanded = false
    @State private var authorization: UNAuthorizationStatus?

    var body: some View {
        OriginalGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                setting(title: "通知", detail: preferences.notifyEnabled
                        ? "用水期间和结束时收到系统提醒" : "已关闭全部通知",
                        enabled: preferences.viewBinding(\.notifyEnabled))
                if preferences.notifyEnabled {
                    if let authorization, !isAuthorized(authorization) {
                        permissionNotice.padding(.top, 12)
                    }
                    ProfileDisclosure(title: "详细设置", expanded: $expanded, alignedToEdges: true)
                        .padding(.top, 10)
                    if expanded {
                        option("用水状态通知", detail: "使用期间在通知栏显示已用时间", key: \.notifyInUse)
                        option("使用结束通知", detail: "停止后显示用时和消费金额", key: \.notifyFinished)
                        option("自动关停提醒", detail: "设备超时自己关闭时提醒", key: \.notifyAutoClose)
                        option("横幅提醒", detail: "开阀失败、设备被占用时从屏幕顶部弹出", key: \.notifyAlert)
                    }
                }
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await readPermission() }
        }
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("请打开通知权限").font(LinYuType.font(13, weight: .medium)).foregroundStyle(colors.warning)
            Text("开启后才能收到用水提醒和结束通知。")
                .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary).padding(.top, 4)
            Button {
                Task {
                    if authorization == .notDetermined {
                        _ = await OriginalNotifications.shared.requestPermission()
                        await readPermission()
                    } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            } label: {
                Text("去开启").font(LinYuType.font(13, weight: .medium))
            }
            .buttonStyle(LinYuButtonStyle(cornerRadius: 10))
            .padding(.top, 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func readPermission() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    private func setting(title: String, detail: String, enabled: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ProfileCardTitle(title)
                Text(detail).font(LinYuType.font(13)).foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProfileSwitch(label: title, isOn: enabled)
        }
    }

    private func option(_ title: String, detail: String, key: ReferenceWritableKeyPath<OriginalPreferences, Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(LinYuType.font(14)).foregroundStyle(colors.textPrimary)
                Text(detail).font(LinYuType.font(11)).foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProfileSwitch(label: title, isOn: preferences.viewBinding(key))
        }
        .padding(.vertical, 6)
    }
}

@MainActor struct ProfileTrendSetting: View {
    @ObservedObject var preferences: OriginalPreferences
    @Environment(\.linYuColors) private var colors

    var body: some View {
        OriginalGlassCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    ProfileCardTitle("消费趋势")
                    Text(preferences.trendEnabled ? "在钱包页显示消费统计图" : "已隐藏钱包页的消费统计图")
                        .font(LinYuType.font(13)).foregroundStyle(colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ProfileSwitch(label: "消费趋势", isOn: preferences.viewBinding(\.trendEnabled))
            }
        }
    }
}

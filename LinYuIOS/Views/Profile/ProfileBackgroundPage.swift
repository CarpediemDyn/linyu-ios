import PhotosUI
import SwiftUI

@MainActor struct ProfileBackgroundPage: View {
    @ObservedObject var preferences: OriginalPreferences
    let onBack: () -> Void
    @Environment(\.linYuColors) private var colors
    @Environment(\.linYuWindow) private var window
    @State private var selection: PhotosPickerItem?
    @State private var showingPicker = false
    @State private var pickerScope: BackgroundScope?
    @State private var resetScope: BackgroundScope?
    @State private var importHandles: [BackgroundScope: OriginalPreferences.BackgroundImportHandle] = [:]

    private var scope: BackgroundScope { preferences.backgroundSelection }
    private var config: BackgroundConfiguration { preferences.configuration(for: scope) }
    private var path: String { preferences.backgroundURL(for: scope)?.path ?? "" }
    private var themeRGB: Int? { config.themeColor }
    private var selectedPalette: LinYuPalette { LinYuPalette(isDark: colors.isDark, customAccent: config.enabled ? config.themeColor : nil) }
    private var confirmReset: Binding<Bool> {
        Binding(get: { resetScope != nil }, set: { if !$0 { resetScope = nil } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ProfileIconAction("arrow_back", label: "返回", color: colors.textPrimary, action: onBack)
                    Text("自定义背景").font(LinYuType.font(20, weight: .bold)).foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                HStack(spacing: 10) {
                    scopeButton("主页", scope: .home)
                    scopeButton("使用页", scope: .shower)
                }
                .padding(.top, 12)
                Text(scope == .shower ? "应用于：洗澡中的使用页" : "应用于：首页 / 账单 / 我的")
                    .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary).padding(.top, 6)
                preview.padding(.top, 14)
                Button {
                    selection = nil
                    pickerScope = scope
                    showingPicker = true
                } label: {
                    Text(path.isEmpty ? "选择背景图片" : "更换背景图片").frame(maxWidth: .infinity)
                }
                .buttonStyle(LinYuButtonStyle(cornerRadius: 14)).padding(.top, 16)
                .accessibilityIdentifier("linyu.background.picker")
                importStatus.padding(.top, 8)
                if !path.isEmpty { tuning.padding(.top, 20) }
                Button { resetScope = scope } label: {
                    Text("恢复默认背景（仅当前页面）").frame(maxWidth: .infinity)
                }
                .buttonStyle(LinYuOutlinedButtonStyle(color: colors.danger, cornerRadius: 14))
                .padding(.top, 24)
                .accessibilityIdentifier("linyu.background.reset")
                Spacer(minLength: 60)
            }
            .padding(window.pageMargin)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(colors.solidSurface.ignoresSafeArea())
        .photosPicker(isPresented: $showingPicker, selection: $selection, matching: .images, preferredItemEncoding: .current)
        .linYuModal(isPresented: confirmReset) { resetDialog }
        .onChange(of: selection) { item in
            guard let item, let destination = pickerScope else { return }
            importHandles[destination] = preferences.beginBackgroundImport(scope: destination) {
                try await item.loadTransferable(type: BackgroundPhoto.self)?.file
            }
        }
        .onDisappear {
            for (scope, handle) in importHandles { preferences.cancelBackgroundImport(scope: scope, matching: handle.id) }
        }
    }

    private func scopeButton(_ title: String, scope: BackgroundScope) -> some View {
        let selected = scope == preferences.backgroundSelection
        return Button { preferences.backgroundSelection = scope } label: {
            Text(title)
                .font(LinYuType.font(14, weight: .medium))
                .foregroundStyle(selected ? Color.white : colors.textPrimary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(selected ? colors.accent : colors.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("linyu.background.scope." + scope.rawValue)
    }

    private var preview: some View {
        BackgroundCanvas(preferences: preferences, scope: scope, isPreview: true)
            .environment(\.linYuColors, selectedPalette)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private var importStatus: some View {
        switch preferences.backgroundImports[scope] {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().tint(colors.accent)
                Text("正在读取和处理图片…").font(LinYuType.font(13))
                Spacer(minLength: 0)
                Button("取消导入") { preferences.cancelBackgroundImport(scope: scope) }
                    .buttonStyle(.plain).foregroundStyle(colors.accent).frame(minHeight: 44)
            }
        case .failed(let message):
            Text(message).font(LinYuType.font(13)).foregroundStyle(colors.danger)
                .accessibilityIdentifier("linyu.background.error")
        case nil: EmptyView()
        }
    }

    private var tuning: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("主题色").font(LinYuType.font(13)).padding(.trailing, 10)
                Circle().fill(themeRGB.map { Color(linYuHex: UInt32(truncatingIfNeeded: $0)) } ?? selectedPalette.accent)
                    .frame(width: 20, height: 20).padding(.trailing, 8)
                Text(themeRGB == nil ? "使用默认强调色" : "已根据图片自动提取")
                    .font(LinYuType.font(12))
            }
            .foregroundStyle(colors.textSecondary)
            .padding(.bottom, 8)
            ProfileBackgroundSlider(title: "透明度", value: preferences.backgroundBinding(\.opacity, scope: scope), range: 0.2...1,
                                    display: String(format: "%.0f%%", config.opacity * 100))
            ProfileBackgroundSlider(title: "模糊度", value: preferences.backgroundBinding(\.blur, scope: scope), range: 0...20,
                                    display: String(format: "%.0f", config.blur))
            ProfileBackgroundSlider(title: "亮度", value: preferences.backgroundBinding(\.brightness, scope: scope), range: 0.4...1.5,
                                    display: String(format: "%.0f%%", config.brightness * 100))
        }
    }

    private var resetDialog: some View {
        LinYuDialogCard {
            VStack(alignment: .leading, spacing: 16) {
                ProfileDialogTitle("恢复默认背景？")
                Text("这将移除当前页面的自定义背景及相关效果。\n不会影响深色 / 浅色模式。")
                    .font(LinYuType.font(14)).foregroundStyle(colors.textSecondary)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ProfileTextAction("取消") { resetScope = nil }
                    Button("恢复默认") {
                        if let resetScope { preferences.resetBackground(scope: resetScope) }
                        resetScope = nil
                    }
                    .buttonStyle(LinYuButtonStyle(cornerRadius: 20))
                }
            }
        }
    }
}

private struct ProfileBackgroundSlider: View {
    @Environment(\.linYuColors) private var colors
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: String

    private var span: Double { range.upperBound - range.lowerBound }
    private var progress: Double { min(1, max(0, (value - range.lowerBound) / span)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).foregroundStyle(colors.textSecondary)
                Spacer()
                Text(display).foregroundStyle(colors.textPrimary)
            }
            .font(LinYuType.font(13))
            GeometryReader { geometry in
                let length = max(1, geometry.size.width - 20)
                let active = length * CGFloat(progress)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(linYuHex: colors.isDark ? 0x4A4458 : 0xE8DEF8))
                        .frame(width: length, height: 4).offset(x: 10)
                    if active > 0 {
                        Capsule().fill(colors.accent).frame(width: active, height: 4).offset(x: 10)
                    }
                    Circle().fill(colors.accent).frame(width: 20, height: 20).offset(x: active)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    let fraction = min(1, max(0, (gesture.location.x - 10) / length))
                    value = range.lowerBound + Double(fraction) * span
                })
            }
            .frame(height: 48)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(display)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + span * 0.05)
            case .decrement: value = max(range.lowerBound, value - span * 0.05)
            @unknown default: break
            }
        }
    }
}

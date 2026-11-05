import PhotosUI
import SwiftUI

@MainActor struct ProfileBackgroundPage: View {
    @ObservedObject var preferences: OriginalPreferences
    let onBack: () -> Void
    @Environment(\.linYuColors) private var colors
    @AppStorage("backgroundScope") private var savedScope = "home"
    @State private var selection: PhotosPickerItem?
    @State private var confirmReset = false
    @State private var importTask: Task<Void, Never>?

    private var shower: Bool { preferences.backgroundScope == "shower" }
    private var path: String { shower ? preferences.showerBackground : preferences.homeBackground }
    private var themeRGB: Int? { shower ? preferences.showerThemeRGB : preferences.homeThemeRGB }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ProfileIconAction("arrow_back", label: "返回", color: colors.textPrimary, action: onBack)
                    Text("自定义背景").font(LinYuType.font(20, weight: .bold)).foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                HStack(spacing: 10) {
                    scopeButton("主页", key: "home")
                    scopeButton("使用页", key: "shower")
                }
                .padding(.top, 12)
                Text(shower ? "应用于：洗澡中的使用页" : "应用于：首页 / 账单 / 我的")
                    .font(LinYuType.font(12)).foregroundStyle(colors.textSecondary).padding(.top, 6)
                preview.padding(.top, 14)
                PhotosPicker(selection: $selection, matching: .images) {
                    Text(path.isEmpty ? "选择背景图片" : "更换背景图片").frame(maxWidth: .infinity)
                }
                .buttonStyle(LinYuButtonStyle(cornerRadius: 14)).padding(.top, 16)
                if !path.isEmpty { tuning.padding(.top, 20) }
                Button { confirmReset = true } label: {
                    Text("恢复默认背景（仅当前页面）").frame(maxWidth: .infinity)
                }
                .buttonStyle(LinYuOutlinedButtonStyle(color: colors.danger, cornerRadius: 14))
                .padding(.top, 24)
                Spacer(minLength: 60)
            }
            .padding(20)
        }
        .background(colors.solidSurface.ignoresSafeArea())
        .linYuModal(isPresented: $confirmReset) { resetDialog }
        .onAppear {
            let scope = savedScope == "shower" ? "shower" : "home"
            if preferences.backgroundScope != scope { preferences.backgroundScope = scope }
        }
        .onChange(of: selection) { item in
            guard let item else { return }
            importTask?.cancel()
            let scope = preferences.backgroundScope
            importTask = Task {
                defer { if !Task.isCancelled { selection = nil } }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), !Task.isCancelled else { return }
                    try preferences.setBackground(data, scope: scope)
                } catch {
                    if !Task.isCancelled { OriginalLogs.shared.add("保存自定义背景失败：\(error.localizedDescription)") }
                }
            }
        }
        .onDisappear { importTask?.cancel() }
    }

    private func scopeButton(_ title: String, key: String) -> some View {
        let selected = key == preferences.backgroundScope
        return Button {
            savedScope = key
            if !selected { preferences.backgroundScope = key }
        } label: {
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
    }

    private var preview: some View {
        GeometryReader { geometry in
            ZStack {
                colors.background
                if !path.isEmpty, let image = OriginalBackgroundPalette.background(
                    path: path, asset: "", brightness: preferences.backgroundBrightness(shower: shower)
                ) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: preferences.backgroundBlur(shower: shower))
                        .opacity(preferences.backgroundOpacity(shower: shower))
                        .accessibilityHidden(true)
                    OriginalGlassCard(padding: 14, cornerRadius: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("示例卡片").font(LinYuType.font(14, weight: .semibold))
                                .foregroundStyle(colors.textPrimary)
                            Text("文字在背景上的可读性效果").font(LinYuType.font(12))
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                    .padding(16)
                    .frame(width: geometry.size.width * 0.7)
                } else {
                    Text("未设置背景").font(LinYuType.font(16)).foregroundStyle(colors.textSecondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .frame(height: 200)
    }

    private var tuning: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("主题色").font(LinYuType.font(13)).padding(.trailing, 10)
                Circle().fill(themeRGB.map { Color(linYuHex: UInt32(truncatingIfNeeded: $0)) } ?? colors.accent)
                    .frame(width: 20, height: 20).padding(.trailing, 8)
                Text(themeRGB == nil ? "使用默认强调色" : "已根据图片自动提取")
                    .font(LinYuType.font(12))
            }
            .foregroundStyle(colors.textSecondary)
            .padding(.bottom, 8)
            ProfileBackgroundSlider(title: "透明度", value: preferences.viewBinding(\.opacity), range: 0.2...1,
                                    display: String(format: "%.0f%%", preferences.opacity * 100))
            ProfileBackgroundSlider(title: "模糊度", value: preferences.viewBinding(\.blur), range: 0...20,
                                    display: String(format: "%.0f", preferences.blur))
            ProfileBackgroundSlider(title: "亮度", value: preferences.viewBinding(\.brightness), range: 0.4...1.5,
                                    display: String(format: "%.0f%%", preferences.brightness * 100))
        }
    }

    private var resetDialog: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileDialogTitle("恢复默认背景？")
            Text("这将移除当前页面的自定义背景及相关效果。\n不会影响深色 / 浅色模式。")
                .font(LinYuType.font(14)).foregroundStyle(colors.textSecondary)
            HStack(spacing: 8) {
                Spacer()
                ProfileTextAction("取消") { confirmReset = false }
                Button("恢复默认") {
                    importTask?.cancel()
                    let scope = preferences.backgroundScope
                    let file = path
                    preferences.resetBackground(scope: scope)
                    // The preferences adapter clears the reference. Remove only the image owned by this scope.
                    if !file.isEmpty,
                       let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                        let expected = support.appendingPathComponent("Backgrounds", isDirectory: true)
                            .appendingPathComponent(scope == "shower" ? "shower.image" : "home.image")
                        if URL(fileURLWithPath: file).standardizedFileURL == expected.standardizedFileURL {
                            try? FileManager.default.removeItem(at: expected)
                        }
                    }
                    confirmReset = false
                }
                .buttonStyle(LinYuButtonStyle(cornerRadius: 20))
            }
        }
        .padding(24).frame(maxWidth: 560, alignment: .leading)
        .background(colors.solidSurface, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 32)
        .accessibilityAddTraits(.isModal)
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

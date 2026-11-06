import SwiftUI
import UIKit

extension Color {
    init(linYuHex value: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: alpha)
    }
}

/// Exact Theme.kt palette. Android's glass is an RGBA fill, not a system material.
struct LinYuPalette {
    let isDark: Bool
    var customAccent: Int? = nil
    var background: Color { Color(linYuHex: isDark ? 0x0E131D : 0xF1F5F9) }
    var card: Color { Color(linYuHex: isDark ? 0x1D232E : 0xFFFFFF, alpha: Double(isDark ? 191 : 184) / 255) }
    var solidSurface: Color { Color(linYuHex: isDark ? 0x161B22 : 0xFFFFFF) }
    var primary: Color { Color(linYuHex: isDark ? 0xE6EDF3 : 0x0D1117) }
    var accent: Color { Color(linYuHex: UInt32(customAccent ?? (isDark ? 0x58A6FF : 0x2563EB))) }
    var textPrimary: Color { Color(linYuHex: isDark ? 0xE6EDF3 : 0x111827) }
    var textSecondary: Color { Color(linYuHex: isDark ? 0x8B949E : 0x6B7280) }
    var success: Color { Color(linYuHex: isDark ? 0x3FB950 : 0x22C55E) }
    var warning: Color { Color(linYuHex: isDark ? 0xD29922 : 0xF59E0B) }
    var danger: Color { Color(linYuHex: isDark ? 0xF85149 : 0xEF4444) }
    var activeBackground: Color { Color(linYuHex: isDark ? 0x1B1F23 : 0xFFF7ED) }
    var surfaceVariant: Color { Color(linYuHex: isDark ? 0x21262D : 0xF0F0F0) }
    var border: Color { Color(linYuHex: isDark ? 0xFFFFFF : 0x000000, alpha: 20.0 / 255) }
    var onAccent: Color {
        let rgb = customAccent ?? (isDark ? 0x58A6FF : 0x2563EB)
        func channel(_ n: Int) -> Double { let v = Double(n) / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * channel((rgb >> 16) & 255) + 0.7152 * channel((rgb >> 8) & 255) + 0.0722 * channel(rgb & 255)
        return luminance > 0.5 ? Color(linYuHex: 0x0F172A) : .white
    }
}

private struct LinYuColorsKey: EnvironmentKey { static let defaultValue = LinYuPalette(isDark: false) }
extension EnvironmentValues {
    var linYuColors: LinYuPalette {
        get { self[LinYuColorsKey.self] }
        set { self[LinYuColorsKey.self] = newValue }
    }
}

struct LinYuWindowLayout {
    let size: CGSize
    var narrow: Bool { size.width < 360 }
    var short: Bool { size.height < 460 }
    var pageMargin: CGFloat { narrow ? 12 : size.width >= 600 ? 28 : 20 }
}

private struct LinYuWindowKey: EnvironmentKey {
    static let defaultValue = LinYuWindowLayout(size: CGSize(width: 390, height: 780))
}

extension EnvironmentValues {
    var linYuWindow: LinYuWindowLayout {
        get { self[LinYuWindowKey.self] }
        set { self[LinYuWindowKey.self] = newValue }
    }
}

enum LinYuType {
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

@MainActor extension OriginalPreferences {
    func viewBinding<Value>(_ keyPath: ReferenceWritableKeyPath<OriginalPreferences, Value>) -> Binding<Value> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }
}

struct OriginalGlassCard<Content: View>: View {
    @Environment(\.linYuColors) private var colors
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 22
    private let content: Content
    init(padding: CGFloat = 20, cornerRadius: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.padding = padding; self.cornerRadius = cornerRadius; self.content = content()
    }
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.card, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(colors.border, lineWidth: 0.8))
    }
}

struct LinYuButtonStyle: ButtonStyle {
    @Environment(\.linYuColors) private var colors
    @Environment(\.isEnabled) private var enabled
    var color: Color? = nil
    var cornerRadius: CGFloat = 16
    var height: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var labelSize: CGFloat = 14
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(LinYuType.font(labelSize, weight: .medium))
            .multilineTextAlignment(.center).padding(.horizontal, 20).frame(minHeight: height)
            .foregroundStyle(colors.isDark && color == nil ? Color(linYuHex: 0x062E6F) : .white)
            .background((color ?? colors.accent).opacity(enabled ? 1 : 0.38), in: RoundedRectangle(cornerRadius: cornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.interpolatingSpring(stiffness: 700, damping: 35), value: configuration.isPressed)
    }
}

struct LinYuOutlinedButtonStyle: ButtonStyle {
    @Environment(\.linYuColors) private var colors
    @Environment(\.isEnabled) private var enabled
    var color: Color? = nil
    var cornerRadius: CGFloat = 14
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(LinYuType.font(14, weight: .medium)).padding(.horizontal, 20).frame(minHeight: 44)
            .foregroundStyle((color ?? colors.accent).opacity(enabled ? 1 : 0.38))
            .background(configuration.isPressed ? colors.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(colors.textSecondary.opacity(0.8), lineWidth: 1))
    }
}

struct LinYuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.interpolatingSpring(stiffness: 700, damping: 35), value: configuration.isPressed)
    }
}

struct LinYuIconButton: View {
    @Environment(\.linYuColors) private var colors
    let icon: String
    let label: String
    var filled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            LinYuIcon(name: icon, size: 20).foregroundStyle(colors.textPrimary)
                .frame(width: 44, height: 44).background(filled ? colors.card : .clear, in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct LinYuSectionTitle: View {
    @Environment(\.linYuColors) private var colors
    let title: String
    var body: some View { Text(title).font(LinYuType.font(18, weight: .bold)).foregroundStyle(colors.textPrimary) }
}

struct LinYuTailText: View {
    let text: String
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold
    var body: some View {
        Text(text).font(LinYuType.font(size, weight: weight)).lineLimit(1)
            .minimumScaleFactor(0.75).truncationMode(.head)
    }
}

private struct LinYuDialogHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct LinYuDialogCard<Content: View>: View {
    @Environment(\.linYuColors) private var colors
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var measuredHeight: CGFloat = 0
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        GeometryReader { geometry in
            let tight = geometry.size.width < 360 || geometry.size.height < 460 || typeSize.isAccessibilitySize
            let edge: CGFloat = tight ? 12 : 32
            let available = max(1, geometry.size.height - 24)
            ScrollView {
                content
                    .padding(tight ? 16 : 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { measured in
                            Color.clear.preference(key: LinYuDialogHeight.self, value: measured.size.height)
                        }
                    }
            }
            .frame(width: max(1, min(560, geometry.size.width - 2 * edge)))
            .frame(height: measuredHeight > 0 ? min(available, measuredHeight) : available)
            .background(colors.solidSurface, in: RoundedRectangle(cornerRadius: 28))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .foregroundStyle(colors.textPrimary)
            .font(LinYuType.font(14))
            .onPreferenceChange(LinYuDialogHeight.self) { measuredHeight = $0 }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityAddTraits(.isModal)
    }
}

struct LinYuModal<Modal: View>: ViewModifier {
    @Binding var isPresented: Bool
    var canDismiss: Bool
    var onDismiss: () -> Void
    let modal: Modal
    init(isPresented: Binding<Bool>, canDismiss: Bool = true, onDismiss: @escaping () -> Void = {}, @ViewBuilder content: () -> Modal) {
        _isPresented = isPresented; self.canDismiss = canDismiss; self.onDismiss = onDismiss; modal = content()
    }
    func body(content: Content) -> some View {
        content.accessibilityHidden(isPresented).overlay {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.32).ignoresSafeArea().contentShape(Rectangle())
                        .onTapGesture { if canDismiss { isPresented = false; onDismiss() } }
                    modal
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(100)
                    .accessibilityAction(.escape) { if canDismiss { isPresented = false; onDismiss() } }
            }
        }.animation(.easeInOut(duration: 0.2), value: isPresented)
    }
}

extension View {
    func linYuModal<Modal: View>(isPresented: Binding<Bool>, canDismiss: Bool = true, onDismiss: @escaping () -> Void = {}, @ViewBuilder content: () -> Modal) -> some View {
        modifier(LinYuModal(isPresented: isPresented, canDismiss: canDismiss, onDismiss: onDismiss, content: content))
    }
}

struct LinYuPillNavigation: View {
    @Environment(\.linYuColors) private var colors
    @Binding var selection: Int
    @Namespace private var pill
    private let titles = ["首页", "账单", "我的"]
    private let icons = ["home", "ic_receipt_long", "person"]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                Button {
                    guard selection != index else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.interpolatingSpring(stiffness: 380, damping: 28)) { selection = index }
                } label: {
                    HStack(spacing: 4) {
                        LinYuIcon(name: icons[index], size: 16)
                        Text(titles[index]).font(LinYuType.font(11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }.foregroundStyle(selection == index ? colors.onAccent : Color(linYuHex: colors.isDark ? 0x94A3B8 : 0x64748B))
                        .animation(.easeInOut(duration: 0.2), value: selection)
                        .scaleEffect(selection == index ? 1.04 : 1)
                        .animation(.interpolatingSpring(stiffness: 400, damping: 28.8), value: selection)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(RoundedRectangle(cornerRadius: 22))
                        .background {
                            if selection == index {
                                RoundedRectangle(cornerRadius: 22).fill(colors.accent)
                                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1).matchedGeometryEffect(id: "selection", in: pill)
                            }
                        }
                }.buttonStyle(.plain).accessibilityLabel(titles[index]).accessibilityIdentifier("linyu.tab.\(index)")
            }
        }.padding(4).frame(maxWidth: 260)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                // Compose draws the pill fill/border behind its clickable cells. Keep
                // the entire decoration behind SwiftUI buttons too, including AX hits.
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(linYuHex: colors.isDark ? 0x1A202C : 0xFFFFFF, alpha: Double(colors.isDark ? 184 : 216) / 255))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Color(linYuHex: colors.isDark ? 0xFFFFFF : 0x000000, alpha: Double(colors.isDark ? 40 : 24) / 255), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 7)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

@MainActor struct OriginalBackground: View {
    @ObservedObject var preferences: OriginalPreferences
    let shower: Bool
    var body: some View {
        BackgroundCanvas(preferences: preferences, scope: shower ? .shower : .home)
            .ignoresSafeArea(.container).allowsHitTesting(false).accessibilityHidden(true)
    }
}

import SwiftUI

final class LinYuThemeReveal: ObservableObject {
    @Published var isAnimating = false
    var origin = CGPoint.zero
}

private struct LinYuRevealKey: EnvironmentKey {
    static let defaultValue = LinYuThemeReveal()
}
extension EnvironmentValues {
    var linYuThemeReveal: LinYuThemeReveal {
        get { self[LinYuRevealKey.self] }
        set { self[LinYuRevealKey.self] = newValue }
    }
}

@MainActor struct LinYuThemeHost<Content: View>: View {
    @ObservedObject var preferences: OriginalPreferences
    @Environment(\.colorScheme) private var systemScheme
    @StateObject private var reveal = LinYuThemeReveal()
    @State private var displayDark = false
    @State private var oldDark = false
    @State private var progress: Double = 0
    @State private var generation = UUID()
    private let content: Content
    init(preferences: OriginalPreferences, @ViewBuilder content: () -> Content) {
        self.preferences = preferences; self.content = content()
        _displayDark = State(initialValue: preferences.theme == "dark")
    }
    private var requestedDark: Bool {
        preferences.theme == "dark" || (preferences.theme == "system" && systemScheme == .dark)
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                content
                    .environment(\.linYuColors, LinYuPalette(isDark: displayDark, customAccent: preferences.homeThemeRGB))
                    .environment(\.linYuThemeReveal, reveal)
                    .tint(LinYuPalette(isDark: displayDark, customAccent: preferences.homeThemeRGB).accent)
                if reveal.isAnimating {
                    LinYuRevealOverlay(progress: progress, origin: reveal.origin,
                                       size: geometry.size, color: LinYuPalette(isDark: oldDark).background)
                        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(displayDark ? .dark : .light)
        .onAppear { displayDark = requestedDark }
        .onChange(of: preferences.theme) { _ in beginReveal() }
        .onChange(of: systemScheme) { _ in if preferences.theme == "system" { beginReveal() } }
    }
    private func beginReveal() {
        guard !reveal.isAnimating, displayDark != requestedDark else { return }
        let token = UUID(); generation = token
        let target = requestedDark
        oldDark = displayDark; progress = 0; reveal.isAnimating = true
        Task { @MainActor in
            await Task.yield()
            guard generation == token else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.65)) { progress = 1 }
            try? await Task.sleep(nanoseconds: 130_000_000)
            guard generation == token else { return }
            displayDark = target
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard generation == token else { return }
            reveal.isAnimating = false
        }
    }
}

private struct LinYuRevealOverlay: View, Animatable {
    var progress: Double
    let origin: CGPoint
    let size: CGSize
    let color: Color
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        let center = origin == .zero ? CGPoint(x: size.width - 36, y: 48) : origin
        let radius = max(max(hypot(center.x, center.y), hypot(size.width - center.x, center.y)),
                         max(hypot(center.x, size.height - center.y), hypot(size.width - center.x, size.height - center.y))) * 1.15
        let currentRadius = radius * CGFloat(min(1, max(0, (progress - 0.2) / 0.8)))
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            path.addEllipse(in: CGRect(x: center.x - currentRadius, y: center.y - currentRadius,
                                      width: currentRadius * 2, height: currentRadius * 2))
        }.fill(color, style: FillStyle(eoFill: true)).opacity(min(1, progress / 0.2))
    }
}

private struct LinYuThemeFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
@MainActor struct LinYuThemeToggle: View {
    @ObservedObject var preferences: OriginalPreferences
    @Environment(\.linYuThemeReveal) private var reveal
    @Environment(\.linYuColors) private var colors
    @State private var frame = CGRect.zero
    var body: some View {
        Button {
            guard !reveal.isAnimating else { return }
            reveal.origin = CGPoint(x: frame.midX, y: frame.midY)
            preferences.theme = colors.isDark ? "light" : "dark"
        } label: {
            Text(colors.isDark ? "🌙" : "☀️").font(LinYuType.font(20)).frame(width: 40, height: 40)
        }.buttonStyle(.plain).accessibilityLabel("切换深浅主题")
            .background(GeometryReader { proxy in Color.clear.preference(key: LinYuThemeFrameKey.self, value: proxy.frame(in: .global)) })
            .onPreferenceChange(LinYuThemeFrameKey.self) { frame = $0 }
    }
}

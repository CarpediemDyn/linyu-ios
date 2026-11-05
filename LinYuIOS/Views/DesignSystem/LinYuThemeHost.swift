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
    @State private var revealStart: Date?
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
            TimelineView(.animation(paused: revealStart == nil)) { timeline in
                let progress = revealStart.map { Self.easedProgress(timeline.date.timeIntervalSince($0) / 0.65) } ?? 1
                let dark = revealStart != nil && progress < 0.2 ? oldDark : displayDark
                let palette = LinYuPalette(isDark: dark, customAccent: preferences.homeThemeRGB)
                ZStack {
                content
                    .environment(\.linYuColors, palette)
                    .environment(\.linYuThemeReveal, reveal)
                    .tint(palette.accent)
                if revealStart != nil {
                    LinYuRevealOverlay(progress: progress, origin: reveal.origin,
                                       size: geometry.size, color: LinYuPalette(isDark: oldDark).background)
                        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
                }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .preferredColorScheme(preferences.theme == "system" ? nil : (dark ? .dark : .light))
            }
        }
        .coordinateSpace(name: "linyu.theme")
        .onAppear { displayDark = requestedDark }
        .onChange(of: preferences.theme) { _ in beginReveal() }
        .onChange(of: systemScheme) { _ in if preferences.theme == "system" { displayDark = requestedDark } }
        .task(id: revealStart) {
            guard revealStart != nil else { return }
            do { try await Task.sleep(nanoseconds: 650_000_000) } catch { return }
            revealStart = nil; reveal.isAnimating = false
        }
    }
    private func beginReveal() {
        guard !reveal.isAnimating, displayDark != requestedDark else { return }
        oldDark = displayDark; displayDark = requestedDark
        reveal.isAnimating = true; revealStart = .now
    }
    private static func easedProgress(_ time: Double) -> Double {
        let target = min(1, max(0, time))
        var lower = 0.0, upper = 1.0
        for _ in 0..<16 {
            let t = (lower + upper) / 2, u = 1 - t
            let x = 1.2 * u * u * t + 0.6 * u * t * t + t * t * t
            if x < target { lower = t } else { upper = t }
        }
        let t = (lower + upper) / 2
        return t * t * (3 - 2 * t)
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
            .background(GeometryReader { proxy in Color.clear.preference(key: LinYuThemeFrameKey.self, value: proxy.frame(in: .named("linyu.theme"))) })
            .onPreferenceChange(LinYuThemeFrameKey.self) { frame = $0 }
    }
}

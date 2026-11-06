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

/// Keeps the live page mounted once. Display-link ticks belong to the UIKit mask only.
@MainActor struct LinYuThemeHost<Content: View>: View {
    @ObservedObject var preferences: OriginalPreferences
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var reveal = LinYuThemeReveal()
    @State private var displayDark: Bool
    @State private var transition: Transition?
    private let content: Content

    private struct Transition {
        let id = UUID()
        let oldDark: Bool
        let targetDark: Bool
        let origin: CGPoint
    }

    init(preferences: OriginalPreferences, @ViewBuilder content: () -> Content) {
        self.preferences = preferences
        self.content = content()
        _displayDark = State(initialValue: preferences.theme == "dark")
    }

    private var requestedDark: Bool {
        preferences.theme == "dark" || (preferences.theme == "system" && systemScheme == .dark)
    }

    var body: some View {
        GeometryReader { geometry in
            let palette = LinYuPalette(isDark: displayDark, customAccent: preferences.homeThemeRGB)
            content
                .environment(\.linYuColors, palette)
                .environment(\.linYuWindow, LinYuWindowLayout(size: geometry.size))
                .environment(\.linYuThemeReveal, reveal)
                .environment(\.colorScheme, displayDark ? .dark : .light)
                .tint(palette.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { palette.background.ignoresSafeArea(.container) }
                .overlay {
                    if let transition {
                        GeometryReader { overlay in
                            let offset = overlay.frame(in: .named("linyu.theme")).origin
                            let origin = transition.origin == .zero ? CGPoint.zero
                                : CGPoint(x: transition.origin.x - offset.x, y: transition.origin.y - offset.y)
                            LinYuRevealDrawing(
                                origin: origin,
                                oldColor: UIColor(LinYuPalette(isDark: transition.oldDark).background),
                                previewApplied: displayDark == transition.targetDark,
                                onPreview: { applyPreview(id: transition.id) },
                                onCompletion: { finish(id: transition.id) }
                            )
                        }
                        .id(transition.id)
                        .ignoresSafeArea(.container)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.identity)
                    }
                }
                .preferredColorScheme(preferences.theme == "system" ? nil : (displayDark ? .dark : .light))
                .onChange(of: geometry.size) { _ in finishCurrent() }
        }
        .coordinateSpace(name: "linyu.theme")
        .onAppear { applyImmediately() }
        .onChange(of: preferences.theme) { _ in beginReveal() }
        .onChange(of: systemScheme) { _ in
            if preferences.theme == "system" { applyImmediately() }
        }
        .onChange(of: reduceMotion) { reduced in if reduced { applyImmediately() } }
        .onChange(of: scenePhase) { phase in if phase != .active { applyImmediately() } }
        .onDisappear { applyImmediately() }
    }

    private func withoutAnimation(_ action: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, action)
    }

    private func applyImmediately() {
        withoutAnimation {
            displayDark = requestedDark
            transition = nil
            reveal.isAnimating = false
            reveal.origin = .zero
        }
    }

    private func beginReveal() {
        // A programmatic preference change during a reveal is reconciled at completion.
        guard transition == nil else { return }
        guard !reduceMotion, scenePhase == .active, displayDark != requestedDark else {
            applyImmediately()
            return
        }
        withoutAnimation {
            transition = Transition(oldDark: displayDark, targetDark: requestedDark, origin: reveal.origin)
            reveal.origin = .zero
            reveal.isAnimating = true
        }
    }

    private func applyPreview(id: UUID) {
        guard let transition, transition.id == id else { return }
        withoutAnimation { displayDark = transition.targetDark }
    }

    private func finish(id: UUID) {
        guard let transition, transition.id == id else { return }
        withoutAnimation {
            displayDark = transition.targetDark
            self.transition = nil
            reveal.isAnimating = false
        }
        if displayDark != requestedDark { beginReveal() }
    }

    private func finishCurrent() {
        if let transition { finish(id: transition.id) }
    }
}

private struct LinYuThemeFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
@MainActor struct LinYuThemeToggle: View {
    @ObservedObject var preferences: OriginalPreferences
    @Environment(\.linYuThemeReveal) private var reveal

    var body: some View {
        LinYuThemeToggleButton(preferences: preferences, reveal: reveal)
    }
}

/// EnvironmentKey transports the reference but does not subscribe to its Combine changes.
/// Observe the lock explicitly so completion re-enables the button without another page update.
@MainActor private struct LinYuThemeToggleButton: View {
    @ObservedObject var preferences: OriginalPreferences
    @ObservedObject var reveal: LinYuThemeReveal
    @Environment(\.linYuColors) private var colors
    @State private var frame = CGRect.zero
    var body: some View {
        Button {
            guard !reveal.isAnimating else { return }
            reveal.origin = CGPoint(x: frame.midX, y: frame.midY)
            // Lock synchronously so a second tap cannot queue another preference change.
            reveal.isAnimating = true
            preferences.theme = colors.isDark ? "light" : "dark"
        } label: {
            Text(colors.isDark ? "🌙" : "☀️").font(LinYuType.font(20)).frame(width: 40, height: 40)
        }.buttonStyle(.plain).disabled(reveal.isAnimating)
            .accessibilityLabel("切换深浅主题")
            .accessibilityValue(colors.isDark ? "深色" : "浅色")
            .accessibilityIdentifier("linyu.theme.toggle")
            .background(GeometryReader { proxy in Color.clear.preference(key: LinYuThemeFrameKey.self, value: proxy.frame(in: .named("linyu.theme"))) })
            .onPreferenceChange(LinYuThemeFrameKey.self) { frame = $0 }
    }
}

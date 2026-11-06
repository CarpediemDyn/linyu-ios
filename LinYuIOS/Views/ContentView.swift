import SwiftUI

@MainActor struct ContentView: View {
    var body: some View {
#if targetEnvironment(simulator)
        OriginalRootView(model: LoginFeedbackFixture.model())
#else
        OriginalRootView()
#endif
    }
}

@main struct LinYuIOSApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

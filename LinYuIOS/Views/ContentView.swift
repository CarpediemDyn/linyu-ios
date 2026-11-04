import SwiftUI

@MainActor struct ContentView: View {
    var body: some View {
        OriginalRootView()
    }
}

@main struct LinYuIOSApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

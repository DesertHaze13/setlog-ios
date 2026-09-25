import SwiftUI

@main
struct SetlogApp: App {
    @StateObject private var theme = SolarTheme()
    @StateObject private var store = WorkoutStore()
    @StateObject private var watchBridge = WatchBridge()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .environmentObject(theme)
                .preferredColorScheme(theme.dark.map { $0 ? .dark : .light })
                .onAppear { watchBridge.connect(store: store) }
        }
    }
}

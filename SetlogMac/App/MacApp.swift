import SwiftUI

@main
struct DonyLiftsMacApp: App {
    @StateObject private var store = WorkoutStore()
    var body: some Scene {
        WindowGroup {
            MacContentView().environmentObject(store)
                .frame(minWidth: 760, minHeight: 550)
        }
    }
}

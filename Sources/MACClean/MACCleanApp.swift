import SwiftUI

@main
struct MACCleanApp: App {
    @StateObject private var cleanupStore = CleanupStore()
    @StateObject private var appsStore = AppsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cleanupStore)
                .environmentObject(appsStore)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}


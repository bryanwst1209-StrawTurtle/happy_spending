import SwiftUI
import SwiftData
import HappySpendingCore

@main
struct HappySpendingApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(SharedModelContainer.shared)
    }
}

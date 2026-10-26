import SwiftUI
import SwiftData
import HappySpendingCore

@main
struct HappySpendingApp: App {
    @State private var appearance = AppearanceModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appearance)
        }
        .modelContainer(SharedModelContainer.shared)
    }
}

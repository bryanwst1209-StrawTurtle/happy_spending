import SwiftUI
import SwiftData
import HappySpendingCore

@main
struct HappySpendingApp: App {
    @State private var appearance = AppearanceModel()
    @State private var backup = BackupService()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appearance)
                .environment(backup)
        }
        .modelContainer(SharedModelContainer.shared)
    }
}

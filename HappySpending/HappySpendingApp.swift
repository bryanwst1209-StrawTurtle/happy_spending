import SwiftUI
import SwiftData
import HappySpendingCore

@main
struct HappySpendingApp: App {
    @State private var appearance = AppearanceModel()
    @State private var backup = BackupService()
    @State private var achievements = AchievementCenter()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appearance)
                .environment(backup)
                .environment(achievements)
        }
        .modelContainer(SharedModelContainer.shared)
    }
}

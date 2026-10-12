import SwiftUI
import SwiftData
import HappySpendingCore

@main
struct HappySpendingApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: LedgerCategory.self, LedgerEntry.self)
            try DefaultCategories.seedIfNeeded(in: container.mainContext)
        } catch {
            fatalError("无法初始化数据存储:\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}

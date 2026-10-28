import SwiftData
import HappySpendingCore

/// 全局共享的数据容器。app 界面和被快捷指令在后台唤起的动作共用它,
/// 避免同一进程里有两个容器指向同一份数据。首次创建时写入默认分类,
/// 所以全新安装后第一次就被快捷指令唤起也能正常分类。
@MainActor
enum SharedModelContainer {
    static let shared: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: LedgerCategory.self, LedgerEntry.self, MerchantCategory.self, AchievementUnlock.self, OpenDay.self
            )
            try DefaultCategories.seedIfNeeded(in: container.mainContext)
            return container
        } catch {
            fatalError("无法初始化数据存储:\(error)")
        }
    }()
}

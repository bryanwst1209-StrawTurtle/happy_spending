import SwiftUI
import SwiftData
import HappySpendingCore

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppearanceModel.self) private var appearance
    @Environment(BackupService.self) private var backup

    /// 只查没有分类的账,再挑出支出,作为账单页签的角标。
    @Query(LedgerQueries.uncategorized()) private var uncategorized: [LedgerEntry]
    @Query(LedgerQueries.earliest()) private var anyEntry: [LedgerEntry]

    /// 账单页签的角标:待归类的笔数,为 0 时不显示。
    private var pendingCount: Int { PendingCategorization.pending(uncategorized).count }

    var body: some View {
        TabView {
            Tab("记账", systemImage: "plus.circle.fill") { RecordView() }
            Tab("账单", systemImage: "list.bullet.rectangle") { BillsView() }
                .badge(pendingCount)
            Tab("统计", systemImage: "chart.pie.fill") { StatsView() }
            Tab("设置", systemImage: "gearshape.fill") { SettingsView() }
                .badge(backup.needsReminder(hasEntries: !anyEntry.isEmpty) ? Text("!") : nil)
        }
        // 每天第一次打开或回到前台时自动备份(没开自动备份时什么也不做)。
        .task { await backup.autoBackupIfNeeded(context: context, appearance: appearance) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await backup.autoBackupIfNeeded(context: context, appearance: appearance) }
        }
    }
}

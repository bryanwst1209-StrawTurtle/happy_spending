import SwiftUI
import SwiftData
import HappySpendingCore

struct RootTabView: View {
    /// 只查没有分类的账,再挑出支出,作为账单页签的角标。
    @Query(LedgerQueries.uncategorized()) private var uncategorized: [LedgerEntry]

    /// 账单页签的角标:待归类的笔数,为 0 时不显示。
    private var pendingCount: Int { PendingCategorization.pending(uncategorized).count }

    var body: some View {
        TabView {
            Tab("记账", systemImage: "plus.circle.fill") { RecordView() }
            Tab("账单", systemImage: "list.bullet.rectangle") { BillsView() }
                .badge(pendingCount)
            Tab("统计", systemImage: "chart.pie.fill") { StatsView() }
            Tab("设置", systemImage: "gearshape.fill") { SettingsView() }
        }
    }
}

import SwiftUI
import SwiftData
import HappySpendingCore

struct RootTabView: View {
    @Query private var entries: [LedgerEntry]

    /// 账单页签的角标:待归类的笔数,为 0 时不显示。
    private var pendingCount: Int { PendingCategorization.pending(entries).count }

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

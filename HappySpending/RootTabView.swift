import SwiftUI
import SwiftData
import HappySpendingCore

struct RootTabView: View {
    enum Page: Hashable { case record, bills, stats, settings }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppearanceModel.self) private var appearance
    @Environment(BackupService.self) private var backup
    @Environment(AchievementCenter.self) private var achievements

    /// 只查没有分类的账,再挑出支出,作为账单页签的角标。
    @Query(LedgerQueries.uncategorized()) private var uncategorized: [LedgerEntry]
    @Query(LedgerQueries.earliest()) private var anyEntry: [LedgerEntry]
    @State private var page = Page.record

    /// 账单页签的角标:待归类的笔数,为 0 时不显示。
    private var pendingCount: Int { PendingCategorization.pending(uncategorized).count }

    var body: some View {
        TabView(selection: $page) {
            Tab("记账", systemImage: "plus.circle.fill", value: .record) { RecordView() }
            Tab("账单", systemImage: "list.bullet.rectangle", value: .bills) { BillsView() }
                .badge(pendingCount)
            Tab("统计", systemImage: "chart.pie.fill", value: .stats) { StatsView() }
            Tab("设置", systemImage: "gearshape.fill", value: .settings) { SettingsView() }
                .badge(backup.needsReminder(hasEntries: !anyEntry.isEmpty) ? Text("!") : nil)
        }
        // 打开或回到前台:记下今天打开过、自动备份(没开就跳过)、检查成就。
        .task { await appeared() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await appeared() }
        }
        .overlay(alignment: .top) {
            if let toast = achievements.toast {
                Button {
                    achievements.dismissToast()
                    page = .stats
                    achievements.showWall = true
                } label: {
                    ToastView(text: toast)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: achievements.toast) { _, new in new != nil }
    }

    private func appeared() async {
        achievements.appeared(context: context, backup: backup)
        await backup.autoBackupIfNeeded(context: context, appearance: appearance)
        achievements.check(context: context, backup: backup)
    }
}

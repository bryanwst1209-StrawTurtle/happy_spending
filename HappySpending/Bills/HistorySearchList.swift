import SwiftUI
import SwiftData
import HappySpendingCore

/// 账单页搜"全部":在所有月份里搜,结果按月份分组。停止输入约 0.3 秒后才查。
struct HistorySearchList: View {
    @Environment(\.modelContext) private var context

    let query: String
    /// 编辑、删除、撤销后由账单页加一,触发重查。
    let revision: Int
    let pendingCount: Int
    let onCategorize: () -> Void
    let onEdit: (LedgerEntry) -> Void
    let onDelete: (LedgerEntry) -> Void

    @State private var results: [LedgerEntry] = []
    @State private var searched = false

    private let calendar = DayStamp.calendar

    private var rows: [EntryRow] { results.map(\.row) }
    private var groups: [MonthGroup] { BillsLogic.groupByMonth(rows, calendar: calendar) }
    private var resultsByID: [UUID: LedgerEntry] {
        Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        List {
            if pendingCount > 0 {
                PendingEntryRow(count: pendingCount, action: onCategorize)
            }
            if !results.isEmpty {
                Section {
                    Text("找到 \(results.count) 笔 · 支出 \(Money.display(Statistics.summary(rows).expenseCents))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .appRowBackground()
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        EntryRowView(row: row, showsDate: true)
                            .appRowBackground()
                            .onTapGesture { if let entry = resultsByID[row.id] { onEdit(entry) } }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("删除", role: .destructive) {
                                    if let entry = resultsByID[row.id] {
                                        results.removeAll { $0.id == row.id }
                                        onDelete(entry)
                                    }
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(BillsLogic.monthTitle(group.month, calendar: calendar))
                        Spacer()
                        Text("支出 " + Money.display(group.expenseCents)).monospacedDigit()
                    }
                }
            }
        }
        .appListBackground()
        .overlay {
            if searched && results.isEmpty {
                ContentUnavailableView.search(text: query).allowsHitTesting(false)
            }
        }
        .task(id: "\(revision)|\(query)") {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = (try? HistorySearch.search(query, in: context)) ?? []
            searched = true
        }
    }
}

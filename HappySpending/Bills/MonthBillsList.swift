import SwiftUI
import SwiftData
import HappySpendingCore

/// 账单页的"本月"模式:只从数据库查所选月份的账。
struct MonthBillsList: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [LedgerEntry]

    let month: Date
    let query: String
    let pendingCount: Int
    let isCurrentMonth: Bool
    let onCategorize: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPickMonth: () -> Void
    let onBackToCurrent: () -> Void
    let onEdit: (LedgerEntry) -> Void
    let onDelete: (LedgerEntry) -> Void

    private let calendar = DayStamp.calendar

    init(
        month: Date,
        query: String,
        pendingCount: Int,
        isCurrentMonth: Bool,
        onCategorize: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onPickMonth: @escaping () -> Void,
        onBackToCurrent: @escaping () -> Void,
        onEdit: @escaping (LedgerEntry) -> Void,
        onDelete: @escaping (LedgerEntry) -> Void
    ) {
        self.month = month
        self.query = query
        self.pendingCount = pendingCount
        self.isCurrentMonth = isCurrentMonth
        self.onCategorize = onCategorize
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onPickMonth = onPickMonth
        self.onBackToCurrent = onBackToCurrent
        self.onEdit = onEdit
        self.onDelete = onDelete
        _entries = Query(LedgerQueries.entries(in: .month(month), calendar: DayStamp.calendar))
    }

    private var rows: [EntryRow] { entries.map(\.row) }
    private var groups: [DayGroup] {
        BillsLogic.groupByDay(BillsLogic.search(rows, query: query), calendar: calendar)
    }
    private var summary: PeriodSummary { Statistics.summary(rows) }
    private var entriesByID: [UUID: LedgerEntry] {
        Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var monthTitle: String { BillsLogic.monthTitle(month, calendar: calendar) }

    var body: some View {
        List {
            if pendingCount > 0 {
                PendingEntryRow(count: pendingCount, action: onCategorize)
            }
            Section {
                PeriodSwitcher(
                    title: monthTitle,
                    isNextDisabled: isCurrentMonth,
                    backTitle: isCurrentMonth ? nil : "回到本月",
                    onTitleTap: onPickMonth,
                    onBack: onBackToCurrent,
                    onPrevious: onPrevious,
                    onNext: onNext
                )
                .listRowBackground(Color.clear)
                summaryRow
                    .appRowBackground()
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        EntryRowView(row: row)
                            .appRowBackground()
                            .onTapGesture { if let entry = entriesByID[row.id] { onEdit(entry) } }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("删除", role: .destructive) {
                                    if let entry = entriesByID[row.id] { onDelete(entry) }
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(BillsLogic.dayTitle(group.day, calendar: calendar))
                        Spacer()
                        Text(daySubtotal(group)).monospacedDigit()
                    }
                }
            }
        }
        .appListBackground()
        .overlay {
            // 占位不接收点击,免得挡住上面的 ‹ › 和标题。
            Group {
                if rows.isEmpty {
                    ContentUnavailableView(isCurrentMonth ? "本月还没有账单" : "这个月没有账单", systemImage: "tray")
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(
                        item: CSVFile(
                            name: CSVExporter.fileName(for: .month(month), calendar: calendar),
                            rows: { [rows] in rows }
                        ),
                        preview: SharePreview("导出 \(monthTitle)")
                    ) { Label("导出当月 CSV", systemImage: "calendar") }
                    ShareLink(
                        item: CSVFile(
                            name: CSVExporter.fileName(for: nil, calendar: calendar),
                            rows: { [container = context.container] in
                                try container.mainContext.fetch(LedgerQueries.all()).map(\.row)
                            }
                        ),
                        preview: SharePreview("导出全部账单")
                    ) { Label("导出全部 CSV", systemImage: "tray.full") }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private var summaryRow: some View {
        HStack {
            summaryCell("收入", summary.incomeCents, .green)
            summaryCell("支出", summary.expenseCents, .primary)
            summaryCell("结余", summary.balanceCents, .primary)
        }
    }

    private func summaryCell(_ title: String, _ cents: Int, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.display(cents)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func daySubtotal(_ group: DayGroup) -> String {
        var parts: [String] = []
        if group.expenseCents > 0 { parts.append("支出 " + Money.display(group.expenseCents)) }
        if group.incomeCents > 0 { parts.append("收入 " + Money.display(group.incomeCents)) }
        return parts.joined(separator: "  ")
    }
}

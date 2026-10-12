import SwiftUI
import SwiftData
import HappySpendingCore

/// 删除前的快照,用于"撤销"。
private struct DeletedEntry: Equatable {
    let id: UUID
    let amountInCents: Int
    let kind: EntryKind
    let date: Date
    let createdAt: Date
    let note: String
    let categoryID: UUID?

    init(_ entry: LedgerEntry) {
        id = entry.id
        amountInCents = entry.amountInCents
        kind = entry.kind
        date = entry.date
        createdAt = entry.createdAt
        note = entry.note
        categoryID = entry.category?.id
    }
}

struct BillsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var month = Date.now
    @State private var query = ""
    @State private var editing: LedgerEntry?
    @State private var undo: DeletedEntry?
    @State private var errorMessage: String?

    private let calendar = Calendar.current

    private var allRows: [EntryRow] { entries.map(\.row) }
    private var monthRows: [EntryRow] { Period.month(month).filter(allRows, calendar: calendar) }
    private var groups: [DayGroup] {
        BillsLogic.groupByDay(BillsLogic.search(monthRows, query: query), calendar: calendar)
    }
    private var summary: PeriodSummary { Statistics.summary(monthRows) }
    private var entriesByID: [UUID: LedgerEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }
    private var monthTitle: String {
        month.formatted(.dateTime.year().month().locale(Locale(identifier: "zh_CN")))
    }
    private var frequentIDs: [UUID] {
        BillsLogic.frequentCategoryIDs(
            allRows, kind: editing?.kind ?? .expense,
            excluding: Set(categories.filter(\.isArchived).map(\.id))
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PeriodSwitcher(
                        title: monthTitle,
                        onPrevious: { shiftMonth(-1) },
                        onNext: { shiftMonth(1) }
                    )
                    .listRowBackground(Color.clear)
                    summaryRow
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.rows) { row in
                            EntryRowView(row: row)
                                .onTapGesture { editing = entriesByID[row.id] }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("删除", role: .destructive) {
                                        if let entry = entriesByID[row.id] { delete(entry) }
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
            .overlay {
                if monthRows.isEmpty {
                    ContentUnavailableView("本月还没有账单", systemImage: "tray")
                } else if groups.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("账单")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索备注或分类")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(
                            item: CSVFile(
                                name: CSVExporter.fileName(for: .month(month), calendar: calendar),
                                rows: monthRows
                            ),
                            preview: SharePreview("导出 \(monthTitle)")
                        ) { Label("导出当月 CSV", systemImage: "calendar") }
                        ShareLink(
                            item: CSVFile(
                                name: CSVExporter.fileName(for: nil, calendar: calendar),
                                rows: allRows
                            ),
                            preview: SharePreview("导出全部账单")
                        ) { Label("导出全部 CSV", systemImage: "tray.full") }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                }
            }
            .sheet(item: $editing) { entry in
                EntryEditSheet(entry: entry, categories: categories, frequentIDs: frequentIDs)
            }
            .overlay(alignment: .bottom) {
                if let undo {
                    ToastView(text: "已删除一笔", actionTitle: "撤销") { restore(undo) }
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "")
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

    private func shiftMonth(_ delta: Int) {
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func delete(_ entry: LedgerEntry) {
        let snapshot = DeletedEntry(entry)
        context.delete(entry)
        guard persist() else { return }
        withAnimation { undo = snapshot }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if undo == snapshot { withAnimation { undo = nil } }
        }
    }

    private func restore(_ snapshot: DeletedEntry) {
        let entry = LedgerEntry(
            id: snapshot.id,
            amountInCents: snapshot.amountInCents,
            kind: snapshot.kind,
            date: snapshot.date,
            note: snapshot.note,
            category: categories.first { $0.id == snapshot.categoryID },
            createdAt: snapshot.createdAt
        )
        context.insert(entry)
        _ = persist()
        withAnimation { undo = nil }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

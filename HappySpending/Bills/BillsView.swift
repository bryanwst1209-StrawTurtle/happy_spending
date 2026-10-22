import SwiftUI
import SwiftData
import HappySpendingCore

/// 账单页的搜索范围。
enum BillsSearchScope: Hashable {
    case month, all
}

struct BillsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(LedgerQueries.uncategorized()) private var uncategorized: [LedgerEntry]
    @Query(LedgerQueries.recent()) private var recent: [LedgerEntry]
    @Query(LedgerQueries.earliest()) private var earliest: [LedgerEntry]

    @State private var month = DayStamp.stamp(.now)
    @State private var query = ""
    @State private var scope = BillsSearchScope.month
    @State private var editing: LedgerEntry?
    @State private var undo: DeletedEntrySnapshot?
    @State private var errorMessage: String?
    @State private var categorizing = false
    @State private var pickingMonth = false
    /// 搜"全部"的结果在编辑、删除、撤销后要重查;每次改动加一。
    @State private var searchRevision = 0

    private let calendar = DayStamp.calendar

    private var now: Date { DayStamp.stamp(.now) }
    /// 所有月份里待归类的笔数。
    private var pendingCount: Int { PendingCategorization.pending(uncategorized).count }
    /// 编辑页、归类面板算"常用分类"用的最近 300 笔。
    private var recentRows: [EntryRow] { recent.map(\.row) }
    private var isCurrentMonth: Bool { HistoryRange.isCurrent(.month(month), now: now, calendar: calendar) }
    private var isSearchingAll: Bool {
        scope == .all && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearchingAll {
                    HistorySearchList(
                        query: query,
                        revision: searchRevision,
                        pendingCount: pendingCount,
                        onCategorize: { categorizing = true },
                        onEdit: { editing = $0 },
                        onDelete: delete
                    )
                } else {
                    MonthBillsList(
                        month: month,
                        query: query,
                        pendingCount: pendingCount,
                        isCurrentMonth: isCurrentMonth,
                        onCategorize: { categorizing = true },
                        onPrevious: { shiftMonth(-1) },
                        onNext: { shiftMonth(1) },
                        onPickMonth: { pickingMonth = true },
                        onBackToCurrent: { month = now },
                        onEdit: { editing = $0 },
                        onDelete: delete
                    )
                }
            }
            .navigationTitle("账单")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索备注、分类或金额")
            // "本月 / 全部"自己画在搜索框下方,只在输入了搜索词时出现。
            // 不用系统的 `.searchScopes`:iOS 26 上它在搜索框下方留一条看不见的范围栏,
            // 即使不在搜索也会挡住下面月份切换按钮的点击。
            .safeAreaInset(edge: .top) {
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Picker("搜索范围", selection: $scope) {
                        Text("本月").tag(BillsSearchScope.month)
                        Text("全部").tag(BillsSearchScope.all)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
            }
            .sheet(item: $editing, onDismiss: { searchRevision += 1 }) { entry in
                EntryEditSheet(entry: entry, categories: categories, rows: recentRows)
            }
            .sheet(isPresented: $categorizing) {
                CategorizeSheet(categories: categories, rows: recentRows)
            }
            .sheet(isPresented: $pickingMonth) {
                MonthPickerSheet(
                    current: month,
                    years: HistoryRange.years(earliest: earliest.first?.date, now: now, calendar: calendar),
                    yearOnly: false,
                    now: now
                ) { month = $0 }
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

    private func shiftMonth(_ delta: Int) {
        // 已经是当前月时 › 置灰;这里再拦一次,不翻到未来。
        guard delta < 0 || !isCurrentMonth else { return }
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
    }

    private func delete(_ entry: LedgerEntry) {
        let snapshot = DeletedEntrySnapshot(entry)
        context.delete(entry)
        guard persist() else { return }
        searchRevision += 1
        withAnimation { undo = snapshot }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if undo == snapshot { withAnimation { undo = nil } }
        }
    }

    private func restore(_ snapshot: DeletedEntrySnapshot) {
        // 连点两次"撤销"不能造出两笔同 id 的账单。
        guard undo == snapshot,
              (try? context.fetchCount(LedgerQueries.entry(id: snapshot.id))) == 0
        else { return }
        let entry = snapshot.makeEntry(categories: categories)
        context.insert(entry)
        _ = persist()
        searchRevision += 1
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

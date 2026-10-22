import SwiftUI
import SwiftData
import HappySpendingCore

/// 待归类面板:一次一笔,选好分类就归好并显示下一笔;全部处理完自动关闭。
struct CategorizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    /// 只查没有分类的账;队列再从中挑出支出并排序。
    @Query(LedgerQueries.uncategorized()) private var entries: [LedgerEntry]

    let categories: [LedgerCategory]
    let rows: [EntryRow]

    /// 这次打开面板时跳过的账;不记下来,下次打开还会出现。
    @State private var skipped: Set<UUID> = []
    @State private var selectedID: UUID?
    @State private var notice: String?
    @State private var errorMessage: String?

    private var queue: [LedgerEntry] {
        PendingCategorization.pending(entries).filter { !skipped.contains($0.id) }
    }
    private var current: LedgerEntry? { queue.first }
    private var selected: LedgerCategory? { categories.first { $0.id == selectedID } }

    /// 选中的是有二级分类的一级分类:等用户选二级分类,或点"就用『X』"。
    private var waitingForSubcategory: LedgerCategory? {
        guard let selected, selected.parent == nil,
              selected.children.contains(where: { !$0.isArchived })
        else { return nil }
        return selected
    }

    private var frequentIDs: [UUID] {
        BillsLogic.frequentCategoryIDs(
            rows, kind: .expense,
            excluding: Set(categories.filter(\.isArchived).map(\.id))
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let current {
                    VStack(alignment: .leading, spacing: 16) {
                        summary(current)
                        CategoryPicker(
                            kind: .expense, categories: categories,
                            frequentIDs: frequentIDs, selectedID: $selectedID
                        )
                        if let waitingForSubcategory {
                            Button("就用『\(waitingForSubcategory.name)』") {
                                assign(current, to: waitingForSubcategory)
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Color.clear
                }
            }
            .navigationTitle("待归类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("跳过") {
                        if let current { skipped.insert(current.id) }
                    }
                    .disabled(current == nil)
                }
            }
            .onChange(of: selectedID) {
                // 没有二级分类的一级分类、任意二级分类:点了就归好。
                guard let current, let selected, waitingForSubcategory == nil else { return }
                assign(current, to: selected)
            }
            .onChange(of: current?.id) { _, id in
                selectedID = nil
                guard id == nil else { return }
                // 全部处理完:有提示就让它多停一会儿再关。
                Task {
                    if notice != nil { try? await Task.sleep(for: .seconds(1.5)) }
                    dismiss()
                }
            }
            .overlay(alignment: .top) {
                if let notice {
                    ToastView(text: notice)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
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

    private func summary(_ entry: LedgerEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Money.display(entry.amountInCents))
                .font(.largeTitle.weight(.semibold).monospacedDigit())
            Text(entry.merchant ?? (entry.note.isEmpty ? "没有商户名" : entry.note))
                .font(.headline)
            HStack(spacing: 6) {
                Text(BillsLogic.dayTitle(entry.date, calendar: DayStamp.calendar))
                if let source = entry.autoSource {
                    Text("·")
                    Text(source.displayName)
                }
                Spacer()
                Text("还剩 \(queue.count) 笔")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func assign(_ entry: LedgerEntry, to category: LedgerCategory) {
        let merchant = entry.merchant
        do {
            let others = try PendingCategorization.assign(entry, to: category, in: context)
            if others > 0 { show(PendingCategorization.notice(count: others, merchant: merchant)) }
        } catch {
            selectedID = nil
            errorMessage = error.localizedDescription
        }
    }

    private func show(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if notice == text { notice = nil } }
        }
    }
}

import SwiftUI
import SwiftData
import HappySpendingCore

struct EntryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let entry: LedgerEntry
    let categories: [LedgerCategory]
    let rows: [EntryRow]

    @State private var form: EntryFormState
    @State private var errorMessage: String?
    /// 同商户一起归好时的提示;点"好"后关闭编辑页。
    @State private var backfillNotice: String?

    init(entry: LedgerEntry, categories: [LedgerCategory], rows: [EntryRow]) {
        self.entry = entry
        self.categories = categories
        self.rows = rows
        _form = State(initialValue: EntryFormState(entry: entry))
    }

    var body: some View {
        NavigationStack {
            EntryFormView(
                form: $form,
                categories: categories,
                frequentIDs: frequentIDs,
                saveTitle: "保存",
                onSave: apply
            )
            .padding(.horizontal)
            .onChange(of: form.kind) {
                form.categoryID = CategoryRules.resolveSelection(
                    current: form.categoryID, kind: form.kind,
                    categories: categories, lastUsed: nil
                )
            }
            .navigationTitle("编辑账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
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
            .alert(backfillNotice ?? "", isPresented: Binding(
                get: { backfillNotice != nil },
                set: { if !$0 { backfillNotice = nil } }
            )) {
                Button("好") { dismiss() }
            }
        }
    }

    private var frequentIDs: [UUID] {
        BillsLogic.frequentCategoryIDs(
            rows, kind: form.kind,
            excluding: Set(categories.filter(\.isArchived).map(\.id))
        )
    }

    private func apply() {
        guard form.amount.isValid else { return }
        let previousCategoryID = entry.category?.id
        entry.amountInCents = form.amount.cents
        entry.kind = form.kind
        entry.date = DayStamp.stamp(form.date)
        entry.note = form.note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.category = categories.first { $0.id == form.categoryID }
        do {
            // 改了自动账的分类就记住"这个商户 → 这个分类",并把同商户还没分类的支出一起归好。
            let learned = try MerchantMemory.learnFromEdit(
                entry: entry, previousCategoryID: previousCategoryID, in: context
            )
            let others = try learned ? PendingCategorization.backfill(sameMerchantAs: entry, in: context) : 0
            try context.save()
            if others > 0 {
                backfillNotice = PendingCategorization.notice(count: others, merchant: entry.merchant)
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

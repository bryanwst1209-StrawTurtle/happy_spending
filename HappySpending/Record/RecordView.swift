import SwiftUI
import SwiftData
import HappySpendingCore

struct RecordView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \LedgerEntry.createdAt, order: .reverse) private var entries: [LedgerEntry]

    @Environment(\.scenePhase) private var scenePhase

    @State private var form = EntryFormState()
    @State private var savedCount = 0
    @State private var showToast = false
    @State private var errorMessage: String?

    private var archivedIDs: Set<UUID> {
        Set(categories.filter(\.isArchived).map(\.id))
    }

    private var frequentIDs: [UUID] {
        BillsLogic.frequentCategoryIDs(
            entries.prefix(300).map(\.row),
            kind: form.kind,
            excluding: archivedIDs
        )
    }

    var body: some View {
        EntryFormView(
            form: $form,
            categories: categories,
            frequentIDs: frequentIDs,
            saveTitle: "完成",
            onSave: save
        )
        .padding(.horizontal)
        .overlay(alignment: .top) {
            if showToast {
                ToastView(text: "已记一笔")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sensoryFeedback(.success, trigger: savedCount)
        .onAppear(perform: ensureCategory)
        .onChange(of: form.kind) { ensureCategory() }
        .onChange(of: categories.count) { ensureCategory() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { form.refreshDefaultDate() }
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

    /// 确保选中的分类属于当前类型且未归档;否则回到上次用过的分类,再不行就取第一个一级分类。
    private func ensureCategory() {
        let lastUsed = entries.first {
            $0.kind == form.kind && $0.category.map { !$0.isArchived } == true
        }?.category
        form.categoryID = CategoryRules.resolveSelection(
            current: form.categoryID, kind: form.kind,
            categories: categories, lastUsed: lastUsed
        )
    }

    private func save() {
        guard form.amount.isValid else { return }
        let category = categories.first { $0.id == form.categoryID }
        let entry = LedgerEntry(
            amountInCents: form.amount.cents,
            kind: form.kind,
            date: form.date,
            note: form.note.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category
        )
        context.insert(entry)
        do {
            try context.save()
        } catch {
            context.delete(entry)
            errorMessage = error.localizedDescription
            return
        }
        form.resetAfterSave()
        savedCount += 1
        withAnimation { showToast = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showToast = false }
        }
    }
}

import SwiftUI
import SwiftData
import HappySpendingCore

struct EntryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let entry: LedgerEntry
    let categories: [LedgerCategory]
    let frequentIDs: [UUID]

    @State private var form: EntryFormState
    @State private var errorMessage: String?

    init(entry: LedgerEntry, categories: [LedgerCategory], frequentIDs: [UUID]) {
        self.entry = entry
        self.categories = categories
        self.frequentIDs = frequentIDs
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
        }
    }

    private func apply() {
        guard form.amount.isValid else { return }
        entry.amountInCents = form.amount.cents
        entry.kind = form.kind
        entry.date = Calendar.current.startOfDay(for: form.date)
        entry.note = form.note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.category = categories.first { $0.id == form.categoryID }
        do {
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import SwiftUI
import HappySpendingCore

struct EntryFormView: View {
    @Binding var form: EntryFormState
    let categories: [LedgerCategory]
    let frequentIDs: [UUID]
    let saveTitle: String
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Picker("类型", selection: $form.kind) {
                ForEach(EntryKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(form.amount.displayText)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentTransition(.numericText())

            ScrollView {
                CategoryPicker(
                    kind: form.kind,
                    categories: categories,
                    frequentIDs: frequentIDs,
                    selectedID: $form.categoryID
                )
            }

            HStack(spacing: 8) {
                DatePicker(
                    "日期",
                    selection: Binding(
                        get: { form.date },
                        set: { form.date = $0; form.isDateChosen = true }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                Button("今天") { form.date = .now; form.isDateChosen = false }
                Button("昨天") {
                    form.date = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
                    form.isDateChosen = true
                }
                Spacer()
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            TextField("备注(可选)", text: $form.note)
                .textFieldStyle(.roundedBorder)

            NumericKeypad(
                saveTitle: saveTitle,
                canSave: form.canSave,
                onKey: { form.amount.press($0) },
                onSave: onSave
            )
        }
    }
}

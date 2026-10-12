import Foundation
import HappySpendingCore

struct EntryFormState: Equatable {
    var kind: EntryKind = .expense
    var amount = AmountInput()
    var categoryID: UUID?
    var date: Date = .now
    var note: String = ""

    var canSave: Bool { amount.isValid }

    init() {}

    init(entry: LedgerEntry) {
        kind = entry.kind
        amount = AmountInput(cents: entry.amountInCents)
        categoryID = entry.category?.id
        date = entry.date
        note = entry.note
    }

    /// 连续记账:只清空金额和备注,保留类型、分类和日期。
    mutating func resetAfterSave() {
        amount = AmountInput()
        note = ""
    }
}

import Foundation
import HappySpendingCore

struct EntryFormState: Equatable {
    var kind: EntryKind = .expense
    var amount = AmountInput()
    var categoryID: UUID?
    var date: Date = .now
    /// 用户有没有明确选过日期(日期选择器、"昨天")。没选过的默认日期会跟着"今天"走。
    var isDateChosen = false
    var note: String = ""

    var canSave: Bool { amount.isValid }

    init() {}

    init(entry: LedgerEntry) {
        kind = entry.kind
        amount = AmountInput(cents: entry.amountInCents)
        categoryID = entry.category?.id
        date = DayStamp.localDate(from: entry.date)
        isDateChosen = true
        note = entry.note
    }

    /// App 被挂起过夜后回到前台:没被用户明确选过的默认日期要跟上"今天"。
    mutating func refreshDefaultDate(now: Date = .now, calendar: Calendar = .current) {
        date = EntryDate.refreshedDefault(current: date, isUserChosen: isDateChosen, now: now, calendar: calendar)
    }

    /// 连续记账:只清空金额和备注,保留类型、分类和日期。
    mutating func resetAfterSave() {
        amount = AmountInput()
        note = ""
    }
}

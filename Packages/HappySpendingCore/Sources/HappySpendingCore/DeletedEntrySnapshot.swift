import Foundation

/// 删除一笔账之前的快照,用于"撤销"重新建回这一笔。
/// 自动账的来源和商户也要带回来,否则撤销后它会变成手动账(丢掉"自动"标记和分类记忆)。
public struct DeletedEntrySnapshot: Equatable, Sendable {
    public let id: UUID
    public let amountInCents: Int
    public let kind: EntryKind
    public let date: Date
    public let createdAt: Date
    public let note: String
    public let categoryID: UUID?
    public let autoSourceRaw: String?
    public let merchant: String?

    public init(_ entry: LedgerEntry) {
        id = entry.id
        amountInCents = entry.amountInCents
        kind = entry.kind
        date = entry.date
        createdAt = entry.createdAt
        note = entry.note
        categoryID = entry.category?.id
        autoSourceRaw = entry.autoSourceRaw
        merchant = entry.merchant
    }

    /// 用快照重新建一笔账(还没插入上下文)。分类按 ID 在 `categories` 里找,找不到就是未分类。
    public func makeEntry(categories: [LedgerCategory]) -> LedgerEntry {
        let entry = LedgerEntry(
            id: id,
            amountInCents: amountInCents,
            kind: kind,
            date: date,
            note: note,
            category: categories.first { $0.id == categoryID },
            createdAt: createdAt,
            calendar: DayStamp.calendar,
            merchant: merchant
        )
        entry.autoSourceRaw = autoSourceRaw
        return entry
    }
}

import Foundation
import SwiftData

@Model
public final class LedgerEntry {
    public var id: UUID
    public var amountInCents: Int
    public var kindRaw: String
    public var date: Date
    public var createdAt: Date
    public var note: String
    public var category: LedgerCategory?

    public var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        amountInCents: Int,
        kind: EntryKind,
        date: Date,
        note: String = "",
        category: LedgerCategory? = nil,
        createdAt: Date = .now,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.amountInCents = amountInCents
        self.kindRaw = kind.rawValue
        self.date = calendar.startOfDay(for: date)
        self.createdAt = createdAt
        self.note = note
        self.category = category
    }
}

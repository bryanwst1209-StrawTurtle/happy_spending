import Foundation
import SwiftData

@Model
public final class LedgerCategory {
    public var id: UUID
    public var name: String
    public var symbolName: String
    public var colorHex: String
    public var kindRaw: String
    public var sortOrder: Int
    public var isArchived: Bool
    public var parent: LedgerCategory?

    @Relationship(deleteRule: .nullify, inverse: \LedgerCategory.parent)
    public var children: [LedgerCategory] = []

    @Relationship(deleteRule: .nullify, inverse: \LedgerEntry.category)
    public var entries: [LedgerEntry] = []

    public var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// "餐饮 · 午餐";一级分类就是 "餐饮"。
    public var displayName: String {
        if let parent { "\(parent.name) · \(name)" } else { name }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        symbolName: String,
        colorHex: String,
        kind: EntryKind,
        sortOrder: Int = 0,
        parent: LedgerCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
        self.isArchived = false
        self.parent = parent
    }
}

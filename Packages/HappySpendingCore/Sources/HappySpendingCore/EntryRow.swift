import Foundation

public enum Uncategorized {
    public static let name = "未分类"
    public static let colorHex = "#8E8E93"
    public static let symbolName = "questionmark.circle.fill"
}

/// 一笔账的纯值快照,供统计、分组、导出等纯函数使用。
public struct EntryRow: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let createdAt: Date
    public let kind: EntryKind
    public let cents: Int
    public let note: String
    public let topCategoryID: UUID?
    public let topCategoryName: String
    public let topColorHex: String
    /// 一级分类的默认图标;`topIconData` 有值时界面用它代替。
    public let topSymbolName: String
    public let topIconData: Data?
    public let subCategoryID: UUID?
    public let subCategoryName: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        createdAt: Date? = nil,
        kind: EntryKind,
        cents: Int,
        note: String = "",
        topCategoryID: UUID?,
        topCategoryName: String,
        topColorHex: String,
        topSymbolName: String = Uncategorized.symbolName,
        topIconData: Data? = nil,
        subCategoryID: UUID? = nil,
        subCategoryName: String? = nil
    ) {
        self.id = id
        self.date = date
        self.createdAt = createdAt ?? date
        self.kind = kind
        self.cents = cents
        self.note = note
        self.topCategoryID = topCategoryID
        self.topCategoryName = topCategoryName
        self.topColorHex = topColorHex
        self.topSymbolName = topSymbolName
        self.topIconData = topIconData
        self.subCategoryID = subCategoryID
        self.subCategoryName = subCategoryName
    }

    /// "餐饮 · 午餐";没有二级分类时就是 "餐饮"。
    public var displayCategory: String {
        if let subCategoryName { "\(topCategoryName) · \(subCategoryName)" } else { topCategoryName }
    }
}

extension LedgerEntry {
    public var row: EntryRow {
        let top = category?.parent ?? category
        let sub = category?.parent == nil ? nil : category
        return EntryRow(
            id: id,
            date: date,
            createdAt: createdAt,
            kind: kind,
            cents: amountInCents,
            note: note,
            topCategoryID: top?.id,
            topCategoryName: top?.name ?? Uncategorized.name,
            topColorHex: top?.colorHex ?? Uncategorized.colorHex,
            topSymbolName: top?.symbolName ?? Uncategorized.symbolName,
            topIconData: top?.iconData,
            subCategoryID: sub?.id,
            subCategoryName: sub?.name
        )
    }
}
